-- ============================================================================
-- PROJETO: Movimentador de Contas e Rastreabilidade
-- ETAPA 2: Controle de acesso (RBAC) e conformidade com a LGPD
-- ARQUIVO: 03_security_rbac.sql
-- AMBIENTE: pgAdmin 4
-- EXECUTAR COMO: postgres ou outro administrador com CREATEROLE
-- ============================================================================

SET client_encoding = 'UTF8';

SET TIME ZONE 'America/Campo_Grande';

SET password_encryption = 'scram-sha-256';


-- ============================================================================
-- 1. ROLES FUNCIONAIS NOLOGIN
-- ============================================================================

DO $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'role_operacional'
    ) THEN

        CREATE ROLE role_operacional
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOBYPASSRLS
            INHERIT;

    END IF;


    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'role_gestao'
    ) THEN

        CREATE ROLE role_gestao
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOBYPASSRLS
            INHERIT;

    END IF;


    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'role_admin_workflow'
    ) THEN

        CREATE ROLE role_admin_workflow
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOBYPASSRLS
            INHERIT;

    END IF;

END
$$;


-- Garante as propriedades corretas mesmo em uma reexecução.

ALTER ROLE role_operacional
    WITH NOLOGIN
         NOSUPERUSER
         NOCREATEDB
         NOCREATEROLE
         NOREPLICATION
         NOBYPASSRLS
         INHERIT;


ALTER ROLE role_gestao
    WITH NOLOGIN
         NOSUPERUSER
         NOCREATEDB
         NOCREATEROLE
         NOREPLICATION
         NOBYPASSRLS
         INHERIT;


ALTER ROLE role_admin_workflow
    WITH NOLOGIN
         NOSUPERUSER
         NOCREATEDB
         NOCREATEROLE
         NOREPLICATION
         NOBYPASSRLS
         INHERIT;


-- ============================================================================
-- 2. USUARIOS DE BANCO COM LOGIN
-- ============================================================================
-- Senhas exclusivas para laboratorio.
--
-- Em ambiente real:
-- utilizar cofre de segredos e politica de troca de senhas.
--
-- O password_encryption foi definido como SCRAM-SHA-256 anteriormente.
-- ============================================================================

DO $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'usr_auditor_op'
    ) THEN

        CREATE ROLE usr_auditor_op
            LOGIN
            PASSWORD 'Lab_Auditor_2026';

    END IF;


    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'usr_coordenador_gestao'
    ) THEN

        CREATE ROLE usr_coordenador_gestao
            LOGIN
            PASSWORD 'Lab_Gestao_2026';

    END IF;


    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'usr_dba_admin'
    ) THEN

        CREATE ROLE usr_dba_admin
            LOGIN
            PASSWORD 'Lab_Dba_2026';

    END IF;

END
$$;


-- Garante propriedades corretas dos usuarios.

ALTER ROLE usr_auditor_op
    WITH LOGIN
         PASSWORD 'Lab_Auditor_2026'
         NOSUPERUSER
         NOCREATEDB
         NOCREATEROLE
         NOREPLICATION
         NOBYPASSRLS
         INHERIT;


ALTER ROLE usr_coordenador_gestao
    WITH LOGIN
         PASSWORD 'Lab_Gestao_2026'
         NOSUPERUSER
         NOCREATEDB
         NOCREATEROLE
         NOREPLICATION
         NOBYPASSRLS
         INHERIT;


ALTER ROLE usr_dba_admin
    WITH LOGIN
         PASSWORD 'Lab_Dba_2026'
         NOSUPERUSER
         NOCREATEDB
         NOCREATEROLE
         NOREPLICATION
         NOBYPASSRLS
         INHERIT;


-- ============================================================================
-- 3. SEARCH_PATH
-- ============================================================================

ALTER ROLE usr_auditor_op
    SET search_path = workflow, public;


ALTER ROLE usr_coordenador_gestao
    SET search_path = workflow, public;


ALTER ROLE usr_dba_admin
    SET search_path = workflow, audit, public;


-- ============================================================================
-- 4. REMOCAO DE ASSOCIACOES INDEVIDAS
-- ============================================================================

REVOKE role_gestao, role_admin_workflow
FROM usr_auditor_op;


REVOKE role_operacional, role_admin_workflow
FROM usr_coordenador_gestao;


REVOKE role_operacional, role_gestao
FROM usr_dba_admin;


-- ============================================================================
-- 5. ASSOCIACAO CORRETA DAS ROLES
-- ============================================================================

GRANT role_operacional
TO usr_auditor_op;


GRANT role_gestao
TO usr_coordenador_gestao;


GRANT role_admin_workflow
TO usr_dba_admin;


-- ============================================================================
-- 6. HIGIENIZACAO DA ROLE PUBLIC
-- ============================================================================
-- Politica Zero Trust:
-- nenhum acesso amplo deve permanecer concedido por padrao.
-- ============================================================================

REVOKE ALL
ON DATABASE movimentador_contas
FROM PUBLIC;


