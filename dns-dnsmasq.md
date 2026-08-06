# DNS interno — dnsmasq no proxy `.32` (split-DNS dos ambientes)

> **Substitui** o split-DNS via `/ip dns static` do MikroTik (ver `mikrotik-split-dns.md`,
> agora SUPERADO). O MikroTik 6.49 não dava conta: regex sem alternância, não casava o apex
> vazio, nome-exato não ganhava de regex, e sem AAAA-NODATA. Agora o `.32` roda **dnsmasq**
> e o MikroTik só **encaminha** pra ele.
>
> Aplicado e testado: **2026-06-01**.

## Arquitetura
```
cliente LAN ─DHCP→ MikroTik (.1) ─forward→ dnsmasq @ .32 ─┬─ *.{stage,dev,qa01,qa02,qa03} → .32 (proxy) / exceções
cliente VPN ─push DNS .1 (block-outside-dns)─────────────┘   └─ resto → 1.1.1.1 / 8.8.8.8
```
- dnsmasq escuta **só** em `192.168.2.32:53` (`bind-interfaces`); o `systemd-resolved` do `.32`
  fica intacto em `127.0.0.53`. **nginx não é afetado.**
- MikroTik: `/ip dns set servers=192.168.2.32` (encaminha tudo pro dnsmasq) e **sem** `/ip dns static` de sittax.

## Config — `/etc/dnsmasq.d/sittax-split.conf` (no `.32`)
```ini
bind-interfaces
listen-address=192.168.2.32
no-resolv
server=1.1.1.1
server=8.8.8.8
# Ambientes -> proxy .32 (wildcard = apex + TODOS os subdomínios, numa linha)
address=/stage.sittax.com.br/192.168.2.32
address=/dev.sittax.com.br/192.168.2.32
address=/qa01.sittax.com.br/192.168.2.32
address=/qa02.sittax.com.br/192.168.2.32
address=/qa03.sittax.com.br/192.168.2.32
# Exceções (dnsmasq usa o match MAIS ESPECÍFICO automaticamente)
address=/db.dev.sittax.com.br/192.168.1.109        # Postgres direto (TCP 5432, NÃO passa pelo proxy)
address=/internal.dev.sittax.com.br/192.168.2.116  # direto no .116
```
> Por que é melhor que o MikroTik: wildcard numa linha (apex+subs), **mais-específico ganha**
> (db.dev sobrepõe o wildcard dev), **AAAA = NODATA** automático (força IPv4 sem sinkhole `::1`),
> e forward do resto pra internet.

## Setup no `.32` (feito)
```bash
sudo apt-get install -y dnsmasq
sudo tee /etc/dnsmasq.d/sittax-split.conf   # conteúdo acima
sudo dnsmasq --test                          # valida sintaxe
sudo systemctl enable --now dnsmasq
ss -ulnp 'sport = :53'                        # dnsmasq em 192.168.2.32:53; systemd-resolved em 127.0.0.53
```
Alterar/adicionar host: editar o `.conf` → `sudo systemctl reload dnsmasq`.

## MikroTik — virou forwarder (feito)
```routeros
/ip dns set servers=192.168.2.32
/ip dns static remove [find where comment~"split-DNS"]
/ip dns static remove [find where comment~"sinkhole"]
/ip dns cache flush
```

## VPN (`.138`)
**Sem mudança necessária:** o push continua `dhcp-option DNS 192.168.2.1` + `block-outside-dns`;
o `.1` encaminha pro `.32`. (Opcional: pushar `192.168.2.32` direto p/ tirar um hop.)

## Validação (2026-06-01, perguntando pro MikroTik `.1`)
| Nome | Resposta |
|---|---|
| `stage` / `rt.qa02` / `api.dev` | `192.168.2.32` |
| `db.dev` | `192.168.1.109` |
| `internal.dev` | `192.168.2.116` |
| `app.sittax.com.br` | público (Cloudflare) |
| `google.com` | resolve |
| AAAA (`stage`/`db.dev`) | NODATA |

## Manutenção
- **Host novo de ambiente** (`*.dev`, `*.stage`, `*.qa0x`): já é coberto pelo wildcard — **nada a fazer**.
- Só precisa de linha nova para: um **novo prefixo de ambiente** (ex.: `qa04`) ou uma **exceção**
  (host do ambiente que vai pra um IP diferente do `.32`, como `db.dev`).
- Clientes podem precisar de `ipconfig /flushdns` para largar respostas antigas em cache.
