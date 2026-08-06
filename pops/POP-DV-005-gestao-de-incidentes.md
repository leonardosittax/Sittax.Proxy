# POP-DV-005 — Gestão de Incidentes

## 1. Objetivo

Padronizar a detecção, classificação, comunicação, mitigação e registro de incidentes que afetem os produtos **Sittax**, **Sittax.ST** e **Sittax.Recupera** ou a infraestrutura que os sustenta — reduzindo o tempo de recuperação e transformando cada incidente em histórico e aprendizado registrados.

## 2. Aplicação

Este processo deve ser utilizado quando houver indisponibilidade, degradação ou comportamento anômalo em produção ou homologação:

- Aplicação fora do ar, lentidão generalizada ou erros em massa;
- Falha de integração externa (SEFAZ, eCac, Serpro, IOB/Econet);
- Falha de infraestrutura (rede, banco de dados, mensageria, certificados);
- Suspeita de incidente de segurança.

Os incidentes chegam por quatro canais, todos válidos para abrir o processo: **alertas do monitoramento** (Sentinel via Telegram/WhatsApp e Grafana — Anexo E.1), **suporte/cliente**, **falha dos testes agendados da madrugada** e **percepção do próprio time** durante o uso.

## 3. Responsáveis

| Papel | Quem | Responsabilidade |
|---|---|---|
| Detecção e abertura | Qualquer membro do time | Registra e comunica imediatamente |
| Coordenação | Time de DevOps (Leonardo, Glaucyo, Leandro) | Conduz triagem, mitigação e registro; ponto único de comunicação técnica |
| Participação | Devs dos produtos envolvidos | Atuam junto na investigação e correção; em **S1**, toda a equipe é mobilizada |
| Comunicação a clientes | Suporte/Atendimento | Comunica clientes quando houver impacto externo, orientado pela coordenação |

## 4. Pré-requisitos

- Acesso às plataformas de monitoramento e aos acessos de emergência (Anexo E.1);
- Conhecimento da tabela de **causas conhecidas** (Anexo E.2) — consultá-la antes de formular hipóteses novas;
- Conhecimento do playbook de incident report (Anexo E.4).

## 5. Passo a Passo

1. **Registrar.** Abrir o registro do incidente com horário de detecção, sintoma e quem detectou. Em S1/S2 o registro não pode atrasar a mitigação — uma linha basta no início; o incident report completo (Anexo E.4) é elaborado durante/após a resposta;
2. **Classificar a severidade:**

   | Nível | Definição | Mobilização |
   |---|---|---|
   | **S1** | Produção fora do ar ou risco de perda de dados | **Toda a equipe** |
   | **S2** | Degradação severa ou funcionalidade crítica indisponível em produção | DevOps + devs envolvidos |
   | **S3** | Impacto parcial em produção ou ambiente de homologação fora | DevOps ou dev responsável, fluxo priorizado |
   | **S4** | Impacto menor, sem urgência | Backlog |

3. **Comunicar e mobilizar.** S1/S2: avisar imediatamente o canal do time e mobilizar conforme a tabela; definir quem coordena. Suporte comunica clientes se houver impacto externo;
4. **Triagem.** Percorrer as causas conhecidas (Anexo E.2) e, em paralelo, investigar com as ferramentas de observabilidade (Anexo E.1): estado de servidores/stacks/filas no Sentinel; dashboards, **traces (Tempo), logs (Loki) e profiling (Pyroscope)** via Grafana para chegar à causa; verificar mudanças recentes (último deploy? mudança de pipeline? mudança de rede?);
5. **Mitigar** com a ação mais barata e reversível primeiro (Anexo E.3): rollback para regressão pós-deploy, restart controlado para serviço travado, contenção de ofensor de rede, acompanhamento quando a causa é externa. ⚠️ Ações em VPN/roteador exigem cautela extra (risco de perda do próprio acesso — Anexo E.3);
6. **Validar a recuperação** com os mesmos indicadores que detectaram o problema — não apenas pela ausência de reclamações. Conferir a mensagem de **normalização** do alerta no Sentinel, quando aplicável;
7. **Encerrar e registrar.** Concluir o **incident report** (Anexo E.4) com timeline, métricas, traces, causa raiz, ações tomadas e lições;
8. **Post-mortem (obrigatório para S1/S2)** em até 5 dias úteis, a partir do incident report: o que aconteceu, por quê, como foi detectado, o que reduziria detecção/recuperação e ações preventivas — cada ação preventiva vira um item de backlog (work item/PBI) com dono. Sem busca de culpados;
9. **Atualizar este POP** quando o incidente revelar causa recorrente nova (acrescentar ao Anexo E.2).

