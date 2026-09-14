# Relatório detalhado - Etapa 2

## 1. Identificação

- **Projeto:** Movimentador de Contas e Rastreabilidade
- **Disciplina:** Administração de Banco de Dados (DBA)
- **Integrantes:** Bruno Ferreira, Kennedy Silva e Vinicius dos Anjos
- **Etapa:** Controle de Acesso (RBAC) e Conformidade com a LGPD
- **Script principal:** `scripts/03_security_rbac.sql`

## 2. Objetivo

A Etapa 2 transforma o banco modelado na Etapa 1 em um ambiente controlado pelo princípio do menor privilégio. Em vez de todos os usuários acessarem todas as tabelas, cada perfil recebe somente as permissões necessárias para sua função.

Também foram aplicadas medidas de minimização: operadores não visualizam hashes de credenciais e gestores consultam informações consolidadas por views, sem acessar registros individuais.

## 3. Requisitos atendidos

| Exigência | Implementação |
|---|---|
| Higienizar `PUBLIC` | revogação no banco, schemas, tabelas, sequências e funções |
| `role_operacional` | role `NOLOGIN` com leitura operacional, inserção de movimentações/comentários e atualização limitada da conta |
| `role_gestao` | role `NOLOGIN` com `SELECT` somente nas views gerenciais |
| `role_admin_workflow` | role `NOLOGIN` com administração das tabelas e sequências do workflow |
| Três usuários de teste | `usr_auditor_op`, `usr_coordenador_gestao` e `usr_dba_admin` |
| Senhas criptografadas | `password_encryption = 'scram-sha-256'` |
| Segurança em nível de coluna | operador lê dados públicos de `usuarios`, mas não `credencial_hash` |
| View LGPD | `vw_gestao_setores` e `vw_fluxo_resumido` |
| Menor privilégio | matriz automática de conferência com `has_table_privilege` e `has_column_privilege` |

## 4. Diferença entre perfil da aplicação e role do PostgreSQL

Na Etapa 1, `workflow.usuarios.perfil_acesso` foi criado como um dado de negócio. O valor `OPERACIONAL` nessa coluna, sozinho, não protege o banco.

Na Etapa 2 foram criadas roles reais do PostgreSQL. São elas que fazem o SGBD autorizar ou negar cada comando. Essa separação é importante:

- tabela `workflow.usuarios`: identidade usada pela aplicação e pelo histórico de negócio;
- login `usr_auditor_op`: identidade que abre a sessão no PostgreSQL;
- role `role_operacional`: conjunto de privilégios herdado pelo login.

## 5. Perfis implementados

### 5.1 Operacional

O operador pode:

- consultar setores, contas, movimentações e comentários;
- consultar apenas colunas públicas da tabela `usuarios`;
- inserir movimentações;
- inserir comentários;
- atualizar somente `setor_atual_id` e `status_conta`.

O operador não pode:

- excluir ou alterar movimentações históricas;
- excluir comentários;
- visualizar `credencial_hash`;
- alterar código, convênio ou valor de uma conta;
- consultar a tabela de auditoria.

A atualização limitada da conta foi concedida para que uma movimentação válida possa alterar o setor atual sem permitir adulteração de dados financeiros. O script ofensivo executa inserção da movimentação, atualização do setor e comentário dentro da mesma transação.

### 5.2 Gestão

O perfil gerencial pode consultar somente:

- `workflow.vw_gestao_setores`;
- `workflow.vw_fluxo_resumido`.

Ele não possui `SELECT` direto nas tabelas-base. Isso reduz a exposição de identificadores individuais e deixa o acesso coerente com dashboards.

### 5.3 Administração

O administrador possui controle das tabelas e sequências do schema `workflow`. Na Etapa 3, a tabela de auditoria revoga escrita até desse perfil e concede somente leitura forense.

O superusuário PostgreSQL continua sendo tecnicamente capaz de contornar privilégios. Por isso, credenciais de superusuário devem ser restritas e monitoradas em um ambiente real.

## 6. Higienização da role `PUBLIC`

