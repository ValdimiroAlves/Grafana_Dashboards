# Instalação do servidor SAAP na Raspberry Pi 5 (do zero)

Guia completo, assumindo que **nada foi instalado** na Pi ainda. Ao final, a Pi
sobe o broker MQTT + Node-RED + PostgreSQL + Grafana automaticamente a cada
boot, e os nós ESP32 publicam nela.

Tempo estimado: 40–60 min (a maior parte é download).

---

## 0. O que você vai precisar

| Item | Observação |
|---|---|
| Raspberry Pi 5 |  |
| Fonte USB-C 27 W oficial |  **use esta**, fonte fraca causa instabilidade |
| Cooler ativo instalado na Pi |  instale **antes** de ligar; a Pi 5 esquenta |
| Cartão microSD 128 GB A2/V30 |  (ou um SSD USB, melhor para uso contínuo) |
| Gabinete | |
| Cabo de rede (ideal) ou Wi-Fi | rede cabeada é mais estável para um servidor |
| Outro computador (Windows) | para gravar o cartão e acessar por SSH |
| Leitor de cartão microSD | (leitor/adaptador USB) |


---

## 1. Gravar o sistema operacional no cartão (no PC Windows)

1. Baixe e instale o **Raspberry Pi Imager**: <https://www.raspberrypi.com/software/>
2. Insira o cartão microSD no PC.
3. Abra o Imager:
   - **Dispositivo:** Raspberry Pi 5
   - **Sistema operacional:** *Raspberry Pi OS Lite (64-bit)*
     (em "Raspberry Pi OS (other)"). É sem interface gráfica — é o certo para um servidor.
   - **Armazenamento:** o cartão microSD
4. Clique em **Avançar** e depois em **Editar definições** (a engrenagem / "Sim" para personalizar):
   - **Hostname:** `saap`
   - **Ativar SSH:** sim → "Usar autenticação por senha"
   - **Usuário e senha:** usuário `saap`, senha forte (anote)
   - **Wi-Fi** (se não for usar cabo): SSID, senha, país `BR`
   - **Localização:** fuso `America/Sao_Paulo`, teclado `br`
5. **Gravar**. Aguarde terminar e a verificação.
6. Retire o cartão do PC.

---

## 2. Primeiro boot da Pi

1. Com a Pi **desligada**: insira o cartão, conecte o cabo de rede (se for usar
   cabo) e por último a fonte USB-C.
2. Aguarde ~2 min no primeiro boot (ele expande o sistema de arquivos e reinicia).
3. Descubra o endereço da Pi:
   - Tente pelo nome: no PC, `ping saap.local`
   - Ou veja a lista de dispositivos no seu roteador (procure "saap")

---

## 3. Conectar por SSH (do PC Windows)

Abra o **PowerShell** ou **Terminal** no Windows:

```powershell
ssh saap@saap.local
```

(ou `ssh saap@192.168.x.x` com o IP encontrado). Aceite a chave (`yes`) e digite a senha.

Você está agora no terminal da Pi. Os próximos comandos rodam **na Pi**.

---

## 4. Atualizar o sistema

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y git curl mosquitto-clients
sudo reboot
```

A conexão SSH vai cair no reboot. Espere 1 min e reconecte:

```powershell
ssh saap@saap.local
```

Confirme o relógio (timestamps errados estragam os gráficos):

```bash
timedatectl
# "System clock synchronized: yes" e o fuso America/Sao_Paulo
```

---

## 5. Dar um IP fixo à Pi (importante)

Os nós ESP32 vão gravar o endereço do broker. Se o IP da Pi mudar, eles param de
publicar. Escolha **uma** das opções:

**Opção A — reserva no roteador (mais simples):** no painel do seu roteador,
em DHCP / "Reserva de endereço", fixe o IP atual da Pi pelo MAC dela.
Veja o MAC com:

```bash
ip a | grep -A1 'state UP' | grep link/ether
```

**Opção B — IP estático na Pi (Raspberry Pi OS Bookworm usa NetworkManager):**

```bash
# descubra o nome da conexão (ex.: "Wired connection 1")
nmcli connection show

