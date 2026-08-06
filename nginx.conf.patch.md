# Patch nginx — reduzir 522 intermitente

> **Contexto (2026-06-01):** relacionado ao isolamento de homologação — ver
> `plano-isolamento-homologacao.md` (§0) e `mikrotik-split-dns.md`.
>
> A **§1 abaixo (mapear hostnames explicitamente) é a parte de "corrigir as URLs".** Hoje os
> ambientes (`stage`, `*.{dev,qa01,qa02,qa03}.sittax.com.br`) e a família `*homologacao`
> caem no **catch-all `allDefault` (.116)** por `default`. Vale torná-los **explícitos** nos
> mapas `map $ssl_preread_server_name` (443, em `upstream_https.conf`) e `map $host`
> (80, em `upstream_http.conf`) para: clareza nos logs, roteamento previsível e para casar
> com o split-DNS estreito (que cobre só `stage|dev|qa01|qa02|qa03`). A lista completa de
> hostnames roteados pelo `.116` foi levantada das labels do Traefik (Host rules).
>
> **Status do restante deste patch (failover/timeouts/rlimit): NÃO aplicado.**

## 1. Adicionar `stage.sittax.com.br` explícito (clareza nos logs)

**`upstream_https.conf`** — antes do `default`:
```nginx
map $ssl_preread_server_name $lk_backend_name_https {
    ...
    stage.sittax.com.br         allDefault;   # tornar explícito (era default)
    api.stage.sittax.com.br     allDefault;   # idem
    autenticacao.stage.sittax.com.br allDefault;
    ...
    default                     allDefault;
}
```

**`upstream_http.conf`** — mesma coisa no `map $host $backend_name_http`:
```nginx
stage.sittax.com.br         allDefault_http;
```

## 2. Failover mais rápido nos upstreams (HTTPS)

**`upstream_https.conf`** — alterar `allDefault`:
```nginx
upstream allDefault {
    server 192.168.2.116:443 max_fails=2 fail_timeout=10s;
    server 192.168.1.116:443 backup max_fails=2 fail_timeout=10s;
}
```

Mesma coisa em `allDefault_http` (porta 80), `sentry`, `grafana`, etc. — qualquer upstream que tenha backup.

**Efeito**: se backend principal falhar 2x em 10s, nginx tira de circulação por 10s e usa o backup. Hoje fica oscilando indefinidamente.

## 3. Timeout no bloco stream/443

**`nginx.conf`** — dentro de `stream { server { listen 443; ... } }`:
```nginx
server {
    listen 443;
    listen [::]:443;
    ...
    proxy_pass $backend_name_https;
    ssl_preread on;

    # NOVO: fail fast em vez de esperar Cloudflare estourar (100s)
    proxy_connect_timeout 5s;     # default: 60s
    proxy_timeout         1h;     # default: 10m — sessões WebSocket/long poll mantêm
    proxy_next_upstream   on;     # tenta backup se falhar
}
```

## 4. Aumentar `worker_rlimit_nofile` (kernel file descriptors)

`worker_connections 16384` × 2 (cliente + upstream) × `worker_processes` (auto = CPUs) pode estourar o `ulimit -n` (default 1024 no Ubuntu). Adicionar no topo do `nginx.conf`:

```nginx
worker_rlimit_nofile 65535;
```

## 5. Diagnóstico que você roda no host

Rodar em `192.168.2.32` pra ver o estado atual:

```bash
# Logs de erro recentes (procura por upstream timed out, connection refused)
sudo tail -200 /var/log/nginx/stream_https.error.log | grep -E "stage|2.116|1.116|timeout|refused"
sudo tail -200 /var/log/nginx/http_router.error.log | grep -E "stage|2.116|1.116"

# Conexões ativas pra Cloudflare (porta 443)
ss -tn state established 'sport = :443' | wc -l

# Backend principal está respondendo?
curl -k -o /dev/null -w "HTTP %{http_code}  connect=%{time_connect}s  total=%{time_total}s\n" \
  --connect-timeout 5 --max-time 10 \
  --resolve stage.sittax.com.br:443:192.168.2.116 \
  https://stage.sittax.com.br/

# Backup
curl -k -o /dev/null -w "HTTP %{http_code}  connect=%{time_connect}s  total=%{time_total}s\n" \
  --connect-timeout 5 --max-time 10 \
  --resolve stage.sittax.com.br:443:192.168.1.116 \
  https://stage.sittax.com.br/

# ulimit do user www-data (que roda o nginx)
sudo -u www-data bash -c 'ulimit -n'

# Carga + conexões no backend 192.168.2.116 (se acessível por SSH)
ssh user@192.168.2.116 'uptime; ss -tn | wc -l'
```

## 6. Validar config antes de reload

```bash
sudo nginx -t                  # syntax check
sudo systemctl reload nginx    # zero downtime
```

## 7. (opcional) Olhar no Grafana

Como você já tem log JSON indo pro Vector→ClickHouse, query útil:

```sql
SELECT ts, host, status, upstream_status, upstream_time, upstream
FROM netmon.nginx_access
WHERE host LIKE '%stage.sittax.com.br%'
  AND ts > now() - INTERVAL 1 HOUR
  AND (upstream_status IN ('', '0') OR status >= 500)
ORDER BY ts DESC
LIMIT 100
```

Se aparecerem várias linhas com `upstream_status=''` ou `upstream_time>5`, é o backend `192.168.2.116` lentando — não o nginx.
