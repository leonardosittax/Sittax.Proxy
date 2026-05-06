#!/usr/bin/env bash
# audit.sh — coleta config completa do MK via SSH (precisa enable-mgmt.rsc rodado antes).
#
# Variáveis:
#   MK_HOST     (default 192.168.2.1)
#   MK_USER     (default admin)
#   MK_PASS     (default vazio — exporte ou crie ~/.mk-pass)
#
# Uso:
#   MK_PASS='senha' ./audit.sh > audit-output.txt 2>&1
set -euo pipefail
MK_HOST="${MK_HOST:-192.168.2.1}"
MK_USER="${MK_USER:-admin}"
MK_PASS="${MK_PASS:-$(test -r ~/.mk-pass && cat ~/.mk-pass)}"
[ -z "$MK_PASS" ] && { echo "[!] MK_PASS vazio. Exporte ou crie ~/.mk-pass"; exit 1; }

mk() {
  sshpass -p "$MK_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o KexAlgorithms=+diffie-hellman-group14-sha1 \
    -o HostKeyAlgorithms=+ssh-rsa \
    "$MK_USER@$MK_HOST" "$1"
}

section() { printf '\n===== %s =====\n' "$1"; }

section "identidade & versao";   mk '/system identity print; /system resource print'
section "interfaces";            mk '/interface print; /interface list print; /interface list member print'
section "ip addresses";          mk '/ip address print'
section "rotas";                 mk '/ip route print'
section "default route";         mk '/ip route print where dst-address=0.0.0.0/0'
section "dhcp client";           mk '/ip dhcp-client print detail'
section "pppoe client";          mk '/interface pppoe-client print detail'
section "NAT dst-nat";           mk '/ip firewall nat print detail where chain=dstnat'
section "NAT src-nat";           mk '/ip firewall nat print detail where chain=srcnat'
section "firewall filter";       mk '/ip firewall filter print detail'
section "firewall mangle";       mk '/ip firewall mangle print detail'
section "address-list";          mk '/ip firewall address-list print'
section "queue tree";            mk '/queue tree print detail'
section "queue simple";          mk '/queue simple print detail'
section "connections count";    mk '/ip firewall connection print count-only'
section "top connections (>5MB reply)"; mk '/ip firewall connection print detail where reply-bytes>5000000'
section "traffic-flow (netflow export)"; mk '/ip traffic-flow print; /ip traffic-flow target print'
section "sniffer/tzsp";          mk '/tool sniffer print'
section "logging";               mk '/system logging print'
section "ip service";            mk '/ip service print'
section "users";                 mk '/user print'
section "users active";          mk '/user active print'
section "dns";                   mk '/ip dns print; /ip dns static print'
section "dhcp leases";           mk '/ip dhcp-server lease print'
section "health";                mk '/system health print'

echo
echo "audit OK. Salve a saída e me envie."
