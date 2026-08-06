# Plano de Ação — Isolamento de Acesso ao Ambiente de Homologação

> **Status (2026-06-01):** PARCIALMENTE EXECUTADO, com abordagem **simplificada** frente ao
> rascunho original (3 camadas). A solução real: **split-DNS no MikroTik + ajustes na VPN `.138`,
> concentrando o roteamento no proxy `.32`** — ver **§0**. O **bloqueio público foi adiado**
> (não aplicado). As seções 1–9 abaixo são o rascunho original (contexto/achados ainda úteis,
> partes superadas pela §0).
>
> **Objetivo:** ambientes de homolog/dev/QA (`*.{stage,dev,qa01,qa02,qa03}.sittax.com.br`)
> acessíveis por **VPN ou LAN do escritório**, mantendo **Let's Encrypt** e **sem** apontar
> DNS público para IP interno. **Produção (`app.sittax.com.br`) permanece pública/intacta.**

---

## 0. Execução real (2026-06-01)

### ✅ O que foi feito (passo a passo)

1. **Levantamento.** Via DNS público: `stage.sittax.com.br` (apex) estava **atrás do
   Cloudflare (orange)** e `*.stage` era **wildcard cinza** (`→ devserver → 177.223.44.35`).
   A premissa do rascunho ("tudo gray, DNS → WAN") estava **errada para o apex**.
   `.149` (observability stage) continua **vivo**.

2. **Split-DNS — `dnsmasq` no `.32`** (manda os ambientes para o proxy `.32`):
   - **Decisão final:** o split-DNS **saiu do MikroTik** e foi para **dnsmasq no `.32`**. O MikroTik
     6.49 não dava conta (sem alternância `(a|b|c)`, não casava o apex vazio, nome-exato não ganhava
     de regex, sem AAAA-NODATA — fonte de "alguns problemas"). O MikroTik agora **só encaminha**
     (`/ip dns set servers=192.168.2.32`) e perdeu os `static` de sittax.
   - dnsmasq (`/etc/dnsmasq.d/sittax-split.conf`, escuta só `192.168.2.32:53`):
     `address=/<env>.sittax.com.br/192.168.2.32` (wildcard = apex + subdomínios numa linha) p/
     `stage|dev|qa01|qa02|qa03`; exceções `db.dev → 192.168.1.109` (Postgres) e
     `internal.dev → 192.168.2.116` (dnsmasq usa o match mais específico); **AAAA = NODATA**
     automático (força IPv4, sem sinkhole). Produção (`app.sittax.com.br`) é encaminhada pra
     internet, não vai pro `.32`.
   - Comandos e detalhes: **`dns-dnsmasq.md`** (o `mikrotik-split-dns.md` ficou SUPERADO/histórico).

3. **VPN OpenVPN `.138`** (`/etc/openvpn/server/server.conf`):
   - `push "dhcp-option DNS 192.168.2.1"` + `push "block-outside-dns"` — faz o cliente usar o
     DNS do túnel (corrige vazamento de DNS do Windows no split-tunnel). **Server-side, sem
     mexer na máquina do usuário** (só reconectar).
   - `tun-mtu 1500` + `mssfix 1360` — corrigiu **HTTPS resetando pela VPN**: era **MTU/PMTUD
     blackhole** (WAN PPPoE 1492; `ping -f -l 1472` dava timeout, `1400` passava).
   - Confirmado: VPN resolve `stage → 192.168.2.32` e abre HTTPS com cert LE válido.

4. **Cloudflare:** `stage` e `sentry` tirados do proxy (**orange → gray**) → resolvem direto
   na origem (`177.223.44.35`), eliminando o erro **525** (handshake CF↔origem).
   `grafana.sittax.com.br` **ainda orange**.

5. **Proxy `.32`:** gate de bloqueio público preparado em `upstream_https.conf`
   (`geo $allowed_ip` com `default 0`) — **NÃO deployado** (bloqueio adiado).

### 🔧 O que ainda precisa corrigir (URLs e pendências)

