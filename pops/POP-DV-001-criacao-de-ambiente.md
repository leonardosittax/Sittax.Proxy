# POP-DV-001 — Criação de Ambiente

## 1. Objetivo

Padronizar o processo de criação de ambientes para os produtos **Sittax**, **Sittax.ST** e **Sittax.Recupera** — incluindo suas dependências e pré-condições — garantindo que todo ambiente nasça completo (orquestração, configuração, dados, mensageria, DNS, certificado e monitoramento), seguro e rastreável desde o primeiro dia.

## 2. Aplicação

Este processo deve ser utilizado quando:

- For criado um novo ambiente de homologação/QA (ex.: um novo `qa-04`);
- Um produto passar a existir em um ambiente onde ainda não roda (ex.: habilitar Recupera em um `qa-*`);
- For criado um novo ambiente ou serviço de **produção**;
- For preparado o **ambiente local** de um novo desenvolvedor.

## 3. Responsáveis

| Papel | Quem | Responsabilidade |
|---|---|---|
| Execução | Time de DevOps — Leonardo Queiros (principal) e Glaucyo | Provisiona orquestração, pipelines, DNS, banco e monitoramento |
| Aprovação | Time, em reunião de alinhamento | Decide a criação do ambiente; decisão registrada no PBI da demanda |
| Solicitação | Time de produto/desenvolvimento | Define produtos, serviços e configurações necessárias |

## 4. Pré-requisitos

- Decisão de criação aprovada em reunião do time e registrada como PBI;
- Nome do ambiente definido dentro do padrão de nomenclatura (ver Anexo A.1);
- Acessos necessários disponíveis: Azure DevOps (pipelines e Variable Groups), Jenkins, orquestrador (Docker Swarm), DNS/Cloudflare e, para produção, infraestrutura OCI;
- Capacidade de infraestrutura verificada (CPU/RAM/disco do host de homologação);
- Cota de emissão de certificados Let's Encrypt verificada;
- Para ambiente local: máquina do desenvolvedor atendendo aos requisitos da documentação de setup local (Anexo A.7).

## 5. Passo a Passo

### 5.1 Ambiente de homologação/QA (novo ou produto novo em ambiente existente)

1. **Definir escopo.** Registrar no PBI: nome do ambiente, produtos contemplados e nível de exposição (interno via VPN/LAN — padrão — ou público);
2. **Dados e mensageria.** Criar as bases de dados e o virtual host de mensageria do ambiente (Anexo A.5);
3. **Configuração.** Criar a Variable Group do ambiente no Azure DevOps, a partir de um ambiente similar, revisando item a item (Anexo A.2);
4. **Pipelines.** Incluir o ambiente nas pipelines de build e deploy (Anexo A.3);
5. **Orquestração.** Criar a stack do ambiente no Docker Swarm com os serviços, limites e roteamento (Anexo A.4);
6. **DNS.** Criar os registros públicos e as entradas de DNS interno/split-DNS (Anexo A.6);
7. **Certificado.** Aguardar a emissão automática do certificado TLS e validá-lo;
8. **Primeiro deploy.** Executar o deploy inicial pelo processo de Deploy em Homologação (POP-DV-003);
9. **Monitoramento.** Confirmar que os serviços emitem telemetria e incluir o ambiente nos dashboards e suítes de teste aplicáveis (POP-DV-006);
10. **Encerramento.** Documentar nomes, endereços e decisões; encerrar o PBI com as evidências (seção 8).

### 5.2 Ambiente de produção

Segue a **mesma sequência** do item 5.1, executada na infraestrutura interna da OCI, com as particularidades de produção:

- DNS público **com proxy Cloudflare ativo** e WAF na borda;
- Variable Group e segredos de produção;
- Deploy executado via Pipeline/Releases do Azure DevOps (POP-DV-004);
- Janela e comunicação alinhadas com o time antes da ativação.

### 5.3 Ambiente local do desenvolvedor

Seguir a documentação de setup local padrão (Anexo A.7). O ambiente local não cria dependência em infraestrutura compartilhada e não requer aprovação — apenas os acessos concedidos no onboarding.

## 6. Critérios de Sucesso

- Todos os serviços do ambiente ativos, com réplicas completas e sem reinício em loop;
- HTTPS respondendo com certificado válido pelos canais previstos (VPN/LAN para ambientes internos; internet para produção);
- Aplicação funcional: SPA servindo o ambiente correto, API com health-check positivo e autenticação operando;
- Pipelines de deploy reconhecem o ambiente sem ajustes manuais;
- Telemetria do ambiente visível no monitoramento;
- PBI encerrado com as evidências da seção 8.

## 7. Riscos

