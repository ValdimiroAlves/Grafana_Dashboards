# SAAP — Servidor de chão de fábrica (broker + painel)

Este diretório sobe, com um comando, todo o lado do servidor do SAAP:
o broker MQTT, a integração/validação dos eventos, o banco de dados e o
painel de gestão (Grafana).

## Pipeline

```
Nó de bancada (ESP32)                    Servidor (Raspberry Pi 5 / PC)
┌───────────────┐   MQTT/Wi-Fi   ┌────────────┐   ┌──────────┐   ┌────────────┐   ┌─────────┐
│ sensor + botão │ ─────────────▶ │ Mosquitto  │ ▶ │ Node-RED │ ▶ │ PostgreSQL │ ▶ │ Grafana │
│ conta + publica│                │ (broker)   │   │ (valida) │   │ (histórico)│   │ (painel)│
└───────────────┘                └────────────┘   └──────────┘   └────────────┘   └─────────┘
```

> **Por que não ligar o Grafana direto no MQTT?** O Grafana precisa de histórico
> para mostrar "peças por hora" ao longo do turno, e MQTT só carrega a mensagem
> do momento — por isso existe um banco relacional (PostgreSQL) no meio. O
> Node-RED é quem assina o MQTT, confere se o payload tem o formato esperado
> e só então grava no banco; ele também é a camada que evita duplicar um
> evento reenviado (RF03) via `INSERT ... ON CONFLICT DO NOTHING`, apoiado nos
> índices únicos definidos em `postgres/init/001_schema.sql`.

## Pré-requisitos

- Docker + Docker Compose
- Portas 1883 (MQTT), 3000 (Grafana) e 1880 (editor do Node-RED) livres

> **Instalar na Raspberry Pi 5 do zero?** Siga o
> [INSTALL-raspberrypi.md](INSTALL-raspberrypi.md) — cobre desde gravar o cartão
> até os containers subindo sozinhos no boot.

## Subir

```bash
cp .env.example .env        # troque GRAFANA_PASSWORD e POSTGRES_PASSWORD
chmod -R a+rX grafana mosquitto postgres   # Grafana (uid 472) precisa ler as configs
chmod a+rw node-red/flows.json             # o Node-RED (uid 1000) precisa poder salvar o fluxo
docker compose up -d --build               # --build: a 1ª vez compila a imagem do Node-RED
docker compose ps           # todos "running"
```

Na primeira subida, abra o editor do Node-RED em `http://localhost:1880`,
clique duas vezes no node **"Gravar evento"** → editar a config **"PostgreSQL"**
→ preencha o campo **Password** com o valor de `POSTGRES_PASSWORD` do seu `.env`
→ **Update** → **Deploy** (botão vermelho no canto superior direito). Isso só
precisa ser feito uma vez: o Node-RED guarda a senha criptografada em
`flows_cred.json`, dentro do volume `node_red_data` — **nunca** em texto puro
no `flows.json` versionado.

Abra o painel: <http://localhost:3000> (usuário `admin`, senha do `.env`).
O data source **PostgreSQL-SAAP** e o dashboard **SAAP — Produção em tempo real**
já vêm provisionados (pasta `SAAP` no menu Dashboards).

## Acesso remoto (fora da rede local)

Use **Tailscale** — passo a passo na seção 16 do
[INSTALL-raspberrypi.md](INSTALL-raspberrypi.md). Resumo: instala o Tailscale no
host da Pi, os integrantes acessam `http://cara:3000` pela malha privada, e
`tailscale funnel 3000` gera um link HTTPS público quando precisar mostrar para
avaliadores. **Só o Grafana é exposto** — MQTT, Postgres e o editor do
Node-RED ficam só na LAN.

## Testar sem hardware

```bash
pip install paho-mqtt
python simulador/simula_bancadas.py
# em ~30 s os painéis do Grafana começam a se mexer
```

O simulador já publica `evt_id`, `total_turno`, `total_hora` e `origem` — os
mesmos campos que o schema do Postgres foi desenhado para receber. O firmware
do FlowCount ainda não envia `evt_id`/`sequence` (ver nota em
`postgres/init/001_schema.sql`); enquanto isso não muda, testar com o
simulador é a forma mais fácil de ver a deduplicação "forte" (por `evt_id`)
funcionando de verdade.

Simular uma parada de bancada (para ver o gráfico "peças por minuto" cair a zero):

```bash
python simulador/simula_bancadas.py --micro-parada B02
```

Publicar um evento avulso na mão:

```bash
mosquitto_pub -h localhost -t "fabrica/setorA/bancada/B01/evento" \
  -m '{"bancada":"B01","evt_id":"B01-000001","ts":"2026-09-09T14:30:00.123456-03:00","delta":1,"total_turno":1,"total_hora":1,"origem":"sensor"}'
```

Para ver o evento sendo validado e gravado, acompanhe `docker compose logs -f
node-red` ou abra a aba **Debug** no editor (`http://localhost:1880`).

## Modelo de dados (PostgreSQL)

| Elemento | Valor | Origem |
|---|---|---|
| tabela | `producao` | `postgres/init/001_schema.sql` |
| coluna | `bancada` | campo `bancada` do JSON |
| coluna | `evt_id` (opcional, `NULL` se o nó não enviar) | campo `evt_id` do JSON |
| coluna | `ocorrido_em` (timestamptz) | campo `ts` do JSON — horário real da passagem, gerado no nó |
| coluna | `recebido_em` (timestamptz, `now()`) | horário em que o Node-RED gravou a linha |
| coluna | `delta`, `total_turno`, `total_hora` | campos numéricos do JSON |
| coluna | `origem` | campo `origem` do JSON |

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

