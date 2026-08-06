# MikroTik (`192.168.2.1`) — Split-DNS dos ambientes (homolog/dev/qa)

> ⛔ **SUPERADO (2026-06-01).** O split-DNS saiu do MikroTik e foi para **dnsmasq no `.32`** —
> ver **`dns-dnsmasq.md`**. O MikroTik 6.49 não dava conta (sem alternância `(a|b|c)`, não casava
> o apex vazio, nome-exato não ganhava de regex, sem AAAA-NODATA). Agora o MikroTik só **encaminha**
> pro `.32` (`/ip dns set servers=192.168.2.32`) e **não tem mais** `/ip dns static` de sittax.
> Este arquivo fica como **histórico** dos achados/gotchas da RouterOS.

> **Objetivo:** VPN e LAN resolverem os ambientes
> `*.{stage,dev,qa01,qa02,qa03}.sittax.com.br` para o **proxy interno `192.168.2.32`**
> (que roteia por SNI até o `.116`), mantendo **produção** (`app.sittax.com.br`, etc.)
> e o restante resolvendo **público** normalmente.
>
> **Exceção `dev`:** `db.dev.sittax.com.br` é **PostgreSQL (TCP 5432)**, não HTTP/SNI —
> então **não passa pelo proxy `.32`**; resolve direto no banco `192.168.1.109`.
> Os demais hosts de `dev` vão pro `.32` normalmente.
>
> A regex é **estreita de propósito**: a versão ampla (`^(.*\.)?sittax\.com\.br$`)
> capturava produção também e quebrava o acesso a `app.sittax.com.br` pela VPN.
>
> Última atualização: **2026-06-01**.

---

## 1. Split-DNS

`stage`/`qa01`/`qa02`/`qa03` usam **regex** (mandam tudo pro `.32`).
`dev` é tratado **sem regex** (lista por nome exato), porque o `db.dev` precisa de um
destino diferente e a RouterOS 6.49 **não tem negative-lookahead** para excluir um host
de dentro de um regex.

> ⚠️ **NÃO usar alternância `(stage|dev|qa01|qa02|qa03)` numa única regra** — a RouterOS
> **6.49.10 não casa** esse padrão (testado 2026-06-01: derrubou o split-DNS, `stage`
> voltou pro Cloudflare). Usar **uma entrada por ambiente**.

```routeros
# DNS interno precisa estar ligado (provavelmente já está):
/ip dns set allow-remote-requests=yes

# ver entradas atuais relacionadas a sittax:
/ip dns static print where regexp~"sittax"

# remover regras antigas (amplas OU com alternância):
/ip dns static remove [find where comment~"split-DNS"]
/ip dns static remove [find where comment~"sinkhole"]

# A -> stage/qa0x pro proxy interno .32 (uma entrada por ambiente, regex):
/ip dns static add type=A regexp="^(.*\\.)?stage\\.sittax\\.com\\.br\$" address=192.168.2.32 comment="split-DNS envs"
/ip dns static add type=A regexp="^(.*\\.)?qa01\\.sittax\\.com\\.br\$"  address=192.168.2.32 comment="split-DNS envs"
/ip dns static add type=A regexp="^(.*\\.)?qa02\\.sittax\\.com\\.br\$"  address=192.168.2.32 comment="split-DNS envs"
/ip dns static add type=A regexp="^(.*\\.)?qa03\\.sittax\\.com\\.br\$"  address=192.168.2.32 comment="split-DNS envs"

# AAAA -> sinkhole (::1) p/ forçar IPv4 (nomes atrás do Cloudflare têm AAAA público):
/ip dns static add type=AAAA regexp="^(.*\\.)?stage\\.sittax\\.com\\.br\$" address=::1 comment="sinkhole AAAA envs"
/ip dns static add type=AAAA regexp="^(.*\\.)?qa01\\.sittax\\.com\\.br\$"  address=::1 comment="sinkhole AAAA envs"
/ip dns static add type=AAAA regexp="^(.*\\.)?qa02\\.sittax\\.com\\.br\$"  address=::1 comment="sinkhole AAAA envs"
/ip dns static add type=AAAA regexp="^(.*\\.)?qa03\\.sittax\\.com\\.br\$"  address=::1 comment="sinkhole AAAA envs"
```

> ⚠️ **O regex `^(.*\.)?<env>\.sittax\.com\.br$` NÃO pega o apex** (`stage.sittax.com.br`):
> a RouterOS 6.49 **não casa o grupo opcional `(.*\.)?` vazio** (testado 2026-06-01 —
> `api.stage` resolvia, mas `stage` ia pro Cloudflare). Por isso os **apex precisam de
> entrada por nome exato** (abaixo). Os regex acima cobrem só os **subdomínios**.

