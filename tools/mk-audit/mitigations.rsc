# mitigations.rsc — Sugestões para o MK Sittax baseadas no diagnóstico de
# 2026-05-06. **REVISE E AJUSTE NOMES DE INTERFACE/IP** antes de aplicar.
#
# Aplicar em duas fases:
#   1) Marcação (mangle) + queue para a frota CFTV (.54/.122/.220/.41)
#   2) Hardening WAN (drop UDP amplification + unsolicited inbound)
#
# Se algo der errado, /ip firewall nat/filter/mangle/queue undo são reversíveis.

############################################################
# FASE 1 — Limitar upload da frota CFTV
############################################################

# Address list dos hosts ofensores
/ip firewall address-list add list=cftv-fleet address=192.168.1.54  comment="DVR/CFTV 1"
/ip firewall address-list add list=cftv-fleet address=192.168.1.122 comment="DVR/CFTV 2"
/ip firewall address-list add list=cftv-fleet address=192.168.1.220 comment="DVR/CFTV 3"
/ip firewall address-list add list=cftv-fleet address=192.168.1.41  comment="DVR/CFTV 4"

# Marca conexao -> packet das saidas para 8080/9090 vindas da frota
/ip firewall mangle add chain=prerouting action=mark-connection \
  src-address-list=cftv-fleet protocol=tcp dst-port=8080,9090 \
  new-connection-mark=cftv-up passthrough=yes \
  comment="CFTV upload connection"

/ip firewall mangle add chain=prerouting action=mark-packet \
  connection-mark=cftv-up new-packet-mark=cftv-up passthrough=no \
  comment="CFTV upload packet"

# Queue tree limitando upload total a 5M (ajuste para sua banda)
# Coloque parent=<nome-interface-WAN>. Use /interface print para ver.
# Exemplo se WAN for ether1:
/queue tree add name=q-cftv-up parent=ether1 packet-mark=cftv-up \
  max-limit=5M limit-at=2M priority=8 \
  comment="Limita upload da frota CFTV"

############################################################
# FASE 2 — Hardening WAN
############################################################

# (Pré-requisito) Tenha uma interface list "WAN" com sua interface uplink.
# /interface list add name=WAN
# /interface list member add list=WAN interface=ether1   # <- ajuste

# 2a) Drop portas UDP típicas de amplificação DDoS chegando da WAN
/ip firewall filter add chain=input action=drop \
  in-interface-list=WAN protocol=udp \
  dst-port=19,17,53,123,137,161,389,1434,1900,5683,11211 \
  comment="drop UDP amplification ports (input)"

/ip firewall filter add chain=forward action=drop \
  in-interface-list=WAN protocol=udp \
  dst-port=19,17,53,123,137,161,389,1434,1900,5683,11211 \
  comment="drop UDP amplification ports (forward)"

# 2b) Drop tráfego inbound não-solicitado (sem dst-nat correspondente)
/ip firewall filter add chain=forward action=drop \
  in-interface-list=WAN connection-state=new connection-nat-state=!dstnat \
  comment="drop unsolicited inbound (no DNAT match)"

# 2c) Drop pacotes invalidos
/ip firewall filter add chain=input   action=drop connection-state=invalid comment="drop invalid input"
/ip firewall filter add chain=forward action=drop connection-state=invalid comment="drop invalid forward"

# 2d) Limita SYN flood na WAN (200 SYN/s)
/ip firewall filter add chain=input action=drop \
  in-interface-list=WAN protocol=tcp tcp-flags=syn,!ack,!fin,!psh,!rst,!urg \
  src-address-type=!local connection-limit=200,32 \
  comment="rate-limit SYN flood"

############################################################
# FASE 3 — Bloqueio de exploits IoT contra DVR
############################################################

# Vimos no log do nginx tentativa de exploit /device.rsp?...wget...arm7 vinda
# da WAN. Como o nginx hoje retorna 404 (192.168.2.116 nao tem o endpoint),
# nao ha vetor direto. Mas se algum DVR tiver port-forward, ele pode estar
# vulneravel. Auditoria recomendada:

# /ip firewall nat print where chain=dstnat
#   -> qualquer regra com to-addresses dentro de 192.168.1.{54,122,220,41}
#      DEVE ser revisada/removida.

:put "Mitigations carregadas. Reveja queue tree (ajuste interface WAN) e address-list."
