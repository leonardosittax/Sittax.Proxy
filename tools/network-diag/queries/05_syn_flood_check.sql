-- Heurística de SYN flood: muitos pacotes pequenos com flag SYN para o IP
-- público vindo de muitas origens distintas em curta janela. Se aparecer src
-- com >>1k flows e poucas dst_ports = candidato a flood.
SELECT toStartOfMinute(time_received)              AS minute,
       count()                                     AS flows,
       uniq(src_addr)                              AS uniq_src,
       sum(packets)                                AS pkts,
       formatReadableSize(sum(bytes))              AS B
FROM netflow.flows
WHERE time_received > now() - INTERVAL 24 HOUR
  AND dst_addr = '177.223.44.35'
  AND proto = 'TCP'
  AND positionCaseInsensitive(tcp_flags, '02') > 0   -- SYN bit (TCP flag 0x02)
GROUP BY minute
HAVING flows > 1000
ORDER BY minute DESC
LIMIT 30;