```routeros
# Apex de stage/qa0x — entrada por NOME EXATO (o regex não pega apex):
/ip dns static add name="stage.sittax.com.br" address=192.168.2.32 comment="split-DNS envs"
/ip dns static add name="qa01.sittax.com.br"  address=192.168.2.32 comment="split-DNS envs"
/ip dns static add name="qa02.sittax.com.br"  address=192.168.2.32 comment="split-DNS envs"
/ip dns static add name="qa03.sittax.com.br"  address=192.168.2.32 comment="split-DNS envs"
/ip dns static add type=AAAA name="stage.sittax.com.br" address=::1 comment="sinkhole AAAA envs"
/ip dns static add type=AAAA name="qa01.sittax.com.br"  address=::1 comment="sinkhole AAAA envs"
/ip dns static add type=AAAA name="qa02.sittax.com.br"  address=::1 comment="sinkhole AAAA envs"
/ip dns static add type=AAAA name="qa03.sittax.com.br"  address=::1 comment="sinkhole AAAA envs"
```

### 1.1 `dev` — sem regex (carve-out do `db.dev`)

```routeros
# db.dev -> PostgreSQL DIRETO no .109 (TCP 5432; NÃO é HTTP/SNI, NÃO passa pelo proxy .32):
/ip dns static add name="db.dev.sittax.com.br" address=192.168.1.109 comment="split-DNS dev db"
/ip dns static add type=AAAA name="db.dev.sittax.com.br" address=::1 comment="sinkhole AAAA dev db"

# demais hosts dev (HTTP/SNI) -> proxy interno .32:
/ip dns static add name="dev.sittax.com.br"                  address=192.168.2.32 comment="split-DNS envs"
/ip dns static add name="api.dev.sittax.com.br"              address=192.168.2.32 comment="split-DNS envs"
/ip dns static add name="apuracao.dev.sittax.com.br"         address=192.168.2.32 comment="split-DNS envs"
/ip dns static add name="autenticacao.dev.sittax.com.br"     address=192.168.2.32 comment="split-DNS envs"
/ip dns static add name="ecac-consulta.dev.sittax.com.br"    address=192.168.2.32 comment="split-DNS envs"
/ip dns static add name="ecac-transmissao.dev.sittax.com.br" address=192.168.2.32 comment="split-DNS envs"
/ip dns static add name="rabbitmq.dev.sittax.com.br"         address=192.168.2.32 comment="split-DNS envs"
/ip dns static add name="rt.dev.sittax.com.br"               address=192.168.2.32 comment="split-DNS envs"
/ip dns static add name="upload.dev.sittax.com.br"           address=192.168.2.32 comment="split-DNS envs"
/ip dns static add name="worker-services.dev.sittax.com.br"  address=192.168.2.32 comment="split-DNS envs"
/ip dns static add name="internal.dev.sittax.com.br"         address=192.168.2.32 comment="split-DNS envs"

# AAAA sinkhole p/ forçar IPv4 nos hosts dev acima:
/ip dns static add type=AAAA name="dev.sittax.com.br"                  address=::1 comment="sinkhole AAAA envs"
/ip dns static add type=AAAA name="api.dev.sittax.com.br"              address=::1 comment="sinkhole AAAA envs"
/ip dns static add type=AAAA name="apuracao.dev.sittax.com.br"         address=::1 comment="sinkhole AAAA envs"
/ip dns static add type=AAAA name="autenticacao.dev.sittax.com.br"     address=::1 comment="sinkhole AAAA envs"
/ip dns static add type=AAAA name="ecac-consulta.dev.sittax.com.br"    address=::1 comment="sinkhole AAAA envs"
/ip dns static add type=AAAA name="ecac-transmissao.dev.sittax.com.br" address=::1 comment="sinkhole AAAA envs"
/ip dns static add type=AAAA name="rabbitmq.dev.sittax.com.br"         address=::1 comment="sinkhole AAAA envs"
/ip dns static add type=AAAA name="rt.dev.sittax.com.br"               address=::1 comment="sinkhole AAAA envs"
/ip dns static add type=AAAA name="upload.dev.sittax.com.br"           address=::1 comment="sinkhole AAAA envs"
/ip dns static add type=AAAA name="worker-services.dev.sittax.com.br"  address=::1 comment="sinkhole AAAA envs"
/ip dns static add type=AAAA name="internal.dev.sittax.com.br"         address=::1 comment="sinkhole AAAA envs"
```

