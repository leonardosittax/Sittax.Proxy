# proxy-logs — Observabilidade do nginx (Sittax.Proxy)

Pipeline de logs estruturados do nginx (192.168.2.32) → Vector → ClickHouse →
Grafana, reusando a stack `netmon-*` que já existe em 192.168.2.50.

```
nginx (access_log JSON via syslog UDP/5140)
    │
    ▼
Vector (192.168.2.50)  ──▶  ClickHouse  netmon.nginx_access
                                            │
                                            ▼
                                       Grafana 3001
```

## Como o deploy do nginx funciona

O repo Sittax.Proxy é o source-of-truth. O `update.sh` (no root do repo) copia
`nginx.conf` + `upstream_*.conf` de `/home/nginx/.nginx/` para `/etc/nginx/`,
testa e reinicia. Por isso a parte do nginx **já está integrada diretamente em
`nginx.conf`** (log_format `http_json` + `stream_json` + dois `access_log
syslog:...`). Para aplicar:

```bash
sshpass -p '@Sittax#' ssh nginx@192.168.2.32 'cd ~/.nginx && bash update.sh'
```

(O `update.sh` pede confirmação `y/n` antes de reiniciar.)

## Arquivos

| Caminho | Status |
|---|---|
| `clickhouse/nginx-init.sql` | **Aplicado** — DB `netmon` + tabelas `nginx_access` / `nginx_access_1m` (TTL 30/90 dias) |
| `vector/nginx-syslog.yaml` | Append manual em `/home/ubuntu/netmon/vector/vector.yaml` no host de obs |
| `grafana/dashboard-proxy-requests.json` | **Publicado:** http://192.168.2.50:3001/d/sittax-proxy-requests |
| `grafana/install-proxy-dashboard.sh` | (Re)publica o dashboard via API |
| `install.sh` | Script orquestrador — aplica o que é seguro de automatizar |

## Passos manuais que faltam

1. **No nginx (192.168.2.32):**
   ```bash
   sshpass -p '@Sittax#' ssh nginx@192.168.2.32 'cd ~/.nginx && bash update.sh'
   ```
2. **No host de obs (192.168.2.50):**
   - Mesclar `vector/nginx-syslog.yaml` em `/home/ubuntu/netmon/vector/vector.yaml`
     (juntar as chaves `sources`, `transforms`, `sinks` — não duplicar).
   - Em `/home/ubuntu/netmon/docker-compose.yml`, na seção `services.vector`,
     adicionar:
     ```yaml
     ports:
       - "5140:5140/udp"
     ```
   - Reiniciar:
     ```bash
     cd /home/ubuntu/netmon && docker compose up -d vector
     ```

Não automatizei a parte 2 para não corromper a config do operador.

## O que tem no dashboard

1. Requisições/s (HTTP) e sessões/s (TLS stream) por SNI/host
2. Status code split (2xx/3xx/4xx/5xx) — stack
3. Latência HTTP p50/p95/p99
4. Top hosts, SNI, backends, URIs, client IPs, User-Agents
5. **Tentativas de exploit** — heurística por padrão de URI (`wget`, `device.rsp`,
   `.env`, `wp-admin`, `phpunit`, etc) e UA (`zgrab`, `nuclei`, `sqlmap`...)
6. 5xx recentes
