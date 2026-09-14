# Node-RED oficial + o node de PostgreSQL, já instalado no userDir (/data).
#
# node_red_data é um volume NOMEADO (vazio na primeira subida): o Docker copia
# o conteúdo que a imagem tem em /data — inclusive este node_modules — para
# dentro do volume nesse primeiro boot. Depois disso o volume manda; para
# atualizar o node instalado, é preciso `docker compose down -v` (apaga o
# volume) ou entrar no container e rodar o npm install manualmente.
FROM nodered/node-red:5.0.7

USER root
WORKDIR /data
RUN npm install --omit=dev node-red-contrib-postgresql@0.16.2 \
    && chown -R node-red:node-red /data
USER node-red