sudo nmcli connection modify "Wired connection 1" \
  ipv4.method manual \
  ipv4.addresses 192.168.1.50/24 \
  ipv4.gateway 192.168.1.1 \
  ipv4.dns "192.168.1.1 1.1.1.1"

sudo nmcli connection up "Wired connection 1"
```

Ajuste `192.168.1.x` para a faixa da sua rede. Anote o IP escolhido — é o
**endereço do broker** que vai no firmware dos ESP32.

---

## 6. Instalar o Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

Saia e reconecte para o grupo `docker` valer:

```bash
exit
```
```powershell
ssh saap@saap.local
```

Teste:

```bash
docker run --rm hello-world
docker compose version
```

O Docker já sobe sozinho no boot. As imagens `eclipse-mosquitto`, `postgres`,
`nodered/node-red` e `grafana-oss` têm versão **arm64**, que é o que a Pi 5
usa — não precisa mudar nada no `docker-compose.yml`. A imagem do Node-RED é
compilada na própria Pi na primeira subida (`docker compose up --build`),
porque instala ali o node de PostgreSQL — isso adiciona alguns minutos só na
primeira vez.

---

## 7. Copiar o projeto para a Pi

**Se o repositório já existe no GitHub** (é este mesmo repositório —
`docker-compose.yml` fica na raiz dele, sem subpasta):

```bash
cd ~
git clone <URL-do-repositorio> saap-servidor
cd saap-servidor
```

**Se ainda não existe no GitHub** — copie a pasta inteira do seu PC. No
**PowerShell do Windows**, dentro da pasta do projeto:

```powershell
scp -r . saap@saap.local:/home/saap/saap-servidor
```

E na Pi:

```bash
cd ~/saap-servidor
```

---

## 8. Configurar e subir

```bash
cp .env.example .env
nano .env            # troque GRAFANA_PASSWORD e POSTGRES_PASSWORD; Ctrl+O, Enter, Ctrl+X
```

O Mosquitto exige senha e **não sobe sem o arquivo de senhas** — gere
antes de continuar (`-c` cria o arquivo, só use na primeira vez):

```bash
docker run --rm -v "$(pwd)/mosquitto/config:/mosquitto/config" eclipse-mosquitto:2 \
  mosquitto_passwd -c -b /mosquitto/config/passwd flowcount "TROQUE-ESTA-SENHA"
```

Anote a senha — ela vai entrar também no `menuconfig` de cada ESP32
(`FLOWCOUNT_MQTT_USERNAME`/`FLOWCOUNT_MQTT_PASSWORD`) e no Node-RED (mais abaixo).

```bash
# IMPORTANTE: o Grafana roda como uid 472 dentro do container e precisa
# de permissão de leitura nas pastas de configuração copiadas para a Pi.
sudo chmod -R a+rX grafana mosquitto postgres

docker compose up -d --build
docker compose ps    # os 4 serviços devem aparecer como "running"
```

> Se você já subiu antes de rodar o `chmod`, rode-o agora e depois
> `docker compose restart grafana node-red`.

> `chmod: changing permissions of 'mosquitto/config/passwd': Operation not
> permitted`? Normal, pode ignorar — o `passwd` foi criado por dentro de um
> container (`mosquitto_passwd`, passo anterior), então pertence ao usuário
> interno do Mosquitto, não ao usuário `saap` da Pi; só o dono (ou root) muda
> a permissão dele, e ele já nasce legível pelo próprio Mosquitto. O `chmod`
> segue normalmente para `grafana/` e `postgres/` apesar do erro nessa linha.

A primeira subida baixa ~500 MB de imagens e compila a imagem do Node-RED —
pode levar alguns minutos.

> As cinco telas do Grafana (Produção, Sistema, Diagnóstico, Histórico/Gestão
> e a visão geral) sobem juntas automaticamente. A tela **Sistema** (CPU/
> memória/temperatura da Pi) depende do `pid: host` que já está no
> `docker-compose.yml` deste repositório — nada extra pra configurar na Pi.
> Detalhes e como aplicar isso numa instalação que já existia: seção
> "Métricas de sistema e do broker" no [README.md](README.md).

Acompanhe a ingestão:

```bash
docker compose logs -f node-red
# deve conectar em mosquitto:1883 e em postgres:5432 sem erro
```

Depois, abra `http://saap.local:1880` (ou `http://<ip-da-pi>:1880`) e
configure as duas credenciais que ficam em branco no `flows.json`:

