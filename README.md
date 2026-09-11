# SAAP — Servidor de chão de fábrica (broker + painel)

Este diretório sobe, com um comando, todo o lado do servidor do SAAP:
o broker MQTT, o banco de séries temporais e o painel de gestão (Grafana).

## Pipeline

```
Nó de bancada (ESP32)                    Servidor (Raspberry Pi 5 / PC)
┌───────────────┐   MQTT/Wi-Fi   ┌────────────┐   ┌──────────┐   ┌──────────┐   ┌─────────┐
│ sensor + botão │ ─────────────▶ │ Mosquitto  │ ▶ │ Telegraf │ ▶ │ InfluxDB │ ▶ │ Grafana │
│ conta + publica│                │ (broker)   │   │ (ingestão)│   │ (histórico)│  │ (painel)│
└───────────────┘                └────────────┘   └──────────┘   └──────────┘   └─────────┘
```

> **Por que não ligar o Grafana direto no MQTT?** O Grafana precisa de histórico
> para mostrar "peças por hora" ao longo do turno. MQTT só carrega a mensagem do
> momento. Por isso entra um banco de séries temporais (InfluxDB) no meio, e o
> Telegraf é quem lê o MQTT e grava lá. O Grafana só consulta o InfluxDB.

## Pré-requisitos

- Docker + Docker Compose
- Porta 1883 (MQTT) e 3000 (Grafana) livres

> **Instalar na Raspberry Pi 5 do zero?** Siga o
> [INSTALL-raspberrypi.md](INSTALL-raspberrypi.md) — cobre desde gravar o cartão
> até os containers subindo sozinhos no boot.

## Subir

```bash
cp .env.example .env        # e troque a senha do Grafana
chmod -R a+rX grafana telegraf mosquitto   # Grafana (uid 472) precisa ler as configs
docker compose up -d
docker compose ps           # todos "running"
```

Abra o painel: <http://localhost:3000>  (usuário `admin`, senha do `.env`).
O data source **InfluxDB-SAAP** e o dashboard **SAAP — Produção em tempo real**
já vêm provisionados (pasta `SAAP` no menu Dashboards).

## Acesso remoto (fora da rede local)

Use **Tailscale** — passo a passo na seção 16 do
[INSTALL-raspberrypi.md](INSTALL-raspberrypi.md). Resumo: instala o Tailscale no
host da Pi, os integrantes acessam `http://cara:3000` pela malha privada, e
`tailscale funnel 3000` gera um link HTTPS público quando precisar mostrar para
avaliadores. **Só o Grafana é exposto** — MQTT e InfluxDB ficam só na LAN.

## Testar sem hardware

```bash
pip install paho-mqtt
python simulador/simula_bancadas.py
# em ~30 s os painéis do Grafana começam a se mexer
```

Simular uma parada de bancada (para ver o gráfico "peças por minuto" cair a zero):

```bash
python simulador/simula_bancadas.py --micro-parada B02
```

Publicar um evento avulso na mão:

```bash
mosquitto_pub -h localhost -t "fabrica/setorA/bancada/B01/evento" \
  -m '{"bancada":"B01","evt_id":"B01-000001","ts":"2026-09-09T14:30:00.123456-03:00","delta":1,"total_turno":1,"total_hora":1,"origem":"sensor"}'
```

## Modelo de dados (InfluxDB)

| Elemento | Valor | Origem |
|---|---|---|
| measurement | `producao` | fixado no `telegraf.conf` (`name_override`) |
| tag | `bancada` = `B01`, `B02`, ... | campo `bancada` do JSON (`tag_keys`) |
| field | `delta` (1 por peça), `total_turno`, `total_hora` | campos numéricos do JSON |
| field (texto) | `evt_id`, `origem` | `json_string_fields` |
| timestamp | horário do evento no nó, **com fração de segundo** | `json_time_key = "ts"` |

Mensagem MQTT esperada (tópico `fabrica/<setor>/bancada/<id>/evento`):

```json
{
  "bancada": "B01",
  "evt_id": "B01-000482",
  "ts": "2026-09-09T14:22:31.481003-03:00",
  "delta": 1,
  "total_turno": 482,
  "total_hora": 37,
  "origem": "sensor"
}
```

> **`ts` precisa ter milissegundos/microssegundos.** A chave de um ponto no
> InfluxDB é `measurement + tags + timestamp`. Se dois eventos da mesma bancada
> tiverem o mesmo `ts` (ex.: só segundos), o segundo **sobrescreve** o primeiro e
> a contagem some. O RTC DS3231 dá só 1 s de resolução — o firmware deve
> complementar com o `millis()` (ou um contador de sequência) para o `ts` ficar
> único. O `evt_id` sozinho **não** resolve isso (é field, não entra na chave).

## Painéis e consultas (InfluxQL)

O dashboard já traz estes painéis. As consultas usam `$timeFilter` (Grafana troca
pelo intervalo de tempo selecionado no canto superior direito).

| Painel | Tipo | Consulta |
|---|---|---|
| Peças no período — linha toda | Stat | `SELECT sum("delta") FROM "producao" WHERE $timeFilter` |
| Peças por bancada | Bar gauge | `SELECT sum("delta") FROM "producao" WHERE $timeFilter GROUP BY "bancada"` |
| Peças por hora | Time series (barras) | `SELECT sum("delta") FROM "producao" WHERE $timeFilter GROUP BY time(1h), "bancada" fill(0)` |
| Total do turno por bancada | Tabela | `SELECT last("total_turno") FROM "producao" WHERE $timeFilter GROUP BY "bancada"` |
| Peças por minuto | Time series (linha) | `SELECT sum("delta") FROM "producao" WHERE $timeFilter GROUP BY time(1m), "bancada" fill(0)` |

### Meta de produção

Para "comparar com a meta" (RF10): no painel *Peças por bancada*, em
**Field > Thresholds**, ponha o valor da meta (ex.: 80 peças/turno) — as barras
ficam verdes ao atingir e vermelhas abaixo. Já vem um exemplo com degraus em 40 e 80.

## Alerta de micro-parada (RF09)

Duas formas:

**A) Alerta nativo do Grafana (mais simples).**
Alerting > Alert rules > New. Query:
`SELECT sum("delta") FROM "producao" WHERE time > now() - 5m GROUP BY "bancada" fill(0)`
Condição: `last()` de A `is below 1`.
Em *Configure no data and error handling*, marque **Alerting** para "No data"
(cobre a bancada que parou de mandar qualquer mensagem).
Use um *mute timing* para valer só no horário de turno.

**B) Node-RED (mais determinístico).**
Se quiser a regra mais robusta e com histórico próprio, adicione um container
Node-RED assinando o mesmo MQTT: um nó que zera um timer a cada evento por
bancada e dispara um alerta se o timer passar de N minutos. Grava o evento
`micro_parada` de volta no InfluxDB (measurement `eventos`) para aparecer no painel.

## Editar o dashboard e salvar no repositório (Entrega 6)

1. Ajuste os painéis pela interface do Grafana.
2. Dashboard settings (engrenagem) > **JSON Model** > copie tudo.
3. Cole em `grafana/dashboards/saap.json` e faça commit.
   No próximo `docker compose up` o painel já sobe com suas alterações.

## Segurança (antes de usar de verdade)

- `mosquitto.conf`: trocar `allow_anonymous true` por `password_file`.
- InfluxDB: `INFLUXDB_HTTP_AUTH_ENABLED=true` + usuário/senha.
- Grafana: senha forte no `.env`; desabilitar sign-up.
