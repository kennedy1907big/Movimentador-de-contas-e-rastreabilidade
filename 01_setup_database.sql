-- ============================================================================
-- PROJETO: Movimentador de Contas e Rastreabilidade
-- ETAPA 1: Provisionamento e modelagem fisica
-- ARQUIVO: 01_setup_database.sql
-- SGBD: PostgreSQL 14 ou superior
-- ============================================================================

-- Faz o psql interromper a execucao no primeiro erro encontrado.
\set ON_ERROR_STOP on

-- O PostgreSQL nao possui CREATE DATABASE IF NOT EXISTS. A combinacao abaixo
-- consulta o catalogo e executa o CREATE DATABASE somente se ele nao existir.
-- \gexec e \connect sao comandos do cliente psql.
SELECT 'CREATE DATABASE movimentador_contas
        WITH ENCODING = ''UTF8''
        TEMPLATE = template0'
WHERE NOT EXISTS (
    SELECT 1
      FROM pg_database
     WHERE datname = 'movimentador_contas'
) \gexec

\connect movimentador_contas

SET client_encoding = 'UTF8';
SET TIME ZONE 'America/Campo_Grande';

-- Necessaria para gerar hashes de credenciais ficticias no script de carga.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

BEGIN;

-- Separacao logica entre dados do negocio e a futura infraestrutura de auditoria.
CREATE SCHEMA IF NOT EXISTS workflow;
CREATE SCHEMA IF NOT EXISTS audit;

COMMENT ON SCHEMA workflow IS
    'Dados operacionais do Movimentador de Contas e Rastreabilidade.';
COMMENT ON SCHEMA audit IS
    'Estruturas de auditoria. As tabelas e triggers serao implementadas na Etapa 3.';

-- ---------------------------------------------------------------------------
-- SETORES
-- Areas que recebem e movimentam as contas no fluxo hospitalar.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workflow.setores (
    id          BIGINT GENERATED ALWAYS AS IDENTITY,
    nome        VARCHAR(100) NOT NULL,
    status      VARCHAR(10)  NOT NULL DEFAULT 'ATIVO',
    criado_em   TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_setores PRIMARY KEY (id),
    CONSTRAINT uq_setores_nome UNIQUE (nome),
    CONSTRAINT ck_setores_status CHECK (status IN ('ATIVO', 'INATIVO'))
);

COMMENT ON TABLE workflow.setores IS
    'Setores participantes da esteira operacional de contas.';

