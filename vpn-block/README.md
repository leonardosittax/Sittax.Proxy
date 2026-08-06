# Isolamento de homologação por VPN — como foi construído

Implantado no proxy `192.168.2.32`, branch `vpn-gate`.

> **Estado atual: o bloqueio está DESLIGADO.** Em 06/08/2026 o gate voltou para
> `default 1` (libera todos) porque o split-DNS não estava confiável em todas as
> máquinas. Toda a mecânica continua no lugar e pronta — religar é uma linha.

---

## A ideia

Homologação passa a responder **só para quem está na VPN**. Quem vem de fora
recebe uma página dizendo que o acesso é restrito — não um erro de conexão.

```
  dentro da VPN            NetBird ns ─→ dnsmasq ─→ 192.168.2.32 ─→ backend
  na LAN do escritorio     MikroTik  ─→ dnsmasq ─→ 192.168.2.32 ─→ backend
  de fora                  DNS publico ─→ 177.223.44.35 ─→ .32 ─→ pagina 403
```

A Cloudflare **não foi tocada**: o DNS público continua apontando para o IP do
escritório. A separação acontece toda no `.32`.

## As quatro peças

### 1. Gate no nginx (`upstream_https.conf`)

`geo $allowed_ip` classifica a origem; um `map` decide o destino:

```nginx
map "$is_public_sni:$allowed_ip" $backend_name_https {
    "0:0"      blocked_page;             # nem publico nem interno
    default    $lk_backend_name_https;   # roteia normal
}
```

Ligar o bloqueio = `default 0` no `geo`. Desligar = `default 1`.

**O gate é só na porta 443.** A 80 fica livre de propósito: é por onde passa o
desafio HTTP-01 do Let's Encrypt, e a renovação do Traefik no `.116` depende
disso.

Exceções que continuam públicas ficam em `$is_public_sni`, cada uma com motivo
declarado (hoje: `registry` e `n8nmarketing`).

### 2. Página de bloqueio com TLS terminado

A 443 é **passthrough** (`ssl_preread`): o nginx encaminha bytes cifrados e não
consegue escrever resposta HTTP. Para mostrar a página é preciso terminar TLS —
e para isso, ter certificado válido do hostname.

O caso bloqueado vai para `127.0.0.1:8443`, um listener que escolhe o
certificado por SNI e devolve **403** com a página:

```nginx
server {
    listen 127.0.0.1:8443 ssl http2;
    ssl_certificate     $blockpage_cert.crt;   # mapa gerado, ver abaixo
    ssl_certificate_key $blockpage_cert.key;
    error_page 403 /index.html;
    location / { return 403; }
}
```

A página (`blocked.html`) é deliberadamente enxuta: diz só que o acesso é
restrito a rede autorizada. Uma versão anterior citava o produto de VPN e
comandos de diagnóstico — informação de graça para quem estiver sondando.

### 3. Espelhamento dos certificados

`sync-traefik-certs.sh`, com timer diário.

Puxa o `acme.json` do Traefik (`.116`), extrai os certificados válidos,
descarta os vencidos, grava em `/etc/nginx/certs/` e regenera
`/etc/nginx/certs_map.conf` — o mapa SNI → certificado. Recarrega o nginx só se
algo mudou, e **aborta sem tocar em nada** se o download vier vazio.

Por que espelhar em vez de emitir: um segundo cliente ACME brigaria com o
Traefik pelo desafio HTTP-01 dos mesmos nomes e gastaria rate limit do Let's
Encrypt à toa. Os certificados já existem — basta copiá-los.

O acesso ao `.116` usa chave dedicada com **comando fixo** no `authorized_keys`:
ela só consegue ler aquele arquivo, qualquer outro comando é ignorado.

Há um fallback autoassinado para SNI desconhecido — sem ele o handshake cairia
antes de conseguir mostrar a página.

### 4. DNS interno

- **LAN:** MikroTik encaminha para o dnsmasq do `.32`
- **VPN:** nameserver group do NetBird (`homolog-interno`, 34 domínios) +
  rota `192.168.2.32/32`

O dnsmasq é **uma instância só**, na mesma máquina do proxy. Isso é
proposital: não adiciona domínio de falha, porque se o `.32` cair o proxy cai
junto e homologação fica inacessível de qualquer jeito.

A rota `/32` existe porque o dnsmasq responde `192.168.2.32` para todos (não
tem split-horizon). O cliente VPN chega nesse mesmo IP pelo túnel; o da LAN,
pelo cabo.

> **Medição importante:** o proxy enxerga o cliente VPN com o IP do túnel
> (`100.81.x.x`), **sem mascaramento**. Por isso `100.81.0.0/16` está na
> allowlist do `geo`.

## Arquivos

| arquivo | o que é |
|---|---|
| `blocked.html` | a página servida a quem é bloqueado |
| `sync-traefik-certs.sh` | espelha os certificados do Traefik |
| `sync-traefik-certs.{service,timer}` | unidades systemd do espelhamento |
| `sittax-split.conf` | config do dnsmasq (cópia da que está em `/etc/dnsmasq.d/`) |
| `diagnostico-dns.ps1` | coleta dados na máquina do dev quando o split-DNS falha |
| `qa02-consolidacao/` | composes do `st`/`recupera` consolidados em qa-02 |

## Operação

**Religar o bloqueio:**

```bash
# no .32, em /home/nginx/.nginx
# trocar 'default 1' por 'default 0' no geo $allowed_ip de upstream_https.conf
sudo cp upstream_https.conf /etc/nginx/ && sudo nginx -t && sudo systemctl reload nginx
```

**Rollback completo:**

```bash
cd /home/nginx/.nginx
git checkout vpn-only          # estado anterior a tudo isto
sudo cp nginx.conf upstream_*.conf /etc/nginx/
sudo systemctl reload nginx
```

A branch `vpn-gate` tem os passos em commits separados — dá para voltar só a
página, só o gate, ou tudo.

**Validar (de um host realmente externo, não da LAN):**

```bash
curl -s --resolve stage.sittax.com.br:443:177.223.44.35 \
     https://stage.sittax.com.br/ -o /dev/null \
     -w '%{http_code} verify=%{ssl_verify_result}\n'
# bloqueado e correto  -> 403 verify=0
```

`verify=0` é o que importa: significa certificado válido, sem alerta no
navegador.

## Resultado medido em 06/08/2026, com o gate ligado

| | |
|---|---|
| de fora, 97 domínios | 95 bloqueados com a página, certificado válido |
| de dentro da VPN | 96 dos 97 idênticos à baseline anterior |
| ACME na porta 80 | seguiu passando |

As exceções: `ecactransmissaohomologacao` (certificado já vencido no próprio
Traefik, cai no autoassinado — bloqueia igual, sem página) e `n8nmarketing`
(público de propósito).

## Pendências

- **Renovar o certificado de `ecactransmissaohomologacao`** no Traefik, ou
  remover o domínio.
- **30 registros DNS órfãos** na Cloudflare apontando para `devserver`
  (famílias `devops01`, `apiqa0x`, `jaeger`, `loki`, `backstage`,
  `sorry-cypress`), sem nada roteando. Limpeza pendente de decisão.
- **Redirect do `portainerdev` para o `infra`** — pedido, não feito.
