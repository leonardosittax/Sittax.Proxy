#!/usr/bin/env bash
# Instala/atualiza o dashboard "NetFlow — Detecção de Anomalias e Ataques"
# no Grafana de observabilidade (192.168.2.50:3001).
set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:-http://192.168.2.50:3001}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-TempGrafana2026!}"
DASH_FILE="${1:-$(dirname "$0")/dashboard-anomalies.json}"

[ -f "$DASH_FILE" ] || { echo "Dashboard $DASH_FILE não encontrado"; exit 1; }

# Localiza/cria a pasta NetFlow
FOLDER_UID=$(curl -sf -u "$GRAFANA_USER:$GRAFANA_PASS" "$GRAFANA_URL/api/folders" \
  | grep -oE '"uid":"[^"]+","title":"NetFlow"' | head -1 | cut -d'"' -f4)

if [ -z "$FOLDER_UID" ]; then
  echo "Pasta 'NetFlow' não existe; criando..."
  FOLDER_UID=$(curl -sf -u "$GRAFANA_USER:$GRAFANA_PASS" \
    -H 'Content-Type: application/json' \
    -d '{"title":"NetFlow"}' \
    "$GRAFANA_URL/api/folders" | grep -oE '"uid":"[^"]+"' | head -1 | cut -d'"' -f4)
fi

echo "Pasta NetFlow uid=$FOLDER_UID"

PAYLOAD=$(printf '{"dashboard": %s, "folderUid": "%s", "overwrite": true, "message": "install via script"}' \
  "$(cat "$DASH_FILE")" "$FOLDER_UID")

RESP=$(curl -sf -u "$GRAFANA_USER:$GRAFANA_PASS" \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD" \
  "$GRAFANA_URL/api/dashboards/db")

echo "$RESP"
URL=$(echo "$RESP" | grep -oE '"url":"[^"]+"' | head -1 | cut -d'"' -f4)
echo "Dashboard publicado: ${GRAFANA_URL}${URL}"
