-- ============================================================================
-- PROJETO: Movimentador de Contas e Rastreabilidade
-- ETAPA 3: Trilha de auditoria e triggers automaticos
-- ARQUIVO: 04_audit_setup.sql
-- EXECUTAR COMO: postgres ou outro administrador do banco
-- ============================================================================

\set ON_ERROR_STOP on
\connect movimentador_contas

SET client_encoding = 'UTF8';
SET TIME ZONE 'America/Campo_Grande';

BEGIN;

CREATE TABLE IF NOT EXISTS audit.logged_actions (
    id                     BIGINT GENERATED ALWAYS AS IDENTITY,
    schema_name            TEXT        NOT NULL,
    table_name             TEXT        NOT NULL,
    session_user_name      TEXT        NOT NULL,
    effective_user_name    TEXT        NOT NULL,
    transaction_id         BIGINT      NOT NULL,
    transaction_started_at TIMESTAMPTZ NOT NULL,
    occurred_at            TIMESTAMPTZ NOT NULL,
    action                 CHAR(1)     NOT NULL,
    old_data               JSONB,
    new_data               JSONB,
    client_address         INET,
    application_name       TEXT,

    CONSTRAINT pk_logged_actions PRIMARY KEY (id),
    CONSTRAINT ck_logged_actions_action CHECK (action IN ('I', 'U', 'D')),
    CONSTRAINT ck_logged_actions_payload CHECK (
        (action = 'I' AND old_data IS NULL AND new_data IS NOT NULL)
        OR
        (action = 'U' AND old_data IS NOT NULL AND new_data IS NOT NULL)
        OR
        (action = 'D' AND old_data IS NOT NULL AND new_data IS NULL)
    )
);

COMMENT ON TABLE audit.logged_actions IS
    'Trilha append-only de INSERT, UPDATE e DELETE nas tabelas criticas.';
COMMENT ON COLUMN audit.logged_actions.session_user_name IS
    'Usuario que abriu a sessao e originou a operacao.';
COMMENT ON COLUMN audit.logged_actions.effective_user_name IS
    'Usuario efetivo dentro da funcao SECURITY DEFINER.';
COMMENT ON COLUMN audit.logged_actions.old_data IS
    'Estado anterior da linha; preenchido em UPDATE e DELETE.';
COMMENT ON COLUMN audit.logged_actions.new_data IS
    'Novo estado da linha; preenchido em INSERT e UPDATE.';

CREATE INDEX IF NOT EXISTS idx_logged_actions_table_time
    ON audit.logged_actions (schema_name, table_name, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_logged_actions_session_user
    ON audit.logged_actions (session_user_name, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_logged_actions_action
    ON audit.logged_actions (action, occurred_at DESC);

-- SECURITY DEFINER permite que a funcao grave no schema audit mesmo quando o
-- usuario operacional nao possui acesso direto a tabela de log.
CREATE OR REPLACE FUNCTION audit.fn_log_workflow_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, audit
AS $$
DECLARE
    v_old_data JSONB;
    v_new_data JSONB;
    v_action   CHAR(1);
BEGIN
    CASE TG_OP
        WHEN 'INSERT' THEN
            v_action := 'I';
            v_old_data := NULL;
            v_new_data := to_jsonb(NEW);
        WHEN 'UPDATE' THEN
            v_action := 'U';
            v_old_data := to_jsonb(OLD);
            v_new_data := to_jsonb(NEW);
        WHEN 'DELETE' THEN
            v_action := 'D';
            v_old_data := to_jsonb(OLD);
            v_new_data := NULL;
        ELSE
            RAISE EXCEPTION 'Operacao de auditoria nao suportada: %', TG_OP;
    END CASE;

    INSERT INTO audit.logged_actions (
        schema_name,
        table_name,
        session_user_name,
        effective_user_name,
        transaction_id,
        transaction_started_at,
        occurred_at,
        action,
        old_data,
        new_data,
        client_address,
        application_name
    )
    VALUES (
        TG_TABLE_SCHEMA,
        TG_TABLE_NAME,
        SESSION_USER,
        CURRENT_USER,
        txid_current(),
        transaction_timestamp(),
        clock_timestamp(),
        v_action,
        v_old_data,
        v_new_data,
        inet_client_addr(),
        current_setting('application_name', TRUE)
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION audit.fn_log_workflow_changes() IS
    'Captura OLD/NEW e metadados da sessao para tabelas criticas do workflow.';

DROP TRIGGER IF EXISTS trg_audit_contas_workflow
    ON workflow.contas_workflow;

CREATE TRIGGER trg_audit_contas_workflow
AFTER INSERT OR UPDATE OR DELETE
ON workflow.contas_workflow
FOR EACH ROW
EXECUTE FUNCTION audit.fn_log_workflow_changes();

DROP TRIGGER IF EXISTS trg_audit_movimentacoes
    ON workflow.movimentacoes;

CREATE TRIGGER trg_audit_movimentacoes
AFTER INSERT OR UPDATE OR DELETE
ON workflow.movimentacoes
FOR EACH ROW
EXECUTE FUNCTION audit.fn_log_workflow_changes();

-- ---------------------------------------------------------------------------
-- PROTECAO DA TRILHA
-- ---------------------------------------------------------------------------
REVOKE ALL ON audit.logged_actions FROM PUBLIC;
REVOKE ALL ON audit.logged_actions
    FROM role_operacional, role_gestao, role_admin_workflow;

REVOKE ALL ON SEQUENCE audit.logged_actions_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE audit.logged_actions_id_seq
    FROM role_operacional, role_gestao, role_admin_workflow;

REVOKE ALL ON FUNCTION audit.fn_log_workflow_changes() FROM PUBLIC;
REVOKE ALL ON FUNCTION audit.fn_log_workflow_changes()
    FROM role_operacional, role_gestao, role_admin_workflow;

-- O DBA de workflow pode investigar, mas nao inserir, atualizar ou excluir logs.
GRANT USAGE ON SCHEMA audit TO role_admin_workflow;
GRANT SELECT ON audit.logged_actions TO role_admin_workflow;

COMMIT;

-- ---------------------------------------------------------------------------
-- CONFERENCIA DA INSTALACAO
-- ---------------------------------------------------------------------------
SELECT
    event_object_schema AS schema_alvo,
    event_object_table AS tabela_alvo,
    trigger_name,
    action_timing,
    event_manipulation AS operacao
FROM information_schema.triggers
WHERE trigger_schema = 'workflow'
  AND trigger_name IN (
      'trg_audit_contas_workflow',
      'trg_audit_movimentacoes'
  )
ORDER BY tabela_alvo, operacao;

SELECT *
FROM (
    VALUES
        (
            'dba_pode_consultar_auditoria',
            has_table_privilege(
                'usr_dba_admin',
                'audit.logged_actions',
                'SELECT'
            ),
            TRUE
        ),
        (
            'dba_pode_excluir_auditoria',
            has_table_privilege(
                'usr_dba_admin',
                'audit.logged_actions',
                'DELETE'
            ),
            FALSE
        ),
        (
            'operador_pode_consultar_auditoria',
            has_table_privilege(
                'usr_auditor_op',
                'audit.logged_actions',
                'SELECT'
            ),
            FALSE
        )
) AS matriz(teste, resultado_obtido, resultado_esperado)
ORDER BY teste;