1. Node **"eventos de produção"** → editar config **"Mosquitto local"** →
   aba **Security** → usuário `flowcount` + a senha gerada acima → **Update**.
2. Node **"Gravar evento"** → editar config **"PostgreSQL"** → campo
   Password → a senha de `POSTGRES_PASSWORD` → **Update**.
3. **implementar** (botão vermelho, canto superior direito) — só depois de
   mexer nas duas.

Só precisa fazer isso uma vez por instalação — o Node-RED guarda as duas
senhas criptografadas no volume `node_red_data`.

---

## 9. Acessar o painel

De qualquer PC/celular na mesma rede:

```
http://saap.local:3000
```

(ou `http://192.168.1.50:3000` com o IP fixo). Login: `admin` / senha do `.env`.

Menu **Dashboards → pasta SAAP → "SAAP — Produção em tempo real"**. Vai estar
vazio até chegar dado.



---

## 10. Testar com dados falsos (sem os ESP32)

Na Pi:

```bash
sudo apt install -y python3-paho-mqtt
python3 ~/saap-servidor/simulador/simula_bancadas.py --broker localhost \
  --mqtt-user flowcount --mqtt-password "TROQUE-ESTA-SENHA"
```

Em ~30 s os painéis do Grafana começam a se mover. `Ctrl+C` para parar.

Ver as mensagens cruas chegando no broker:

```bash
mosquitto_sub -h localhost -u flowcount -P "TROQUE-ESTA-SENHA" -t 'fabrica/#' -v
```

Ver os dados já gravados no banco:

```bash
docker exec -it saap-postgres psql -U saap -d saap \
  -c 'SELECT * FROM producao ORDER BY recebido_em DESC LIMIT 5;'
```

---

## 11. Apontar os nós ESP32 para a Pi


No firmware de cada nó, configure:

```
MQTT_BROKER = "192.168.1.50"   // IP fixo da Pi
MQTT_PORT   = 1883
TOPICO      = "fabrica/setorA/bancada/B01/evento"
```

Teste a publicação de um nó a partir do PC antes de mexer no firmware:

```powershell
# instale o mosquitto no Windows ou rode o simulador apontando para a Pi:
python .\simulador\simula_bancadas.py --broker 192.168.1.50 `
  --mqtt-user flowcount --mqtt-password "TROQUE-ESTA-SENHA"
