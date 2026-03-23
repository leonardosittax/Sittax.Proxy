#!/bin/bash
# =============================================================================
# migrate-ip.sh
# Detecta o IP atual na faixa 192.168.1.0/24 e fixa o equivalente em
# 192.168.2.0/24 via netplan (Ubuntu 18.04+)
# =============================================================================

set -euo pipefail

OLD_PREFIX="192.168.1"
NEW_PREFIX="192.168.2"
NETPLAN_DIR="/etc/netplan"

# ---------------------------------------------------------------------------
# 1. Descobrir interface e IP atual na faixa 192.168.1.x
# ---------------------------------------------------------------------------
IFACE=""
OLD_IP=""
CIDR_SUFFIX=""

while IFS= read -r line; do
    if [[ "$line" =~ ^[0-9]+:\ ([^:]+): ]]; then
        CURRENT_IFACE="${BASH_REMATCH[1]}"
    fi
    if [[ "$line" =~ inet\ (${OLD_PREFIX//./\\.}\.[0-9]+)/([0-9]+) ]]; then
        OLD_IP="${BASH_REMATCH[1]}"
        CIDR_SUFFIX="${BASH_REMATCH[2]}"
        IFACE="$CURRENT_IFACE"
        break
    fi
done < <(ip addr show)

if [[ -z "$OLD_IP" ]]; then
    echo "❌ Nenhum IP na faixa ${OLD_PREFIX}.0/24 encontrado. Nada a fazer."
    exit 0
fi

# Extrai o último octeto para montar o novo IP
LAST_OCTET="${OLD_IP##*.}"
NEW_IP="${NEW_PREFIX}.${LAST_OCTET}"

echo "=============================================="
echo "  Interface  : $IFACE"
echo "  IP atual   : ${OLD_IP}/${CIDR_SUFFIX}"
echo "  Novo IP    : ${NEW_IP}/${CIDR_SUFFIX}"
echo "=============================================="
read -rp "Confirmar migração? [s/N] " CONFIRM
[[ "${CONFIRM,,}" != "s" ]] && echo "Abortado." && exit 0

# ---------------------------------------------------------------------------
# 2. Descobrir o gateway padrão atual
# ---------------------------------------------------------------------------
GW=$(ip route show default | awk '/default/ {print $3; exit}')
if [[ -z "$GW" ]]; then
    read -rp "Gateway não detectado. Informe manualmente: " GW
fi
echo "  Gateway    : $GW"

# ---------------------------------------------------------------------------
# 3. Detectar o arquivo netplan ativo para a interface
# ---------------------------------------------------------------------------
NETPLAN_FILE=$(grep -rl "$IFACE" "$NETPLAN_DIR"/*.yaml 2>/dev/null | head -1 || true)
if [[ -z "$NETPLAN_FILE" ]]; then
    # Usa o primeiro arquivo .yaml disponível ou cria um novo
    NETPLAN_FILE=$(ls "$NETPLAN_DIR"/*.yaml 2>/dev/null | head -1 || echo "${NETPLAN_DIR}/99-migrate.yaml")
fi

echo "  Netplan    : $NETPLAN_FILE"

# ---------------------------------------------------------------------------
# 4. Backup do arquivo atual
# ---------------------------------------------------------------------------
BACKUP="${NETPLAN_FILE}.bak.$(date +%Y%m%d%H%M%S)"
cp "$NETPLAN_FILE" "$BACKUP"
echo "  Backup     : $BACKUP"

# ---------------------------------------------------------------------------
# 5. Gravar nova configuração netplan
# ---------------------------------------------------------------------------
cat > "$NETPLAN_FILE" <<EOF
# Gerado por migrate-ip.sh em $(date)
# Backup anterior: $BACKUP
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: no
      addresses:
        - ${NEW_IP}/${CIDR_SUFFIX}
      routes:
        - to: default
          via: ${GW}
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
EOF

chmod 600 "$NETPLAN_FILE"

# ---------------------------------------------------------------------------
# 6. Aplicar
# ---------------------------------------------------------------------------
echo ""
echo "⚙️  Aplicando nova configuração (netplan apply)..."
netplan apply

echo ""
echo "✅ Migração concluída!"
echo "   ${OLD_IP} → ${NEW_IP}"
echo ""
echo "⚠️  Se você perdeu a conexão SSH, reconecte via ${NEW_IP}"
