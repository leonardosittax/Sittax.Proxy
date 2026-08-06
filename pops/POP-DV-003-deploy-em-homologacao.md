# POP-DV-003 — Deploy em Homologação

## 1. Objetivo

Padronizar o deploy dos produtos **Sittax**, **Sittax.ST** e **Sittax.Recupera** nos ambientes não produtivos (`dev`, `qa-01`, `qa-02`, `qa-03`, `stage`), garantindo rollout sem indisponibilidade, respeito à regra de uso de cada ambiente e rastreabilidade da versão entregue.

## 2. Aplicação

Este processo deve ser utilizado quando:

- Uma branch/versão precisar ser disponibilizada para teste em um ambiente de QA;
- For preparada uma release candidate em `stage` (pré-release, etapa anterior ao POP-DV-004);
- O ambiente compartilhado `dev` precisar ser atualizado;
- For necessário restaurar um ambiente não produtivo para uma versão anterior (rollback).

## 3. Responsáveis

| Papel | Quem | Responsabilidade |
|---|---|---|
| Execução | O próprio desenvolvedor | Qualquer dev aciona pipeline/release conforme a necessidade — sem solicitação ou aprovação prévia |
| Validação | O desenvolvedor que deployou | Confere o ambiente após o rollout (seção 5.3) |
| Suporte à esteira | Time de DevOps (Leonardo Queiros e Glaucyo) | Mantém as pipelines (POP-DV-002) e apoia quando o rollout falha |

## 4. Pré-requisitos

- Branch(es) definidas para cada repositório envolvido;
- Código validado pela esteira de PR (`Sittax-validate`: build, testes unitários e E2E em `dev`);
- **Regra de uso do ambiente alvo respeitada** (Anexo C.1): `dev` é compartilhado; cada `qa-*` tem dono — alinhar com o dono antes; `stage` é pré-release;
- Variable Group do ambiente atualizada (endpoints, conexões).

## 5. Passo a Passo

### 5.1 Sittax e Recupera — pipeline `sittax-solutions`

1. Acionar a pipeline (manual) informando: ambiente, produtos a deployar e branch por repositório (Anexo C.2);
2. Acompanhar os builds disparados via Jenkins — as imagens são publicadas no registry com a tag de release;
3. Acompanhar o rollout no Swarm (job `Solutions/Deploy.Stack`) — atualização serviço a serviço, sem indisponibilidade (Anexo C.2);
4. Validar o ambiente (seção 5.3);
5. Quando o deploy estiver associado a uma demanda, registrar no PBI a versão e as branches entregues.

### 5.2 Sittax.ST — fluxo próprio

O ST possui esteira de deploy própria, independente da `sittax-solutions`:

1. Acionar a pipeline do ST (API e/ou SPA);
2. A etapa de release builda a imagem, publica no registry local e atualiza os serviços de homologação do ST no Swarm (Anexo C.2);
3. Validar nos endereços de homologação do ST (seção 5.3).

### 5.3 Validação pós-deploy

Executada pelo dev que deployou:

1. Serviços ativos com réplicas completas (Anexo C.3);
2. Versão correta respondendo (`/versao` do SPA) e ambiente certo (não a página de fallback);
3. Health-check da API e login funcionando;
4. Quando aplicável, executar as suítes E2E automatizadas contra o ambiente (Anexo C.4).

### 5.4 Rollback

Reexecutar o deploy informando a versão/branch anterior, ou atualizar os serviços diretamente para a tag anterior (Anexo C.5). Registrar o motivo quando o rollback decorrer de defeito.

## 6. Critérios de Sucesso

- Todos os serviços alvo convergiram, sem reinício em loop;
- `/versao` e health refletem a versão recém-deployada;
- Smoke test do dev concluído sem erro;
- Regra de uso do ambiente respeitada (dono do `qa-*` ciente, quando aplicável);
- Versão registrada no PBI quando houver demanda associada.

## 7. Riscos

| Risco | Impacto | Mitigação |
|---|---|---|
| Deploy sobre teste em andamento em `qa-*` | Perda de cenário de teste do dono do ambiente | Alinhar com o dono antes (pré-requisito) |
| Serviço não converge (réplicas 0) | Ambiente fora do ar | Validação 5.3; verificar recursos do host e logs do serviço |
| Tag errada (ex.: `val.*` de validação) | Versão incoerente com o esperado | Conferir a tag no run antes de validar |
| Variable Group desatualizada | Ambiente apontando para endpoints errados | Pré-requisito; revisar grupo ao mudar configuração |
| ST deployado por caminho errado | Versões divergentes entre os fluxos | ST sempre pelo fluxo próprio (5.2) |
| Timeout do rollout em serviço pesado | Atualização incompleta | Verificar logs do job de deploy; reexecutar o serviço específico |

## 8. Evidências

