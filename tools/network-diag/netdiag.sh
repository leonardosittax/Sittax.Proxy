#!/usr/bin/env bash
# netdiag.sh — diagnóstico rápido da rede usando NetFlow no ClickHouse
# Roda no host de observabilidade (192.168.2.50). Lê netflow.flows.
#
# Uso:
#   netdiag.sh now                  # snapshot 1 min: top flows ativos agora
#   netdiag.sh top [WINDOW]         # top hosts LAN por upload (1h, 24h, 7d ...)
#   netdiag.sh peaks [WINDOW]       # minutos com maior tráfego
#   netdiag.sh suspect [WINDOW]     # hosts mandando para portas 8080/9090/etc fora do padrão
#   netdiag.sh inbound [WINDOW]     # quem mais bate no IP público
#   netdiag.sh window FROM TO       # pares src→dst no intervalo (formato: "YYYY-MM-DD HH:MM")
#   netdiag.sh host IP [WINDOW]     # tudo o que o IP fez no período
#   netdiag.sh ports [WINDOW]       # bytes por proto:porta destino
#   netdiag.sh hourly [WINDOW]      # bytes por hora
#
# WINDOW: aceita "1 HOUR", "30 MINUTE", "24 HOUR", "7 DAY". Default: 1 HOUR.
set -euo pipefail

CH_CONTAINER="${CH_CONTAINER:-netmon-clickhouse}"
WIN="${2:-1 HOUR}"
PUB_IP="${PUB_IP:-177.223.44.35}"

# Regex sem o cabeçalho 192.168 (LAN privada). Usado para "externo".
PRIV_RE='^(192\\.168\\.|10\\.|172\\.(1[6-9]|2[0-9]|3[0-1])\\.|127\\.|169\\.254\\.|255\\.255\\.255\\.255$)'

q() {
  docker exec -i "$CH_CONTAINER" clickhouse-client --format=PrettyCompact -q "$1"
}

human_win() { echo "INTERVAL $WIN"; }

