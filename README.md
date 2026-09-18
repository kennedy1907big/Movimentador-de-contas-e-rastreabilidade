# Movimentador de Contas e Rastreabilidade

Projeto prático da disciplina **Administração de Banco de Dados (DBA)**.

## Identificação

- **Instituição:** AEMS
- **Disciplina:** Administração de Banco de Dados (DBA)
- **Projeto:** Movimentador de Contas e Rastreabilidade
- **Integrantes:**
  - Bruno Ferreira
  - Kennedy Silva
  - Vinicius dos Anjos
- **SGBD:** PostgreSQL 14 ou superior
- **Situação:** implementação técnica concluída; evidências reais pendentes de execução local

> O nome da instituição não aparece nos documentos fornecidos e deve ser preenchido antes do envio final.

## 1. Objetivo

Provisionar, modelar, proteger e auditar o banco próprio do sistema satélite **Movimentador de Contas e Rastreabilidade**.

O banco registra apenas o workflow operacional: setor atual, movimentações, responsáveis e comentários. O ERP MV permanece como fonte oficial e imutável dos dados hospitalares. Nenhum script deste projeto altera o MV.

## 2. Organização das etapas

O PDF oficial apresenta três etapas. Para permitir entregas separadas, o projeto foi organizado em quatro marcos didáticos:

| Marco deste repositório | Conteúdo | Correspondência oficial |
|---|---|---|
| Etapa 1 | banco, schemas, tabelas e carga | Etapa 1 |
| Etapa 2 | RBAC, menor privilégio, SCRAM e LGPD | Etapa 2 |
| Etapa 3 | tabela e triggers de auditoria | primeira parte da Etapa 3 |
| Etapa 4 | ataques, perícia e parecer | parte final da Etapa 3 |

Essa divisão não altera o escopo do professor; apenas separa a implementação em entregas acumulativas.



## 4. Pré-requisitos

- PostgreSQL 14 ou superior;
- cliente `psql`;
- usuário administrativo com permissão para criar banco, extensão e roles;
- acesso local ou autorizado à instância de testes;
- execução em ambiente de desenvolvimento/homologação, nunca no MV produtivo.

Os scripts usam comandos do `psql`, como `\connect`, `\gexec`, `\gset` e `\echo`. A execução recomendada é pelo terminal ou pelo **SQL Shell (psql)** do Windows.

## 5. Execução completa

Executar obrigatoriamente na ordem numérica:

```bash
psql -U postgres -f scripts/01_setup_database.sql
psql -U postgres -f scripts/02_seed_data.sql
psql -U postgres -f scripts/03_security_rbac.sql
psql -U postgres -f scripts/04_audit_setup.sql
psql -U postgres -f scripts/05_attack_simulation.sql
psql -U postgres -f scripts/06_forensic_queries.sql
```

Para uma demonstração realmente limpa após testes anteriores, o banco pode ser
removido **somente no ambiente de laboratório** e recriado pela sequência acima:

```bash
psql -U postgres -d postgres \
  -c "DROP DATABASE IF EXISTS movimentador_contas WITH (FORCE);"
```

Esse comando apaga definitivamente o banco do exercício. Conferir o nome do
banco antes de executá-lo e nunca utilizá-lo em um ambiente institucional.

Para salvar evidências no Linux, macOS ou Git Bash:

```bash
psql -U postgres -f scripts/05_attack_simulation.sql \
  > evidencias/05_attack_simulation_output.txt 2>&1

psql -U postgres -f scripts/06_forensic_queries.sql \
  > evidencias/06_forensic_queries_output.txt 2>&1
```

No PowerShell:

```powershell
psql -U postgres -f scripts/05_attack_simulation.sql *> evidencias/05_attack_simulation_output.txt
psql -U postgres -f scripts/06_forensic_queries.sql *> evidencias/06_forensic_queries_output.txt
```

## 6. Senhas do laboratório

O script `03_security_rbac.sql` cria usuários exclusivamente para demonstração:

| Usuário | Role | Senha didática |
|---|---|---|
| `usr_auditor_op` | `role_operacional` | `Lab_Auditor_2026` |
| `usr_coordenador_gestao` | `role_gestao` | `Lab_Gestao_2026` |
| `usr_dba_admin` | `role_admin_workflow` | `Lab_Dba_2026` |

