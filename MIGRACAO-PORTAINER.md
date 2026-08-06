# Migração do Portainer — homologação

De `portainerdev.sittax.com.br` (CE 2.39.3, dentro do swarm no `.116`) para
`infra.sittax.com.br` (fork BySittax 2.43.0, na VM `new-vpn`), em 06/08/2026.

**Nenhum serviço foi reimplantado.** Os 121 serviços do swarm seguiram rodando
do começo ao fim.

---

## O bloqueio que definiu a estratégia

A API do Portainer **recusa criar stack com nome que já existe no swarm**
(`checkUniqueStackNameInDocker` verifica o label `com.docker.stack.namespace`),
e **não há flag de bypass**. Recriar os stacks exigiria removê-los antes — ou
seja, derrubada real, não atualização gradual.

A saída foi um endpoint de **adoção** no fork:

```
POST /stacks/adopt/swarm?endpointId=<id>
{
  "Name": "dev",
  "SwarmID": "...",
  "StackFileContent": "...",
  "Env": [...],
  "Product": "simples-hml"
}
```

É o inverso exato da checagem existente: **exige** que o namespace já esteja
rodando, grava o registro (compose, env, produto) e **não chama deploy**.

Prova de que não toca em nada: `Version.Index` e `UpdatedAt` do serviço
idênticos antes e depois, e 124 serviços antes / 124 depois com zero diferença.

Código em `api/http/handler/stacks/stack_adopt.go` no repo do fork.

## Como ficou organizado

**38 stacks adotadas** (depois consolidadas em 30), agrupadas em 7 produtos.
O sufixo `-hml` marca o ambiente:

| produto | stacks |
|---|---|
| `plataforma-hml` | 15 — postgres, redis, rabbit, kafka, minio, sonarqube, redmine, odoo, perfex, n8n, browserless, sittax-db, sittax-hub, sorry-cypress |
| `simples-hml` | 5 — `dev`, `qa-01`, `qa-02`, `qa-03`, `sittax-stage` |
| `token-hml` | 4 — bytoken, flytoken, assinatura, storage-token |
| `certificados-hml` | 2 |
| `nfe-hml` | 2 |
| `st-hml` · `recupera-hml` | 1 cada, após consolidação |

Produto é a unidade de **produto**, não de ambiente — `simples` tem os cinco
ambientes dentro dele.

Os **11 stacks `sittax-*` parados** não foram migrados (confirmado pelo
`docker stack ls`: nenhum implantado). Os composes ficaram em `legacy-stacks/`,
fora do git por conterem credenciais.

## Env unificada no produto

O fork injeta a env do produto em todos os serviços das stacks dele no deploy;
o valor local do serviço vence quando há conflito.

Subiram para `simples-hml` **62 variáveis** idênticas nos 5 ambientes: bloco
inteiro de OTel/Pyroscope, `CORECLR_*`, `LD_PRELOAD`, `SQL_SERVER_CONEXAO*`,
`SITTAX_DB_*`. O compose do `qa-03` caiu de **919 para 464 linhas**.

**Ficaram de fora, de propósito:**

- `JWT_SECRET`, `JWT_EMISSOR`, `RABBIT_SENHA`, `RABBIT_SERVIDOR`,
  `REDIS_SENHA`, `REDIS_SERVIDOR` — textualmente iguais nos composes, mas são
  `${VAR}` que interpolam valores **diferentes por ambiente**. Subir isso faria
  dev, qa e stage compartilharem o mesmo segredo JWT.
- `RABBIT_USUARIO`, `RABBIT_VIRTUAL_HOST`, `REDIS_PORTA`, `SWAGGER_ATIVO` —
  usadas como fonte de `${}` para outras variáveis. Mover quebrou a mensageria
  dos 5 ambientes (ver `LICOES-ANTES-DO-PROXIMO.md`, item 3).

## Reconciliação de imagem — o passo obrigatório

**59 de 71 serviços** rodavam imagem diferente da do compose. O CI atualiza
direto no serviço e nunca volta ao Portainer.

Como o compose já era parametrizado (`image: ${IMAGE}`), bastou corrigir as
variáveis para a tag que realmente rodava — sem tocar no compose:

| stack | `IMAGE` no Portainer | rodando de verdade |
|---|---|---|
| qa-01 | `2.20260519.8` | `2.20260805.7` |
| qa-02 | `2.20260519.9` | `2.20260803.10` |
| qa-03 | `2.20260519.5` | `2.20260730.1` |
| sittax-stage | `2.20260629.9` | `2.20260805.8` |
| dev | `latest` | `2.20260805.5` |

Depois da correção o redeploy virou no-op: imagens preservadas, 13/13 saudáveis
em cada ambiente.

> Um serviço (`dev_sincronizacao`) rodava build que **não existe mais nem no
> registry nem em disco** — só sobrevivia enquanto o container original estivesse
> de pé. Qualquer restart o mataria. Fica como alerta: serviço preso a imagem
> irreproduzível é bomba-relógio.

## Consolidação do `st` e do `recupera`

Os 9 stacks avulsos rodavam com `JWT_SECRET` de qa01/qa02 mas `JWT_EMISSOR`
apontando para domínios legados `*homologacao` — entre dois ambientes.

Viraram `st-qa-02` (3 serviços) e `recupera-qa-02` (3), com **emissor único** em
`autenticacao.qa02.sittax.com.br`. Os duplicados de `autenticacao` e `upload`
saíram: agora usam os do próprio qa-02. Os `Host()` legados foram mantidos por
retrocompatibilidade.

Composes em `vpn-block/qa02-consolidacao/`.

## Estado final

| | |
|---|---|
| endpoints no `infra` | `it-administrator-server` e `swarm-homologacao`, ambos UP |
| swarm visível | 4 nós, ~95 containers |
| stacks | 30, todas com produto |
| Portainer antigo | perdeu acesso ao agent (ver abaixo) |

**O Portainer antigo não fala mais com o swarm.** O agent confia na primeira
chave que recebe; ao ser reiniciado, quem reconquistou a confiança foi o
`infra`. Como o antigo está para ser descontinuado, isso vai na direção certa —
mas foi consequência, não planejamento. Para revertê-lo, bastaria reiniciar o
agent com o antigo conectando primeiro.

## Pendências

- Redirect de `portainerdev.sittax.com.br` para `infra.sittax.com.br`
- `dev_sincronizacao` fora do ar — imagem irrecuperável, atualização virá pela
  Azure
- Aplicar aos outros 4 ambientes a simplificação com âncoras já feita no `qa-03`
