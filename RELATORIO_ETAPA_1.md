# Relatório detalhado - Etapa 1

## 1. Identificação

- **Projeto:** Movimentador de Contas e Rastreabilidade
- **Disciplina:** Administração de Banco de Dados (DBA)
- **Integrantes:** Bruno Ferreira, Kennedy Silva e Vinicius dos Anjos
- **Etapa:** Provisionamento de Instância e Modelagem Física do Banco Próprio
- **Tecnologia adotada:** PostgreSQL 14 ou superior

## 2. Finalidade desta etapa

A Etapa 1 constrói a base sobre a qual serão aplicados o controle de acesso e a auditoria nas etapas seguintes. O objetivo foi criar um ambiente isolado, transformar o modelo conceitual fornecido em tabelas relacionais e inserir uma massa de dados suficiente para demonstrar o fluxo de contas entre os setores.

O projeto não substitui o ERP MV. O MV permanece como fonte oficial e imutável. O banco `movimentador_contas` registra somente informações necessárias ao workflow: setor atual, movimentações, responsáveis e comentários.

## 3. Atendimento aos requisitos do professor

| Requisito | Implementação | Local no projeto |
|---|---|---|
| Banco dedicado | banco `movimentador_contas` | início de `01_setup_database.sql` |
| Schema de negócio | schema `workflow` | `01_setup_database.sql` |
| Schema de auditoria | schema `audit`, reservado para a Etapa 3 | `01_setup_database.sql` |
| Tabela de setores | `workflow.setores` | `01_setup_database.sql` |
| Tabela de usuários | `workflow.usuarios` | `01_setup_database.sql` |
| Tabela de contas | `workflow.contas_workflow` | `01_setup_database.sql` |
| Tabela de movimentações | `workflow.movimentacoes` | `01_setup_database.sql` |
| Tabela de comentários | `workflow.comentarios` | `01_setup_database.sql` |
| PK, FK, UNIQUE e NOT NULL | constraints nomeadas nas cinco tabelas | `01_setup_database.sql` |
| 4 setores | Auditoria, Central de Guias, Faturamento e Recurso de Glosa | `02_seed_data.sql` |
| 4 usuários | quatro cadastros fictícios vinculados aos setores | `02_seed_data.sql` |
| 3 contas em trânsito | `CTA-000010`, `CTA-000011` e `CTA-000012` | `02_seed_data.sql` |
| Movimentações e anotações | quatro movimentações e quatro comentários | `02_seed_data.sql` |

Todos os itens obrigatórios da Etapa 1 foram cobertos. As estruturas de RBAC e de trilha de auditoria foram conscientemente deixadas para as etapas indicadas pelo enunciado.

## 4. Arquitetura escolhida

### 4.1 Isolamento do ambiente

Foi adotado um banco chamado `movimentador_contas`. Essa separação impede que tabelas do sistema satélite sejam misturadas às tabelas do ERP legado. A consequência prática é que manutenção, backup, permissões e evolução do workflow podem ser administrados de forma independente.

Dentro do banco foram criados dois schemas:

- `workflow`: contém as cinco tabelas operacionais desta etapa;
- `audit`: reserva o espaço lógico para a trilha de auditoria que será criada na Etapa 3.

Um schema funciona como uma divisão lógica dentro do mesmo banco. Ele organiza objetos e permite que, posteriormente, sejam aplicadas permissões distintas a cada conjunto.

### 4.2 Não interferência com o MV

O modelo armazena `codigo_conta` como referência lógica. Não há qualquer conexão ou comando de escrita dirigido ao banco MV. A decisão segue a premissa central do documento da Direção: o ERP continua como fonte oficial, enquanto o novo banco controla apenas a movimentação processual.

### 4.3 Fluxo modelado

O fluxo usado na massa de testes segue a sequência conceitual:

```text
Auditoria -> Central de Guias -> Faturamento -> Recurso de Glosa
```

A tabela `contas_workflow` informa onde a conta está agora. A tabela `movimentacoes` preserva por onde ela passou. Assim, o estado atual e o histórico não são confundidos.

## 5. Explicação das tabelas

### 5.1 `setores`

Representa as áreas que recebem as contas. O nome é único para impedir dois cadastros idênticos. O campo `status` aceita somente `ATIVO` ou `INATIVO`, evitando valores livres como “ativado”, “sim” ou “funcionando”.

### 5.2 `usuarios`

Representa os usuários da aplicação, não as contas de login do PostgreSQL. Cada usuário pertence a um setor por meio de `setor_id`. O login corporativo é único e o perfil é limitado a `OPERACIONAL`, `GESTAO` ou `ADMINISTRADOR`.

