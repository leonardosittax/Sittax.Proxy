# MK audit — RouterOS script para colar no terminal do Winbox.
# SOMENTE LEITURA: nada é alterado. Imprime o que precisamos para entender
# NAT, firewall, mangle, queues, conexões e estado da WAN.
#
# Como usar:
#   1) Winbox > New Terminal
#   2) Cole o conteúdo todo. Aperte Enter ao final.
#   3) Selecione/copie a saída e me mande.

:put "===== identidade & versao ====="
/system identity print
/system resource print
/system routerboard print

:put "\n===== INTERFACES (lista + status) ====="
/interface print detail
/interface ethernet print detail
/interface list print
/interface list member print

:put "\n===== IP ADDRESSES & ROTAS ====="
/ip address print
/ip route print

:put "\n===== ROTAS DEFAULT (com gw upstream) ====="
/ip route print where dst-address=0.0.0.0/0

:put "\n===== DHCP CLIENT ====="
/ip dhcp-client print detail

:put "\n===== PPPoE CLIENT ====="
/interface pppoe-client print detail

:put "\n===== NAT (dst-nat = port forwards) ====="
/ip firewall nat print detail where chain=dstnat
:put "\n----- src-nat / masquerade -----"
/ip firewall nat print detail where chain=srcnat

:put "\n===== FIREWALL FILTER ====="
/ip firewall filter print detail

:put "\n===== FIREWALL MANGLE ====="
/ip firewall mangle print detail

:put "\n===== ADDRESS LISTS ====="
/ip firewall address-list print

:put "\n===== QUEUE TREE ====="
/queue tree print detail

:put "\n===== SIMPLE QUEUE ====="
/queue simple print detail

:put "\n===== CONEXOES TOP 30 (ativas) ====="
/ip firewall connection print count-only
:put "(parcial — muitas conexoes; coletar top 30 manualmente se precisar)"
/ip firewall connection print detail without-paging where reply-bytes>5000000

:put "\n===== TRAFFIC FLOW (NetFlow EXPORT) ====="
/ip traffic-flow print
/ip traffic-flow target print

:put "\n===== TZSP / SNIFFER STREAMING ====="
/tool sniffer print
/system logging print

:put "\n===== SERVICOS HABILITADOS ====="
/ip service print

:put "\n===== USERS ATIVOS ====="
/user print
/user active print

:put "\n===== DNS ====="
/ip dns print
/ip dns static print

:put "\n===== TOP 20 host DHCP leases ====="
/ip dhcp-server lease print

:put "\n===== HEALTH (CPU/RAM/temp) ====="
/system health print
:put "fim do audit"
