# POP-DV-006 — Monitoramento de Aplicações

## 1. Objetivo

Padronizar a operação do monitoramento das aplicações **Sittax**, **Sittax.ST** e **Sittax.Recupera** — rotina de verificação, inclusão de novos serviços/ambientes, gestão de alertas e manutenção da stack de observabilidade — garantindo que todo serviço nasça observável e que degradações sejam detectadas pelo monitoramento antes de o cliente reportar.

## 2. Aplicação

Este processo deve ser utilizado:

- Na rotina diária de verificação de saúde dos ambientes;
- Ao colocar um novo serviço ou ambiente no ar (complementa o POP-DV-001);
- Na criação e ajuste de regras de alerta, thresholds e janelas de notificação;
- Na manutenção da stack de observabilidade (retenção, atualizações, sincronização);
- Como fonte primária de detecção para a Gestão de Incidentes (POP-DV-005).

## 3. Responsáveis

| Papel | Quem | Responsabilidade |
|---|---|---|
| Operação e manutenção | Leonardo Queiros (único operador hoje) | Opera e mantém a stack de observabilidade (`Sittax.Observability`) e o Sentinel (`Sittax.Monitor`); este POP é também instrumento de repasse do conhecimento ao time |
| Consumo de alertas | Todo o time | Acompanha as notificações no grupo (Telegram/WhatsApp); anomalia confirmada abre incidente (POP-DV-005) |

## 4. Pré-requisitos

- Conhecer a arquitetura da observabilidade (Anexo F.1) — em especial a separação entre as duas instâncias: **prod (Coolify, recebe apenas produção)** e **stage (`192.168.2.149`, recebe stage/qa/dev)**;
- Acessos: Grafana prod e stage, Sentinel (perfil admin para configuração), SSH ao `.149`, Coolify (prod) e manager `.116`;
- Entendimento do arranjo de alertas: **o Sentinel é o canal oficial de notificação** (Telegram/WhatsApp); o Grafana é a plataforma de investigação e análise.

## 5. Passo a Passo

### 5.1 Rotina diária (início do expediente)

1. **Alertas da noite:** revisar o grupo (Telegram/WhatsApp) — alerta sem mensagem de normalização correspondente é pendência aberta → triagem;
2. **Sentinel:** verificar Servidores (CPU/memória/disco), Ambientes (réplicas das stacks), Sites monitorados e filas RabbitMQ;
3. **Sintéticos da madrugada:** resultados da `Testes.Integracao` (03h BRT) e `sittax-testes` (05h BRT) — distinguir indisponibilidade externa (SEFAZ/órgãos) de regressão própria antes de abrir incidente;
4. **Grafana prod:** RED overview e erros/latência — procurar exceptions novas ou degradação;
5. Anomalia confirmada → abrir incidente (POP-DV-005).

### 5.2 Incluir novo serviço/ambiente no monitoramento

1. **Telemetria:** construir o serviço sobre a imagem base (auto-instrumentation OTel) e conferir as variáveis `OTEL_*` apontando para o ingest **do ambiente correto** (produção → `otel.sittax.com.br`; stage/qa/dev → `otel.stage.sittax.com.br`);
2. **Sentinel:** cadastrar o que se aplicar — servidor (job do node_exporter), stack/serviço (réplicas requeridas), fila RabbitMQ (thresholds) e/ou site monitorado (URL + status esperado);
3. **Dashboards:** provisionar os dashboards do ambiente no Grafana correto (UIDs sufixados por ambiente — Anexo F.2);
4. **Alertas:** definir regras, níveis e janelas no Sentinel (Anexo F.3);
5. **Validar:** gerar tráfego de teste e confirmar traces/logs/métricas chegando e o card verde no Sentinel **antes** de considerar o serviço em operação.

### 5.3 Gestão de alertas

1. Criar/ajustar regras no Sentinel: thresholds por métrica e servidor, consumers mínimos/mensagens máximas por fila, réplicas requeridas por serviço, status codes por site (Anexo F.3);
2. Configurar nível (aviso/alerta/crítico), janelas de horário/dias e templates de mensagem;
3. Revisar periodicamente falsos positivos — ajustar grace period, thresholds e janelas para manter a confiança do time no canal;
4. **Limitação conhecida:** as regras de alerting do Grafana (PROD) existem mas não têm canal de notificação configurado — valem como registro/investigação; a notificação oficial é do Sentinel. Evolução futura: configurar contact point real no Grafana.

