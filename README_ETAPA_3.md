# Entrega acumulativa - Etapa 3

## Identificação

- **Projeto:** Movimentador de Contas e Rastreabilidade
- **Disciplina:** Administração de Banco de Dados (DBA)
- **Integrantes:** Bruno Ferreira, Kennedy Silva e Vinicius dos Anjos
- **Instituição:** preencher antes da entrega

## Conteúdo

Esta entrega inclui as Etapas 1 e 2 e acrescenta a trilha automática de auditoria:

```text
scripts/
├── 01_setup_database.sql
├── 02_seed_data.sql
├── 03_security_rbac.sql
└── 04_audit_setup.sql
```

Relatórios incluídos:

- `docs/RELATORIO_ETAPA_1.md`;
- `docs/RELATORIO_ETAPA_2.md`;
- `docs/RELATORIO_ETAPA_3.md`.

## Execução

```bash
psql -U postgres -f scripts/01_setup_database.sql
psql -U postgres -f scripts/02_seed_data.sql
psql -U postgres -f scripts/03_security_rbac.sql
psql -U postgres -f scripts/04_audit_setup.sql
```

## Resultado esperado

- tabela protegida `audit.logged_actions`;
- triggers em `contas_workflow` e `movimentacoes`;
- captura de `I`, `U` e `D`;
- estados `OLD` e `NEW` em JSONB;
- autoria por `SESSION_USER`;
- timestamps e identificador da transação;
- operador sem acesso à auditoria;
- DBA funcional com somente `SELECT` na auditoria.

## Observação técnica

Operações barradas por falta de privilégio não chegam aos triggers. Elas serão demonstradas na Etapa 4 didática por meio da saída do terminal e, quando disponível, do log do servidor.

