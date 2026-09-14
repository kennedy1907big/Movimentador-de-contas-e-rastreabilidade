# Guia simples para apresentação

## Identificação

- **Projeto:** Movimentador de Contas e Rastreabilidade
- **Disciplina:** Administração de Banco de Dados (DBA)
- **Integrantes:** Bruno Ferreira, Kennedy Silva e Vinicius dos Anjos
- **Tempo sugerido:** 8 a 12 minutos

## 1. O que o professor pediu

O professor pediu que a equipe assumisse o papel de DBA e Governança de Dados para criar o banco do sistema satélite **Movimentador de Contas e Rastreabilidade**.

O trabalho precisava demonstrar três partes principais:

1. criação e modelagem do banco;
2. segurança com roles, menor privilégio e LGPD;
3. auditoria, simulação de acessos indevidos e investigação forense.

O ERP MV continua sendo a fonte oficial das informações. Nosso banco não altera o MV; ele registra apenas o fluxo das contas entre os setores.

## 2. Divisão sugerida entre os integrantes

| Integrante | Parte sugerida |
|---|---|
| Bruno Ferreira | introdução, objetivo, Etapa 1 e modelagem |
| Kennedy Silva | Etapa 2, roles, acessos e LGPD |
| Vinicius dos Anjos | Etapa 3, auditoria, testes e conclusão |

A divisão é apenas uma sugestão. Todos devem entender o projeto completo para responder perguntas.

## 3. Fala de abertura - Bruno

> Boa noite. Nosso trabalho é o Movimentador de Contas e Rastreabilidade. A ideia é criar um banco próprio para acompanhar em qual setor uma conta hospitalar está, quem realizou cada movimentação e quais comentários foram registrados. O sistema MV continua sendo a fonte oficial. Nosso projeto funciona como uma camada separada de workflow e não realiza alterações no MV.

> Nós usamos PostgreSQL e organizamos o trabalho em seis scripts, executados em ordem. Os dois primeiros criam e alimentam o banco, o terceiro configura a segurança, o quarto cria a auditoria e os dois últimos realizam os testes e a investigação.

## 4. Etapa 1 - Banco e modelagem

### O que foi feito

- banco dedicado `movimentador_contas`;
- schema `workflow` para os dados operacionais;
- schema `audit` para a trilha de auditoria;
- cinco tabelas relacionadas;
- carga inicial com dados fictícios.

### Tabelas principais

| Tabela | Finalidade |
|---|---|
| `setores` | registra Auditoria, Central de Guias, Faturamento e Recurso de Glosa |
| `usuarios` | guarda os usuários da aplicação e o setor de cada um |
| `contas_workflow` | informa a conta, o convênio, o valor e o setor atual |
| `movimentacoes` | guarda origem, destino, executor, horário e observação |
| `comentarios` | registra ocorrências e anotações sobre a conta |

### Como foi feito

> Criamos chaves primárias para identificar os registros e chaves estrangeiras para relacionar as tabelas. Também usamos UNIQUE para impedir códigos e logins repetidos, NOT NULL para obrigar os dados importantes e CHECK para limitar status e impedir valores inválidos.

### Exemplo simples

> Quando uma conta sai da Auditoria e vai para a Central de Guias, a tabela de contas mostra a Central como setor atual. A tabela de movimentações mantém o histórico com a origem, o destino, o usuário e o horário.

### O que mostrar na tela

Executar ou mostrar o resultado de:

```sql
SELECT * FROM workflow.setores;
SELECT * FROM workflow.contas_workflow;
SELECT * FROM workflow.movimentacoes;
```

## 5. Etapa 2 - Segurança, RBAC e LGPD - Kennedy

### O que é RBAC

> RBAC é o controle de acesso baseado em papéis. Em vez de liberar permissões individualmente sem padrão, nós criamos funções de acesso e vinculamos cada usuário a uma delas.

### Roles criadas

| Role | Permissões principais |
|---|---|
| `role_operacional` | consulta dados operacionais, insere movimentações e comentários |
| `role_gestao` | consulta somente as views de resumo |
| `role_admin_workflow` | administra as tabelas e sequências do workflow |

### Usuários de teste

- `usr_auditor_op` recebe a role operacional;
- `usr_coordenador_gestao` recebe a role de gestão;
- `usr_dba_admin` recebe a role administrativa.

### Menor privilégio

> Aplicamos o princípio do menor privilégio. Cada usuário recebe somente o necessário para sua função. O operador pode inserir uma nova movimentação, mas não pode apagar ou alterar o histórico. O gestor não acessa diretamente as tabelas; ele consulta views com dados consolidados.

### LGPD

> Para reduzir a exposição, não armazenamos nome, CPF, diagnóstico ou prontuário de pacientes. Também protegemos a coluna `credencial_hash`: o operador consegue ver as colunas públicas do usuário, mas não consegue consultar o hash da credencial.

### Higienização de `PUBLIC`

> Removemos os privilégios amplos da role PUBLIC nos schemas, tabelas, sequências e funções. Depois concedemos cada acesso de forma explícita.

### Views gerenciais

- `vw_gestao_setores`: totais, contas abertas, valor aproximado e tempo médio por setor;
- `vw_fluxo_resumido`: quantidade de movimentações entre os setores.

### O que mostrar na tela