- Link do run da pipeline com os parâmetros usados (ambiente, produtos, branches);
- Verificação da versão (`/versao`) e dos serviços ativos;
- Resultado E2E (quando executado);
- Registro no PBI quando o deploy estiver associado a uma demanda.

## 9. Histórico de Alterações

| Versão | Data | Autor | Descrição |
|---|---|---|---|
| 1.0 | 2026-06-11 | Leonardo Queiros | Versão inicial |

---

## Anexo C — Detalhes técnicos de execução

### C.1 Regra de uso dos ambientes

| Ambiente | Uso |
|---|---|
| `dev` | Compartilhado por todos; também recebe deploy automático da pipeline de validação de PR (`Sittax-validate`) |
| `qa-01` / `qa-02` / `qa-03` | Cada um tem **dono** — deploy combinado com o dono do ambiente |
| `stage` | **Pré-release** — última validação antes de produção (POP-DV-004) |
| `comercial` | Demonstração/apresentação comercial |

### C.2 Fluxos de deploy

**Sittax e Recupera — `sittax-solutions` (Azure DevOps, manual):**
- Parâmetros: `ambiente` (`dev`/`qa-01`/`qa-02`/`qa-03`/`stage`), `produtoST`/`produtoRecupera` (deploy cirúrgico — só toca os produtos marcados) e branch por repositório (`sittaxBranch`, `recuperaApiBranch` etc.);
- Builds via Jenkins (`Sittax/Sittax`, `Sittax/Sittax.Spa`, `Recupera/*`) → push no OCIR com tag `2.$(Build.BuildNumber)`;
- Rollout via job `Solutions/Deploy.Stack`: SSH no manager `192.168.2.116` e, por serviço:
  `docker service update --image <ocir>/<imagem>:<versão> --with-registry-auth --update-order start-first <env>_<serviço>` (timeout 240s/serviço; `start-first` = zero-downtime).

**Sittax.ST — esteira própria:**
- Pipelines em `Sittax.ST.Api/deploy/` e `Sittax.ST.Spa/deploy/` com release script (`azure-pipelines-release.sh`);
- Publica no registry local `localhost:5500` (tags `sittax-st-api:2.<build>` / `sittax-st-app:2.<build>`) e atualiza os serviços `sittax-st-api-homolog_*` / `sittax-st-app_*` no Swarm;
- Endereços de homologação: `sthomologacao.sittax.com.br` (SPA) e `apisthomologacao.sittax.com.br` (API).

### C.3 Verificações

- `docker service ls | grep <env>_` — réplicas completas;
- `/versao` do SPA; health-check da API; login (valida banco);
- Acesso pela VPN NetBird ou pela LAN resolve pelo split-DNS com certificado válido.

> ⚠️ **`docker service ls` em `1/1` não é saúde.** O container sobe e a aplicação
> pode estar sem conexão com o broker — em 06/08/2026 sete serviços do stage
> ficaram horas sem consumir fila nenhuma com o painel todo verde. O `ls` também
> esconde task nova presa no escalonamento, porque continua contando a antiga.
>
> Para serviço que consome fila, verificar **no broker**:
> ```bash
> docker exec <rabbit> rabbitmqctl list_connections client_properties
> docker exec <rabbit> rabbitmqctl list_queues name messages consumers
> ```
> E para ver a task real, não a réplica:
> ```bash
> docker service ps <svc> --no-trunc --format '{{.CurrentState}}|{{.Error}}'
> ```

### C.3.1 Reconciliação antes de reimplantar pelo Portainer

**Obrigatório.** O `Deploy.Stack` atualiza a imagem direto no serviço e não volta
ao Portainer, então o compose guardado lá diverge sozinho. Reimplantar sem
reconciliar **reverte serviços para builds antigos** — em 06/08/2026 eram 59 de
71, com diferença de até dois meses.

Antes de qualquer `stack deploy`/update pela UI:

```bash
# 1. o que roda de verdade
docker service ls --format '{{.Name}}|{{.Image}}' | grep '^<env>_'

# 2. comparar com a variavel IMAGE* da stack no Portainer e corrigi-la
#    (o compose e parametrizado: nao precisa editar o compose, so a variavel)
```

Só depois de as duas listas baterem é que o redeploy é seguro. Um serviço preso a
imagem que não existe mais no registry não volta de jeito nenhum — aconteceu com
o `dev_sincronizacao`.

### C.4 E2E automatizado

Suítes Cypress: `Sittax.ST.Ui.Test` e `Sittax.Recupera.Ui.Test` (pool `Automatizados`, `targetEnv=hml`). Resultados no Sorry-Cypress; vídeos/screenshots no MinIO.

### C.5 Rollback

`docker service update --image <imagem>:<tag-anterior> --with-registry-auth <serviço>` ou reexecução da pipeline com a versão/branch anterior.
