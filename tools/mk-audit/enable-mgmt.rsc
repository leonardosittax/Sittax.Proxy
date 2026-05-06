# enable-mgmt.rsc — habilita serviços de gerência do MK SOMENTE na LAN
# (192.168.2.0/24). NÃO expõe à WAN. Rode uma vez no terminal do Winbox.
#
# Depois disso o audit.sh consegue coletar via SSH.

# SSH na LAN
/ip service set ssh address=192.168.2.0/24,192.168.1.0/24 disabled=no

# API SSL na LAN (RouterOS REST API requer certificado — habilita por garantia)
/ip service set api-ssl address=192.168.2.0/24,192.168.1.0/24 disabled=no
/ip service set api address=192.168.2.0/24,192.168.1.0/24 disabled=no

# WWW (REST) só na LAN — http simples; troque para www-ssl em produção
/ip service set www address=192.168.2.0/24,192.168.1.0/24 disabled=no

# Fortalece: desabilita serviços inseguros
/ip service set telnet disabled=yes
/ip service set ftp disabled=yes

# Confirma
/ip service print
:put "OK — SSH/API/REST liberados apenas para 192.168.2.0/24 e 192.168.1.0/24"