-- ---------------------------------------------------------------------------
-- USUARIOS
-- Usuarios da aplicacao, vinculados a um setor e a um perfil funcional.
-- A credencial e armazenada somente como hash, nunca como senha em texto puro.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workflow.usuarios (
    id                BIGINT GENERATED ALWAYS AS IDENTITY,
    login_corporativo VARCHAR(100) NOT NULL,
    nome_completo     VARCHAR(150) NOT NULL,
    setor_id          BIGINT       NOT NULL,
    credencial_hash   TEXT         NOT NULL,
    perfil_acesso     VARCHAR(20)  NOT NULL,
    status            VARCHAR(10)  NOT NULL DEFAULT 'ATIVO',
    criado_em         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_usuarios PRIMARY KEY (id),
    CONSTRAINT uq_usuarios_login UNIQUE (login_corporativo),
    CONSTRAINT fk_usuarios_setor
        FOREIGN KEY (setor_id)
        REFERENCES workflow.setores (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    CONSTRAINT ck_usuarios_perfil CHECK (
        perfil_acesso IN ('OPERACIONAL', 'GESTAO', 'ADMINISTRADOR')
    ),
    CONSTRAINT ck_usuarios_status CHECK (status IN ('ATIVO', 'INATIVO')),
    CONSTRAINT ck_usuarios_login_nao_vazio CHECK (
        btrim(login_corporativo) <> ''
    ),
    CONSTRAINT ck_usuarios_nome_nao_vazio CHECK (
        btrim(nome_completo) <> ''
    )
);

COMMENT ON TABLE workflow.usuarios IS
    'Usuarios funcionais da aplicacao; nao se confundem com roles do PostgreSQL.';
COMMENT ON COLUMN workflow.usuarios.credencial_hash IS
    'Hash de autenticacao. A leitura desta coluna sera restringida na Etapa 2.';

-- ---------------------------------------------------------------------------
-- CONTAS_WORKFLOW
-- Guarda somente a referencia logica e os dados necessarios ao workflow.
-- O ERP MV permanece como fonte oficial; esta tabela nao replica o prontuario.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workflow.contas_workflow (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY,
    codigo_conta        VARCHAR(30)  NOT NULL,
    convenio            VARCHAR(100) NOT NULL,
    valor_aproximado    NUMERIC(14,2) NOT NULL,
    setor_atual_id      BIGINT       NOT NULL,
    data_entrada_fluxo  TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status_conta        VARCHAR(25)  NOT NULL DEFAULT 'RECEBIDA',

    CONSTRAINT pk_contas_workflow PRIMARY KEY (id),
    CONSTRAINT uq_contas_workflow_codigo UNIQUE (codigo_conta),
    CONSTRAINT fk_contas_workflow_setor_atual
        FOREIGN KEY (setor_atual_id)
        REFERENCES workflow.setores (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    CONSTRAINT ck_contas_workflow_valor CHECK (valor_aproximado >= 0),
    CONSTRAINT ck_contas_workflow_codigo_nao_vazio CHECK (
        btrim(codigo_conta) <> ''
    ),
    CONSTRAINT ck_contas_workflow_convenio_nao_vazio CHECK (
        btrim(convenio) <> ''
    ),
    CONSTRAINT ck_contas_workflow_status CHECK (
        status_conta IN (
            'RECEBIDA',
            'EM_ANALISE',
            'PENDENTE',
            'AGUARDANDO_GUIA',
            'EM_CONFERENCIA',
            'ENCAMINHADA',
            'DEVOLVIDA',
            'FINALIZADA'
        )
    )
);

COMMENT ON TABLE workflow.contas_workflow IS
    'Referencia logica das contas no fluxo; o MV continua sendo a fonte oficial.';

-- ---------------------------------------------------------------------------
-- MOVIMENTACOES
-- Historico do transito de cada conta entre dois setores diferentes.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workflow.movimentacoes (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY,
    conta_id            BIGINT      NOT NULL,
    setor_origem_id     BIGINT      NOT NULL,
    setor_destino_id    BIGINT      NOT NULL,
    usuario_executor_id BIGINT      NOT NULL,
    movimentado_em      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    observacoes         TEXT,

    CONSTRAINT pk_movimentacoes PRIMARY KEY (id),
    CONSTRAINT fk_movimentacoes_conta
        FOREIGN KEY (conta_id)
        REFERENCES workflow.contas_workflow (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    CONSTRAINT fk_movimentacoes_setor_origem
        FOREIGN KEY (setor_origem_id)
        REFERENCES workflow.setores (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    CONSTRAINT fk_movimentacoes_setor_destino
        FOREIGN KEY (setor_destino_id)
        REFERENCES workflow.setores (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    CONSTRAINT fk_movimentacoes_usuario_executor
        FOREIGN KEY (usuario_executor_id)
        REFERENCES workflow.usuarios (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    CONSTRAINT ck_movimentacoes_setores_diferentes CHECK (
        setor_origem_id <> setor_destino_id
    )
);

COMMENT ON TABLE workflow.movimentacoes IS
    'Historico cronologico de transferencias das contas entre setores.';

-- ---------------------------------------------------------------------------
-- COMENTARIOS
-- Ocorrencias e observacoes registradas durante o tratamento da conta.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workflow.comentarios (
    id               BIGINT GENERATED ALWAYS AS IDENTITY,
    conta_id         BIGINT      NOT NULL,
    usuario_autor_id BIGINT      NOT NULL,
    comentado_em     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    descricao        TEXT        NOT NULL,

    CONSTRAINT pk_comentarios PRIMARY KEY (id),
    CONSTRAINT fk_comentarios_conta
        FOREIGN KEY (conta_id)
        REFERENCES workflow.contas_workflow (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    CONSTRAINT fk_comentarios_usuario_autor
        FOREIGN KEY (usuario_autor_id)
        REFERENCES workflow.usuarios (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    CONSTRAINT ck_comentarios_descricao_nao_vazia CHECK (
        btrim(descricao) <> ''
    )
);

COMMENT ON TABLE workflow.comentarios IS
    'Comentarios e ocorrencias contextuais vinculados a uma conta.';

-- Indices para as chaves estrangeiras e consultas operacionais mais frequentes.
-- As constraints UNIQUE ja criam seus proprios indices automaticamente.
CREATE INDEX IF NOT EXISTS idx_usuarios_setor
    ON workflow.usuarios (setor_id);

CREATE INDEX IF NOT EXISTS idx_contas_setor_atual
    ON workflow.contas_workflow (setor_atual_id);

CREATE INDEX IF NOT EXISTS idx_movimentacoes_conta_data
    ON workflow.movimentacoes (conta_id, movimentado_em DESC);

CREATE INDEX IF NOT EXISTS idx_movimentacoes_setor_destino
    ON workflow.movimentacoes (setor_destino_id);

CREATE INDEX IF NOT EXISTS idx_movimentacoes_usuario
    ON workflow.movimentacoes (usuario_executor_id);

CREATE INDEX IF NOT EXISTS idx_comentarios_conta_data
    ON workflow.comentarios (conta_id, comentado_em DESC);

CREATE INDEX IF NOT EXISTS idx_comentarios_usuario
    ON workflow.comentarios (usuario_autor_id);

COMMIT;

-- Conferencia rapida das estruturas criadas.
SELECT schema_name
  FROM information_schema.schemata
 WHERE schema_name IN ('workflow', 'audit')
 ORDER BY schema_name;

SELECT table_schema, table_name
  FROM information_schema.tables
 WHERE table_schema IN ('workflow', 'audit')
   AND table_type = 'BASE TABLE'
 ORDER BY table_schema, table_name;

