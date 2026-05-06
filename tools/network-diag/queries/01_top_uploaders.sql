-- Top hosts LAN por bytes enviados para a WAN nas últimas 24h.
-- Cada linha = 1 host interno; 'up' é o total de upload medido pelo MK via NetFlow.
SELECT src_addr,
       formatReadableSize(sum(bytes))              AS up,
       formatReadableSize(sum(bytes)*8/(24*3600))  AS bps_avg,
       sum(packets)                                AS pkts,
       uniq(dst_addr)                              AS uniq_dst,
       groupUniqArray(5)(dst_addr)                 AS sample_dsts
FROM netflow.flows
WHERE time_received > now() - INTERVAL 24 HOUR
  AND match(src_addr, '^192\.168\.')
  AND NOT match(dst_addr, '^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|127\.|169\.254\.|255\.255\.255\.255$)')
GROUP BY src_addr
ORDER BY sum(bytes) DESC
LIMIT 30;