## 6. Critérios de Sucesso

- Incidente registrado com horário de detecção e severidade classificada;
- Mitigação aplicada e recuperação validada por indicador (métrica/log/normalização do alerta), não por suposição;
- Incident report completo com timeline, causa raiz e lições;
- Post-mortem realizado para S1/S2, com ações preventivas no backlog.

## 7. Riscos

| Risco | Impacto | Mitigação |
|---|---|---|
| Diagnóstico por suposição ("é DDoS", "é o deploy") | Mitigação errada, incidente prolongado | Causas conhecidas + investigação por traces/logs/métricas antes de agir (passo 4) |
| Alertas do Grafana sem canal de notificação configurado | Alertas críticos disparam mas ninguém é notificado (hoje só o Sentinel notifica) | Configurar contact point real no Grafana; enquanto isso, tratar o Sentinel como canal primário |
| Perda do próprio acesso ao mexer em VPN/roteador | Time isolado da infraestrutura durante o incidente | Cautelas do Anexo E.3 (backup de config, acesso alternativo) |
| Mitigar sem registrar | Conhecimento perdido, incidente recorrente | Passos 1 e 7 obrigatórios |
| Rollback sem plano (migrations) | Agravamento com perda de dados | Seguir o plano de reversão do POP-DV-004 |
| Falta de coordenador definido | Ações duplicadas/conflitantes | Passo 3 define quem coordena |

## 8. Evidências

- **Incident report** em `Sittax.Observability/reports/` (Anexo E.4) com timeline (detecção → mitigação → recuperação), métricas, traces e causa raiz;
- Alertas disparados e normalizados (histórico do Sentinel / mensagens Telegram-WhatsApp);
- Comandos executados e configurações alteradas (com diff/backup quando aplicável);
- Post-mortem (S1/S2) e work items das ações preventivas no backlog.

## 9. Histórico de Alterações

| Versão | Data | Autor | Descrição |
|---|---|---|---|
| 1.0 | 2026-06-11 | Leonardo Queiros | Versão inicial |

---

## Anexo E — Referências técnicas para resposta a incidentes

### E.1 Plataformas de monitoramento e acessos de emergência

Os dois sistemas de monitoramento têm papéis distintos no incidente: o **Sentinel** (`Sittax.Monitor`) **detecta e notifica**; o **Grafana** da stack `Sittax.Observability` é onde se **investiga** a causa raiz (traces, logs, métricas, profiling).

| Plataforma | Onde | O que oferece no incidente |
|---|---|---|
| **Sentinel** (`Sittax.Monitor`) | `https://sentinel.sittax.com.br` | Status de servidores (CPU/memória/disco), ambientes/stacks com réplicas (agente no manager `.116`, atualização ~60s), filas RabbitMQ, uptime de sites monitorados, eventos do Watchdog (memory pressure); **alertas automáticos via Telegram/WhatsApp** em níveis aviso/alerta/crítico, com mensagem de normalização |
| **Grafana** (`Sittax.Observability`) | `https://grafana.sittax.com.br` (prod) / `https://grafana.stage.sittax.com.br` (stage/QA, host `192.168.2.149`) | Dashboards (RED overview, HTTP performance, DB overview, .NET runtime, slow queries, RabbitMQ, servidores); **traces** (Tempo), **logs** (Loki), **métricas** (Mimir) e **profiling contínuo** (Pyroscope) para investigação de causa raiz |
| Ingest de telemetria | `https://otel.sittax.com.br` (prod) / `https://otel.stage.sittax.com.br` (stage/QA) | Endpoint OTLP que as aplicações .NET usam — indisponibilidade aqui = cegueira de telemetria (não afeta as aplicações). ⚠️ **O de homologação está fora do ar**; a rota no proxy foi mantida pronta para quando a stack voltar |
| Sessões reais | OpenReplay (`openreplay.sittax.com.br`) | Reprodução de sessões com erro no frontend |
| Sintéticos | Pipelines agendadas (Azure DevOps) e Sorry-Cypress | Sinal de regressão ou indisponibilidade externa |
| Rede | Grafana NetFlow / ClickHouse `netflow.flows` | Top talkers, saturação de upload. ⚠️ O `192.168.2.50` não responde desde 06/08/2026 — confirmar endereço atual |
| Serviços | `docker service ls` / `logs` no manager `192.168.2.116` | Estado e logs dos serviços |
| **Acessos de emergência** | Swarm manager `.116`, proxy `.32`, MikroTik `.1`, VM `new-vpn` (control plane NetBird + Portainer) | Atuação direta quando as plataformas não bastam |

