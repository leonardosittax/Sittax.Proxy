-- Detecta hosts cujo tráfego de upload nos últimos 60 min está muito acima da
-- média histórica do mesmo host (z-score simples sobre 7 dias).
WITH hourly AS (
  SELECT src_addr,
         toStartOfHour(time_received) AS h,
         sum(bytes) AS up
  FROM netflow.flows
  WHERE time_received > now() - INTERVAL 7 DAY
    AND match(src_addr, '^192\.168\.')
    AND NOT match(dst_addr, '^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)')
  GROUP BY src_addr, h
),
stats AS (
  SELECT src_addr,
         avg(up)    AS mean,
         stddevPop(up) AS sd
  FROM hourly
  WHERE h < toStartOfHour(now()) - INTERVAL 1 HOUR
  GROUP BY src_addr
),
last_hour AS (
  SELECT src_addr, sum(bytes) AS up_last
  FROM netflow.flows
  WHERE time_received > now() - INTERVAL 1 HOUR
    AND match(src_addr, '^192\.168\.')
    AND NOT match(dst_addr, '^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)')
  GROUP BY src_addr
)
SELECT s.src_addr                                   AS host,
       formatReadableSize(l.up_last)                AS up_last_hour,
       formatReadableSize(toUInt64(s.mean))         AS hist_mean,
       round((l.up_last - s.mean) / nullIf(s.sd, 0), 2) AS zscore
FROM stats s
JOIN last_hour l USING (src_addr)
WHERE l.up_last > 100*1024*1024
  AND s.sd > 0
ORDER BY zscore DESC NULLS LAST
LIMIT 20;