### 5.4 Manutenção da stack

1. **Observability prod (Coolify):** mudanças sempre via UI/API do Coolify — as configs são embedadas na imagem (`Dockerfile.with-config`); nunca operar docker direto no host;
2. **Observability stage (`.149`):** docker-compose manual via SSH em `/home/ubuntu/.observability/`; ⚠️ a sincronização com o repositório `Sittax.Observability` é **manual** (scp/rsync) — toda mudança aplicada no host deve ser refletida no repo (e vice-versa);
3. **Retenção/disco:** acompanhar volumes de Mimir/Tempo/Loki/Pyroscope, MinIO (vídeos/screenshots do Sorry-Cypress) e ClickHouse de NetFlow (`.50`);
4. **Atualizações de componentes** (collectors, Grafana, storages): aplicar primeiro no stage (`.149`), validar, depois promover a prod;
5. **Sentinel:** aplicação própria no Swarm (app + worker de alertas + banco `monitoring`); o `docker-health-agent` roda no manager `.116` — conferir que segue reportando (status das stacks com atualização ~60s).

## 6. Critérios de Sucesso

- Rotina diária executada, com anomalias triadas no mesmo dia;
- Serviço/ambiente novo emitindo telemetria e visível no Sentinel **antes** do go-live;
- Alertas chegando no grupo com normalização funcionando e falsos positivos sob controle;
- Stack sem perda de telemetria (disco/retenção saudáveis; ingest disponível);
- Incidentes detectados majoritariamente pelo monitoramento, não por reclamação de cliente.

## 7. Riscos

| Risco | Impacto | Mitigação |
|---|---|---|
| Operação concentrada em uma única pessoa | Sem operador em ausência/férias (bus factor) | Este POP como repasse; envolver gradualmente o time de DevOps na operação |
| Ingest OTLP indisponível | Cegueira total de telemetria sem afetar as aplicações (falha silenciosa) | Verificação de chegada de dados na rotina diária (5.1.4) |
| Sentinel fora do ar | Perda do canal oficial de alertas | Monitorar o monitor (uptime do Sentinel); Grafana como fallback de investigação |
| Alerting do Grafana sem canal | Regras críticas disparam sem notificar | Sentinel como canal oficial (5.3.4); configurar contact point como evolução |
| Divergência repo × host `.149` | Mudança perdida ao recriar o ambiente | Disciplina de sync manual (5.4.2) |
| Disco cheio (Mimir/Tempo/Loki/MinIO/ClickHouse) | Perda de histórico ou parada de ingestão | Acompanhamento de retenção (5.4.3) |
| Falsos positivos frequentes | Time passa a ignorar o canal de alertas | Revisão periódica (5.3.3) |
| Operar docker direto no host Coolify | Quebra da gestão do Coolify sobre a stack | Mudanças só via UI/API (5.4.1) |

## 8. Evidências

- Anomalias da rotina diária registradas no canal do time (com print/indicador);
- Para serviço novo: confirmação de telemetria (traces/dashboard) e card no Sentinel, anexadas ao PBI de criação (POP-DV-001);
- Histórico de alertas enviados/normalizados (Sentinel);
- Mudanças na stack versionadas no repositório `Sittax.Observability` (commits) e registradas em PBI quando estruturais.

## 9. Histórico de Alterações

| Versão | Data | Autor | Descrição |
|---|---|---|---|
| 1.0 | 2026-06-11 | Leonardo Queiros | Versão inicial |

---

## Anexo F — Arquitetura e referências técnicas

### F.1 Arquitetura da observabilidade

O monitoramento é composto por **dois sistemas distintos**, ambos desenvolvidos internamente:

- **`Sittax.Observability`** — a **stack de observabilidade** (`https://grafana.sittax.com.br`): Grafana, dashboards e os armazenamentos de traces, logs, métricas e profiling (OTel Collector, Mimir, Tempo, Loki, Pyroscope). É onde se **investiga** a causa raiz.
- **`Sittax.Monitor`** — o **Sentinel** (`https://sentinel.sittax.com.br`): painel de status operacional e **canal oficial de alertas**. É onde se **detecta e é notificado**.

