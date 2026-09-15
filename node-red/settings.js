// Settings mínimo do Node-RED para o SAAP. Substitui o settings.js padrão da
// imagem (bind mount em /data/settings.js) — qualquer campo omitido aqui usa
// o padrão interno do próprio Node-RED, então não precisa repetir tudo.
//
// A adição real deste arquivo é o functionGlobalContext: dá acesso a `os` e
// `fs` dentro de nodes Function, sem precisar da aba "Setup" (que também
// exigiria isso aqui). É o que a tela "Sistema" usa para ler carga/memória
// (via os.loadavg()/totalmem()/freemem(), refletindo a Pi real por causa do
// `pid: host` no docker-compose.yml) e a temperatura (via fs, lendo
// /host_thermal/thermal_zone0/temp — ver o bind mount de /sys/class/thermal).
module.exports = {
    flowFile: 'flows.json',
    uiPort: process.env.PORT || 1880,

    logging: {
        console: {
            level: 'info',
            metrics: false,
            audit: false
        }
    },

    functionGlobalContext: {
        os: require('os'),
        fs: require('fs')
    },

    editorTheme: {
        projects: {
            enabled: false
        }
    }
};