`PUBLIC` representa todos os usuários do banco. O script remove privilégios implícitos e também impede criação livre de objetos no schema `public`.

Foram revogados:

- privilégios no banco `movimentador_contas`;
- acesso aos schemas `workflow` e `audit`;
- privilégios nas tabelas e sequências existentes;
- execução de funções existentes;
- privilégios padrão sobre objetos futuros criados pelo executor.

Depois da revogação, os acessos necessários são concedidos explicitamente às roles funcionais.

## 7. Segurança em nível de coluna

O comando de concessão lista as colunas permitidas:

```sql
GRANT SELECT (
    id,
    login_corporativo,
    nome_completo,
    setor_id,
    status
) ON workflow.usuarios TO role_operacional;
```

Como `credencial_hash` não está na lista, uma consulta que tente acessá-la recebe `permission denied`. Isso atende à minimização e evita exposição desnecessária de credenciais.

## 8. Views gerenciais

### `vw_gestao_setores`

Agrupa por setor:

- total de contas;
- contas abertas;
- contas finalizadas;
- valor aproximado consolidado;
- tempo médio de permanência em horas.

### `vw_fluxo_resumido`

Agrupa movimentações por origem e destino, exibindo volume e intervalo temporal do fluxo. Não mostra o código individual da conta nem o usuário executor.

As duas views possuem agregações e são somente leitura. A opção `security_barrier` reduz possibilidades de o otimizador combinar filtros externos de maneira que exponha dados subjacentes.

## 9. SCRAM-SHA-256

O script define `password_encryption = 'scram-sha-256'` antes da criação e alteração dos usuários. Assim, as credenciais são armazenadas no catálogo no formato SCRAM.

Isso resolve o formato de armazenamento. Para exigir SCRAM na conexão, o servidor também precisa utilizar `scram-sha-256` no arquivo `pg_hba.conf`. Portanto, armazenamento da senha e regra de autenticação do servidor são controles relacionados, mas diferentes.

As senhas incluídas são exclusivas do laboratório:

| Usuário | Senha didática |
|---|---|
| `usr_auditor_op` | `Lab_Auditor_2026` |
| `usr_coordenador_gestao` | `Lab_Gestao_2026` |
| `usr_dba_admin` | `Lab_Dba_2026` |

Elas devem ser alteradas ou retiradas do repositório em qualquer uso fora da atividade acadêmica.

## 10. Como executar e demonstrar

Executar as três primeiras etapas em ordem:

```bash
psql -U postgres -f scripts/01_setup_database.sql
psql -U postgres -f scripts/02_seed_data.sql
psql -U postgres -f scripts/03_security_rbac.sql
```

Ao fim do terceiro script, mostrar a matriz de testes. Todos os valores da coluna `resultado_obtido` devem ser iguais aos da coluna `resultado_esperado`.

Pontos para explicar oralmente:

1. roles funcionais não fazem login porque servem apenas para agrupar permissões;
2. os três usuários de teste fazem login e herdam somente uma role;
3. o operador grava novos eventos, mas não altera o histórico;
4. a gestão consulta views, não tabelas-base;
5. o hash da credencial é protegido por coluna;
6. `PUBLIC` perde os acessos amplos.

## 11. Limitações e próximos controles

- O RBAC não registra sozinho quem alterou os dados; isso será feito pelos triggers da Etapa 3.
- Tentativas negadas precisam ser capturadas no terminal ou no log do servidor.
- As senhas são didáticas e não representam uma política corporativa final.
- Em produção, autenticação centralizada por SSO/AD pode ser superior ao login local.
- A atualização de setor e a inserção da movimentação devem ocorrer na mesma transação da aplicação.

## 12. Conclusão

A Etapa 2 implementa uma política de acesso restritiva e verificável. O operador recebe permissões suficientes para trabalhar sem poder apagar o histórico, a gestão recebe somente dados agregados e o administrador fica separado dos perfis de uso diário. A coluna sensível de credencial permanece protegida e as senhas dos usuários PostgreSQL são armazenadas em SCRAM-SHA-256.

