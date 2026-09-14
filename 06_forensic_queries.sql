-- ============================================================================
-- PROJETO: Movimentador de Contas e Rastreabilidade
-- ETAPA 4 DIDATICA: Consultas forenses e parecer tecnico
-- ARQUIVO: 06_forensic_queries.sql
-- OBSERVACAO: no PDF, este conteudo integra oficialmente a Etapa 3.
-- ============================================================================

\set ON_ERROR_STOP on
\connect movimentador_contas usr_dba_admin

SET client_encoding = 'UTF8';
SET TIME ZONE 'America/Campo_Grande';

\echo '============================================================'
\echo '1. LINHA DO TEMPO COMPLETA DA AUDITORIA'
\echo '============================================================'

SELECT
    a.id AS log_id,
    a.occurred_at,
    a.transaction_id,
    a.session_user_name AS autor_da_sessao,
    a.table_name,
    CASE a.action
        WHEN 'I' THEN 'INSERT'
        WHEN 'U' THEN 'UPDATE'
        WHEN 'D' THEN 'DELETE'
    END AS operacao,
    CASE
        WHEN a.table_name = 'contas_workflow'
            THEN COALESCE(a.new_data, a.old_data)->>'codigo_conta'
        WHEN a.table_name = 'movimentacoes'
            THEN c.codigo_conta
    END AS codigo_conta,
    a.old_data,
    a.new_data
FROM audit.logged_actions AS a
LEFT JOIN workflow.contas_workflow AS c
       ON c.id = NULLIF(
           COALESCE(a.new_data, a.old_data)->>'conta_id',
           ''
       )::BIGINT
WHERE a.schema_name = 'workflow'
ORDER BY a.occurred_at, a.id;

\echo '============================================================'
\echo '2. AUTORIA E QUANTIDADE DE ACOES POR USUARIO'
\echo '============================================================'

SELECT
    session_user_name AS autor_da_sessao,
    table_name,
    action,
    COUNT(*) AS quantidade,
    MIN(occurred_at) AS primeira_ocorrencia,
    MAX(occurred_at) AS ultima_ocorrencia
FROM audit.logged_actions
GROUP BY session_user_name, table_name, action
ORDER BY autor_da_sessao, table_name, action;

\echo '============================================================'
\echo '3. OPERACOES DO USUARIO OPERACIONAL'
\echo '============================================================'

SELECT
    id,
    occurred_at,
    table_name,
    action,
    old_data,
    new_data
FROM audit.logged_actions
WHERE session_user_name = 'usr_auditor_op'
ORDER BY occurred_at, id;

\echo '============================================================'
\echo '4. COMPARACAO OLD E NEW DAS CONTAS ALTERADAS'
\echo '============================================================'

SELECT
    id AS log_id,
    occurred_at,
    session_user_name,
    old_data->>'codigo_conta' AS codigo_conta,
    old_data->>'setor_atual_id' AS setor_anterior_id,
    new_data->>'setor_atual_id' AS setor_novo_id,
    old_data->>'status_conta' AS status_anterior,
    new_data->>'status_conta' AS status_novo
FROM audit.logged_actions
WHERE table_name = 'contas_workflow'
  AND action = 'U'
ORDER BY occurred_at, id;

\echo '============================================================'
\echo '5. MOVIMENTACOES REGISTRADAS COM AUTORIA DE NEGOCIO'
\echo '============================================================'

SELECT
    m.id AS movimentacao_id,
    c.codigo_conta,
    so.nome AS setor_origem,
    sd.nome AS setor_destino,
    u.login_corporativo AS executor_registrado,
    m.movimentado_em,
    m.observacoes
FROM workflow.movimentacoes AS m
JOIN workflow.contas_workflow AS c ON c.id = m.conta_id
JOIN workflow.setores AS so ON so.id = m.setor_origem_id
JOIN workflow.setores AS sd ON sd.id = m.setor_destino_id
JOIN workflow.usuarios AS u ON u.id = m.usuario_executor_id
ORDER BY m.movimentado_em, m.id;

\echo '============================================================'
\echo '6. VERIFICACAO DA IMUTABILIDADE PARA O OPERADOR'
\echo '============================================================'

SELECT *
FROM (
    VALUES
        (
            'DELETE em movimentacoes',
            has_table_privilege(
                'usr_auditor_op',
                'workflow.movimentacoes',
                'DELETE'
            ),
            FALSE
        ),
        (
            'UPDATE em movimentacoes',
            has_table_privilege(
                'usr_auditor_op',
                'workflow.movimentacoes',
                'UPDATE'
            ),
            FALSE
        ),
        (
            'SELECT em credencial_hash',
            has_column_privilege(
                'usr_auditor_op',
                'workflow.usuarios',
                'credencial_hash',
                'SELECT'
            ),
            FALSE
        ),
        (
            'DELETE na trilha de auditoria pelo DBA',
            has_table_privilege(
                'usr_dba_admin',
                'audit.logged_actions',
                'DELETE'
            ),
            FALSE
        )
) AS matriz(privilegio_testado, possui_privilegio, esperado)
ORDER BY privilegio_testado;

\echo '============================================================'
\echo '7. BUSCA DE UPDATE OU DELETE NO HISTORICO DE MOVIMENTACOES'
\echo '============================================================'

SELECT
    COUNT(*) FILTER (WHERE action = 'U') AS updates_auditados,
    COUNT(*) FILTER (WHERE action = 'D') AS deletes_auditados,
    COUNT(*) FILTER (WHERE action = 'I') AS inserts_auditados
FROM audit.logged_actions
WHERE table_name = 'movimentacoes';

\echo '============================================================'
\echo '8. INTEGRIDADE ENTRE SETOR ATUAL E ULTIMA MOVIMENTACAO'
\echo '============================================================'

WITH ultima_movimentacao AS (
    SELECT DISTINCT ON (m.conta_id)
        m.conta_id,
        m.setor_destino_id,
        m.movimentado_em
    FROM workflow.movimentacoes AS m
    ORDER BY m.conta_id, m.movimentado_em DESC, m.id DESC
)
SELECT
    c.codigo_conta,
    s_atual.nome AS setor_atual,
    s_destino.nome AS destino_da_ultima_movimentacao,
    um.movimentado_em,
    (c.setor_atual_id = um.setor_destino_id) AS consistente
FROM workflow.contas_workflow AS c
JOIN ultima_movimentacao AS um ON um.conta_id = c.id
JOIN workflow.setores AS s_atual ON s_atual.id = c.setor_atual_id
JOIN workflow.setores AS s_destino ON s_destino.id = um.setor_destino_id
ORDER BY c.codigo_conta;

\echo '============================================================'
\echo 'PARECER TECNICO RESUMIDO'
\echo '============================================================'
\echo 'As operacoes autorizadas aparecem em audit.logged_actions.'
\echo 'As tentativas negadas nao chegam ao trigger: a prova e a mensagem'
\echo 'permission denied do script 05 e, quando disponivel, o log do servidor.'
\echo 'O operador nao possui UPDATE/DELETE no historico nem acesso ao hash.'

