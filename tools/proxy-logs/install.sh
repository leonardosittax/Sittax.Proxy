#!/usr/bin/env bash
# Aplica o pipeline de logs do nginx em ordem.
#  1. Cria tabela ClickHouse netmon.nginx_access (idempotente)
#  2. Adiciona config Vector e exposição de porta + reinicia container
#  3. Sobe dashboard Grafana
#  4. Imprime os passos manuais necessários no host nginx
#
# Uso: ./install.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOST_OBS="${HOST_OBS:-ubuntu@192.168.2.50}"
HOST_PROXY="${HOST_PROXY:-nginx@192.168.2.32}"
PASS="${SSHPASS:-@Sittax#}"

run_obs() { sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$HOST_OBS" "$@"; }

echo "=== [1/3] Criando tabela ClickHouse ==="
sshpass -p "$PASS" scp -o StrictHostKeyChecking=no "$DIR/clickhouse/nginx-init.sql" "$HOST_OBS:/tmp/nginx-init.sql"
run_obs "docker exec -i netmon-clickhouse clickhouse-client --multiquery < /tmp/nginx-init.sql && rm /tmp/nginx-init.sql"
echo "  OK"

echo "=== [2/3] Configurando Vector ==="
echo "  ⚠ atualização manual necessária:"
echo "  1) Edite /home/ubuntu/netmon/vector/vector.yaml e APPENDE o conteúdo de"
echo "     vector/nginx-syslog.yaml (mescle as chaves sources/transforms/sinks)."
echo "  2) Edite /home/ubuntu/netmon/docker-compose.yml — em services.vector adicione:"
echo "       ports:"
echo "         - \"5140:5140/udp\""
echo "  3) cd /home/ubuntu/netmon && docker compose up -d vector"
echo
echo "  (Não automatizei isso para não corromper a config do operador.)"

echo "=== [3/3] Subindo dashboard Grafana ==="
bash "$DIR/grafana/install-proxy-dashboard.sh"

echo
echo "=== Falta no host do nginx (192.168.2.32) ==="
echo "  O nginx.conf no repo já tem os log_format + access_log syslog. Deploy:"
echo "    sshpass -p '$PASS' ssh $HOST_PROXY 'cd ~/.nginx && bash update.sh'"
echo
echo "Após isso: dashboard em ${GRAFANA_URL:-http://192.168.2.50:3001}/d/sittax-proxy-requests"