1. **URLs fora do padrão de ambiente** — rodam no `.116` mas o split-DNS estreito **NÃO cobre**
   (resolvem público; OK enquanto nada está bloqueado, mas ficam de fora quando bloquear):
   - Família **`homologacao`**: `homologacao.sittax.com.br`, `apihomologacao`,
     `autenticacaohomologacao`, `apuracaohomologacao`, `recuperahomologacao`, … (parece ambiente real).
   - Família **`st`**: `sthomologacao`, `apisthomologacao`, `previewst`, …
   - Tools **`*dev`** (concatenado): `portainerdev`, `browserlessdev`, `traefikdev`, `storagedev`, …
   - `redmine`, `sonarqube`, `n8nmarketing`.
   - ➡️ **Decidir quais entram no split-DNS.** Nomes concatenados (`apihomologacao`, sem ponto)
     exigem ajuste de regex (ver `mikrotik-split-dns.md`). Tornar esses hosts **explícitos** nos
     mapas do nginx: ver **`nginx.conf.patch.md` §1**.

2. 🔴 **Let's Encrypt PAUSADO** no `.116` (`429 rateLimited` — conta temporariamente pausada).
   Certs **não renovam**.
   - **Unpause** no link `portal.letsencrypt.org/sfe/...` que aparece nos logs do `traefik_traefik`.
   - **Reduzir nº de domínios/pedidos** (`acme.json` com **1.15 MB** = domínios demais → rate limit).
   - **Crítico agora** que `stage`/`sentry` são **gray** (dependem do cert de **origem** direto,
     sem o cert de borda do Cloudflare como rede de segurança).

3. **Serviços down:** muitos `qa-02_*` e `qa-03_*` em **0 réplicas** no Swarm do `.116`.

4. **Bloqueio público** (núcleo do objetivo) **ainda não aplicado** — adiado. Opções: dropar
   **443 de entrada na WAN** do MikroTik (`in-interface=<WAN>`), ou deployar o gate do `.32`
   (`upstream_https.conf`). **Porta 80/ACME não pode ser bloqueada** (renovação LE).

### 📁 Arquivos relacionados
- **`mikrotik-split-dns.md`** — comandos do split-DNS (apex `name=` + subdomínios regex + sinkhole AAAA).
- **`upstream_https.conf`** — gate de bloqueio (`geo` default-deny) — **não deployado**.
- **`nginx.conf.patch.md`** — patch de 522/failover + mapeamento explícito de `stage.*` (URLs).

---

## 1. Topologia descoberta (verificada)