```

---

## 12. Garantir que sobe sozinho após queda de energia

Já está resolvido:

- o serviço do Docker é habilitado no boot pelo instalador (`systemctl is-enabled docker` → `enabled`);
- os containers têm `restart: unless-stopped` no `docker-compose.yml`.

Teste de verdade: `sudo reboot`, espere 2 min, reconecte e rode `docker compose ps`
(rode dentro de `~/saap-servidor`). Os 4 serviços devem estar "running" sem você fazer nada.

---

## 13. Manutenção

| Tarefa | Comando (dentro de `~/saap-servidor`) |
|---|---|
| Ver status | `docker compose ps` |
| Ver logs | `docker compose logs -f` |
| Parar tudo | `docker compose down` (não apaga os dados) |
| Subir de novo | `docker compose up -d` |
| Atualizar imagens | `docker compose pull && docker compose up -d` |
| Limpar lixo do Docker | `docker system prune -f` |
| Backup do PostgreSQL | `docker exec saap-postgres pg_dump -U saap saap > backup-saap-$(date +%F).sql` |
| Backup do Grafana | `docker run --rm -v saap-servidor_grafana_data:/data -v $PWD:/backup alpine tar czf /backup/grafana-backup.tgz /data` |

> O nome do volume começa com o nome da pasta (`saap-servidor_...`). Confirme com `docker volume ls`.

---

## 14. Problemas comuns

| Sintoma | Causa provável / solução |
|---|---|
| Raio / aviso de "under-voltage" | Fonte fraca. Use a fonte 27 W oficial do kit. |
| Pi trava ou reinicia sob carga | Cooler não instalado ou cartão ruim. Instale o cooler; considere SSD USB. |
| `saap.local` não resolve | Use o IP direto. No Windows, instale o "Bonjour" ou use o IP. |
| Grafana abre mas painel vazio | Nenhum dado ainda. Rode o simulador (passo 10). |
| `node-red` reiniciando nos logs | Erro de conexão. Veja `docker compose logs node-red`. Confirme que `mosquitto` e `postgres` estão "running". |
| Painel "evento gravado" no Node-RED sempre vazio | A senha do Postgres não foi configurada no node "Gravar evento" (ver passo 8) — o insert está falhando silenciosamente; veja `docker compose logs node-red` para o erro real. |
| Grafana sem data source / dashboard e log com `provisioning ... permission denied` | As pastas copiadas não têm leitura para o uid 472. Rode `chmod -R a+rX grafana mosquitto postgres` e `docker compose restart grafana`. |
| Log com `database is locked` (Grafana) | SQLite no cartão SD. Já mitigado com `GF_DATABASE_WAL=true` no compose; se persistir, migre o boot para SSD USB. |
| Gráficos com horário errado | Relógio da Pi. `timedatectl` deve mostrar "synchronized: yes". Sem internet no boot, a Pi 5 tem RTC de hardware — ligue-a à internet ao menos uma vez para sincronizar. |
| Dados não aparecem no PostgreSQL | Veja o formato da mensagem MQTT (passo 10) — o campo `ts` precisa ser ISO 8601 com fuso, ex.: `2026-09-09T14:22:31-03:00`. Confira também a aba Debug do Node-RED: se o evento aparecer como "inválido", o payload não bateu com o formato esperado. |
| Nós ESP32 não conectam | Firewall do roteador isolando dispositivos, ou IP do broker errado no firmware. Teste com `mosquitto_sub` na Pi enquanto o nó tenta publicar. |
| Painel não abre pelo endereço `.ts.net` depois de um reboot | `sudo tailscale serve status` (ou `funnel status`). Se estiver vazio, re-rode `sudo tailscale serve --bg 3000` — ou crie o serviço systemd da seção 16. |
| `tailscale up` falha com "would exceed device/user limit" | Plano grátis: 3 usuários / 100 dispositivos. Remova nós antigos no admin console ou use compartilhamento de nó (seção 16, passo 3, Opção B). |

---

## 15. Segurança antes de usar "de verdade"

- Mosquitto: já pede senha (`password_file`, passo 8) — falta só TLS antes de
  expor além da LAN, e não há ACL por tópico (qualquer autenticado publica ou
  assina em qualquer tópico).
- PostgreSQL: já pede usuário/senha (`POSTGRES_PASSWORD` no `.env`) — só troque
  o valor padrão de `.env.example` antes de qualquer uso real.
- Node-RED: o editor em `:1880` não tem login por padrão. `node-red/settings.js`
  já existe no repositório — falta só adicionar `adminAuth` nele antes de
  expor além da LAN de teste.
- Grafana: senha forte no `.env`, cadastro e acesso anônimo desativados (já no `docker-compose.yml`).
- Não exponha as portas 1883/1880/3000 direto na internet — use o Tailscale
  (seção 16). Só o Grafana deve sair; MQTT, Postgres e o editor do Node-RED
  ficam só na LAN.

---

## 16. Acesso remoto com Tailscale

Para acessarem o painel **de fora da rede local**, sem
mexer no roteador e mesmo com CGNAT da operadora. O Tailscale roda **no host da
Pi** (não em container) e passa a alcançar a porta 3000 que o Docker já publica.
**Só o Grafana é exposto** — Mosquitto (1883), PostgreSQL (5432) e o editor
do Node-RED (1880) continuam só na LAN.

Três modos, do mais privado para o mais aberto. Comece pelo 1/2 para o time; ligue
o 3 só quando precisar do link público (avaliadores, pitch) e desligue depois.

### 16.1. Instalar e conectar (na Pi)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --hostname=cara
```

Abra a URL de login que aparece e autentique (conta Google/GitHub/e-mail — essa
conta vira a "dona" do tailnet). Confira:

```bash
tailscale status      # deve listar "cara" com um IP 100.x.y.z
tailscale ip -4
```