### E.2 Causas conhecidas (consultar antes de hipótese nova)

| Sintoma | Causa conhecida | Verificação |
|---|---|---|
| Queda geral de rede / lentidão ("parece DDoS") | DVRs de CFTV internos (`.54`, `.122`, `.220`) saturando upload nas portas 8080/9090 | Top talkers no ClickHouse `netflow.flows` |
| Serviço de produção down "sem motivo" | Restart policy esgotada após OOMs repetidos (pressão de memória) | Eventos do Watchdog no Sentinel; `docker service ps`; dashboard .NET runtime (memória/GC) |
| Ambiente de homolog/QA fora | Serviços com réplicas 0 no Swarm do `.116` | Página Ambientes do Sentinel. ⚠️ `docker service ls` em `1/1` **não** é saúde: serviço pode estar de pé sem consumir fila. Conferir conexões e filas no broker |
| Certificado TLS inválido/não renova | Rate limit Let's Encrypt (`429`) na conta do Traefik | Logs do `traefik_traefik` no `.116` |
| Erro 525 em um domínio | Cloudflare em modo proxy (orange) contra certificado de origem | Modo do registro no Cloudflare |
| HTTPS resetando via VPN | MTU/PMTUD (WAN PPPoE 1492) | `ping -f -l 1400` pelo túnel. No NetBird (WireGuard) o ajuste é o MTU da interface `wt0`, não há `mssfix` |
| Falha de autenticação/dados em dev | Postgres `192.168.1.109` (`db.dev`) fora | Conectividade na porta 5432 |
| Integrações falhando em massa | Indisponibilidade externa (SEFAZ/eCac/Serpro) | Resultado da `Testes.Integracao` da madrugada; status oficial dos órgãos |

### E.3 Ações de mitigação e cautelas

- **Regressão pós-deploy:** rollback conforme POP-DV-003 (homolog) ou POP-DV-004 (produção);
- **Serviço travado:** `docker service update --force <serviço>` (restart controlado). ⚠️ No `.116`, atualizações de serviço conflitam com a esteira de CI/CD — coordenar com o time de DevOps antes;
- **Pressão de memória/OOM:** investigar com o dashboard .NET runtime + Pyroscope (profiling de alocação) antes de só reiniciar — histórico mostra recorrência (ver incident reports);
- **Filas acumulando:** página de filas do Sentinel + dashboard RabbitMQ; verificar consumers ativos;
- **Ofensor interno de rede:** limitar/bloquear no MikroTik — **antes**, exportar backup da configuração;
- **VPN/roteador:** mexer em policy, rota ou nameserver do NetBird afeta o próprio caminho de acesso — risco de auto-lockout. Garantir acesso alternativo (SSH pela LAN, console do provedor) **antes** de alterar. Lembrar que rota e DNS são distribuídos por grupo: tirar um peer do grupo errado corta o acesso dele sem erro aparente;
- **Causa externa (SEFAZ, eCac, Serpro):** comunicar, acompanhar e registrar — não há mitigação local.

### E.4 Incident report (registro oficial)

Os incidentes são registrados como **incident reports em Markdown** no repositório `Sittax.Observability`, pasta `reports/`, no padrão `incident-AAAA-MM-DD-<descricao>.md`, seguindo o playbook `reports/create-incident-reports.md` (como capturar traces, logs e métricas, e a estrutura do documento). Conteúdo mínimo: timeline, métricas e traces relevantes, causa raiz, ações tomadas e lições. Exemplos no histórico: OOM em API, memory leak em endpoint, services down por restart policy esgotada, timeout em consultas.