| Host | Papel | Detalhes confirmados |
|---|---|---|
| **192.168.2.32** (`nginx`) | Proxy reverso | nginx em modo **stream / TLS passthrough** (`ssl_preread`, sem terminar TLS). Porta 80 cai no router HTTP `127.0.0.1:8080`. Configs em `/etc/nginx/upstream_*.conf`. |
| **192.168.2.116** (`sittaxcicd`) | **Homologação + catch-all + esteira CI** | **Traefik (Docker Swarm) + CrowdSec.** ACME = **HTTP-01** (`leresolver`, entrypoint `web` = `:80`), `acme.json` em `/home/ubuntu/traefik/acme.json`. `http-catchall` redireciona 80→443. É o backend `allDefault`/`allDefault_http`. SSH: `ubuntu`. |
| **192.168.2.138** | **VPN OpenVPN (homolog)** | `topology subnet` + `client-config-dir ccd` + `push "route 192.168.0.0 255.255.0.0"`. **Sem `redirect-gateway` → split-tunnel.** Pool VPN: **`10.8.0.0/24`**. Política `FORWARD` = **`ACCEPT`** (ver Achado #2). SSH: `ubuntu` (sudo pede senha). |
| **192.168.2.1** | Gateway / MikroTik | hEX RB750Gr3, RouterOS 6.49.10. Candidato natural a resolver DNS interno (split-DNS). |
| 177.223.44.35 | IP público (WAN) | DNS público de `stage.*` deve apontar para cá (confirmar — ver Fase 0). |
| ~~192.168.2.149~~ | Traefik antigo | **DESCONTINUADO** — migrou tudo p/ `.116`. |
| ~~192.168.2.250 / .249~~ | bytoken / bytoken2 | **DESCONTINUADOS.** |

**Agente VPN** (`Sittax.Monitor/vpn-agent`): roda junto ao `.138`. Faz **IP fixo por cliente** (CCD `ifconfig-push`, faixa `10.8.0.0/24`) e **ACL por cliente** via `iptables -I FORWARD -s <ip_cliente> -d <destino> -j ACCEPT` (tabela `vpn_acls`). **Premissa do código** (`firewall.service.ts`): *"o DROP geral de FORWARD já bloqueia o resto"* — premissa hoje **falsa** (Achado #2).

---

## 2. Princípio da solução — 3 camadas

```
                         stage.sittax.com.br ?
        ┌─────────────────────────┼──────────────────────────┐
   INTERNET PÚBLICA          VPN / LAN escritório        Let's Encrypt (ACME)
        │                         │                            │
   DNS público                SPLIT-DNS (interno)          DNS público
   → 177.223.44.35            → 192.168.2.116              → 177.223.44.35
        │                         │ (direto, via túnel)        │
   proxy .32                  .138 (VPN) decide QUEM        proxy .32 porta 80
   bloqueia 443 (CAMADA 1)    pode (CAMADA 3, opcional)     /.well-known/acme-challenge/
   🚫                         ✅ autorizado / 🚫 não         → .116:80 → renova ✅
```

| Camada | Onde | O que faz | Risco | Prioridade |
|---|---|---|---|---|
| **1. Bloqueio público** | proxy `.32` (`upstream_https.conf`) | nega SNI `*.stage` na 443; mantém 80 p/ ACME | Baixo | **Núcleo** |
| **2. Split-DNS** | MikroTik `.1` + push OpenVPN `.138` | VPN/LAN resolvem `stage → .116` e vão direto | Baixo | **Núcleo** |
| **3. ACL granular por usuário** | agente no `.138` | limita *quais* clientes VPN chegam no `.116` | Médio / **experimental** | Opcional |

> As camadas 1 + 2 **já entregam o objetivo** ("homolog só pela VPN/escritório, internet bloqueada, LE funcionando"). A camada 3 só é necessária se **alguns** usuários da VPN **não** podem ver a homologação.

---

## 3. Achados importantes (riscos a tratar)

### Achado #1 — O bloqueio de IP atual do proxy é um no-op
Em `upstream_https.conf`, o `geo $allowed_ip { default 1; ... }` tem **default `1` (permitido)** e **todas** as entradas também são `1`. Logo `$allowed_ip` é **sempre 1** e as regras `"prometheus.sittax.com.br:0" → deny_backend` (e `monitor`, `prometheus2`) **nunca disparam**. Hoje `prometheus`/`monitor` estão **abertos**, apesar de parecerem protegidos.
➡️ O plano **não mexe** nesse bloco (pra não mudar o comportamento atual deles) e cria um `geo` **dedicado** com `default 0` só para a homologação.

### Achado #2 — `FORWARD` em ACCEPT torna o ACL do agente decorativo
No `.138`: `-P FORWARD ACCEPT`. Como não existe o DROP geral que o `firewall.service.ts` assume, **qualquer cliente VPN alcança qualquer host da LAN hoje** (incl. homologação), tendo ACL ou não.
➡️ A camada 3 **só funciona** depois de transformar o VPN→LAN em **default-deny** (com rede de resgate — ver Fase 2).

### Achado #3 — Rota empurrada é larga demais
`push "route 192.168.0.0 255.255.0.0"` (/16) captura **qualquer** `192.168.x.x`. Se a rede **doméstica** do usuário for `192.168.0.x`/`192.168.1.x`, o túnel "engole" a LAN da casa dele (impressora/NAS). **Não afeta tráfego de internet** (torrent/streaming continuam pelo ISP de casa — split-tunnel), mas vale estreitar para `192.168.2.0/24`.

### Achado #4 — IP fixo (CCD) não funciona na VPN de PROD
Confirmado pelo time: a versão do OpenVPN em **produção** não suporta a fixação de IP por CCD. Portanto a camada 3 (ACL por IP fixo) é viável **apenas na VPN de homologação (`.138`)**, não em prod. Para este plano isso é OK (o alvo é homolog), mas **documentar** para não tentar replicar em prod.

### Achado #5 — Sobreposição de regras (ACL experimental)
O agente insere regras com `-I FORWARD` (topo) e há ainda as chains do Docker (`DOCKER-USER`, `DOCKER-FORWARD`) no `FORWARD`. Qualquer DROP catch-all precisa ficar **abaixo** dos ACCEPT e a ordem precisa ser validada a cada restart do Docker. Tratar como **experimental**.

### Achado #6 — IP **não é identidade** (a raiz do problema do ACL)
**Motivo real de o `FORWARD` estar em ACCEPT** (dito pelo time): sem IP fixo confiável, bloquear `10.8.0.x` é inútil — o cliente reconecta, **pega outro IP do pool e o DROP deixa de valer**. Bloquear/permitir por IP só funciona se o IP for estável por usuário, o que hoje não é (CCD não fixa de forma confiável; em prod nem suporta — Achado #4).
➡️ **A primitiva de controle tem que ser o certificado / Common Name (CN), não o IP.** Três caminhos robustos (ver Fase 2, reescrita):
1. **Bloqueio total = revogar o certificado (CRL)** via `easyrsa` — o cliente simplesmente não conecta mais, em nenhum IP. O agente já faz isso (`vpn.service.ts`).
2. **Restringir sem bloquear = hook `client-connect`/`learn-address`** — a cada conexão o OpenVPN sabe o CN **e** o IP atribuído naquela sessão; o hook aplica/remove a regra `FORWARD` para `CN → IP-da-sessão`. Sobrevive à troca de IP. O agente **já tem** `hooks.ts` (client-connect/disconnect) — é o lugar certo.
3. **Separar por pool/perfil de IP por tier de acesso** — quem pode ver homolog conecta num perfil/instância que entrega IPs de uma **faixa dedicada** (ex.: `10.8.1.0/24`); o firewall filtra por faixa **estável**, sem depender de fixar IP individual. Controle de quem-vai-pra-qual-faixa é feito pelo certificado/perfil.

---

## 4. FASE 0 — Levantamento prévio (OBRIGATÓRIO antes de bloquear)

Objetivo: descobrir **tudo que acessa `stage.*` de fora da VPN/LAN** para não derrubar a esteira.

- [ ] Confirmar resolução pública: `dig +short stage.sittax.com.br` → deve ser `177.223.44.35` (Cloudflare **cinza/DNS-only**; se for "laranja"/proxied, o passthrough não funcionaria — revisar).
- [ ] Levantar nos logs do proxy quem bate em `stage.*` de IP **externo** (rodar no `.32`):
  ```bash
  sudo grep -hE 'stage\.sittax' /var/log/nginx/stream_https.access.log \
    | grep -vE 'Client: (192\.168\.|10\.8\.|127\.0\.0\.1)' \
    | awk -F'Client: ' '{print $2}' | awk '{print $1}' | sort | uniq -c | sort -rn | head -30
  ```
- [ ] Mapear consumidores legítimos externos e decidir se entram na allowlist:
  - Webhooks de CI/CD (GitHub/GitLab) que disparam deploy na esteira?
  - Servidores Oracle de prod que chamam APIs de homolog? (`129.151.34.229`, `137.131.155.44`, `144.22.229.35`, `168.138.153.188`, `168.75.93.95`)
  - Monitoração/uptime externa apontando para `stage.*`?
  - IP do DevOps (`179.253.141.253`).
- [ ] Resultado → lista final de IPs/CIDRs para o `geo $homolog_allowed` da Fase 1.3.

---

## 5. FASE 1 — Núcleo (split-DNS + bloqueio público) — *baixo risco*

### 1.1 Split-DNS no MikroTik (`192.168.2.1`)
```routeros
/ip dns
set allow-remote-requests=yes

/ip dns static
add name="stage.sittax.com.br" address=192.168.2.116 comment="split-DNS homolog"
add regexp=".*\\.stage\\.sittax\\.com\\.br\$" address=192.168.2.116 comment="split-DNS *.stage"

# DNS só para LAN e VPN (NUNCA expor :53 na WAN — vira open resolver)
/ip firewall filter
add chain=input protocol=udp dst-port=53 src-address=192.168.2.0/24 action=accept comment="DNS LAN"
add chain=input protocol=tcp dst-port=53 src-address=192.168.2.0/24 action=accept
add chain=input protocol=udp dst-port=53 src-address=10.8.0.0/24 action=accept comment="DNS VPN homolog"
add chain=input protocol=tcp dst-port=53 src-address=10.8.0.0/24 action=accept
```

### 1.2 Push do DNS no OpenVPN (`.138`, `server.conf`)
```
# (já existe) rota p/ LAN — recomendado estreitar para 192.168.2.0/24:
# push "route 192.168.2.0 255.255.255.0"
push "dhcp-option DNS 192.168.2.1"
# opcional (OpenVPN 2.5+): manda só este domínio para o DNS da VPN
push "dhcp-option DOMAIN-ROUTE sittax.com.br"
```
> Clientes no escritório (LAN) já usam o MikroTik como DNS via DHCP → a entrada do 1.1 já vale para eles, sem precisar do push.

### 1.3 Bloqueio público no proxy (`.32`, `upstream_https.conf`)
Substituir o bloco de controle de acesso atual por (mantendo o `geo $allowed_ip` antigo intacto — Achado #1):
```nginx
# === Allowlist DEDICADA p/ ambientes restritos (default 0 = NEGA) ===
geo $homolog_allowed {
    default            0;
    127.0.0.1/32       1;
    192.168.1.0/24     1;   # LAN antiga
    192.168.2.0/24     1;   # LAN nova (inclui o próprio .116)
    10.8.0.0/24        1;   # pool OpenVPN homolog (.138)
    172.20.0.0/16      1;   # rede docker
    177.223.44.35      1;   # WAN do escritório (saída/hairpin)
    179.253.141.253    1;   # DevOps
    # >>> ADICIONAR aqui os IPs externos legítimos levantados na FASE 0 <<<
}

# === Marca SNIs de homologação ===
map $ssl_preread_server_name $is_homolog {
    default                              0;
    stage.sittax.com.br                  1;
    "~*^[^.]+\.stage\.sittax\.com\.br$"  1;   # *.stage.sittax.com.br
}

# === (INALTERADO) bloqueio antigo prometheus/monitor — ver Achado #1 ===
map "$ssl_preread_server_name:$allowed_ip" $base_backend_https {
    "prometheus.sittax.com.br:0"   deny_backend;
    "prometheus2.sittax.com.br:0"  deny_backend;
    "monitor.sittax.com.br:0"      deny_backend;
    default                        $lk_backend_name_https;
}

# === Gate final: homolog + IP não autorizado => deny ===
map "$is_homolog:$homolog_allowed" $backend_name_https {
    "1:0"      deny_backend;     # é homolog E fora da allowlist -> bloqueia
    default    $base_backend_https;
}
```
- **Porta 443:** público pedindo SNI `*.stage` → `deny_backend` (`127.0.0.1:9`, conexão recusada).
- **Porta 80:** **NÃO mexer** — `/.well-known/acme-challenge/` segue público e o Traefik renova o cert por HTTP-01. (Endurecer a 80 é opcional e fica para depois.)

### 1.4 Validação e rollback (Fase 1)
```bash
# no .32
sudo nginx -t && sudo systemctl reload nginx     # reload é zero-downtime

# Testes:
#  - de fora da VPN: https://stage.sittax.com.br  -> deve FALHAR (conexão recusada)
#  - na VPN/LAN (com split-DNS):                  -> deve ABRIR normal, cert válido
#  - renovação LE:  curl -I http://stage.sittax.com.br/.well-known/acme-challenge/teste  -> chega no .116
```
**Rollback:** `git checkout upstream_https.conf && sudo nginx -t && sudo systemctl reload nginx`.
No MikroTik: `/ip dns static remove [find comment~"split-DNS"]`.

### ✅ Teste rápido ANTES de tudo (sem mexer em nada)
Num PC **na VPN**, adicionar ao `hosts` (`/etc/hosts` ou `C:\Windows\System32\drivers\etc\hosts`):
```
192.168.2.116   stage.sittax.com.br
```
Abrir `https://stage.sittax.com.br`. Se carregar com cert válido → o caminho direto funciona e o split-DNS vai funcionar. (Remover a linha depois do teste.)

---

## 6. FASE 2 — (opcional / EXPERIMENTAL) controle granular por usuário no `.138`

> Só necessária se **alguns** usuários da VPN não podem ver a homologação.
> **Experimental** (Achados #2, #4, #5, #6). Não fazer junto com a Fase 1 — validar separadamente.
>
> ⚠️ **Não controle por IP** (Achado #6): IP não é identidade. Escolha uma das abordagens por **certificado/CN** abaixo.

### Opção 2A — Bloqueio total = revogar o certificado (mais simples e robusto)
"Tirar o Leonardo" de vez = revogar o cert dele (CRL via `easyrsa`, já implementado no agente). Ele não conecta mais, em nenhum IP. Não exige mexer no FORWARD. **Recomendado para "remover acesso".**

### Opção 2B — Restringir sem bloquear (CN → IP-da-sessão, via hook)
Para "Leonardo conecta mas **não** vê homolog": usar o `client-connect`/`client-disconnect` (o agente já tem `hooks.ts`). A cada conexão, o hook recebe o CN e o `$ifconfig_pool_remote_ip` daquela sessão e:
- aplica `iptables -I FORWARD -s <IP_da_sessão> -d 192.168.2.116 -p tcp --dport 443 -j ACCEPT` **se** o CN for autorizado;
- no disconnect, remove a regra daquele IP.
Combinar com o **default-deny** abaixo. Como a regra é (re)criada por CN a cada conexão, **sobrevive à troca de IP** — resolve exatamente o problema do Achado #6.

### Opção 2C — Tier por faixa de IP (sem fixar IP individual)
Autorizados conectam num perfil/instância que entrega IPs de faixa dedicada (ex.: `10.8.1.0/24`); firewall libera só `10.8.1.0/24 → 192.168.2.116`. Faixa é estável; o "quem entra em qual faixa" é decidido pelo certificado/perfil, não por fixação individual.

---

**Pré-requisito comum (2B/2C) — transformar VPN→LAN em default-deny COM rede de resgate:**
```bash
# 1) REDE DE RESGATE primeiro: reverte tudo em 10 min se algo travar
echo 'iptables -P FORWARD ACCEPT; iptables -D FORWARD -s 10.8.0.0/24 -d 192.168.0.0/16 -j DROP 2>/dev/null' \
  | at now + 10 minutes

# 2) Garantir ACCEPT do que não pode cair (established + acesso do próprio agente/SSH)
sudo iptables -I FORWARD 1 -m state --state ESTABLISHED,RELATED -j ACCEPT

# 3) (as ACLs por cliente do agente entram aqui, ACIMA do DROP, via -I FORWARD)

# 4) DROP catch-all VPN -> LAN (no FINAL, abaixo dos ACCEPT)
sudo iptables -A FORWARD -s 10.8.0.0/24 -d 192.168.0.0/16 -j DROP
```
Validar acesso de um cliente autorizado e de um não-autorizado. Se OK, **cancelar o resgate** (`atq` / `atrm`) e **persistir** (`netfilter-persistent save` ou equivalente). Reavaliar a ordem após qualquer `restart` do Docker (Achado #5).

**Modelo de ACL para "tem acesso à homologação"** (via UI do Monitor / API do agente), por chave autorizada:
| destinationIp | port | proto | nota |
|---|---|---|---|
| `192.168.2.116` | `443` | tcp | app homolog |
| `192.168.2.116` | `80` | tcp | redirect/ACME (se necessário) |

Quem **não** tem essas ACLs → bloqueado pelo DROP catch-all.

**Limitações a registrar:** não replicar em **prod** (CCD não funciona lá — Achado #4); cuidado com sobreposição/ordem de regras (Achado #5).

---

## 7. Checklist de execução (fim de semana)

- [ ] **Fase 0** concluída (lista de IPs externos legítimos fechada).
- [ ] Teste do `hosts` na VPN OK (cert válido indo direto no `.116`).
- [ ] **1.1** split-DNS no MikroTik aplicado e testado (`nslookup stage.sittax.com.br` na VPN → `192.168.2.116`).
- [ ] **1.2** push DNS no OpenVPN + reconectar 1 cliente de teste.
- [ ] **1.3** patch no `upstream_https.conf` + `nginx -t` + reload.
- [ ] **1.4** validação: bloqueado de fora / abre de dentro / ACME chega no `.116`.
- [ ] Forçar/verificar uma renovação do cert no Traefik (`.116`) para garantir HTTP-01 intacto.
- [ ] (opcional) **Fase 2** com rede de resgate.
- [ ] Commit das mudanças do `Sittax.Proxy` com mensagem clara.

## 8. Rollback geral
- **Proxy:** `git checkout upstream_https.conf` + reload.
- **MikroTik:** remover entradas `/ip dns static` com comentário `split-DNS`.
- **OpenVPN:** remover linhas `push "dhcp-option DNS ..."` + reiniciar serviço.
- **Firewall .138:** `iptables -P FORWARD ACCEPT` + remover o DROP catch-all (a rede de resgate já faz isso automaticamente em 10 min).

---

## 9. Repositórios/arquivos afetados
- `Sittax.Proxy/upstream_https.conf` — bloqueio público (Fase 1.3).
- MikroTik `192.168.2.1` — `/ip dns static` + firewall input (Fase 1.1).
- OpenVPN `192.168.2.138` — `server.conf` push DNS (Fase 1.2) e firewall `FORWARD` (Fase 2).
- `Sittax.Monitor/vpn-agent` — ACLs por cliente (Fase 2, via UI/API; sem mudança de código necessária para o MVP).