### 16.2. No admin console (<https://login.tailscale.com/admin/machines>)

- Abra o nó `cara` → menu **⋯ → Disable key expiry** (senão o nó desconecta
  sozinho em ~6 meses e pode cair no meio do projeto).
- **DNS:** confirme que **MagicDNS** está habilitado (permite acessar por `http://cara:3000`).

### 16.3. Dar acesso aos integrantes — escolha uma opção

- **Opção A — mesmo tailnet:** admin console → **Users → Invite external users**.
  Plano grátis: até 3 usuários (cabe o grupo). Cada um instala o app Tailscale
  (Windows / Android / iOS) e entra.
- **Opção B — compartilhar só o nó da Pi:** admin console → nó `cara` → **Share** →
  gerar link para a conta Tailscale de cada integrante. Não consome os 3 assentos
  e basta se eles só precisam ver o painel.

Com o Tailscale ligado no aparelho, o painel abre em **`http://cara:3000`**.

### 16.4. (Opcional) HTTPS privado dentro do tailnet

```bash
sudo tailscale serve --bg 3000
sudo tailscale serve status
```

Passa a responder também em **`https://cara.<seu-tailnet>.ts.net`** (só para
membros do tailnet). O nome do tailnet aparece em `tailscale status`.

Quando usar `serve` (ou `funnel`), descomente no `docker-compose.yml`, serviço
`grafana`, e ajuste o nome:

```yaml
      - GF_SERVER_ROOT_URL=https://cara.SEU-TAILNET.ts.net/
      - GF_SERVER_ENFORCE_DOMAIN=false
```

e aplique: `docker compose up -d grafana`.

### 16.5. (Opcional) Link público

1. Admin console → **DNS** → habilitar **HTTPS Certificates**.
2. Admin console → **Access controls** → garantir que o nó pode usar Funnel
   (bloco `nodeAttrs` com `"attr": ["funnel"]`; o console sugere o trecho).
3. Na Pi:

```bash
sudo tailscale funnel --bg 3000
sudo tailscale funnel status
```

URL pública (qualquer pessoa com o link, sem instalar nada):
**`https://cara.<seu-tailnet>.ts.net`**.

Desligar quando não precisar mais:

```bash
sudo tailscale funnel --https=443 off
```

> **Antes de ligar o Funnel:** senha forte no `.env` (o `docker-compose.yml` já
> desliga cadastro e acesso anônimo). Nunca rode `funnel`/`serve` apontando para
> 5432 (PostgreSQL), 1880 (Node-RED) ou 1883 (MQTT).

### 16.6. Sobreviver ao reboot

- `tailscaled` já instala como serviço systemd habilitado — volta no boot com a
  autenticação salva.
- A config de `serve`/`funnel` é persistida pelas versões atuais do Tailscale.
  **Verifique após um `sudo reboot`** com `tailscale serve status`. Se voltar vazio,
  crie o serviço:

```bash
sudo tee /etc/systemd/system/ts-serve.service >/dev/null <<'EOF'
[Unit]
Description=Tailscale serve Grafana
After=tailscaled.service
Wants=tailscaled.service

[Service]
Type=oneshot
ExecStart=/usr/bin/tailscale serve --bg 3000
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable --now ts-serve.service
```

(troque `serve` por `funnel` no `ExecStart` se for o caso).

### 16.7. Verificação

1. `tailscale status` na Pi lista `cara` e os aparelhos dos integrantes.
2. No celular de um integrante, **com Tailscale ligado e no 4G**: abrir
   `http://cara:3000` → login do Grafana → dashboard "SAAP — Produção em tempo real".
3. Se ativou `serve`/`funnel`: repetir com `https://cara.<tailnet>.ts.net`
   (o Funnel deve abrir até num aparelho **sem** Tailscale).

4. `sudo reboot` na Pi; após ~2 min, repetir o passo 2 sem tocar em nada.
5. Rodar o simulador na Pi e ver os painéis se moverem pela URL remota:
   `python3 ~/saap-servidor/simulador/simula_bancadas.py --broker localhost --mqtt-user flowcount --mqtt-password "TROQUE-ESTA-SENHA"`.
