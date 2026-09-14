-- Schema do SAAP no PostgreSQL.
-- Roda automaticamente SÓ na primeira inicialização do volume postgres_data
-- (imagem oficial do Postgres executa tudo em /docker-entrypoint-initdb.d
-- em ordem alfabética, uma única vez, quando o data dir está vazio).

CREATE TABLE IF NOT EXISTS producao (
    id            BIGSERIAL PRIMARY KEY,
    bancada       TEXT NOT NULL,
    evt_id        TEXT,                          -- identificador do evento no nó (station+sessão+sequência); ainda opcional, ver nota abaixo
    ocorrido_em   TIMESTAMPTZ NOT NULL,           -- horário real da passagem, gerado no ESP32 ("ts" do payload MQTT)
    recebido_em   TIMESTAMPTZ NOT NULL DEFAULT now(), -- horário em que o Node-RED gravou o evento
    delta         INTEGER NOT NULL DEFAULT 1,
    origem        TEXT,                          -- "sensor" nos eventos reais; usado por simuladores/testes manuais
    total_turno   INTEGER,                       -- contador local do nó, quando enviado
    total_hora    INTEGER                        -- contador local do nó, quando enviado
);

COMMENT ON TABLE producao IS
    'Um registro por passagem de peça confirmada. RF03: reenvio do mesmo evento não deve '
    'aumentar o total — ver os dois índices únicos abaixo.';
COMMENT ON COLUMN producao.evt_id IS
    'Hoje o firmware do FlowCount NÃO envia este campo (só o simulador envia). Enquanto isso não '
    'mudar, a deduplicação cai para o índice por (bancada, ocorrido_em) logo abaixo.';

-- Deduplicação "forte": quando o nó já enviar evt_id (estação+sessão+sequência),
-- o mesmo evento reenviado nunca gera uma segunda linha.
CREATE UNIQUE INDEX IF NOT EXISTS producao_bancada_evtid_uniq
    ON producao (bancada, evt_id)
    WHERE evt_id IS NOT NULL;

-- Deduplicação "de hoje": enquanto o payload não traz evt_id, dois eventos da mesma
-- bancada com o EXATO mesmo timestamp são tratados como o mesmo evento reenviado.
-- Isso reproduz o comportamento que o InfluxDB tinha antes da migração (chave =
-- measurement+tag+timestamp) — é frágil (dois eventos reais no mesmo instante colidiriam),
-- mas é o que dá para garantir sem o evt_id. Ver checklist: "Incluir session e sequence
-- no payload MQTT".
CREATE UNIQUE INDEX IF NOT EXISTS producao_bancada_ts_uniq
    ON producao (bancada, ocorrido_em)
    WHERE evt_id IS NULL;

-- Consultas do dashboard: produção por período/hora/minuto e última comunicação.
CREATE INDEX IF NOT EXISTS producao_bancada_ocorrido_idx ON producao (bancada, ocorrido_em);
CREATE INDEX IF NOT EXISTS producao_bancada_recebido_idx ON producao (bancada, recebido_em);
