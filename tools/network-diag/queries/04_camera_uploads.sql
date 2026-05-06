-- Hosts LAN enviando para a "frota CFTV" (porta 8080/9090 com múltiplos IPs
-- externos brasileiros). Padrão observado em 2026-05-05/06: hosts .54, .122,
-- .220, .41 enviam para os mesmos 11 IPs externos. Cheira a DVR/NVR fazendo
-- upload de gravação para serviço de monitoramento em nuvem.
SELECT src_addr,
       proto,
       dst_port,
       formatReadableSize(sum(bytes))     AS up,
       sum(packets)                       AS pkts,
       uniq(dst_addr)                     AS uniq_dst,
       groupUniqArray(20)(dst_addr)       AS dst_list
FROM netflow.flows
WHERE time_received > now() - INTERVAL 7 DAY
  AND match(src_addr, '^192\.168\.')
  AND NOT match(dst_addr, '^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)')
  AND dst_port IN (8080, 9090)
  AND proto = 'TCP'
GROUP BY src_addr, proto, dst_port
ORDER BY sum(bytes) DESC;
