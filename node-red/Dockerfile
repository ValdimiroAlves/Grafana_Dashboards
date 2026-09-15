# Node-RED oficial + o node de PostgreSQL + o flows.json deste repositório,
# tudo já dentro do userDir (/data) na hora do build.
#
# node_red_data é um volume NOMEADO (vazio na primeira subida): o Docker copia
# o conteúdo que a imagem tem em /data — node_modules E flows.json — para
# dentro do volume nesse primeiro boot. Depois disso o volume manda.
#
# Por que copiar o flows.json na imagem em vez de dar bind mount nele direto
# (como fizemos com os dashboards do Grafana)? Porque o Node-RED salva o fluxo
# escrevendo um arquivo temporário e RENOMEANDO por cima do flows.json — e não
# dá pra renomear um arquivo por cima de um ponto de bind mount (dá
# "EBUSY: resource busy or locked"). Editar pela interface (localhost:1880) e
# dar Deploy continua funcionando normalmente — só que agora salva dentro do
# volume, não direto no arquivo do repositório. Pra levar uma edição feita
# pela UI de volta pro Git, copie o arquivo de dentro do container primeiro
# (ver README.md), igual já é feito com o dashboard do Grafana.
#
# Consequência: se você editar node-red/flows.json OU node-red/settings.js no
# repo e reconstruir a imagem, isso NÃO atualiza um volume que já existe (ele
# já foi semeado uma vez). Pra aplicar uma mudança do repo a uma instalação já
# rodando, copie o arquivo pra dentro do container (docker cp) ou recrie o
# volume do zero (docker compose down -v — cuidado, isso também apaga o
# node_modules instalado e a senha do Postgres salva em flows_cred.json).
FROM nodered/node-red:5.0.7

# NÃO usar "WORKDIR /data" aqui: a imagem base define WORKDIR /usr/src/node-red
# e um ENTRYPOINT relativo (./entrypoint.sh) resolvido a partir dele. Trocar o
# WORKDIR no Dockerfile persiste na imagem final e quebra esse entrypoint
# ("stat ./entrypoint.sh: no such file or directory"). Por isso instalamos com
# "cd /data && ..." dentro do RUN, sem alterar o WORKDIR da imagem.
USER root
COPY flows.json /data/flows.json
COPY settings.js /data/settings.js
RUN cd /data \
    && npm install --omit=dev node-red-contrib-postgresql@0.16.2 \
    && chown -R node-red:node-red /data
USER node-red
