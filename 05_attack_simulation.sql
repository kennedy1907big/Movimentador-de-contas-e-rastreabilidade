-- ============================================================================
-- PROJETO: Movimentador de Contas e Rastreabilidade
-- ETAPA 4 DIDATICA: Simulacao ofensiva e operacoes validas
-- ARQUIVO: 05_attack_simulation.sql
-- OBSERVACAO: no PDF, este conteudo integra oficialmente a Etapa 3.
-- ============================================================================

\set ON_ERROR_STOP on
\connect movimentador_contas

SET client_encoding = 'UTF8';
SET TIME ZONE 'America/Campo_Grande';

\echo '============================================================'
\echo 'PREPARACAO DO CENARIO PELO ADMINISTRADOR'
\echo '============================================================'

-- Codigo unico permite repetir a simulacao sem apagar evidencias anteriores.
SELECT
    'CTA-TESTE-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS')
        AS codigo_teste
\gset

INSERT INTO workflow.contas_workflow (
    codigo_conta,
    convenio,
    valor_aproximado,
    setor_atual_id,
    data_entrada_fluxo,
    status_conta
)
SELECT
    :'codigo_teste',
    'Convenio Laboratorio',
    1500.00,
    s.id,
    CURRENT_TIMESTAMP,
    'EM_ANALISE'
FROM workflow.setores AS s
WHERE s.nome = 'Auditoria';

SELECT
    c.id AS conta_teste_id,
    so.id AS setor_origem_id,
    sd.id AS setor_destino_id,
    u.id AS usuario_aplicacao_id
FROM workflow.contas_workflow AS c
CROSS JOIN workflow.setores AS so
CROSS JOIN workflow.setores AS sd
CROSS JOIN workflow.usuarios AS u
WHERE c.codigo_conta = :'codigo_teste'
  AND so.nome = 'Auditoria'
  AND sd.nome = 'Central de Guias'
  AND u.login_corporativo = 'ana.auditoria'
\gset

\echo 'Conta de teste criada:' :codigo_teste

-- ---------------------------------------------------------------------------
-- CONEXAO DIRETA COMO OPERADOR
-- A senha de laboratorio e Lab_Auditor_2026.
-- ---------------------------------------------------------------------------
\connect movimentador_contas usr_auditor_op
SET TIME ZONE 'America/Campo_Grande';

SELECT SESSION_USER AS usuario_da_sessao, CURRENT_USER AS usuario_efetivo;

\echo '============================================================'
\echo 'CENARIO A1 - DELETE INDEVIDO NO HISTORICO (DEVE FALHAR)'
\echo '============================================================'
\set ON_ERROR_STOP off

DELETE FROM workflow.movimentacoes
WHERE id = (
    SELECT MIN(id) FROM workflow.movimentacoes
);

\echo '============================================================'
\echo 'CENARIO A2 - UPDATE INDEVIDO NO HISTORICO (DEVE FALHAR)'
\echo '============================================================'

UPDATE workflow.movimentacoes
SET observacoes = 'Historico adulterado'
WHERE id = (
    SELECT MIN(id) FROM workflow.movimentacoes
);

\echo '============================================================'
\echo 'CENARIO B1 - LEITURA DE CREDENCIAL RESTRITA (DEVE FALHAR)'
\echo '============================================================'

SELECT login_corporativo, credencial_hash
FROM workflow.usuarios;

\echo '============================================================'
\echo 'CENARIO B2 - ALTERACAO DE VALOR DA CONTA (DEVE FALHAR)'
\echo '============================================================'

UPDATE workflow.contas_workflow
SET valor_aproximado = 0
WHERE id = :conta_teste_id;

-- A partir daqui, qualquer erro e inesperado e interrompe o script.
\set ON_ERROR_STOP on

\echo '============================================================'
\echo 'CONSULTA AUTORIZADA DE COLUNAS PUBLICAS (DEVE FUNCIONAR)'
\echo '============================================================'

SELECT id, login_corporativo, nome_completo, setor_id, status
FROM workflow.usuarios
ORDER BY id;

\echo '============================================================'
\echo 'CENARIO C - MOVIMENTACAO E COMENTARIO VALIDOS'
\echo '============================================================'

BEGIN;

INSERT INTO workflow.movimentacoes (
    conta_id,
    setor_origem_id,
    setor_destino_id,
    usuario_executor_id,
    movimentado_em,
    observacoes
)
VALUES (
    :conta_teste_id,
    :setor_origem_id,
    :setor_destino_id,
    :usuario_aplicacao_id,
    CURRENT_TIMESTAMP,
    'Operacao valida: Auditoria para Central de Guias.'
);

UPDATE workflow.contas_workflow
SET setor_atual_id = :setor_destino_id,
    status_conta = 'ENCAMINHADA'
WHERE id = :conta_teste_id
  AND setor_atual_id = :setor_origem_id;

INSERT INTO workflow.comentarios (
    conta_id,
    usuario_autor_id,
    comentado_em,
    descricao
)
VALUES (
    :conta_teste_id,
    :usuario_aplicacao_id,
    CURRENT_TIMESTAMP,
    'Guia recebida. Conta transferida para a Central de Guias.'
);

COMMIT;

SELECT
    c.codigo_conta,
    s.nome AS setor_atual,
    c.status_conta
FROM workflow.contas_workflow AS c
JOIN workflow.setores AS s ON s.id = c.setor_atual_id
WHERE c.id = :conta_teste_id;

-- ---------------------------------------------------------------------------
-- TESTE DO PERFIL DE GESTAO
-- A senha de laboratorio e Lab_Gestao_2026.
-- ---------------------------------------------------------------------------
\connect movimentador_contas usr_coordenador_gestao
SET TIME ZONE 'America/Campo_Grande';

\echo '============================================================'
\echo 'GESTAO CONSULTANDO TABELA BASE (DEVE FALHAR)'
\echo '============================================================'
\set ON_ERROR_STOP off

SELECT * FROM workflow.contas_workflow LIMIT 1;

\set ON_ERROR_STOP on

\echo '============================================================'
\echo 'GESTAO CONSULTANDO VIEW SEGURA (DEVE FUNCIONAR)'
\echo '============================================================'

SELECT *
FROM workflow.vw_gestao_setores
ORDER BY setor;

-- ---------------------------------------------------------------------------
-- VERIFICACAO DA AUDITORIA PELO DBA
-- A senha de laboratorio e Lab_Dba_2026.
-- ---------------------------------------------------------------------------
\connect movimentador_contas usr_dba_admin
SET TIME ZONE 'America/Campo_Grande';

\echo '============================================================'
\echo 'REGISTROS GERADOS PELA OPERACAO VALIDA'
\echo '============================================================'

SELECT
    id,
    table_name,
    session_user_name,
    action,
    occurred_at,
    old_data,
    new_data
FROM audit.logged_actions
WHERE
    (
        table_name = 'contas_workflow'
        AND COALESCE(new_data, old_data)->>'codigo_conta' = :'codigo_teste'
    )
    OR
    (
        table_name = 'movimentacoes'
        AND COALESCE(new_data, old_data)->>'conta_id' = :'conta_teste_id'
    )
ORDER BY occurred_at, id;

\echo '============================================================'
\echo 'FIM DA SIMULACAO'
\echo 'Guardar a saida deste terminal como evidencia do trabalho.'
\echo '============================================================'