A credencial é guardada como hash bcrypt. No banco, um hash não revela diretamente a senha original. Os valores de senha presentes no script são somente dados de teste descartáveis e nunca devem ser reutilizados em produção.

Na Etapa 2, a coluna `credencial_hash` deverá ficar invisível para operadores e gestores, conforme a exigência de segurança em nível de coluna.

### 5.3 `contas_workflow`

Registra uma referência da conta, convênio, valor aproximado, setor atual, momento de entrada e status operacional. O código da conta é único. O valor usa `NUMERIC(14,2)`, apropriado para dinheiro, e possui uma regra que proíbe números negativos.

O modelo não contém nome do paciente, CPF, diagnóstico ou prontuário. Essa minimização reduz a exposição de dados pessoais e sensíveis.

### 5.4 `movimentacoes`

Registra cada transferência de uma conta. São obrigatórios:

- a conta movimentada;
- o setor de origem;
- o setor de destino;
- o usuário executor;
- o instante da movimentação.

Uma constraint impede que origem e destino sejam o mesmo setor. As chaves estrangeiras impedem a gravação de IDs inexistentes. O uso de `ON DELETE RESTRICT` evita apagar uma conta, um setor ou um usuário que já possua histórico relacionado.

### 5.5 `comentarios`

Registra ocorrências como “Erro de MAT/MED” ou “Aguardando guia”. O comentário é ligado à conta e ao autor. A descrição é obrigatória e não pode conter apenas espaços.

Nesta etapa, o banco assegura integridade básica. A proibição de edição ou exclusão para perfis operacionais será aplicada por privilégios na Etapa 2, e o registro automático de `OLD` e `NEW` será criado na Etapa 3.

## 6. Por que os tipos foram escolhidos

| Tipo | Uso | Justificativa |
|---|---|---|
| `BIGINT GENERATED ALWAYS AS IDENTITY` | chaves primárias | gera IDs automaticamente e suporta crescimento |
| `VARCHAR(n)` | códigos, nomes e estados | aplica um limite coerente ao dado |
| `TEXT` | hash, comentários e observações | permite conteúdo de tamanho variável |
| `NUMERIC(14,2)` | valor aproximado | mantém precisão decimal para dinheiro |
| `TIMESTAMPTZ` | datas e horas operacionais | preserva o instante com informação de fuso |

O fuso da sessão foi definido como `America/Campo_Grande`. Mesmo assim, o PostgreSQL armazena `TIMESTAMPTZ` internamente de forma normalizada e o apresenta conforme o fuso da sessão, o que é mais confiável para auditoria que um horário sem referência de fuso.

## 7. Integridade aplicada

### 7.1 Chaves primárias

Toda tabela possui uma PK, garantindo que cada linha seja identificada de maneira única.

### 7.2 Chaves estrangeiras

As FKs asseguram que nenhuma movimentação ou comentário aponte para uma conta, usuário ou setor inexistente.

### 7.3 Unicidade

`setores.nome`, `usuarios.login_corporativo` e `contas_workflow.codigo_conta` são únicos. Isso evita duplicidade em campos que representam identidades de negócio.

### 7.4 Campos obrigatórios

`NOT NULL` foi aplicado a todos os dados necessários para explicar um evento. Por exemplo, não existe movimentação sem conta, origem, destino, executor ou horário.

### 7.5 Regras de domínio

Constraints `CHECK` limitam status e perfis, rejeitam valor financeiro negativo, proíbem texto obrigatório vazio e impedem uma movimentação para o mesmo setor.

## 8. Índices

O PostgreSQL cria índices automaticamente para PKs e `UNIQUE`, mas não cria índices automáticos em todas as FKs. Por isso, foram adicionados índices em colunas usadas em relacionamentos e filtros:

- usuário por setor;
- conta por setor atual;
- movimentações por conta e data;
- movimentações por setor de destino;
- movimentações por executor;
- comentários por conta e data;
- comentários por autor.

Esses índices reduzem o custo de consultas operacionais quando a base crescer. O contraponto é que todo índice ocupa espaço e gera custo de manutenção nas escritas; por isso foram criados apenas os mais justificáveis nesta fase.

## 9. Carga inicial

O script `02_seed_data.sql` começa com `TRUNCATE ... RESTART IDENTITY CASCADE`. A finalidade é permitir que a demonstração seja repetida sem duplicar linhas e com os IDs reiniciados. Isso é adequado para desenvolvimento e homologação, mas seria perigoso em produção.

Foram inseridos:

- 4 setores exigidos;
- 4 usuários fictícios;
- 3 contas fictícias, todas atualmente em trânsito;
- 4 movimentações;
- 4 comentários.

A conta `CTA-000012` possui duas movimentações, o que demonstra que uma mesma conta pode atravessar mais de um setor.

## 10. Como demonstrar em sala

