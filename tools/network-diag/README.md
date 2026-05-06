# network-diag — Diagnóstico de tráfego da rede Sittax

Conjunto de scripts e queries para investigar **picos de banda, ataques e
hosts ofensores** usando o NetFlow já coletado do MikroTik.

## Como o pipeline funciona

```
MikroTik (192.168.2.1)  --NetFlow v9 UDP/2055-->  goflow2  -->  Vector  -->  ClickHouse (netflow.flows)
                                                                                  |
                                                                                  +--> Grafana (192.168.2.50:3001)
```

Stack roda em containers Docker no host **192.168.2.50**:
`netmon-clickhouse`, `netmon-goflow2`, `netmon-vector`, `netmon-grafana`.

## Achados iniciais (snapshot 2026-05-06)

* **Pico de 4.8 GiB/min** (≈640 Mbps) em 2026-05-05 19:32 — provável saturação do link.
* Tráfego de pico dominado por **upload** dos hosts:
  * `192.168.1.54`, `192.168.1.122`, `192.168.1.220`, `192.168.1.41` enviando para
    a mesma frota de **11 IPs externos brasileiros na porta TCP/8080** —
    perfil de **DVR/NVR de CFTV em nuvem**.
  * `192.168.1.220` adicionalmente envia para 6 IPs externos na **porta 9090**.
  * `192.168.2.115` e `192.168.2.116` exportam ~14 GiB/dia cada para Microsoft
    (OneDrive/Teams) e Cloudflare — backup/sync legítimos.
* **Não foram observados padrões de ataque externo (DDoS volumétrico ou SYN
  flood)** no período coletado: o tráfego de entrada que parece "atacar" o IP
  público é, em sua maior parte, retorno NATeado de conexões iniciadas pelos
  próprios hosts internos (CDN, MS Teams, QUIC, etc.).

## Conclusão

A internet está caindo por **saturação de upload** causada pelos próprios DVRs
de CFTV (`.54`, `.122`, `.220`, `.41`) e, em menor grau, por backups/sync dos
servidores de aplicação (`.115`, `.116`).

## O que tem aqui

| Caminho                                  | Para que serve |
|------------------------------------------|----------------|
| `netdiag.sh`                             | CLI no host de observabilidade — top talkers, picos, suspeitos, etc. |
| `queries/01_top_uploaders.sql`           | Top hosts LAN por upload em 24h |
| `queries/02_peak_minutes.sql`            | Top 50 minutos com maior tráfego (correlacionar com queda) |
| `queries/03_inbound_to_public.sql`       | Top fontes externas batendo no IP público |
| `queries/04_camera_uploads.sql`          | Frota CFTV (porta 8080/9090) |
| `queries/05_syn_flood_check.sql`         | Heurística de SYN flood |
| `queries/06_amplification_ports.sql`     | Portas UDP usadas em amplificação DDoS |
| `queries/07_anomaly_per_host.sql`        | Hosts com upload anômalo (z-score 7d) |
| `grafana/dashboard-anomalies.json`       | Dashboard "Detecção de Anomalias e Ataques" |
| `grafana/install-dashboard.sh`           | Sobe/atualiza o dashboard via API Grafana |
| `install-on-observability.sh`            | Instala `netdiag` em `/usr/local/bin` no host 192.168.2.50 |

## Uso rápido

```bash
# 1. Instalar dashboard no Grafana
./grafana/install-dashboard.sh
# Acesse: http://192.168.2.50:3001/d/netmon-anomalies

# 2. Instalar CLI no host
./install-on-observability.sh

# 3. Usar a CLI a partir da sua máquina
SSHPASS='@Sittax#'
sshpass -p "$SSHPASS" ssh ubuntu@192.168.2.50 'netdiag top "1 HOUR"'
sshpass -p "$SSHPASS" ssh ubuntu@192.168.2.50 'netdiag peaks "24 HOUR"'
sshpass -p "$SSHPASS" ssh ubuntu@192.168.2.50 'netdiag suspect "1 HOUR"'
sshpass -p "$SSHPASS" ssh ubuntu@192.168.2.50 'netdiag host 192.168.1.54 "6 HOUR"'
sshpass -p "$SSHPASS" ssh ubuntu@192.168.2.50 'netdiag window "2026-05-05 19:30" "2026-05-05 19:35"'
```

## Mitigação no MikroTik

O acesso ao MK em `192.168.2.1` está restrito a **Winbox (8291)** — SSH/HTTP/API
estão fechados externamente. Recomendado:

### 1. Habilite SSH e API REST localmente (não exponha à WAN)

No Winbox terminal:

```routeros
/ip service enable ssh
/ip service enable api-ssl
/ip service set ssh address=192.168.2.0/24
/ip service set api-ssl address=192.168.2.0/24
/ip service set api address=192.168.2.0/24
```

Depois disso, o `netdiag` pode ser estendido para coletar conntrack e
queues do próprio MK.

### 2. Crie queue para limitar upload da "frota CFTV"

```routeros
# Lista os IPs ofensores
/ip firewall address-list add list=cftv address=192.168.1.54 comment="DVR1"
/ip firewall address-list add list=cftv address=192.168.1.122 comment="DVR2"
/ip firewall address-list add list=cftv address=192.168.1.220 comment="DVR3"
/ip firewall address-list add list=cftv address=192.168.1.41 comment="DVR4"

# Marca pacotes desses IPs com upload para portas 8080/9090
/ip firewall mangle add chain=prerouting action=mark-connection \
  src-address-list=cftv dst-port=8080,9090 protocol=tcp \
  new-connection-mark=cftv-up passthrough=yes
/ip firewall mangle add chain=prerouting action=mark-packet \
  connection-mark=cftv-up new-packet-mark=cftv-up passthrough=no

# Cria simple queue limitando a 5 Mbps total (ajuste ao seu link)
/queue simple add name=limit-cftv target=192.168.1.54,192.168.1.122,192.168.1.220,192.168.1.41 \
  max-limit=20M/5M \
  packet-marks=cftv-up
```

### 3. Bloqueie portas inseguras vindas da WAN

Já há geo-block para `prometheus.sittax.com.br` no nginx (`upstream_https.conf`
geo $allowed_ip). Replique no MK para portas que **não** devem ser publicadas:

```routeros
/ip firewall filter add chain=input action=drop in-interface-list=WAN \
  protocol=udp dst-port=53,123,11211,1900,19,17,137,161 \
  comment="drop UDP amplification ports from WAN"

/ip firewall filter add chain=forward action=drop in-interface-list=WAN \
  connection-state=new connection-nat-state=!dstnat \
  comment="drop unsolicited inbound (no DNAT)"
```

## Operação contínua

* O dashboard `NetFlow — Detecção de Anomalias e Ataques` faz refresh a cada 30s
  e mostra: banda total/upload/inbound, top talkers, sources externos, picos
  acima do limiar, hosts com z-score anômalo.
* Para um alerta proativo, criar uma alert rule Grafana baseada na consulta do
  painel "Pico atual janela" — disparar acima de 300 MiB/min sustentado.
