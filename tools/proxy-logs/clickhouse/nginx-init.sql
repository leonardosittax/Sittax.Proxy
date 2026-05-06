-- Schema para logs estruturados do nginx (Sittax proxy 192.168.2.32).
-- Reusa o ClickHouse existente da stack netmon. Banco "netmon" (separado de
-- "netflow") para isolar permissões/TTL.

CREATE DATABASE IF NOT EXISTS netmon;

-- Tabela única para HTTP (req_time>0) e stream/TLS (session_time>0). A coluna
-- `src` distingue. Campos opcionais ficam vazios/zero conforme o caso.
CREATE TABLE IF NOT EXISTS netmon.nginx_access
(
    ts                  DateTime64(3, 'UTC'),
    src                 LowCardinality(String),  -- 'http' | 'stream'
    host                String,                  -- HTTP only: $host
    client              String,                  -- IP que chegou no nginx (CF/127.0.0.1 atrás de stream→http)
    cf_ip               String,                  -- CF-Connecting-IP (HTTP)
    xff                 String,                  -- X-Forwarded-For (HTTP)
    backend             String,                  -- nome do upstream (HTTP) ou backend stream
    upstream            String,                  -- ip:porta do upstream
    upstream_status     String,
    method              LowCardinality(String),  -- GET/POST/...
    uri                 String,
    status              UInt16,
    size                UInt64,                  -- body_bytes_sent (HTTP) ou bytes_sent (stream)
    bytes_recv          UInt64,                  -- stream only
    req_time            Float32,                 -- HTTP $request_time
    upstream_time       String,                  -- HTTP $upstream_response_time (string para suportar "0.000, 0.001")
    session_time        Float32,                 -- stream
    sni                 String,                  -- stream
    protocol            LowCardinality(String),  -- TCP/UDP (stream)
    referer             String,
    ua                  String,
    ssl_proto           LowCardinality(String),
    scheme              LowCardinality(String),
    req_len             UInt32,
    -- Índices para filtros pontuais
    INDEX idx_host host TYPE bloom_filter GRANULARITY 4,
    INDEX idx_client client TYPE bloom_filter GRANULARITY 4,
    INDEX idx_cfip  cf_ip  TYPE bloom_filter GRANULARITY 4,
    INDEX idx_uri   uri    TYPE tokenbf_v1(2048, 2, 0) GRANULARITY 4
)
ENGINE = MergeTree
PARTITION BY toDate(ts)
ORDER BY (ts, host, status)
TTL toDateTime(ts) + INTERVAL 30 DAY
SETTINGS index_granularity = 8192;

-- View materializada agregada por minuto+host+status — acelera dashboards.
CREATE TABLE IF NOT EXISTS netmon.nginx_access_1m
(
    minute          DateTime,
    src             LowCardinality(String),
    host            String,
    status_class    LowCardinality(String),  -- '2xx','3xx','4xx','5xx','other'
    requests        AggregateFunction(count, UInt64),
    bytes           AggregateFunction(sum, UInt64),
    req_time_p95    AggregateFunction(quantile(0.95), Float32),
    req_time_p50    AggregateFunction(quantile(0.50), Float32),
    req_time_max    AggregateFunction(max, Float32)
)
ENGINE = AggregatingMergeTree
PARTITION BY toDate(minute)
ORDER BY (minute, src, host, status_class)
TTL minute + INTERVAL 90 DAY;

CREATE MATERIALIZED VIEW IF NOT EXISTS netmon.nginx_access_1m_mv
TO netmon.nginx_access_1m AS
SELECT
    toStartOfMinute(toDateTime(ts)) AS minute,
    src,
    host,
    multiIf(status BETWEEN 200 AND 299, '2xx',
            status BETWEEN 300 AND 399, '3xx',
            status BETWEEN 400 AND 499, '4xx',
            status BETWEEN 500 AND 599, '5xx',
            'other') AS status_class,
    countState() AS requests,
    sumState(size) AS bytes,
    quantileState(0.95)(req_time) AS req_time_p95,
    quantileState(0.50)(req_time) AS req_time_p50,
    maxState(req_time) AS req_time_max
FROM netmon.nginx_access
GROUP BY minute, src, host, status_class;

-- Permissão para o usuário netflow (mesmo do datasource Grafana)
GRANT SELECT, INSERT ON netmon.* TO netflow;
