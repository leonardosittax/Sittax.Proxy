# POP-DV-002 — Gestão de Pipeline

## 1. Objetivo

Padronizar a criação, alteração, manutenção e acompanhamento das pipelines de CI/CD dos produtos **Sittax**, **Sittax.ST** e **Sittax.Recupera** — incluindo Variable Groups, segredos, agentes de build e jobs Jenkins — garantindo que a esteira seja versionada, revisada, segura e saudável no dia a dia.

## 2. Aplicação

Este processo deve ser utilizado quando:

- For criada uma nova pipeline (build, deploy, testes ou imagem base);
- Forem alterados stages, parâmetros, triggers ou agendamentos de pipeline existente;
- Forem criados ou alterados Variable Groups, segredos ou service connections;
- Houver manutenção em agentes de build (pools) ou no Jenkins (jobs, credenciais, plugins);
- Na rotina de acompanhamento da saúde da esteira (builds quebrados, pipelines agendadas, agentes).

## 3. Responsáveis

| Papel | Quem | Responsabilidade |
|---|---|---|
| Execução | Time de DevOps — Leonardo Queiros e Glaucyo (exclusivo: devs não alteram a esteira) | Cria/altera pipelines, Variable Groups, agentes e jobs Jenkins |
| Revisão | O outro membro do time de DevOps | Revisa toda mudança via pull request antes do merge |
| Decisões estruturais | Time, em reunião de alinhamento | Mudanças de arquitetura da esteira; registradas no PBI |

## 4. Pré-requisitos

- Necessidade registrada como PBI (a mudança nasce de uma demanda, não de edição ad hoc);
- Conhecimento da arquitetura híbrida da esteira (Anexo B.1): **Azure DevOps orquestra, Jenkins executa** — modelo permanente, sem plano de desativação de nenhum dos dois;
- Acesso ao Azure DevOps e ao Jenkins (restrito ao time de DevOps);
- Identificação do repositório onde o YAML da pipeline é versionado (Anexo B.2).

## 5. Passo a Passo

### 5.1 Criar ou alterar pipeline

1. Registrar/referenciar o PBI com motivo e impacto esperado;
2. Criar branch e alterar o YAML no repositório onde a pipeline vive — pipeline é código versionado; nunca alterar somente pela interface;
3. Colocar segredos exclusivamente em Variable Group (flag secret) ou credencial Jenkins — nunca no YAML (Anexo B.3); ao tocar pipeline com credencial em texto plano, migrá-la na mesma mudança;
4. Validar sem afetar release: usar ambiente de desenvolvimento e tags de validação (Anexo B.4);
5. Abrir PR e obter revisão do outro membro do time de DevOps;
6. Após o merge, executar a pipeline de ponta a ponta em ambiente não produtivo;
7. Comunicar o time quando a mudança alterar a forma de uso (novos parâmetros, ambientes ou comportamento).

### 5.2 Variable Groups e segredos

1. Criar/alterar o grupo a partir do PBI; ao criar ambiente novo, clonar de grupo similar e revisar item a item (POP-DV-001);
2. Valores sensíveis sempre com flag secret; nunca registrar valores em PBI, chat ou documentação;
3. Registrar a mudança no PBI (o quê mudou, sem os valores); credencial que tenha sido exposta deve ser rotacionada.

### 5.3 Agentes e Jenkins

1. Mudanças no Jenkins (jobs, credenciais, plugins) devem ser registradas no PBI — o Jenkins não é versionado em Git, o registro é a única rastreabilidade;
2. Manter os agentes saudáveis: espaço em disco (GC de build, Anexo B.5) e conectividade dos pools;
3. Após qualquer mudança, validar que os pools estão online e executando jobs.

### 5.4 Rotina de acompanhamento

1. Conferir diariamente o resultado das pipelines agendadas (Anexo B.2) — em conjunto com a rotina de monitoramento (POP-DV-006);
2. Build quebrado em branch principal é prioridade: tratar no mesmo dia;
3. Verificar fila e saúde dos agentes;
4. Anomalia recorrente vira PBI de melhoria da esteira.

## 6. Critérios de Sucesso

- Pipeline alterada executa de ponta a ponta com sucesso (run verde após o merge);
- Nenhum segredo em texto plano introduzido (verificado na revisão do PR);
- Padrão de versionamento preservado (Anexo B.4);
- Pipelines agendadas executando nos horários previstos e agentes online;
- Mudança rastreável: PR + registro no PBI (incluindo mudanças no Jenkins).

## 7. Riscos

