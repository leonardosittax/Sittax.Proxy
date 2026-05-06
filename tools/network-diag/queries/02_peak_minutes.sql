-- Top 50 minutos com maior tráfego (qualquer direção). Útil para correlacionar
-- com o momento em que a internet caiu.
SELECT toStartOfMinute(time_received)            AS minute,
       formatReadableSize(sum(bytes))            AS B,
       formatReadableSize(sum(bytes)*8/60)       AS bps_avg_min,
       sum(packets)                              AS pkts,
       uniq(src_addr, dst_addr)                  AS pair_count
FROM netflow.flows
WHERE time_received > now() - INTERVAL 7 DAY
GROUP BY minute
ORDER BY sum(bytes) DESC
LIMIT 50;
