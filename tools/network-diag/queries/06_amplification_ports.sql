-- Tráfego UDP em portas tipicamente usadas em amplificação DDoS chegando ao
-- IP público. Se aparecer volume alto = exposição a refletor; se pacotes
-- saírem do nosso IP nessas portas = estamos sendo usados como amplificador.
SELECT toStartOfHour(time_received)                AS h,
       proto,
       src_port,
       dst_port,
       multiIf(dst_addr='177.223.44.35','IN', src_addr='177.223.44.35','OUT', 'OTHER') AS dir,
       formatReadableSize(sum(bytes))              AS B,
       sum(packets)                                AS pkts
FROM netflow.flows
WHERE time_received > now() - INTERVAL 24 HOUR
  AND proto = 'UDP'
  AND (
    src_port IN (53, 123, 11211, 1900, 19, 17, 137, 161, 389, 1434, 5683, 27015) OR
    dst_port IN (53, 123, 11211, 1900, 19, 17, 137, 161, 389, 1434, 5683, 27015)
  )
  AND (src_addr = '177.223.44.35' OR dst_addr = '177.223.44.35')
GROUP BY h, proto, src_port, dst_port, dir
HAVING sum(bytes) > 1024*1024
ORDER BY h DESC, sum(bytes) DESC;
