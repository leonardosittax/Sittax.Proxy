#!/usr/bin/env bash
# Copia netdiag.sh para o host de observabilidade e deixa em /usr/local/bin.
# Uso: ./install-on-observability.sh
set -euo pipefail

HOST="${HOST:-ubuntu@192.168.2.50}"
PASS="${SSHPASS:-@Sittax#}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v sshpass >/dev/null; then
  echo "Instale sshpass: apt install sshpass" ; exit 1
fi

echo "[*] Copiando netdiag.sh para $HOST:/tmp ..."
sshpass -p "$PASS" scp -o StrictHostKeyChecking=no "$SCRIPT_DIR/netdiag.sh" "$HOST:/tmp/netdiag.sh"

echo "[*] Movendo para /usr/local/bin (sudo)..."
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$HOST" "sudo install -m 0755 /tmp/netdiag.sh /usr/local/bin/netdiag && rm /tmp/netdiag.sh"

echo "[*] OK. Teste: sshpass -p '$PASS' ssh $HOST 'netdiag top \"1 HOUR\"'"