REVOKE CREATE
ON SCHEMA public
FROM PUBLIC;


REVOKE ALL
ON SCHEMA workflow
FROM PUBLIC;


REVOKE ALL
ON SCHEMA audit
FROM PUBLIC;


REVOKE ALL
ON ALL TABLES IN SCHEMA workflow
FROM PUBLIC;


REVOKE ALL
ON ALL TABLES IN SCHEMA audit
FROM PUBLIC;


REVOKE ALL
ON ALL SEQUENCES IN SCHEMA workflow
FROM PUBLIC;


REVOKE ALL
ON ALL SEQUENCES IN SCHEMA audit
FROM PUBLIC;


REVOKE ALL
ON ALL FUNCTIONS IN SCHEMA workflow
FROM PUBLIC;


REVOKE ALL
ON ALL FUNCTIONS IN SCHEMA audit
FROM PUBLIC;


-- ============================================================================
-- 7. DEFAULT PRIVILEGES
-- ============================================================================

ALTER DEFAULT PRIVILEGES IN SCHEMA workflow
    REVOKE ALL ON TABLES
    FROM PUBLIC;


ALTER DEFAULT PRIVILEGES IN SCHEMA workflow
    REVOKE ALL ON SEQUENCES
    FROM PUBLIC;


ALTER DEFAULT PRIVILEGES IN SCHEMA workflow
    REVOKE EXECUTE ON FUNCTIONS
    FROM PUBLIC;


ALTER DEFAULT PRIVILEGES IN SCHEMA audit
    REVOKE ALL ON TABLES
    FROM PUBLIC;


ALTER DEFAULT PRIVILEGES IN SCHEMA audit
    REVOKE ALL ON SEQUENCES
    FROM PUBLIC;


ALTER DEFAULT PRIVILEGES IN SCHEMA audit
    REVOKE EXECUTE ON FUNCTIONS
    FROM PUBLIC;


-- Permite conexao ao banco somente para as roles funcionais.

GRANT CONNECT
ON DATABASE movimentador_contas
TO role_operacional,
   role_gestao,
   role_admin_workflow;


-- ============================================================================
-- 8. VIEWS SEGURAS PARA GESTAO
-- ============================================================================

CREATE OR REPLACE VIEW workflow.vw_gestao_setores
WITH (security_barrier = true)
AS
SELECT
    s.id AS setor_id,

    s.nome AS setor,

    COUNT(c.id) AS total_contas,

    COUNT(c.id)
        FILTER (
            WHERE c.status_conta <> 'FINALIZADA'
        ) AS contas_em_aberto,

    COUNT(c.id)
        FILTER (
            WHERE c.status_conta = 'FINALIZADA'
        ) AS contas_finalizadas,

    COALESCE(
        SUM(c.valor_aproximado),
        0.00
    )::NUMERIC(16,2)
        AS valor_total_aproximado,

    ROUND(
        COALESCE(
            AVG(
                EXTRACT(
                    EPOCH FROM (
                        CURRENT_TIMESTAMP -
                        c.data_entrada_fluxo
                    )
                ) / 3600.0
            ),
            0
        )::NUMERIC,
        2
    ) AS tempo_medio_permanencia_horas

FROM workflow.setores AS s

LEFT JOIN workflow.contas_workflow AS c
    ON c.setor_atual_id = s.id

GROUP BY
    s.id,
    s.nome;


COMMENT ON VIEW workflow.vw_gestao_setores IS
    'Indicadores agregados por setor, sem credenciais ou identificadores pessoais.';


-- ============================================================================
-- VIEW DE FLUXO RESUMIDO
-- ============================================================================

CREATE OR REPLACE VIEW workflow.vw_fluxo_resumido
WITH (security_barrier = true)
AS
SELECT

    so.nome AS setor_origem,

    sd.nome AS setor_destino,

    COUNT(*) AS total_movimentacoes,

    MIN(m.movimentado_em)
        AS primeira_movimentacao,

    MAX(m.movimentado_em)
        AS ultima_movimentacao

FROM workflow.movimentacoes AS m

JOIN workflow.setores AS so
    ON so.id = m.setor_origem_id

JOIN workflow.setores AS sd
    ON sd.id = m.setor_destino_id

GROUP BY
    so.nome,
    sd.nome;


COMMENT ON VIEW workflow.vw_fluxo_resumido IS
    'Fluxo consolidado entre setores sem expor usuarios ou contas individuais.';


-- Garante que PUBLIC nao possui acesso as views.

REVOKE ALL
ON workflow.vw_gestao_setores
FROM PUBLIC;


REVOKE ALL
ON workflow.vw_fluxo_resumido
FROM PUBLIC;


-- ============================================================================
-- 9. MENOR PRIVILEGIO - ROLE OPERACIONAL
-- ============================================================================

GRANT USAGE
ON SCHEMA workflow
TO role_operacional;


-- Leitura das informacoes necessarias ao fluxo.

GRANT SELECT
ON workflow.setores,
   workflow.contas_workflow,
   workflow.movimentacoes,
   workflow.comentarios
