# POPs — DevOps Sittax

Procedimentos Operacionais Padrão do pilar DevOps, cobrindo os produtos **Sittax**, **Sittax.ST** e **Sittax.Recupera**.

| Código | Documento | Escopo |
|---|---|---|
| POP-DV-001 | [Criação de Ambiente](POP-DV-001-criacao-de-ambiente.md) | Provisionar ambiente novo (stack Swarm, Variable Groups, DNS, certs, monitoramento) |
| POP-DV-002 | [Gestão de Pipeline](POP-DV-002-gestao-de-pipeline.md) | Criar/alterar pipelines Azure DevOps + jobs Jenkins, Variable Groups e agentes |
| POP-DV-003 | [Deploy em Homologação](POP-DV-003-deploy-em-homologacao.md) | Deploy em `dev`/`qa-01..03`/`stage` via pipeline `sittax-solutions` |
| POP-DV-004 | [Deploy em Produção](POP-DV-004-deploy-em-producao.md) | Release em produção: validação em stage, migrations, rollout, rollback |
| POP-DV-005 | [Gestão de Incidentes](POP-DV-005-gestao-de-incidentes.md) | Detecção, severidade, mitigação, registro e post-mortem |
| POP-DV-006 | [Monitoramento de Aplicações](POP-DV-006-monitoramento-de-aplicacoes.md) | OTEL, sintéticos agendados, OpenReplay, rede; rotina diária |

## Estrutura padrão (template)

Todo POP segue as seções: **Objetivo · Aplicação · Responsáveis · Pré-requisitos · Passo a Passo · Critérios de Sucesso · Riscos · Evidências · Histórico de Alterações**.

## Visão geral da esteira (contexto comum aos POPs)

- **Orquestração:** Azure DevOps (pipelines YAML em `Sittax/pipelines/` e nos repos de cada produto) dispara jobs **Jenkins** (`JenkinsQueueJob@2`, service connection `Jenkins Sittax`) para builds e deploy.
- **Registry:** OCIR `sa-saopaulo-1.ocir.io/grqd4dgol2np` (mirror opcional `registry.sittax.com.br`). Versionamento `2.$(Build.BuildNumber)`; `val.*` para validação de PR; `latest` nunca por pipeline.
- **Deploy:** job `Solutions/Deploy.Stack` → SSH no Swarm manager `192.168.2.116` → `docker service update --with-registry-auth --update-order start-first <env>_<svc>`.
- **Ambientes:** `dev`, `qa-01`, `qa-02`, `qa-03`, `stage` (homolog), `comercial`, `prd`. Acesso interno via split-DNS (dnsmasq no `.32`) + **VPN NetBird**.
- **VPN:** NetBird (WireGuard), gestão em `nb.sittax.com.br`, faixa `100.81.0.0/16`. Rota (`192.168.2.32/32`) e DNS interno são distribuídos **por grupo** — peer fora dos grupos `Homologação`, `Infra` ou `admin` não recebe nenhum dos dois, e o sintoma parece problema de DNS sendo de permissão. O OpenVPN `.138` está **descontinuado**.
- **Gestão de containers:** Portainer em `infra.sittax.com.br` (fork BySittax, na VM `new-vpn`), com o swarm conectado por agent via VPN. Stacks organizadas em **produtos** (`simples-hml`, `st-hml`, `recupera-hml`, `token-hml`, `certificados-hml`, `nfe-hml`, `plataforma-hml`). O `portainerdev.sittax.com.br` está **descontinuado** — redirecionado para o novo.
- **Observabilidade:** OTEL auto-instrumentation (imagem base `sittax-base`), OpenReplay/Clarity, SonarQube, Sorry-Cypress, NetFlow/Grafana. ⚠️ **A stack de observabilidade de homologação está FORA DO AR** desde antes de 06/08/2026 — os endereços antigos (`192.168.2.149`, `192.168.2.50`, coletor `10.0.0.57:4318`) não respondem. Os serviços seguem apontando `OTEL_*` para `otel.stage.sittax.com.br` e a rota no proxy foi mantida de propósito: quando a stack voltar, basta corrigir o IP do upstream `observability` no `.32`.

## Pendências de confirmação

- [ ] **POP-DV-003:** fluxo legado de release do ST (`azure-pipelines-release.sh`, registry `localhost:5500`) ainda está em uso ou foi absorvido pela `sittax-solutions`?
- [ ] **POP-DV-004:** mecanismo oficial do rollout de produção (job `Deploy.Stack` com ENV de produção × Portainer × manual no manager).
- [ ] **Transversal:** credenciais hardcoded em YAMLs/código (registry, JWT, SonarQube) — plano de migração para Variable Groups secretas/cofre e rotação (registrado como risco no POP-DV-002).
- [ ] **POP-DV-006:** para onde vai a stack de observabilidade de homologação quando voltar (o endereço antigo não existe mais).

## Divergência conhecida: compose do Portainer × o que roda

O `Deploy.Stack` atualiza a imagem **direto no serviço** (`docker service update`)
e não volta ao Portainer. O compose guardado lá diverge sozinho: em 06/08/2026,
**59 de 71 serviços** de homologação rodavam imagem diferente da registrada, e
num caso a diferença era de dois meses.

**Consequência prática:** reimplantar uma stack pelo Portainer sem reconciliar
antes reverte serviços para builds antigos. O POP-DV-003 tem o passo obrigatório.

Isso é decisão consciente, não descuido — deploy por serviço mantém o raio de
ação pequeno. A alternativa (esteira atualizar a variável `IMAGE*` da stack no
Portainer) elimina a divergência, mas tem pré-requisitos registrados em
[`../MIGRACAO-PORTAINER.md`](../MIGRACAO-PORTAINER.md): a variável é
compartilhada por 10–11 serviços (deploy passaria a ser da stack inteira), o
Portainer viraria dependência dura da esteira, e falta configurar o registry
OCIR nele.
