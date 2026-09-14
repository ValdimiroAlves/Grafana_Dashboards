-- Define "turno" pelo horário real da passagem (ocorrido_em), não por um
-- contador que o nó precisaria enviar e resetar sozinho. Funciona com
-- hardware real hoje mesmo — o firmware do FlowCount não manda nem precisa
-- mandar nada além de bancada/ts/delta.
--
-- Ajuste os horários abaixo se os turnos reais forem diferentes; é a única
-- função a editar, todas as consultas que usam turno passam por aqui.
CREATE OR REPLACE FUNCTION turno_do_horario(momento TIMESTAMPTZ)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE
        WHEN EXTRACT(HOUR FROM momento AT TIME ZONE 'America/Sao_Paulo') >= 6
         AND EXTRACT(HOUR FROM momento AT TIME ZONE 'America/Sao_Paulo') < 14
            THEN 'Turno 1 (06h-14h)'
        WHEN EXTRACT(HOUR FROM momento AT TIME ZONE 'America/Sao_Paulo') >= 14
         AND EXTRACT(HOUR FROM momento AT TIME ZONE 'America/Sao_Paulo') < 22
            THEN 'Turno 2 (14h-22h)'
        ELSE 'Turno 3 (22h-06h)'
    END;
$$;

COMMENT ON FUNCTION turno_do_horario(TIMESTAMPTZ) IS
    'Turno calculado pelo horário local (America/Sao_Paulo) do evento, não por '
    'contador auto-reportado pelo nó. IMMUTABLE: mesmo instante sempre dá o '
    'mesmo turno, então dá pra indexar/materializar se um dia precisar.';