case "${1:-help}" in
  now)
    echo "=== Flows ativos último 1 min ==="
    q "
      SELECT src_addr, dst_addr, dst_port, proto,
             formatReadableSize(sum(bytes)) AS B,
             sum(packets) AS pkts
      FROM netflow.flows
      WHERE time_received > now() - INTERVAL 1 MINUTE
      GROUP BY src_addr,dst_addr,dst_port,proto
      ORDER BY sum(bytes) DESC
      LIMIT 20"
    ;;

  top)
    echo "=== Top hosts LAN por UPLOAD para WAN — janela $WIN ==="
    q "
      SELECT src_addr,
             formatReadableSize(sum(bytes)) AS up,
             formatReadableSize(sum(bytes)*8/(${WIN// /*})) AS bps_estimate,
             sum(packets) AS pkts,
             uniq(dst_addr) AS uniq_dst
      FROM netflow.flows
      WHERE time_received > now() - $(human_win)
        AND match(src_addr,'^192\\.168\\.')
        AND NOT match(dst_addr,'$PRIV_RE')
      GROUP BY src_addr
      ORDER BY sum(bytes) DESC
      LIMIT 20"
    ;;

  peaks)
    echo "=== Minutos de maior tráfego — janela $WIN ==="
    q "
      SELECT toStartOfMinute(time_received) AS minute,
             formatReadableSize(sum(bytes)) AS B,
             sum(packets) AS pkts,
             uniq(src_addr,dst_addr) AS pairs
      FROM netflow.flows
      WHERE time_received > now() - $(human_win)
      GROUP BY minute
      ORDER BY sum(bytes) DESC
      LIMIT 25"
    ;;

  inbound)
    echo "=== Top SOURCES externos batendo no IP público ($PUB_IP) — janela $WIN ==="
    q "
      SELECT src_addr,
             proto,
             formatReadableSize(sum(bytes)) AS B,
             sum(packets) AS pkts,
             uniq(dst_port) AS uniq_dport
      FROM netflow.flows
      WHERE time_received > now() - $(human_win)
        AND dst_addr='$PUB_IP'
      GROUP BY src_addr, proto
      ORDER BY sum(bytes) DESC
      LIMIT 25"
    ;;

  suspect)
    echo "=== Hosts LAN enviando para portas tipicamente fora do padrão (não 80/443/53/etc) — janela $WIN ==="
    q "
      SELECT src_addr,
             dst_port,
             proto,
             formatReadableSize(sum(bytes)) AS up,
             sum(packets) AS pkts,
             uniq(dst_addr) AS uniq_dst,
             groupUniqArray(5)(dst_addr) AS sample_dsts
      FROM netflow.flows
      WHERE time_received > now() - $(human_win)
        AND match(src_addr,'^192\\.168\\.')
        AND NOT match(dst_addr,'$PRIV_RE')
        AND dst_port NOT IN (80,443,53,123,3478,3479,3480,3481,5223,5228,5938,8443,853,3306,5432,9200)
      GROUP BY src_addr, dst_port, proto
      HAVING sum(bytes) > 50*1024*1024
      ORDER BY sum(bytes) DESC
      LIMIT 25"
    ;;

  window)
    FROM="${2:?from \"YYYY-MM-DD HH:MM\"}"
    TO="${3:?to \"YYYY-MM-DD HH:MM\"}"
    echo "=== Pares src→dst no intervalo $FROM .. $TO ==="
    q "
      SELECT src_addr, dst_addr, dst_port, proto,
             formatReadableSize(sum(bytes)) AS B,
             sum(packets) AS pkts
      FROM netflow.flows
      WHERE time_received BETWEEN '$FROM' AND '$TO'
      GROUP BY src_addr,dst_addr,dst_port,proto
      ORDER BY sum(bytes) DESC
      LIMIT 30"
    ;;

  host)
    IP="${2:?ip}"
    WIN="${3:-1 HOUR}"
    echo "=== Atividade de $IP na janela $WIN ==="
    q "
      SELECT
        if(src_addr='$IP','OUT','IN ') AS dir,
        if(src_addr='$IP', dst_addr, src_addr) AS peer,
        if(src_addr='$IP', dst_port, src_port) AS port,
        proto,
        formatReadableSize(sum(bytes)) AS B,
        sum(packets) AS pkts
      FROM netflow.flows
      WHERE time_received > now() - INTERVAL $WIN
        AND (src_addr='$IP' OR dst_addr='$IP')
      GROUP BY dir, peer, port, proto
      ORDER BY sum(bytes) DESC
      LIMIT 30"
    ;;

  ports)
    echo "=== Top portas destino (LAN→WAN) — janela $WIN ==="
    q "
      SELECT proto, dst_port,
             formatReadableSize(sum(bytes)) AS up,
             sum(packets) AS pkts,
             uniq(src_addr) AS uniq_src
      FROM netflow.flows
      WHERE time_received > now() - $(human_win)
        AND match(src_addr,'^192\\.168\\.')
        AND NOT match(dst_addr,'$PRIV_RE')
      GROUP BY proto, dst_port
      ORDER BY sum(bytes) DESC
      LIMIT 20"
    ;;

  hourly)
    echo "=== Bytes/hora total + LAN→WAN — janela $WIN ==="
    q "
      SELECT toStartOfHour(time_received) AS h,
             formatReadableSize(sum(bytes)) AS total,
             formatReadableSize(sumIf(bytes, match(src_addr,'^192\\.168\\.') AND NOT match(dst_addr,'$PRIV_RE'))) AS up,
             formatReadableSize(sumIf(bytes, dst_addr='$PUB_IP')) AS pub_in
      FROM netflow.flows
      WHERE time_received > now() - $(human_win)
      GROUP BY h
      ORDER BY h"
    ;;

  *)
    sed -n '2,18p' "$0"
    exit 0
    ;;
esac