| Risco | Impacto | Mitigação |
|---|---|---|
| Estouro de cota Let's Encrypt | Ambiente sem certificado; afeta renovações de todos os domínios | Verificar cota antes (pré-requisito); não repetir emissões em loop |
| Variable Group incompleta | Build com tokens não substituídos; comportamento incorreto em runtime | Clonar de ambiente similar e revisar item a item |
| Ambiente ausente na pipeline do SPA | Aplicação serve a página de fallback em vez do ambiente | Atualizar a lista de ambientes da pipeline junto (Anexo A.3) |
| Nome fora do padrão de nomenclatura | Host escapa do DNS interno e resolve público | Seguir o padrão (Anexo A.1); exceções exigem regra manual |
| Falta de capacidade no host | Serviços sem réplicas, ambiente instável | Verificação de capacidade (pré-requisito) |
| Modo Cloudflare incorreto | Interno em proxy gera erro de handshake; produção sem proxy perde WAF | Interno = DNS-only; produção = proxy + WAF (Anexo A.6) |

## 8. Evidências

Anexar ao PBI de criação:

- Registro da aprovação em reunião (no próprio PBI);
- Saída da verificação de serviços ativos do ambiente;
- Verificação do certificado TLS válido;
- Identificação da Variable Group criada (sem expor segredos);
- Commits das alterações (stack, pipelines, DNS interno);
- Execução do primeiro deploy.

## 9. Histórico de Alterações

| Versão | Data | Autor | Descrição |
|---|---|---|---|
| 1.0 | 2026-06-11 | Leonardo Queiros | Versão inicial |

---

## Anexo A — Detalhes técnicos de execução

### A.1 Nomenclatura

Padrão: `<env>.sittax.com.br` + subdomínios `*.<env>.sittax.com.br`. Ambientes atuais: `dev`, `qa-01`, `qa-02`, `qa-03`, `stage`, `comercial`, `prd`. Evitar nomes concatenados sem ponto (ex.: `apisthomologacao`) — ficam fora do split-DNS e exigem regra manual no dnsmasq e no nginx.

### A.2 Variable Groups (Azure DevOps)

Grupos existentes: `Produção`, `Homologação`, `QA01`, `QA02`, `QA03`, `DEV`, `Comercial`. Conter endpoints, strings de conexão e chaves do ambiente. O SPA usa token replacement (`{{BASE_URL}}`, `{{AMBIENTE}}`, `{{BASE_URL_AUTH}}` etc.) — token faltante quebra o build silenciosamente.

### A.3 Pipelines a atualizar

- `sittax-solutions.yml` — adicionar o ambiente ao parâmetro `ambiente`;
- `sittax-spa-amd_arm-64.yml` — adicionar à lista `environments` e criar o job de build (imagem `sittax-spa` é única multi-ambiente; ambiente ausente cai na página `_fallback`);
- Job Jenkins `Solutions/Deploy.Stack` — garantir que aceita o novo valor de `ENV`.

### A.4 Stack no Docker Swarm

Host de homologação: manager `192.168.2.116` (SSH user `ubuntu`). Padrão de serviços: `<env>_<serviço>` (`api`, `app`, `worker-services`...), labels Traefik (router HTTPS + `leresolver` para ACME HTTP-01), limites de memória e réplicas definidos. SPA: `NGINX_ROOT=<env>`. ⚠️ A porta 80 pública não pode ser bloqueada — é o canal de renovação ACME.

### A.5 Dados e mensageria

Bases SQL Server no padrão do ambiente (staging: `SittaxStaging*`, `SittaxRecuperaStaging` etc.). RabbitMQ: virtual host por ambiente (ex.: `Homolog`, `Dev`).

### A.6 DNS

- **Público (Cloudflare):** registro → `177.223.44.35`. Ambientes internos em **gray/DNS-only** (proxy ativo contra cert de origem gera erro 525). **Produção em orange (proxy ativo) + WAF.**
- **Interno (split-DNS):** no proxy `192.168.2.32`, adicionar `address=/<env>.sittax.com.br/192.168.2.32` em `/etc/dnsmasq.d/sittax-split.conf` e o SNI do ambiente nos mapas `upstream_*.conf` do nginx (repositório `Sittax.Proxy`, aplicação via `update.sh`).

### A.7 Setup local do desenvolvedor

Documentação padrão de setup local: **[CONFIRMAR localização — README por produto? wiki?]**. Requisitos típicos: SDKs (.NET/Node), Docker, acesso ao feed npm/NuGet privado e às credenciais de desenvolvimento.

### A.8 Verificações de sucesso

- `docker service ls | grep <env>_` — réplicas completas;
- `curl -v https://<env>.sittax.com.br` — certificado válido;
- `/versao` do SPA e health-check da API respondendo;
- Traces chegando no coletor OTEL (`10.0.0.57:4318`).