As senhas são armazenadas pelo PostgreSQL em SCRAM-SHA-256, mas permanecem documentadas porque o laboratório precisa ser reproduzível. Em um ambiente real, elas devem ser substituídas e retiradas do repositório.

Para exigir SCRAM também durante a conexão, o `pg_hba.conf` da instância deve usar `scram-sha-256`. Exemplo local a ser validado pelo administrador:

```text
host    movimentador_contas    all    127.0.0.1/32    scram-sha-256
```

Não alterar o `pg_hba.conf` de um servidor institucional sem autorização.

## 7. Resumo dos scripts

| Script | Função |
|---|---|
| `01_setup_database.sql` | cria banco, schemas, tabelas, constraints e índices |
| `02_seed_data.sql` | insere setores, usuários, contas, movimentações e comentários fictícios |
| `03_security_rbac.sql` | revoga `PUBLIC`, cria roles/logins, aplica menor privilégio e views LGPD |
| `04_audit_setup.sql` | cria `audit.logged_actions`, função privilegiada e triggers |
| `05_attack_simulation.sql` | executa tentativas negadas e operação válida com usuários reais de banco |
| `06_forensic_queries.sql` | reconstrói autoria, `OLD`/`NEW`, cronologia e integridade |

## 8. Arquitetura

```mermaid
flowchart TD
    MV["ERP MV - fonte oficial"] -->|"consulta somente leitura"| APP["Aplicação satélite"]
    APP --> WF["Schema workflow"]
    WF --> AU["Triggers de auditoria"]
    AU --> LOG["Schema audit"]
```

O projeto não implementa conexão real com o MV. Essa integração depende de autorização da TI e deve ser estritamente `READ ONLY`.

### Modelo relacional

```mermaid
erDiagram
    SETORES ||--o{ USUARIOS : possui
    SETORES ||--o{ CONTAS_WORKFLOW : detem
    SETORES ||--o{ MOVIMENTACOES : origem
    SETORES ||--o{ MOVIMENTACOES : destino
    USUARIOS ||--o{ MOVIMENTACOES : executa
    USUARIOS ||--o{ COMENTARIOS : escreve
    CONTAS_WORKFLOW ||--o{ MOVIMENTACOES : registra
    CONTAS_WORKFLOW ||--o{ COMENTARIOS : recebe
```

## 9. Decisões de modelagem

- **Banco próprio:** `movimentador_contas` isola o workflow do ERP.
- **Segregação por schemas:** `workflow` contém negócio e `audit` contém evidências.
- **Integridade:** PK, FK, `UNIQUE`, `NOT NULL` e `CHECK` protegem a consistência.
- **Imutabilidade operacional:** o operador insere histórico, mas não possui `UPDATE` ou `DELETE` em `movimentacoes`.
- **Valor financeiro:** `NUMERIC(14,2)` evita erros de ponto flutuante.
- **Rastreabilidade temporal:** `TIMESTAMPTZ` preserva instantes com referência de fuso.
- **Credenciais:** hashes da aplicação e usuários SCRAM; nunca senha de paciente ou dado clínico.
- **Minimização:** não há nome, CPF, diagnóstico ou prontuário de pacientes.
- **Índices:** priorizam conta, setor, usuário e cronologia.

## 10. Matriz RBAC

| Recurso/ação | Operacional | Gestão | Administração |
|---|:---:|:---:|:---:|
| consultar setores e contas | sim | somente views | sim |
| consultar histórico | sim | somente consolidado | sim |
| inserir movimentação | sim | não | sim |
| atualizar setor/status atual | sim, só essas colunas | não | sim |
| alterar/excluir movimentação | não | não | sim |
| inserir comentário | sim | não | sim |
| ler `credencial_hash` | não | não | sim |
| consultar auditoria | não | não | sim |
| alterar/excluir auditoria | não | não | não pela role funcional |

Superusuários conservam poderes inerentes ao PostgreSQL e devem ter uso excepcional.

## 11. Views LGPD

`workflow.vw_gestao_setores` apresenta totais, status, valores consolidados e tempo médio por setor.

`workflow.vw_fluxo_resumido` apresenta volume de movimentações por origem e destino.

Nenhuma das views expõe hash de credencial, usuário individual ou identificador de paciente.

## 12. Trilha de auditoria

`audit.logged_actions` registra:

