# mitigations-v2.rsc — Mitigações para o MK Sittax baseadas no audit de
# 2026-05-06. Ajustadas para os nomes/setup REAIS:
#   - WAN é interface PPPoE: pppoe-out1 (interface-list "WAN" já existe)
#   - LAN é bridge1 (interface-list "LAN" já existe)
#   - IP público: 177.223.44.35 (dinâmico via PPPoE — substituir por
#     dst-address-type=local nas regras pra ficar resiliente)
#
# Aplicar EM ORDEM e em fases. Cada fase é independente; teste antes de
# prosseguir. Tudo é reversível com /undo após import, ou removendo a regra
# pelo number na lista.

############################################################
# FASE 0 — Preparação: address-list de gerência
############################################################

# IPs/sub-redes que podem acessar serviços de gerência (RDP/SSH/DB) via WAN.
# AJUSTE para os IPs reais dos seus operadores (escritório/casa/VPN).
/ip firewall address-list add list=allowed-mgmt address=192.168.0.0/16 \
  comment="LAN interna (hairpin/VPN)"
/ip firewall address-list add list=allowed-mgmt address=10.8.0.0/24 \
  comment="OpenVPN clients"

# Adicione abaixo os IPs WAN dos seus operadores. Exemplo:
# /ip firewall address-list add list=allowed-mgmt address=200.x.x.x/32 comment="leonardo casa"
# /ip firewall address-list add list=allowed-mgmt address=179.253.141.253/32 comment="devops fixo"

############################################################
# FASE 1 — Restringir port-forwards críticos a allowed-mgmt
############################################################
# Estratégia: adicionamos uma regra de DROP em forward LOGO ANTES das DSTNAT
# matches, dropando conexões NEW para os IPs internos críticos vindas de fora
# da allowed-mgmt. Como o fasttrack só pega established/related, a primeira
# conexão (NEW) sempre passa pelo filter.
#
# Coloque essas regras no TOPO da chain forward (use place-before).

# Cria action=accept para tráfego de gerência (para fastpath)
/ip firewall filter add chain=forward action=accept place-before=0 \
  in-interface-list=WAN connection-state=new \
  src-address-list=allowed-mgmt \
  dst-address=192.168.1.109 dst-port=1433,3390,6557 protocol=tcp \
  comment="mgmt → SQL/PG/RDP dev-server"

/ip firewall filter add chain=forward action=accept place-before=0 \
  in-interface-list=WAN connection-state=new \
  src-address-list=allowed-mgmt \
  dst-address=192.168.1.122 dst-port=3389 protocol=tcp \
  comment="mgmt → RDP dev-server2"

/ip firewall filter add chain=forward action=accept place-before=0 \
  in-interface-list=WAN connection-state=new \
  src-address-list=allowed-mgmt \
  dst-address=192.168.1.67 dst-port=3389 protocol=tcp \
  comment="mgmt → RDP WinDev"

/ip firewall filter add chain=forward action=accept place-before=0 \
  in-interface-list=WAN connection-state=new \
  src-address-list=allowed-mgmt \
  dst-address=192.168.2.103 dst-port=22,55565 protocol=tcp \
  comment="mgmt → SSH+PG DevOps"

/ip firewall filter add chain=forward action=accept place-before=0 \
  in-interface-list=WAN connection-state=new \
  src-address-list=allowed-mgmt \
  dst-address=192.168.2.230,192.168.2.250,192.168.2.249,192.168.2.248 \
  dst-port=22 protocol=tcp \
  comment="mgmt → SSH demais hosts"

/ip firewall filter add chain=forward action=accept place-before=0 \
  in-interface-list=WAN connection-state=new \
  src-address-list=allowed-mgmt \
  dst-address=192.168.2.116 dst-port=5672,6379,15672 protocol=tcp \
  comment="mgmt → Redis/RabbitMQ"