TO role_operacional;


-- ============================================================================
-- SEGURANCA EM NIVEL DE COLUNA
-- ============================================================================
-- O operador pode visualizar somente os dados publicos.
-- A coluna credencial_hash NAO recebe permissao.
-- ============================================================================

GRANT SELECT (
    id,
    login_corporativo,
    nome_completo,
    setor_id,
    status
)
ON workflow.usuarios
TO role_operacional;


-- Pode registrar novas movimentacoes.

GRANT INSERT
ON workflow.movimentacoes,
   workflow.comentarios
TO role_operacional;


-- Pode atualizar somente o setor atual e o status da conta.

GRANT UPDATE (
    setor_atual_id,
    status_conta
)
ON workflow.contas_workflow
TO role_operacional;


-- Acesso as sequencias necessarias para INSERT.

GRANT USAGE, SELECT
ON SEQUENCE
    workflow.movimentacoes_id_seq,
    workflow.comentarios_id_seq
TO role_operacional;


-- ============================================================================
-- 10. MENOR PRIVILEGIO - ROLE GESTAO
-- ============================================================================
-- Gestao recebe somente SELECT nas views consolidadas.
-- Nao recebe acesso direto as tabelas operacionais.
-- ============================================================================

GRANT USAGE
ON SCHEMA workflow
TO role_gestao;


GRANT SELECT
ON workflow.vw_gestao_setores,
   workflow.vw_fluxo_resumido
TO role_gestao;


-- ============================================================================
-- 11. ROLE ADMIN_WORKFLOW
-- ============================================================================
-- Controle administrativo completo sobre as estruturas do workflow.
-- ============================================================================

GRANT USAGE
ON SCHEMA workflow,
   audit
TO role_admin_workflow;


GRANT ALL PRIVILEGES
ON ALL TABLES IN SCHEMA workflow
TO role_admin_workflow;


GRANT ALL PRIVILEGES
ON ALL SEQUENCES IN SCHEMA workflow
TO role_admin_workflow;


GRANT CREATE
ON SCHEMA workflow,
           audit
TO role_admin_workflow;


-- ============================================================================
-- 12. MATRIZ DE CONFERENCIA DO RBAC
-- ============================================================================

SELECT *
FROM (
    VALUES

        (
            'operador_le_contas',

            has_table_privilege(
                'usr_auditor_op',
                'workflow.contas_workflow',
                'SELECT'
            ),

            TRUE
        ),

        (
            'operador_insere_movimentacao',

            has_table_privilege(
                'usr_auditor_op',
                'workflow.movimentacoes',
                'INSERT'
            ),

            TRUE
        ),

        (
            'operador_exclui_movimentacao',

            has_table_privilege(
                'usr_auditor_op',
                'workflow.movimentacoes',
                'DELETE'
            ),

            FALSE
        ),

        (
            'operador_le_login_publico',

            has_column_privilege(
                'usr_auditor_op',
                'workflow.usuarios',
                'login_corporativo',
                'SELECT'
            ),

            TRUE
        ),

        (
            'operador_le_credencial_hash',

            has_column_privilege(
                'usr_auditor_op',
                'workflow.usuarios',
                'credencial_hash',
                'SELECT'
            ),

            FALSE
        ),

        (
            'gestao_le_view',

            has_table_privilege(
                'usr_coordenador_gestao',
                'workflow.vw_gestao_setores',
                'SELECT'
            ),

            TRUE
        ),

        (
            'gestao_le_tabela_base',

            has_table_privilege(
                'usr_coordenador_gestao',
                'workflow.contas_workflow',
                'SELECT'
            ),

            FALSE
        )

) AS matriz(
    teste,
    resultado_obtido,
    resultado_esperado
)

ORDER BY teste;


-- ============================================================================
-- 13. CONFERENCIA DAS ROLES CRIADAS
-- ============================================================================

SELECT
    rolname,
    rolcanlogin,
    rolsuper,
    rolcreatedb,
    rolcreaterole
FROM pg_roles
WHERE rolname IN (
    'role_operacional',
    'role_gestao',
    'role_admin_workflow',
    'usr_auditor_op',
    'usr_coordenador_gestao',
    'usr_dba_admin'
)
ORDER BY rolname;


-- ============================================================================
-- 14. CONFERENCIA DO FORMATO DAS CREDENCIAIS
-- ============================================================================
-- Nao exibe a senha/hash.
-- Apenas verifica se o PostgreSQL armazenou a credencial como SCRAM.
-- ============================================================================

SELECT
    rolname AS usuario,

    CASE

        WHEN rolpassword LIKE 'SCRAM-SHA-256$%'
            THEN 'SCRAM-SHA-256'

        ELSE 'VERIFICAR_CONFIGURACAO'

    END AS formato_credencial

FROM pg_authid

WHERE rolname IN (
    'usr_auditor_op',
    'usr_coordenador_gestao',
    'usr_dba_admin'
)

ORDER BY rolname;


-- ============================================================================
-- FIM DA ETAPA 2
-- ============================================================================