> 🚨 **Nome exato NÃO ganha de regex no RouterOS.** O resolver retorna a **primeira**
> entrada que casa (normalmente a regex, adicionada antes), **não** a mais específica.
> Logo, enquanto existir QUALQUER regex de `dev` no ar (ex.: o antigo
> `^(.*\.)?dev\.sittax\.com\.br$`), ele casa `db.dev` e **rouba** o destino `.109`.
> Tem que **remover o regex do `dev`**: `/ip dns static remove [find where regexp~"dev"]`
> (não toca em stage/qa — eles não contêm `dev` — nem nas entradas por nome). Confirme com
> `/ip dns static print detail where regexp~"sittax"` que não sobrou regex de `dev`.
>
> ⚠️ **Sem regex em `dev` = lista fixa.** Todo host novo de `dev` (que apareça no Traefik
> do swarm) precisa ser **adicionado à mão** aqui, senão resolve público. Lista capturada
> do dashboard em 2026-06-01: `api, apuracao, autenticacao, ecac-consulta,
> ecac-transmissao, rabbitmq, rt, upload, worker-services`.
>
> 💡 `db.dev` no `192.168.1.109` (sub-rede **antiga** `.1.x`) — alcançável pela VPN porque
> o servidor empurra `push "route 192.168.0.0/16"` (cobre `.1.x` e `.2.x`).

---

## 2. Firewall do `:53` (só LAN e VPN; NUNCA na WAN — vira open resolver)

```routeros
/ip firewall filter
add chain=input protocol=udp dst-port=53 src-address=192.168.0.0/16 action=accept comment="DNS LAN"
add chain=input protocol=tcp dst-port=53 src-address=192.168.0.0/16 action=accept comment="DNS LAN"
```
> A VPN de homolog (`10.8.0.0/24`) chega **mascarada como `192.168.2.138`** (o `.138` faz
> MASQUERADE VPN→LAN), então já cai na regra de LAN acima. Só precisaria de regra explícita
> para `10.8.0.0/24` se o `.138` parar de mascarar.

---

## 3. Validação (em um cliente conectado na VPN)

> ⚠️ TTL das entradas é **1d** — depois de qualquer troca, **limpe os dois caches** ou o
> destino antigo persiste: `/ip dns cache flush` (MikroTik) e `ipconfig /flushdns` (cliente).

```powershell
nslookup api.stage.sittax.com.br     # -> 192.168.2.32   (ambiente vai pro proxy)
nslookup rt.qa02.sittax.com.br       # -> 192.168.2.32
nslookup api.dev.sittax.com.br       # -> 192.168.2.32   (host dev comum vai pro proxy)
nslookup db.dev.sittax.com.br        # -> 192.168.1.109  (banco vai DIRETO, fora do proxy)
nslookup app.sittax.com.br           # -> IP PÚBLICO     (produção; NÃO vai pro .32)
```

---

## 4. O que a regex cobre / NÃO cobre

**Cobre (vai pro `.32`):** `stage` · `qa01` · `qa02` · `qa03` (apex e subdomínios, via regex) e
`dev` (apex + lista fixa de hosts, sem regex).
Ex.: `stage.sittax.com.br`, `api.stage.sittax.com.br`, `autenticacao.dev.sittax.com.br`,
`rt.qa02.sittax.com.br`, `assinador.token.stage.sittax.com.br`.

**Exceção dentro de `dev`:** `db.dev.sittax.com.br` → `192.168.1.109` (banco direto, não proxy).

**NÃO cobre (resolvem público)** — rodam no `.116` mas fora do padrão `{stage,dev,qa0x}`:
- Família **`homologacao`**: `homologacao.sittax.com.br`, `apihomologacao`,
  `autenticacaohomologacao`, `apuracaohomologacao`, `recuperahomologacao`, … (parece ambiente real)
- Família **`st`**: `sthomologacao`, `apisthomologacao`, `previewst`, …
- Tools **`*dev`** (concatenado, não `.dev`): `portainerdev`, `browserlessdev`, `traefikdev`, `storagedev`, …
- `redmine`, `sonarqube`, `n8nmarketing`.

> ⚠️ **Decisão pendente:** se algum desses precisar de acesso interno (ou for bloqueado
> publicamente depois), incluir na regex. A família `homologacao` provavelmente entra.
> Para incluí-la, somar `homologacao` ao grupo — mas cuidado: os nomes dela são
> **concatenados** (`apihomologacao`, sem ponto), então a regex teria que mudar de
> `\.sittax` para algo como `(^|\.)[a-z0-9-]*homologacao\.sittax\.com\.br$`.

---

## Contexto relacionado
- **Proxy `.32`:** `upstream_https.conf` (gate de bloqueio público — **NÃO deployado** ainda).
- **VPN `.138`** (`/etc/openvpn/server/server.conf`):
  `push "dhcp-option DNS 192.168.2.1"` + `push "block-outside-dns"` + `push "route 192.168.0.0/16"`
  + `tun-mtu 1500` + `mssfix 1360`.
- **Plano geral:** `plano-isolamento-homologacao.md`.