| Risco | Impacto | Mitigação |
|---|---|---|
| Credencial em texto plano no YAML/código | Vazamento de acessos (passivo já existente) | Passo 5.1.3; migrar para Variable Group secreta e rotacionar as expostas |
| Mudança sem revisão | Esteira quebrada para todos os produtos | PR obrigatório com revisão do par de DevOps |
| Edição somente pela interface | Mudança não versionada; divergência entre YAML e execução | Pipeline como código (passo 5.1.2) |
| Agente offline ou sem disco | Builds e deploys param | Rotina 5.4 e GC de build (Anexo B.5) |
| Mudança no Jenkins sem registro | Esteira irreproduzível, conhecimento perdido | Passo 5.3.1 |
| Imagem base desatualizada | Vulnerabilidades e telemetria defasada em todos os serviços | Rebuild periódico da imagem base (Anexo B.2) |

## 8. Evidências

- PR aprovado com o diff do YAML;
- Link do run verde da pipeline após a mudança;
- Registro no PBI, incluindo mudanças em Jenkins e Variable Groups — sem valores de segredos;
- Quando houver rotação de credencial: registro de qual credencial foi rotacionada (sem o valor).

## 9. Histórico de Alterações

| Versão | Data | Autor | Descrição |
|---|---|---|---|
| 1.0 | 2026-06-11 | Leonardo Queiros | Versão inicial |

---

## Anexo B — Detalhes técnicos da esteira

### B.1 Arquitetura (híbrido permanente)

Azure DevOps (pipelines YAML) **orquestra**; Jenkins **executa** os jobs pesados (builds e deploy em homologação) via task `JenkinsQueueJob@2`, conectados pela service connection `Jenkins Sittax`. Deploy de produção é executado via Pipeline/Releases do Azure DevOps (POP-DV-004). Não há plano de desativar nenhuma das duas ferramentas.

### B.2 Inventário de pipelines

| Pipeline | Onde vive | Disparo | Função |
|---|---|---|---|
| Sittax-validate | `Sittax/pipelines/Sittax-validate.yml` | PR / `master` / `develop` | Valida PR: build .NET+TS, testes unitários, imagens `val.*`, deploy em DEV, E2E |
| sittax-solutions | `Sittax/pipelines/sittax-solutions.yml` | Manual | Deploy em homolog/QA (POP-DV-003) |
| sittax-adm_arm-64 | `Sittax/pipelines/sittax-adm_arm-64.yml` | `master` | Build .NET + imagem multi-arch (amd64/arm64) → OCIR |
| sittax-spa-amd_arm-64 | `Sittax/pipelines/sittax-spa-amd_arm-64.yml` | `master` | Build SPA multi-ambiente (imagem única, `NGINX_ROOT` em runtime) |
| sittax-base-image | `Sittax/pipelines/sittax-base-image.yml` | Manual | Imagem base .NET + agente OpenTelemetry |
| sittax-testes | `Sittax/pipelines/sittax-testes.yml` | Cron diário 05h BRT (develop) | Testes unitários + SonarQube |
| Testes.Integracao | `Sittax/pipelines/Testes.Integracao/` | Cron diário 03h BRT (develop) | Integrações externas (SEFAZ, IOB/Econet, Serpro, eCac, Siscomex) |
| ST.Api / ST.Spa | `Sittax.ST.*/deploy/` | Azure Pipelines | Build + deploy ST |
| Recupera.Api / Spa / Ui.Test | `Sittax.Recupera.*/azure-pipelines.yml` | `master` | Build API/Worker/SPA + E2E Cypress |
| Jobs Jenkins | `Sittax/Sittax`, `Sittax/Sittax.Spa`, `ST/*`, `Recupera/*`, `Solutions/Deploy.Stack`, `Sittax/Sittax.E2E.Validate` | Disparados pelo Azure | Build, push e rollout no Swarm |

### B.3 Segredos

- Variable Groups por ambiente (`Produção`, `Homologação`, `QA01`–`QA03`, `DEV`, `Comercial`) com flag secret nos valores sensíveis;
- Credenciais Jenkins (ex.: `swarm-deploy-ssh` para o rollout via SSH);
- ⚠️ Passivo conhecido: credenciais hardcoded em YAMLs/código (registry, JWT, SonarQube) — plano: migrar para Variable Group secreta/cofre e **rotacionar** as já expostas.

### B.4 Versionamento de imagens

- Release: `2.$(Build.BuildNumber)`;
- Validação de PR: `val.$(Build.BuildNumber)`;
- `latest` **nunca** é publicada por pipeline.

### B.5 Agentes e registry

- Pools: `Quality` (builds, self-hosted), `Automatizados` (testes de UI), `Azure Pipelines` (hosted, fallback);
- GC dos builders: `docker buildx prune --keep-storage` (20 GB sittax / 10 GB spa / 5 GB base) — sem o GC o disco do agente esgota;
- Registry: OCIR `sa-saopaulo-1.ocir.io/grqd4dgol2np` (mirror opcional `registry.sittax.com.br`).
