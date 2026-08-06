# POP-DV-004 — Deploy em Produção

## 1. Objetivo

Padronizar o deploy dos produtos **Sittax**, **Sittax.ST** e **Sittax.Recupera** em produção, garantindo que as versões cheguem aos clientes com aprovação formal, banco de dados atualizado de forma controlada, rollout sem indisponibilidade e plano de reversão definido.

## 2. Aplicação

Este processo deve ser utilizado quando:

- For publicada uma nova release de qualquer produto em produção (caminho padrão);
- For aplicado um hotfix urgente em produção (trilha de exceção, seção 5.2);
- For necessário reverter produção para uma versão anterior (rollback).

## 3. Responsáveis

| Papel | Quem | Responsabilidade |
|---|---|---|
| Execução | Time de DevOps — Glaucyo ou Leandro | Dispara a Release no Azure DevOps, aplica o rollout e executa o smoke test |
| Aprovação | Glaucyo ou Leandro (pre-deployment approval no Release) | Autoriza formalmente a execução, registrada na própria ferramenta |
| Banco de dados | Revisor do script de migration (auditoria Sentinel) | Revisa e aplica o script SQL antes do rollout |

## 4. Pré-requisitos

- **Caminho padrão:** a mesma build/tag validada em `stage` (pré-release, POP-DV-003) — sem rebuild para produção;
- Aprovação do Release concedida (pre-deployment approval);
- Quando houver migration: script SQL gerado pela esteira, **revisado** e com plano de reversão definido; backup/snapshot do banco realizado;
- **Hotfix (exceção):** pode pular o `stage`, mas mantém todos os demais pré-requisitos — código validado pela esteira de PR, aprovação do Release e migrations revisadas.

## 5. Passo a Passo

### 5.1 Caminho padrão (release)

1. Validar a release candidate em `stage` (POP-DV-003) e congelar a versão (tag) que será promovida;
2. Disparar a Release de produção no Azure DevOps apontando a versão congelada (Anexo D.1);
3. Aguardar a aprovação formal (pre-deployment approval);
4. **Migrations:** aplicar o script revisado **antes** do rollout. Como o rollout mantém versão antiga e nova convivendo por instantes, as migrations devem ser retrocompatíveis — criar antes, remover apenas em release futura (Anexo D.4);
5. Executar o rollout pela Release (atualização serviço a serviço, sem indisponibilidade — Anexo D.1);
6. Executar o smoke test imediato (Anexo D.3);
7. Acompanhar a primeira hora pós-deploy: taxa de erros, exceptions novas e filas (Anexo D.3);
8. Registrar a release no PBI: versão, horário, executor, aprovador e evidências.

### 5.2 Hotfix (exceção)

1. Justificar a urgência no PBI do defeito;
2. Código validado pela esteira de PR (`Sittax-validate`);
3. Seguir os passos 2 a 8 do caminho padrão — a única etapa dispensada é a passagem por `stage`; o acompanhamento pós-deploy (passo 7) deve ser reforçado, pois a versão não teve validação de pré-release.

### 5.3 Rollback

1. Reexecutar a Release com a versão anterior (ou atualizar os serviços diretamente para a tag anterior — Anexo D.5);
2. Migrations: executar o plano de reversão definido no pré-requisito (nem toda migration é reversível — por isso o plano é obrigatório antes do deploy);
3. Registrar o rollback e abrir incidente para tratar a causa (POP-DV-005).

## 6. Critérios de Sucesso

- Versão nova respondendo em produção (`/versao` = tag aprovada) com todos os serviços convergidos;
- Sem elevação de erros 5xx/exceptions na primeira hora pós-deploy;
- Smoke test integralmente verde (Anexo D.3);
- Filas de mensageria saudáveis (workers processando, sem acúmulo anormal);
- Release rastreável: aprovação registrada na ferramenta + PBI com as evidências.

## 7. Riscos

| Risco | Impacto | Mitigação |
|---|---|---|
| Hotfix sem validação em stage | Defeito direto em clientes | Trilha 5.2 restrita a urgências justificadas, com acompanhamento reforçado |
| Migration incompatível durante o rollout | Erros intermitentes enquanto versões convivem | Migrations retrocompatíveis — expand/contract (passo 5.1.4) |
| Migration sem plano de reversão | Rollback impossível ou com perda de dados | Revisão + plano de reversão + backup são pré-requisitos bloqueantes |
| Rebuild em vez de promover a mesma tag | Binário em produção diferente do validado | Caminho padrão exige a mesma build de stage |
| Deploy em período crítico do calendário fiscal | Impacto máximo a clientes | Planejar a janela da release considerando o calendário |
| Indisponibilidade externa (SEFAZ, eCac, Serpro) simultânea ao deploy | Falso diagnóstico de regressão | Conferir o resultado dos testes de integração da madrugada antes de atribuir erros à release |

## 8. Evidências

- Release no Azure DevOps com a aprovação registrada (pre-deployment approval);
- Evidência da validação em `stage` (caminho padrão) ou justificativa da urgência (hotfix);
- Script de migration revisado + confirmação de aplicação e do backup;
- Verificação pós-deploy: `/versao`, health e smoke test;
- Métricas da primeira hora (dashboards) referenciadas no PBI da release.

## 9. Histórico de Alterações

| Versão | Data | Autor | Descrição |
|---|---|---|---|
| 1.0 | 2026-06-11 | Leonardo Queiros | Versão inicial |

---

## Anexo D — Detalhes técnicos de execução

### D.1 Mecanismo de deploy

Produção é deployada via **Pipeline/Releases do Azure DevOps**, com **pre-deployment approval** como gate formal. A infraestrutura de produção roda no ambiente interno da OCI (rede `10.0.0.x`), com borda em Cloudflare **proxy ativo (orange) + WAF**. O rollout atualiza os serviços com `--update-order start-first` (a réplica nova sobe antes de a antiga sair — zero-downtime).

### D.2 Builds de origem

- Imagens geradas pelas pipelines de `master`: `sittax-adm_arm-64` (API/workers), `sittax-spa-amd_arm-64` (SPA multi-ambiente, produção = `NGINX_ROOT=prd`), pipelines de Recupera e ST;
- Registry: OCIR `sa-saopaulo-1.ocir.io/grqd4dgol2np`, tag `2.$(Build.BuildNumber)`;
- A tag promovida a produção é a **mesma** validada em `stage`; `latest` nunca é publicada por pipeline — se usada, é apontada manualmente após o smoke test.

### D.3 Smoke test e acompanhamento

- `/versao` do SPA = tag aprovada; SPA servindo o ambiente `prd` (não a página `_fallback`);
- Health-check da API e login real funcionando;
- Execução de um fluxo crítico de negócio sem erro;
- RabbitMQ: workers consumindo, sem acúmulo anormal nas filas;
- Primeira hora: taxa de 5xx/exceptions na telemetria OTEL (coletor `10.0.0.57:4318`) e sessões no OpenReplay.

### D.4 Migrations

- Script gerado pela esteira (`dotnet ef migrations script`; auditoria automática envia o SQL ao Sentinel);
- Revisão obrigatória + plano de reversão + backup antes da aplicação;
- Aplicação **manual**, antes do rollout;
- Padrão expand/contract: a release N cria/adiciona; a remoção/renomeação destrutiva só ocorre na release N+1, quando nenhuma versão antiga está mais no ar.

### D.5 Rollback

- Reexecutar a Release apontando a tag anterior, ou `docker service update --image <imagem>:<tag-anterior> --with-registry-auth <serviço>` nos serviços afetados;
- Reversão de banco conforme o plano aprovado no pré-requisito.
