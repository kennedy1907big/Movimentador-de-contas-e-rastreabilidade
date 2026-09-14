# Entrega acumulativa - Etapa 2

## Identificação

- **Projeto:** Movimentador de Contas e Rastreabilidade
- **Disciplina:** Administração de Banco de Dados (DBA)
- **Integrantes:** Bruno Ferreira, Kennedy Silva e Vinicius dos Anjos
- **Instituição:** preencher antes da entrega

## Conteúdo

Esta entrega inclui a Etapa 1 completa e acrescenta a Etapa 2 de RBAC e LGPD:

```text
scripts/
├── 01_setup_database.sql
├── 02_seed_data.sql
└── 03_security_rbac.sql
```

Relatórios incluídos:

- `docs/RELATORIO_ETAPA_1.md`;
- `docs/RELATORIO_ETAPA_2.md`.

## Execução

```bash
psql -U postgres -f scripts/01_setup_database.sql
psql -U postgres -f scripts/02_seed_data.sql
psql -U postgres -f scripts/03_security_rbac.sql
```

O terceiro script deve ser executado como `postgres` ou por outro usuário com `CREATEROLE` e privilégios administrativos no banco.

## Resultado esperado

- `PUBLIC` sem privilégios amplos;
- três roles funcionais `NOLOGIN`;
- três usuários de banco com credenciais SCRAM-SHA-256;
- operador sem `DELETE`/`UPDATE` no histórico;
- `credencial_hash` protegida por coluna;
- gestão restrita às views consolidadas;
- matriz final com resultados obtidos iguais aos esperados.

## Senhas de laboratório

| Usuário | Senha |
|---|---|
| `usr_auditor_op` | `Lab_Auditor_2026` |
| `usr_coordenador_gestao` | `Lab_Gestao_2026` |
| `usr_dba_admin` | `Lab_Dba_2026` |

Essas senhas são exclusivamente didáticas e devem ser trocadas em qualquer uso fora da atividade.

