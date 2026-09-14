# Relatório detalhado - Etapa 3

## 1. Identificação

- **Projeto:** Movimentador de Contas e Rastreabilidade
- **Integrantes:** Bruno Ferreira, Kennedy Silva e Vinicius dos Anjos
- **Etapa didática:** Trilha de Auditoria e Triggers Automáticos
- **Script principal:** `scripts/04_audit_setup.sql`

## 2. Objetivo

Esta etapa cria uma trilha técnica separada do workflow. Sempre que uma linha de `contas_workflow` ou `movimentacoes` é inserida, atualizada ou excluída por uma operação autorizada, o trigger registra silenciosamente quem iniciou a sessão, quando ocorreu, qual foi a operação e quais eram os estados anterior e novo.

No documento oficial, toda a auditoria, simulação e perícia pertence à Etapa 3. Para facilitar o desenvolvimento solicitado, este projeto separa a instalação da auditoria nesta entrega e deixa os testes ofensivos para a Etapa 4 didática.

## 3. Estrutura de `audit.logged_actions`

| Coluna | Conteúdo |
|---|---|
| `id` | identificador sequencial do log |
| `schema_name` | schema da tabela afetada |
| `table_name` | tabela afetada |
| `session_user_name` | usuário que abriu a conexão |
| `effective_user_name` | usuário efetivo da função `SECURITY DEFINER` |
| `transaction_id` | identificador da transação PostgreSQL |
| `transaction_started_at` | início lógico da transação |
| `occurred_at` | instante real em que o trigger foi executado |
| `action` | `I`, `U` ou `D` |
| `old_data` | linha anterior em JSONB |
| `new_data` | linha posterior em JSONB |
| `client_address` | endereço do cliente, quando disponível |
| `application_name` | identificação do cliente PostgreSQL |

## 4. Uso de JSONB para OLD e NEW

JSONB permite guardar o estado completo da linha sem criar uma coluna de auditoria para cada atributo da tabela original.

| Operação | `old_data` | `new_data` |
|---|---|---|
| INSERT | `NULL` | linha inserida |
| UPDATE | linha antes da alteração | linha depois da alteração |
| DELETE | linha removida | `NULL` |

A constraint valida essa combinação. Portanto, não é possível inserir um log de `UPDATE` sem os dois estados, por exemplo.

## 5. Função de auditoria

`audit.fn_log_workflow_changes()` é uma função trigger em PL/pgSQL com `SECURITY DEFINER`.

Esse modo é necessário porque o operador não possui `INSERT` em `audit.logged_actions`. Quando o trigger é disparado, a função utiliza os privilégios controlados de seu proprietário para registrar o evento.

O `search_path` da função foi fixado em `pg_catalog, audit`. Essa proteção evita que um usuário crie objetos com nomes semelhantes em outro schema para desviar a resolução de nomes dentro de uma função privilegiada.

## 6. Tabelas auditadas

Foram associados triggers `AFTER INSERT OR UPDATE OR DELETE` a:

- `workflow.contas_workflow`;
- `workflow.movimentacoes`.

Essas são exatamente as duas tabelas exigidas pelo professor. Comentários continuam com autoria e timestamp no próprio registro, mas não foram adicionados à trilha técnica para não ampliar o escopo definido.

## 7. Proteção e imutabilidade

O acesso direto à tabela e à sequência da auditoria é revogado de:

- `PUBLIC`;
- `role_operacional`;
- `role_gestao`;
- `role_admin_workflow`.

Depois, `role_admin_workflow` recebe somente `SELECT`. Assim, `usr_dba_admin` consegue investigar, mas não inserir, alterar ou excluir os registros da trilha.

O proprietário da tabela e os superusuários continuam com poderes administrativos inerentes ao PostgreSQL. Em produção, essas identidades devem ter uso excepcional, controle de acesso rigoroso e monitoramento externo.

## 8. O que acontece dentro de uma transação

O registro de auditoria participa da mesma transação da alteração original. Isso preserva consistência: se a operação de negócio for revertida com `ROLLBACK`, o log criado por ela também é revertido.

Essa característica é correta para registrar mudanças efetivamente confirmadas, mas não substitui logs externos do servidor para tentativas fracassadas ou transações abortadas.

## 9. Limite técnico das tentativas negadas

Um trigger de tabela só executa depois que o PostgreSQL aceita o comando e alcança a tabela. Quando o operador tenta um `DELETE` sem privilégio, o SGBD rejeita o comando antes do trigger.

Portanto:

- alterações válidas e autorizadas: aparecem em `audit.logged_actions`;
- comandos barrados por permissão: aparecem na saída do `psql` e no log do servidor;
- não se deve inserir manualmente uma falsa ocorrência na auditoria para representar o erro.

Esse comportamento está de acordo com o enunciado, que aceita erros de permissão registrados no log do servidor ou capturados nos testes.

## 10. Como executar e demonstrar

Após as Etapas 1 e 2:

```bash
psql -U postgres -f scripts/04_audit_setup.sql
```

O script apresenta:

1. os eventos associados aos dois triggers;
2. confirmação de que o DBA consulta a auditoria;
3. confirmação de que o DBA não exclui a auditoria;
4. confirmação de que o operador nem consulta a auditoria.

Na apresentação, explicar:

> “O operador não recebe acesso ao schema de auditoria. A função privilegiada grava o evento por ele e captura `SESSION_USER`, `OLD`, `NEW`, transação e timestamp. O DBA funcional pode consultar, mas não editar a trilha.”

## 11. Próxima etapa

A Etapa 4 didática irá:

- tentar excluir e alterar movimentações como operador;
- tentar ler `credencial_hash`;
- tentar alterar o valor de uma conta;
- executar uma movimentação e comentário válidos;
- consultar as views como gestor;
- reconstruir a autoria das mudanças pela trilha.

## 12. Conclusão

A trilha criada separa evidência técnica de dados operacionais e protege o log contra escrita dos perfis comuns. O uso de JSONB mantém os estados anterior e novo, enquanto os metadados de sessão e transação permitem reconstruir quem realizou cada mudança válida e em qual momento.