### Passo 1 - explicar o isolamento

> “Criamos um banco dedicado chamado `movimentador_contas`. Dentro dele, o schema `workflow` guarda o negócio e o schema `audit` foi reservado para a auditoria da terceira etapa. Assim, não escrevemos nada no ERP MV.”

### Passo 2 - executar a estrutura

```bash
psql -U postgres -f scripts/01_setup_database.sql
```

Ao final, mostrar que os dois schemas existem e que as cinco tabelas estão no `workflow`.

### Passo 3 - executar a carga

```bash
psql -U postgres -f scripts/02_seed_data.sql
```

Mostrar a consulta de contagem. O resultado esperado é 4, 4, 3, 4 e 4 para setores, usuários, contas, movimentações e comentários.

### Passo 4 - explicar uma conta

Usar `CTA-000010` como exemplo:

1. entrou no fluxo sob responsabilidade da Auditoria;
2. recebeu comentários sobre erro de MAT/MED e espera de guia;
3. foi movimentada pela usuária `ana.auditoria`;
4. encontra-se atualmente na Central de Guias;
5. o histórico registra origem, destino, executor, horário e observação.

### Passo 5 - demonstrar uma restrição

Em um ambiente de teste, pode-se executar a instrução abaixo para provar o `CHECK` de origem e destino. Ela deve falhar, e não deve ser incluída na carga oficial:

```sql
INSERT INTO workflow.movimentacoes (
    conta_id,
    setor_origem_id,
    setor_destino_id,
    usuario_executor_id,
    observacoes
)
SELECT c.id, s.id, s.id, u.id, 'Teste invalido'
FROM workflow.contas_workflow c
JOIN workflow.setores s ON s.nome = 'Auditoria'
JOIN workflow.usuarios u ON u.login_corporativo = 'ana.auditoria'
WHERE c.codigo_conta = 'CTA-000010';
```

O erro comprova que o banco, e não somente a aplicação, impede uma transferência para o próprio setor.

## 11. Perguntas que o professor pode fazer

### Por que criar um banco separado do MV?

Para manter o ERP como fonte oficial, evitar alterações indevidas no legado, reduzir acoplamento e permitir administração própria do workflow.

### Qual a diferença entre `contas_workflow` e `movimentacoes`?

`contas_workflow` mantém o estado atual. `movimentacoes` mantém o histórico de cada troca de setor.

### Por que existe um schema `audit` vazio?

Porque a Etapa 1 exige a separação lógica desde o provisionamento, mas a tabela e os triggers de auditoria pertencem explicitamente à Etapa 3.

### O perfil em `usuarios` já protege o banco?

Não. Nesta etapa ele é um atributo de negócio. A proteção efetiva será implementada com roles e privilégios PostgreSQL na Etapa 2. Essa distinção é importante: gravar a palavra “OPERACIONAL” não concede nem revoga privilégios por si só.

### Por que não armazenar senha normal?

Porque, em caso de acesso indevido à tabela, senhas em texto puro seriam imediatamente expostas. O hash permite validar uma tentativa sem guardar a senha original.

### Este projeto já atende toda a LGPD?

Não se deve afirmar isso. A Etapa 1 aplica minimização e dados fictícios, mas conformidade integral também depende de base legal, governança, retenção, controles de acesso, procedimentos e validação institucional.

### Por que usar `TIMESTAMPTZ`?

Porque a rastreabilidade precisa de um instante exato. Um horário sem fuso pode se tornar ambíguo quando sistemas, servidores ou relatórios usam fusos diferentes.

## 12. Pontos de atenção e limitações

1. A instituição ainda precisa ser preenchida no README antes da entrega.
2. O projeto foi preparado para execução por `psql`, pois usa `\gexec` e `\connect`.
3. A carga é fictícia e reinicia as tabelas; não é um procedimento de produção.
4. A sincronização automática entre o último destino de `movimentacoes` e `contas_workflow.setor_atual_id` ainda não foi implementada. Uma função transacional poderá fazer isso em uma etapa posterior, junto às regras operacionais.
5. O modelo guarda apenas o hash local porque isso foi solicitado no exercício. Em uma implantação corporativa, SSO, Active Directory ou outro provedor de identidade pode ser preferível.
6. RBAC, mascaramento, auditoria imutável e análise forense ainda serão implementados nas Etapas 2 e 3.

## 13. Conclusão

A Etapa 1 entrega uma base relacional isolada e coerente com o cenário do hospital. O modelo distingue o estado atual da conta de seu histórico, registra autores e horários, protege relacionamentos por constraints e evita dados pessoais desnecessários. Com isso, o projeto fica preparado para receber o princípio do menor privilégio na Etapa 2 e a trilha de auditoria na Etapa 3.

