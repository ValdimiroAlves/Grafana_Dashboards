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

## Telas do Grafana

Cinco dashboards, cada um pensado pra um público, com links cruzados entre eles
(canto superior, ao lado do título):

| Tela | uid | Pra quem | O que mostra |
|---|---|---|---|
| SAAP — Produção em tempo real | `saap-main` | visão geral / demonstração | tudo junto, é a original |
| 🏭 Produção | `saap-producao` | operador/técnico | produção do período, meta por esteira, ritmo atual, status da linha |
| 🖥️ Sistema | `saap-sistema` | TI/equipe técnica | CPU, memória e temperatura da Raspberry real, saúde do broker MQTT |
| 🔧 Diagnóstico | `saap-diagnostico` | manutenção | última comunicação, quedas detectadas, clientes MQTT |
| 📈 Histórico / Gestão | `saap-historico` | supervisor/gestor | produção por hora/dia/turno, comparação entre esteiras |

**Não implementado ainda** (fica documentado nas próprias telas, não escondido):
telemetria de saúde do ESP32 (a tela Sistema só cobre o lado do servidor) e
comparação por operador (o sistema não identifica quem está em cada esteira).

## Pré-requisitos

- Docker + Docker Compose
- Portas 1883 (MQTT), 3000 (Grafana) e 1880 (editor do Node-RED) livres

> **Instalar na Raspberry Pi 5 do zero?** Siga o
> [INSTALL-raspberrypi.md](INSTALL-raspberrypi.md) — cobre desde gravar o cartão
> até os containers subindo sozinhos no boot.

## Autenticação MQTT (RNF05 — fazer ANTES de subir)

O `mosquitto.conf` já exige senha (`allow_anonymous false` + `password_file`).
Sem o arquivo de senhas, o Mosquitto **não sobe** — então gere-o antes do
primeiro `docker compose up`:

```bash
docker run --rm -v "$(pwd)/mosquitto/config:/mosquitto/config" eclipse-mosquitto:2 \
  mosquitto_passwd -c -b /mosquitto/config/passwd flowcount "TROQUE-ESTA-SENHA"
```

- `-c` **cria um arquivo novo** (apaga o que existia) — use só na primeira vez.
- Pra adicionar outro usuário depois sem apagar os existentes, repita o comando
  **sem** `-c`.
- `flowcount` é o usuário único usado pelos nós ESP32, pelo simulador e pelo
  Node-RED — não há ACL por tópico nesta entrega (qualquer autenticado pode
  publicar/assinar em qualquer tópico); separar por usuário/ACL fica como
  melhoria futura.
- `mosquitto/config/passwd` **não é versionado** (`.gitignore`) — mesmo com a
  senha em hash, é segredo de implantação, igual ao `.env`.

Anote a senha escolhida: ela entra em três lugares — no `menuconfig` de cada
ESP32 (`FLOWCOUNT_MQTT_USERNAME`/`FLOWCOUNT_MQTT_PASSWORD`), no simulador
(`--mqtt-user`/`--mqtt-password`) e no Node-RED (passo abaixo).

## Subir

```bash
cp .env.example .env        # troque GRAFANA_PASSWORD e POSTGRES_PASSWORD
chmod -R a+rX grafana mosquitto postgres   # Grafana (uid 472) precisa ler as configs
docker compose up -d --build               # --build: a 1ª vez compila a imagem do Node-RED
docker compose ps           # todos "running"
```

> `chmod: changing permissions of 'mosquitto/config/passwd': Operation not
> permitted`? Normal, pode ignorar — esse arquivo foi criado por dentro de um
> container (o `mosquitto_passwd` da seção acima), então pertence ao usuário
> interno do Mosquitto, não ao seu usuário do shell; só o dono (ou root) pode
> mudar a permissão dele. Ele já nasce legível pelo próprio Mosquitto — não
> precisa de chmod nenhum — e o comando continua normalmente para `grafana/`
> e `postgres/` apesar do erro nessa única linha.

Na primeira subida, abra o editor do Node-RED em `http://localhost:1880` e
configure as duas credenciais que ficam em branco no `flows.json` versionado:

1. Clique duas vezes no node **"eventos de produção"** (o de entrada, ícone de
   MQTT) → editar a config **"Mosquitto local"** → aba **Security** → usuário
   `flowcount` e a senha que você gerou acima → **Update**.
2. Clique duas vezes no node **"Gravar evento"** → editar a config
   **"PostgreSQL"** → campo **Password** → o valor de `POSTGRES_PASSWORD` do
   `.env` → **Update**.
3. **Deploy** (botão vermelho no canto superior direito) — só depois de mexer
   nas duas.

Isso só precisa ser feito uma vez por instalação: o Node-RED guarda as duas
senhas criptografadas em `flows_cred.json`, dentro do volume `node_red_data`
— **nunca** em texto puro no `flows.json` versionado.

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
python simulador/simula_bancadas.py --mqtt-user flowcount --mqtt-password "TROQUE-ESTA-SENHA"
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
mosquitto_pub -h localhost -u flowcount -P "TROQUE-ESTA-SENHA" \
  -t "fabrica/setorA/bancada/B01/evento" \
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

### Turno