- schema e tabela;
- `SESSION_USER` e usuário efetivo;
- transação;
- timestamp da transação e instante da ocorrência;
- ação `I`, `U` ou `D`;
- `OLD` e `NEW` em JSONB;
- endereço do cliente e nome da aplicação, quando disponíveis.

A função `audit.fn_log_workflow_changes()` usa `SECURITY DEFINER` e `search_path` fixo. O operador não acessa a tabela de log; o trigger grava silenciosamente com privilégios controlados.

## 13. Simulação ofensiva

O script `05_attack_simulation.sql` cria uma conta exclusiva para cada execução e testa:

1. `DELETE` indevido em movimentações;
2. `UPDATE` indevido em movimentações;
3. leitura de `credencial_hash`;
4. alteração do valor da conta;
5. movimentação e comentário válidos;
6. gestão acessando tabela-base;
7. gestão acessando view segura;
8. DBA consultando a auditoria.

Os quatro primeiros acessos indevidos e a consulta gerencial à tabela-base devem retornar `permission denied`.

## 14. Relatório forense

O script `06_forensic_queries.sql` comprova:

- quem executou cada alteração válida;
- quando e em qual transação a alteração ocorreu;
- quais eram os valores `OLD` e `NEW`;
- quais privilégios o operador não possui;
- que o DBA funcional não pode apagar a trilha;
- se o setor atual corresponde ao destino da última movimentação.

### Limite técnico importante

Tentativas negadas por privilégio não acionam triggers, pois o PostgreSQL barra o comando antes de alcançar a tabela. A prova dessas tentativas é a saída `permission denied` do script 05 e, quando acessível, o log do servidor. A tabela `logged_actions` registra alterações que chegaram ao trigger e foram confirmadas na transação.

### Parecer técnico a confirmar pela execução

> O perfil operacional não consegue alterar ou excluir movimentações históricas nem consultar hashes de credenciais. A operação autorizada produz registros de auditoria com autoria, timestamp e estados anterior/posterior. O perfil gerencial permanece limitado a views consolidadas. O DBA funcional consulta a auditoria, mas não possui privilégios de escrita sobre ela.

As saídas reais devem ser anexadas em `evidencias/` antes da entrega. Não foram fabricadas evidências, pois elas precisam vir da instância PostgreSQL usada pela equipe.

## 15. Resultados esperados

Após `02_seed_data.sql`:

| Entidade | Quantidade |
|---|---:|
| setores | 4 |
| usuários da aplicação | 4 |
| contas iniciais | 3 |
| movimentações iniciais | 4 |
| comentários iniciais | 4 |

Após `05_attack_simulation.sql`, cada execução acrescenta uma nova conta de teste, uma movimentação válida e um comentário. A auditoria registra a criação administrativa da conta, a inserção da movimentação e a atualização operacional da conta.


## 16. Checklist final

- [ ] preencher o nome da instituição;
- [ ] executar os scripts de 01 a 06 na ordem;
- [ ] confirmar todos os resultados da matriz RBAC;
- [ ] salvar as mensagens de acesso negado;
- [ ] salvar a consulta `OLD`/`NEW` e a autoria;
- [ ] adicionar saídas ou prints em `evidencias/`;
- [ ] conferir se nenhum hash foi exposto em prints;
- [ ] subir todos os arquivos para o GitHub;
- [ ] testar novamente a partir de um banco limpo antes da apresentação.

#ETAPA 1
![alt text](image-1.png)
![alt text](image-2.png)
![alt text](image-3.png)
![alt text](image-4.png)

#ETAPA 2
![alt text](image-5.png)
![alt text](image-6.png)
![alt text](image-7.png)
![alt text](image-8.png)
![alt text](image-9.png)
![alt text](image-10.png)
![alt text](image-11.png)
![alt text](image-12.png)
![alt text](image-13.png)
![alt text](image-14.png)
![alt text](image-15.png)
![alt text](image-16.png)
![alt text](image-17.png)
![alt text](image-18.png)
![alt text](image-19.png)
![alt text](image-20.png)
![alt text](image-21.png)
![alt text](image-22.png)
![alt text](image-23.png)

#ETAPA 3
![alt text](image-24.png)
![alt text](image-25.png)
![alt text](image-26.png)
![alt text](image-27.png)
![alt text](image-28.png)

#ETAPA 4
![alt text](image-29.png)
![alt text](image-30.png)
![alt text](image-31.png)
![alt text](image-32.png)
![alt text](image-33.png)
