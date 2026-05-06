#!/usr/bin/env bash
# Sobe/atualiza o dashboard "Proxy Sittax — Requisições" no Grafana 192.168.2.50:3001
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

GRAFANA_URL="${GRAFANA_URL:-http://192.168.2.50:3001}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-TempGrafana2026!}"
DASH_FILE="${1:-$DIR/dashboard-proxy-requests.json}"

# Pasta "Sittax Proxy"
FOLDER_UID=$(curl -sf -u "$GRAFANA_USER:$GRAFANA_PASS" "$GRAFANA_URL/api/folders" \
  | grep -oE '"uid":"[^"]+","title":"Sittax Proxy"' | head -1 | cut -d'"' -f4 || true)
if [ -z "$FOLDER_UID" ]; then
  FOLDER_UID=$(curl -sf -u "$GRAFANA_USER:$GRAFANA_PASS" \
    -H 'Content-Type: application/json' \
    -d '{"title":"Sittax Proxy"}' \
    "$GRAFANA_URL/api/folders" | grep -oE '"uid":"[^"]+"' | head -1 | cut -d'"' -f4)
fi
echo "Folder uid=$FOLDER_UID"

PAYLOAD=$(printf '{"dashboard": %s, "folderUid": "%s", "overwrite": true, "message": "install proxy dashboard"}' \
  "$(cat "$DASH_FILE")" "$FOLDER_UID")

RESP=$(curl -sf -u "$GRAFANA_USER:$GRAFANA_PASS" \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD" \
  "$GRAFANA_URL/api/dashboards/db")
echo "$RESP"
URL=$(echo "$RESP" | grep -oE '"url":"[^"]+"' | head -1 | cut -d'"' -f4)
echo "Dashboard publicado: ${GRAFANA_URL}${URL}"