Só `bancada`, `ts` e `delta` são obrigatórios — o Node-RED descarta (com log
no debug "evento inválido") qualquer mensagem sem esses três campos válidos.

### Deduplicação (RF03)

Dois índices únicos em `producao` fazem o trabalho, e o Node-RED grava com
`INSERT ... ON CONFLICT DO NOTHING` (reenviar o mesmo evento não aumenta o total):

1. **`(bancada, evt_id)` — quando `evt_id` não é nulo.** Robusta: cobre
   estação + sessão + sequência do nó, e sobrevive a reenvios com timestamps
   levemente diferentes.
2. **`(bancada, ocorrido_em)` — quando `evt_id` é nulo.** É o que vale hoje
   para o firmware real do FlowCount, que ainda não envia `evt_id`. Funciona,
   mas é frágil: dois eventos genuinamente distintos da mesma bancada no
   exato mesmo microssegundo colidiriam. Resolver isso é enviar `evt_id`
   (estação+sessão+sequência) pelo firmware — ver checklist do projeto.

> **`ts` precisa ter milissegundos/microssegundos.** Enquanto a deduplicação
> cai no índice por timestamp (item 2 acima), dois eventos da mesma bancada
> com o mesmo `ts` truncado em segundos colidiriam e um deles seria
> silenciosamente descartado. O RTC do nó dá só 1 s de resolução — o firmware
> deve complementar com `millis()` (ou o `evt_id`) para o `ts` ficar único.

## Painéis e consultas (SQL)

O dashboard já traz estes painéis. As consultas usam `$__timeFilter(coluna)`
e `$__timeGroup(coluna, intervalo)` — macros do Grafana para o datasource
PostgreSQL, que ele troca pelo intervalo de tempo selecionado no canto
superior direito.

| Painel | Tipo | Consulta |
|---|---|---|
| Peças no período — linha toda | Stat | `SELECT sum(delta) AS total FROM producao WHERE $__timeFilter(ocorrido_em)` |
| Peças por bancada | Bar gauge | `SELECT bancada, sum(delta) AS total FROM producao WHERE $__timeFilter(ocorrido_em) GROUP BY bancada` |
| Peças por hora | Time series (barras) | `SELECT $__timeGroup(ocorrido_em,'1h') AS time, bancada, sum(delta) AS value FROM producao WHERE $__timeFilter(ocorrido_em) GROUP BY 1, bancada` |
| Total do turno por bancada | Tabela | último `total_turno` não nulo de cada bancada no período (`DISTINCT ON`) |
| Peças por minuto | Time series (linha) | igual ao "por hora", agrupando em `$__timeGroup(ocorrido_em,'1m')` |
| Última comunicação por bancada (RF04) | Tabela | `SELECT bancada, max(recebido_em) FROM producao GROUP BY bancada` — sempre olha o histórico inteiro, não só o período selecionado |

### Meta de produção

Para "comparar com a meta" (RF10): no painel *Peças por bancada*, em
**Field > Thresholds**, ponha o valor da meta (ex.: 80 peças/turno) — as barras
ficam verdes ao atingir e vermelhas abaixo. Já vem um exemplo com degraus em 40 e 80.

## Alerta de micro-parada (RF09)

Duas formas:

**A) Alerta nativo do Grafana (mais simples).**
Alerting > Alert rules > New. Query:
`SELECT bancada, sum(delta) AS total FROM producao WHERE ocorrido_em > now() - interval '5 minutes' GROUP BY bancada`
Condição: `total is below 1`.
Em *Configure no data and error handling*, marque **Alerting** para "No data"
(cobre a bancada que parou de mandar qualquer mensagem).
Use um *mute timing* para valer só no horário de turno.

**B) Dentro do próprio Node-RED (mais determinístico).**
Como o Node-RED já está no pipeline de ingestão, dá para adicionar ali mesmo
um node que zera um timer a cada evento por bancada e dispara um alerta se o
timer passar de N minutos — sem precisar de mais um serviço. Grave o evento
`micro_parada` numa tabela separada (`eventos`, por exemplo) para aparecer
num painel próprio.

## Editar o dashboard e o fluxo, e salvar no repositório

**Dashboard do Grafana:**
1. Ajuste os painéis pela interface do Grafana.
2. Dashboard settings (engrenagem) > **JSON Model** > copie tudo.
3. Cole em `grafana/dashboards/saap.json` e faça commit.
   No próximo `docker compose up` o painel já sobe com suas alterações.

**Fluxo do Node-RED:** diferente do Grafana, `node-red/flows.json` é montado
com bind mount de arquivo único (não é só lido na subida) — então salvar pela
própria interface (`http://localhost:1880` → **Deploy**) já escreve direto
nesse arquivo do repositório. Depois é só `git add node-red/flows.json` e
commitar, igual ao dashboard.

## Segurança (antes de usar de verdade)

- `mosquitto.conf`: trocar `allow_anonymous true` por `password_file`.
- PostgreSQL: já exige usuário/senha (`POSTGRES_PASSWORD` no `.env`) — só
  troque o valor padrão de `.env.example` antes de qualquer uso real.
- Node-RED: o editor em `:1880` **não tem login por padrão**. Antes de expor
  além da LAN de teste, habilite `adminAuth` em `settings.js` (dentro do
  volume `node_red_data`, ou via um `settings.js` próprio montado no compose).
- Grafana: senha forte no `.env`; desabilitar sign-up (já feito no compose).
