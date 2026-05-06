-- Top sources EXTERNOS que mais entregaram tráfego no IP público (177.223.44.35).
-- Inclui (a) respostas a conexões de saída (ex.: CDN, Teams) e (b) possíveis
-- ataques. Discriminar pelo padrão de portas: poucas portas = serviço; muitas
-- portas dst diferentes = spray/scan/varredura (NetFlow vê dst=ephemeral).
SELECT src_addr,
       proto,
       formatReadableSize(sum(bytes))     AS B,
       sum(packets)                       AS pkts,
       uniq(dst_port)                     AS uniq_dport,
       groupUniqArray(5)(dst_port)        AS sample_dport
FROM netflow.flows
WHERE time_received > now() - INTERVAL 24 HOUR
  AND dst_addr = '177.223.44.35'
GROUP BY src_addr, proto
ORDER BY sum(bytes) DESC
LIMIT 30;
