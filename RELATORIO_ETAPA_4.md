# Relatório detalhado - Etapa 4 didática e resultado final

## 1. Enquadramento

O PDF oficial possui três etapas de implementação. Para atender à solicitação de entregas separadas, a parte final da Etapa 3 oficial foi organizada como **Etapa 4 didática**:

- simulação de violações;
- execução de operações válidas;
- investigação forense;
- parecer técnico e coleta de evidências.

Scripts utilizados:

- `scripts/05_attack_simulation.sql`;
- `scripts/06_forensic_queries.sql`.

## 2. Objetivo

Comprovar que as permissões da Etapa 2 bloqueiam ações indevidas e que a auditoria da Etapa 3 registra as ações válidas com autoria, horário e estados `OLD`/`NEW`.

## 3. Cenários ofensivos

| Cenário | Usuário | Comando | Resultado esperado |
|---|---|---|---|
| A1 | `usr_auditor_op` | `DELETE` em `movimentacoes` | `permission denied` |
| A2 | `usr_auditor_op` | `UPDATE` em `movimentacoes` | `permission denied` |
| B1 | `usr_auditor_op` | `SELECT credencial_hash` | `permission denied` |
| B2 | `usr_auditor_op` | alteração de `valor_aproximado` | `permission denied` |
| C | `usr_auditor_op` | movimentação, atualização limitada e comentário | sucesso |
| Gestão negada | `usr_coordenador_gestao` | `SELECT` na tabela-base | `permission denied` |
| Gestão válida | `usr_coordenador_gestao` | `SELECT` na view gerencial | sucesso |

## 4. Preparação repetível

O script cria uma conta com código único no formato `CTA-TESTE-AAAAMMDDHHMMSSmmm`. Isso permite repetir a simulação sem apagar execuções anteriores e preserva uma linha do tempo crescente de evidências.

A preparação é feita pelo administrador. Em seguida, o `psql` abre conexões diretas com cada usuário. A conexão direta é importante porque `SESSION_USER` precisa refletir `usr_auditor_op`, e não o administrador que iniciou o arquivo.

## 5. Operação válida

O cenário C utiliza uma transação com três comandos:

1. insere a movimentação Auditoria → Central de Guias;
2. atualiza somente o setor atual e o status da conta;
3. insere um comentário contextual.

Se qualquer comando válido falhar, `ON_ERROR_STOP` encerra o script e a transação não deve ser tratada como concluída. O trigger registra:

- um `INSERT` em `movimentacoes`;
- um `UPDATE` em `contas_workflow`, com `OLD` e `NEW`;
- autoria `usr_auditor_op` nas duas alterações auditadas.

O comentário não está na tabela de auditoria porque o requisito do professor limitou os triggers a contas e movimentações. A autoria do comentário continua registrada em `workflow.comentarios`.

## 6. Teste gerencial

Depois da operação, o script conecta como `usr_coordenador_gestao`. O acesso à tabela `contas_workflow` deve falhar, enquanto `vw_gestao_setores` deve retornar os indicadores atualizados.

Isso comprova que a gestão enxerga a informação necessária sem receber acesso indiscriminado às tabelas-base.

## 7. Consultas forenses

O script `06_forensic_queries.sql` apresenta oito blocos:

1. linha do tempo completa da auditoria;
2. contagem de ações por usuário, tabela e operação;
3. ações produzidas por `usr_auditor_op`;
4. comparação entre valores `OLD` e `NEW`;
5. histórico de negócio com conta, setores e executor;
6. matriz dos privilégios que sustentam a imutabilidade;
7. contagem de `INSERT`, `UPDATE` e `DELETE` auditados em movimentações;
8. consistência entre o setor atual e o destino da última movimentação.

## 8. Interpretação esperada

Depois de uma execução limpa da sequência completa:

- as quatro tentativas ofensivas do operador devem aparecer como erros no terminal;
- a consulta de colunas públicas deve funcionar;
- a movimentação e o comentário válidos devem ser concluídos;
- a tabela `logged_actions` deve atribuir ao operador o `INSERT` da movimentação e o `UPDATE` da conta;
- o gestor deve falhar na tabela-base e funcionar na view;
- os testes de privilégio devem retornar `FALSE` para `UPDATE`/`DELETE` de movimentações e leitura do hash;
- o teste de consistência deve retornar `TRUE` para a conta criada pela simulação.

## 9. Evidências reais necessárias

Este repositório fornece os testes, mas não fabrica prints. As evidências dependem da execução no PostgreSQL da equipe.

Devem ser adicionados ao GitHub:

- saída de `05_attack_simulation.sql` com os erros e sucessos;
- saída de `06_forensic_queries.sql` com autoria e timestamps;
- opcionalmente, prints do terminal ou do pgAdmin;
- se acessível, trecho do log do PostgreSQL com as tentativas negadas.

O arquivo `evidencias/README.md` contém os comandos de captura e o checklist.

## 10. Parecer forense

Com base na configuração e nos resultados esperados, o parecer a ser confirmado pelas saídas reais é:

> O perfil operacional não possui privilégios para atualizar ou excluir registros da tabela de movimentações e não consegue consultar a coluna de credencial. As tentativas são rejeitadas pelo SGBD antes de alcançar os triggers. A operação operacional autorizada produz registros na trilha `audit.logged_actions`, contendo usuário da sessão, timestamp, identificador da transação e os estados anterior e posterior. O perfil gerencial permanece restrito às views consolidadas. A tabela de auditoria é consultável pelo DBA funcional, mas não pode ser alterada ou excluída por ele.

Esse parecer só deve ser apresentado como comprovado após a equipe anexar as saídas obtidas na própria instalação.

## 11. Roteiro de apresentação

1. Mostrar a estrutura dos schemas e tabelas.
2. Explicar as três roles e seus limites.
3. Exibir a matriz de privilégios da Etapa 2.
4. Mostrar `logged_actions` e os triggers.
5. Executar o script ofensivo.
6. Destacar as mensagens `permission denied`.
7. Mostrar a operação válida e a conta no novo setor.
8. Executar as consultas forenses.
9. Apontar `session_user_name = usr_auditor_op`.
10. Comparar `OLD` e `NEW` da conta.
11. Explicar por que tentativas negadas estão no terminal/log, não na tabela do trigger.
12. Encerrar com o princípio de não alteração do MV.

## 12. Conclusão

O resultado final conecta modelagem, segurança e auditoria. As permissões impedem adulterações pelo operador, as views minimizam a exposição para a gestão e a trilha preserva evidências estruturadas das ações aceitas pelo banco. As saídas reais da execução completam o relatório forense exigido para a entrega final.

