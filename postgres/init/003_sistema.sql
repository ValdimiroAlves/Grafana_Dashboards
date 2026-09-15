-- Métricas de saúde do servidor (tela "Sistema") e do broker MQTT
-- (telas "Sistema" e "Diagnóstico"). Séries temporais simples — um
-- snapshot a cada ~30s, gravado pelo Node-RED.

CREATE TABLE IF NOT EXISTS sistema_metricas (
    id               BIGSERIAL PRIMARY KEY,
    capturado_em     TIMESTAMPTZ NOT NULL DEFAULT now(),
    carga_cpu_1min   REAL,   -- os.loadavg()[0] da Raspberry (não do container — ver node-red pid: host)
    memoria_uso_pct  REAL,   -- (total - livre) / total * 100
    temperatura_c    REAL    -- /sys/class/thermal/thermal_zone0/temp, dividido por 1000
);

CREATE INDEX IF NOT EXISTS sistema_metricas_capturado_idx
    ON sistema_metricas (capturado_em);

COMMENT ON TABLE sistema_metricas IS
    'Snapshot periódico da Raspberry Pi real. Requer node-red com pid: host '
    '(docker-compose.yml) e /sys/class/thermal montado — ver README.md.';

CREATE TABLE IF NOT EXISTS broker_stats (
    id                          BIGSERIAL PRIMARY KEY,
    capturado_em                TIMESTAMPTZ NOT NULL DEFAULT now(),
    clientes_conectados         INTEGER,
    mensagens_recebidas_total   BIGINT,
    uptime_segundos             BIGINT
);

CREATE INDEX IF NOT EXISTS broker_stats_capturado_idx
    ON broker_stats (capturado_em);

COMMENT ON TABLE broker_stats IS
    'Snapshot periódico dos tópicos $SYS/broker/... do próprio Mosquitto '
    '(publicados por padrão a cada 10s, sem precisar mudar mosquitto.conf).';