# Drop genérico das portas críticas vindo da WAN para destinos LAN
/ip firewall filter add chain=forward action=drop place-before=0 \
  in-interface-list=WAN connection-state=new protocol=tcp \
  dst-address=192.168.1.109,192.168.1.122,192.168.1.67,192.168.2.103,192.168.2.116,192.168.2.230,192.168.2.250,192.168.2.249,192.168.2.248 \
  dst-port=22,1433,3389,3390,5672,6379,6557,15672,55565 \
  comment="drop unauthorized mgmt access from WAN"

# Mantém aberto apenas: 80/443 → nginx, 1194/UDP → OpenVPN.

############################################################
# FASE 2 — Hardening WAN básico
############################################################

# 2a) Drop inválidos (sempre primeiro)
/ip firewall filter add chain=input   action=drop connection-state=invalid \
  comment="drop invalid input" place-before=0
/ip firewall filter add chain=forward action=drop connection-state=invalid \
  comment="drop invalid forward" place-before=0

# 2b) Aceita ICMP (boa prática para PMTU)
/ip firewall filter add chain=input action=accept protocol=icmp \
  comment="accept ICMP"

# 2c) Drop UDP de portas de amplificação na WAN
/ip firewall filter add chain=input action=drop \
  in-interface-list=WAN protocol=udp \
  dst-port=19,17,53,123,137,161,389,1434,1900,5683,11211 \
  comment="drop UDP amplification (input)"

/ip firewall filter add chain=forward action=drop \
  in-interface-list=WAN protocol=udp \
  dst-port=19,17,53,123,137,161,389,1434,1900,5683,11211 \
  comment="drop UDP amplification (forward)"

# 2d) Rate-limit SYN flood
/ip firewall filter add chain=input action=drop \
  in-interface-list=WAN protocol=tcp tcp-flags=syn,!ack,!fin,!psh,!rst,!urg \
  connection-limit=200,32 src-address-type=!local \
  comment="rate-limit SYN flood"

# 2e) Drop input WAN catch-all (depois das aceitas acima)
/ip firewall filter add chain=input action=drop in-interface-list=WAN \
  comment="default drop WAN input"

############################################################
# FASE 3 — Identificação do software de upload (.54/.122/.220/.41)
############################################################
# Mangle simples para criar address-list dinâmica de quem fala com
# 45.65.220.0/24 e 191.160.39.0/24 nas portas 8080/9090. Isso permite, no
# Grafana, ver quais hosts ainda estão fazendo. Não bloqueia.

/ip firewall address-list add list=upload-targets address=45.65.220.0/24 \
  comment="ISP target group"
/ip firewall address-list add list=upload-targets address=191.160.39.0/24 \
  comment="ISP target group"
/ip firewall address-list add list=upload-targets address=181.174.245.0/24 \
  comment="ISP target group"

/ip firewall mangle add chain=prerouting action=add-src-to-address-list \
  address-list=heavy-uploaders address-list-timeout=1h \
  protocol=tcp dst-port=8080,9090 dst-address-list=upload-targets \
  src-address=192.168.0.0/16 \
  comment="track local hosts uploading to ISP target group"

# Depois rode: /ip firewall address-list print where list=heavy-uploaders
# para ver quem está mandando agora.

############################################################
# FASE 4 — QoS por host (PCQ) — opcional, ajuste sua banda real
############################################################
# Substitua 50M/50M pela sua banda real (download/upload).
# AJUSTE: PPPoE Brasil residencial geralmente tem upload < download.

# /queue type add name=pcq-up  kind=pcq pcq-classifier=src-address pcq-rate=2M
# /queue type add name=pcq-dn  kind=pcq pcq-classifier=dst-address pcq-rate=10M
# /queue simple add name=fairness target=192.168.0.0/16 \
#   max-limit=50M/10M queue=pcq-dn/pcq-up \
#   comment="fairness por host"

############################################################
# Verificação
############################################################
/ip firewall filter print
/ip firewall address-list print
:put "mitigations-v2 OK — revise as ACLs de allowed-mgmt antes de seguir."