"Turno" **não** é um requisito do documento (`tcc_a`) nem algo que o firmware
do FlowCount envia — é calculado no banco a partir do horário real do evento
(`ocorrido_em`), pela função `turno_do_horario()` em
[`postgres/init/002_turno.sql`](postgres/init/002_turno.sql):

| Turno | Horário (Brasília) |
|---|---|
| Turno 1 | 06h–14h |
| Turno 2 | 14h–22h |
| Turno 3 | 22h–06h |

Só essa função precisa ser editada se os horários reais forem outros — todo o
resto (painel, consultas futuras) consome ela, não repete a lógica.

As colunas `total_turno`/`total_hora` do schema continuam existindo (o
simulador ainda manda os dois), mas não são mais a fonte do painel "Peças por
turno" — eram um contador que o próprio nó teria que zerar sozinho, e o
firmware real nunca chegou a implementar isso.

> **Instalação que já existe (a Pi, por exemplo):** os arquivos em
> `postgres/init/` só rodam automaticamente na **primeira** inicialização do
> volume do Postgres. Numa instalação que já estava de pé antes desta função
> existir, aplique manualmente depois do `git pull`:
> ```bash
> docker exec -i saap-postgres psql -U saap -d saap < postgres/init/002_turno.sql
> ```

### Métricas de sistema e do broker (tela Sistema)

Duas tabelas novas, alimentadas por um fluxo próprio no Node-RED (aba
"SAAP - monitoramento" no editor), gravando um snapshot a cada ~30s:

- **`sistema_metricas`**: carga de CPU, uso de memória e temperatura — lidos
  com `os.loadavg()`/`os.totalmem()`/`os.freemem()` e
  `/host_thermal/thermal_zone0/temp` dentro de um node Function.
- **`broker_stats`**: clientes conectados, mensagens recebidas e uptime — o
  Mosquitto já publica isso sozinho nos tópicos `$SYS/broker/...` (não precisa
  mudar `mosquitto.conf`).

Pra `os.loadavg()`/`os.totalmem()`/`os.freemem()` refletirem a **Raspberry
real** (não o container), o serviço `node-red` no `docker-compose.yml` roda
com `pid: host` — ele passa a enxergar a lista de processos do host (só
leitura, não controla nada). É uma concessão de segurança aceitável numa rede
local de teste (RNF05), mas **não faça isso** numa instalação exposta além da
LAN. A temperatura vem de `/sys/class/thermal`, montado só-leitura e só esse
subdiretório (não o `/sys` inteiro).

> **Instalação que já existe:** três passos, nesta ordem.
> 1. Rode `002_turno.sql` (se ainda não rodou) e `003_sistema.sql`:
>    ```bash
>    docker exec -i saap-postgres psql -U saap -d saap < postgres/init/002_turno.sql
>    docker exec -i saap-postgres psql -U saap -d saap < postgres/init/003_sistema.sql
>    ```
> 2. `settings.js` é arquivo novo e `flows.json` ganhou a aba de monitoramento
>    — nenhum dos dois se atualiza sozinho num volume que já existe (mesma
>    ressalva de sempre). Mais simples recriar o volume do zero do que copiar
>    arquivo por arquivo:
>    ```bash
>    docker compose down
>    docker volume rm grafana_dashboards_node_red_data   # confirme o nome: docker volume ls | grep node_red
>    docker compose up -d --build
>    ```
> 3. Refaça as duas credenciais no editor do Node-RED (o volume novo não tem
>    nenhuma salva) — ver os três passos na seção "Subir", acima.

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
| Peças por turno | Tabela | `SELECT turno_do_horario(ocorrido_em) AS turno, bancada, sum(delta) FROM producao WHERE $__timeFilter(ocorrido_em) GROUP BY turno, bancada` |
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

**Fluxo do Node-RED:** `node-red/flows.json` entra na imagem via `COPY` no
`node-red/Dockerfile` (não é bind mount — o Node-RED salva o fluxo renomeando
um arquivo temporário por cima do `flows.json`, e isso trava com `EBUSY` se o
arquivo for um bind mount). Editar pela interface (`http://localhost:1880` →
**implementar**/Deploy) salva normalmente, só que **dentro do volume**
`node_red_data`, não direto no arquivo do repositório. Pra levar uma edição de
volta pro Git:

```bash
docker cp saap-node-red:/data/flows.json node-red/flows.json
git add node-red/flows.json && git commit -m "atualiza fluxo do Node-RED"
```

E pro caminho inverso — aplicar uma mudança do repositório numa instalação que
já está rodando (o volume já existe e não é re-semeado sozinho):

```bash
docker cp node-red/flows.json saap-node-red:/data/flows.json
docker compose restart node-red
```

## Segurança (antes de usar de verdade)

- Mosquitto: já exige senha (`password_file`) — falta só TLS, se for expor além
  da LAN de teste. Também não há ACL por tópico: qualquer usuário autenticado
  publica/assina em qualquer tópico.
- PostgreSQL: já exige usuário/senha (`POSTGRES_PASSWORD` no `.env`) — só
  troque o valor padrão de `.env.example` antes de qualquer uso real.
- Node-RED: o editor em `:1880` **não tem login por padrão**. Antes de expor
  além da LAN de teste, habilite `adminAuth` em `settings.js` (dentro do
  volume `node_red_data`, ou via um `settings.js` próprio montado no compose).
- Grafana: senha forte no `.env`; desabilitar sign-up (já feito no compose).