Mostrar a matriz que aparece no final de `03_security_rbac.sql`. Os resultados obtidos devem ser iguais aos esperados.

## 6. Etapa 3 - Auditoria e rastreabilidade - Vinicius

### O que foi criado

> Criamos a tabela `audit.logged_actions`. Ela registra automaticamente as mudanças feitas em `contas_workflow` e `movimentacoes`.

Cada registro de auditoria contém:

- tabela afetada;
- usuário que abriu a sessão;
- data e hora;
- número da transação;
- tipo da operação: INSERT, UPDATE ou DELETE;
- estado antigo em `OLD`;
- estado novo em `NEW`.

### Como funciona o trigger

> Os triggers ficam ligados às tabelas críticas. Quando acontece uma operação válida, a função de auditoria é chamada automaticamente. Ela utiliza SECURITY DEFINER para gravar no schema de auditoria mesmo sem dar acesso direto ao operador.

### Proteção da auditoria

> O operador e o gestor não acessam a tabela de auditoria. O DBA funcional pode consultar os registros, mas não pode inserir, alterar ou apagar a trilha.

## 7. Simulação de ataques

O script `05_attack_simulation.sql` realiza os testes pedidos pelo professor.

### Testes que devem falhar

1. operador tentando excluir uma movimentação;
2. operador tentando alterar uma movimentação;
3. operador tentando consultar `credencial_hash`;
4. operador tentando alterar o valor da conta;
5. gestor tentando consultar diretamente a tabela de contas.

Resultado esperado: mensagem `permission denied`.

### Testes que devem funcionar

1. operador consultando colunas públicas;
2. operador registrando uma movimentação válida;
3. operador adicionando um comentário;
4. gestor consultando a view gerencial;
5. DBA consultando a trilha de auditoria.

### Explicação importante

> Uma tentativa negada por falta de permissão não aparece na tabela do trigger, porque o PostgreSQL bloqueia o comando antes de ele chegar à tabela. A evidência dessa tentativa fica na saída do terminal e, quando disponível, no log do servidor. Já as alterações válidas aparecem em `audit.logged_actions`.

## 8. Investigação forense

O script `06_forensic_queries.sql` mostra:

- quem realizou cada alteração;
- quando a alteração aconteceu;
- qual conta foi alterada;
- valores anteriores e novos;
- privilégios que o operador não possui;
- consistência entre o setor atual e a última movimentação.

### O que destacar

> Na coluna `session_user_name` conseguimos identificar o usuário responsável. Em uma atualização, `old_data` mostra como a linha estava e `new_data` mostra como ela ficou. Assim, conseguimos reconstruir o incidente e comprovar a autoria.

## 9. Fala de encerramento

> Como resultado, entregamos um banco separado do MV, com integridade relacional, perfis de acesso, proteção de dados, histórico imutável para o operador e auditoria automática. Os testes comprovam que ações indevidas são bloqueadas e que ações autorizadas ficam rastreáveis. Dessa forma, o projeto atende às orientações de modelagem, segurança, LGPD e investigação definidas pelo professor.

## 10. Ordem da demonstração

1. abrir o repositório e mostrar os seis scripts;
2. mostrar os schemas `workflow` e `audit`;
3. mostrar as cinco tabelas principais;
4. mostrar os dados iniciais;
5. mostrar a matriz de permissões;
6. mostrar os triggers instalados;
7. executar ou apresentar a saída do ataque simulado;
8. destacar os erros `permission denied`;
9. mostrar uma operação válida;
10. mostrar `session_user_name`, `old_data` e `new_data`;
11. apresentar a conclusão.

## 11. Perguntas que o professor pode fazer

### Por que o banco é separado do MV?

Para evitar alterações no sistema oficial, reduzir o acoplamento e guardar somente o workflow da nova aplicação.

### Qual a diferença entre `contas_workflow` e `movimentacoes`?

`contas_workflow` mostra o estado atual. `movimentacoes` preserva o histórico de por onde a conta passou.

### Por que usar chave estrangeira?

Para impedir referências inválidas, como uma movimentação ligada a uma conta ou setor inexistente.

### Por que o operador não pode alterar movimentações?

Porque movimentações são histórico. Se o operador pudesse editá-las, a rastreabilidade perderia confiança.

### Por que a gestão usa views?

Para receber somente dados agregados necessários aos relatórios, sem acessar detalhes desnecessários.

### O que é `OLD` e `NEW`?

`OLD` representa a linha antes da alteração e `NEW` representa a linha depois da alteração.

### Por que o acesso negado não aparece no trigger?

Porque a verificação de permissão acontece antes. O comando é rejeitado sem alcançar a tabela.

### O projeto atende completamente à LGPD?

O projeto aplica minimização e controle de acesso, mas conformidade completa também depende de políticas institucionais, base legal, retenção e avaliação do DPO.

## 12. Cuidados antes de apresentar

- preencher o nome da instituição no `README.md`;
- executar os scripts de 01 a 06 na ordem;
- salvar as saídas reais na pasta `evidencias`;
- confirmar que os testes negados mostram `permission denied`;
- confirmar que a auditoria mostra `usr_auditor_op`;
- não exibir hashes de credenciais nos prints;
- cada integrante deve conhecer, pelo menos, o objetivo de todas as etapas.