> ### ⚠️ Estado em 06/08/2026 — a instância de HOMOLOGAÇÃO está FORA DO AR
>
> Os três endereços da cadeia de stage não respondem: `192.168.2.149` (host da
> stack), `192.168.2.50` (NetFlow/Grafana) e o coletor `10.0.0.57:4318`.
> `otel.stage.sittax.com.br` não entrega telemetria.
>
> **Isso não afeta as aplicações** — elas seguem rodando; o que existe é
> cegueira de telemetria em homologação. A rotina diária (5.1) e os alertas que
> dependem de stage estão sem sinal.
>
> Os serviços continuam com `OTEL_*` apontando para `otel.stage.sittax.com.br`
> **de propósito**, e a rota no proxy `.32` foi mantida declarada (upstream
> `observability`). Quando a stack voltar, basta corrigir o IP do upstream —
> nenhum serviço precisa ser tocado.
>
> A arquitetura descrita abaixo continua válida como desenho; o que mudou foi
> onde (ou se) ela está rodando. **Confirmar o endereço novo antes de usar este
> anexo como referência operacional.**

**Sittax.Observability — duas instâncias independentes da stack:**

| Instância | Onde roda | Recebe telemetria de | URLs |
|---|---|---|---|
| **Prod** | Coolify (gerenciado via UI/API) | **Apenas produção** | `grafana.sittax.com.br`, `otel.sittax.com.br`, `pyroscope.sittax.com.br` |
| **Stage** | ⚠️ **fora do ar** — era `192.168.2.149` (`/home/ubuntu/.observability/`, compose manual), endereço atual a confirmar | `stage`, `qa01`, `qa02`, `qa03`, `dev` | `grafana.stage.sittax.com.br`, `otel.stage.sittax.com.br` |

Fluxo de dados: apps .NET → OTLP (`otel.<env>.sittax.com.br`) → **otel-front** (2 réplicas, filtros leves) → **otel-back** (2 réplicas, transforms + spanmetrics) → **Mimir** (métricas), **Tempo** (traces), **Loki** (logs), **Pyroscope** (profiling contínuo) → **Grafana**. Sampling de traces: prod 10%, stage/qa 100%.

**Sentinel** (`Sittax.Monitor`, `https://sentinel.sittax.com.br`): app própria (Node/React + Postgres `monitoring`) com worker de alertas; coleta servidores via Prometheus/Mimir, stacks via `docker-health-agent` (manager `.116`, ~60s), filas via API do RabbitMQ, uptime de sites via HTTP e eventos do `Sittax.Watchdog` (memory pressure). Notifica **Telegram** (grupo) e **WhatsApp** (via n8n).

Complementares: OpenReplay (sessões reais), Sorry-Cypress/MinIO (E2E), NetFlow/Grafana (rede — ⚠️ o `.50:3001` não responde desde 06/08/2026), pipelines agendadas (sintéticos).

### F.2 Dashboards principais (Grafana)

- **Aplicação:** `sittax-red-overview` (RED method), `sittax-http-performance`, `sittax-db-overview` + `sittax-slow-queries`, `sittax-dotnet-runtime` (memória/GC/threads), `sittax-active-sessions`;
- **Por ambiente:** mesmos dashboards com UID sufixado (`-stage`, `-qa01`...) no Grafana de stage;
- **Plataforma:** `sittax-otel-collector` (saúde da própria stack), folders de Produção (RabbitMQ, servidores), CI-CD (agentes de build/teste).

### F.3 Alertas no Sentinel (tipos e parâmetros)

| Tipo | Parâmetros | Default |
|---|---|---|
| Servidor | CPU / memória / disco | 80% / 80% / 95% |
| Fila RabbitMQ | consumers mínimos; mensagens máximas | 10k mensagens |
| Site monitorado | status codes esperados, método, timeout | — |
| Stack/serviço | réplicas requeridas | réplicas da stack |
| Watchdog | eventos de memory pressure (dry-run/kill) | — |

Comportamento: níveis **aviso/alerta/crítico**, grace period (15s) contra falsos positivos transitórios, janelas de horário/dias por nível, mensagem automática de **normalização** quando a métrica volta ao normal, templates customizáveis.

### F.4 Manutenção

- **Prod (Coolify):** configs embedadas via `Dockerfile.with-config`; mudanças só pela UI/API do Coolify;
- **Stage (`.149`):** compose com bind mounts; sync manual repo ↔ host (scp/rsync);
- **Ordem de atualização:** stage → validação → prod;
- Limites de recursos (CPU/memória/GOMEMLIMIT) definidos no compose — revisar ao adicionar carga.
