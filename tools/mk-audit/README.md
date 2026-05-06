# mk-audit — Auditoria do MikroTik Sittax (192.168.2.1)

O MK hoje só tem **Winbox/8291** aberto: SSH, API REST, SNMP, HTTP estão
fechados. Esse diretório tem dois caminhos:

1. **Caminho rápido** (`audit.rsc`) — comandos para colar no terminal do
   Winbox e me devolver a saída (cola em `audit-output.txt`).
2. **Caminho automatizado** (`enable-mgmt.rsc` + `audit.sh`) — primeiro habilita
   serviços de gerência **somente na LAN**, depois roda o `audit.sh` que coleta
   tudo via SSH.

> Os arquivos `.rsc` são scripts RouterOS prontos pra colar/import; nada deles
> mexe em NAT, firewall ou queue — são apenas leituras + ativação de serviços
> internos. Mitigações sugeridas (queue CFTV, drop amplification) ficam em
> `mitigations.rsc` e devem ser revisadas com calma antes de aplicar.

## Caminho rápido (sem habilitar nada)

1. Abre o Winbox em `192.168.2.1`, menu **New Terminal**.
2. Cole o conteúdo de `audit.rsc`. Ele só executa `print` em comandos seguros.
3. Copie tudo o que aparecer no terminal e me cole de volta — daí eu mostro
   a próxima ação.

## Caminho automatizado

```bash
# 1) Cole enable-mgmt.rsc no terminal do Winbox (uma vez)
# 2) Rode o audit:
cd tools/mk-audit
./audit.sh > audit-output.txt
# 3) Abra o arquivo e me mande
```

## Mitigações sugeridas (não aplicadas automaticamente)

* `mitigations.rsc` — queue para limitar a frota CFTV (.54/.122/.220) a 5 Mbps
  total de upload, drop de portas UDP típicas de amplificação na WAN, e
  hardening básico (drop unsolicited inbound).

**Revise e ajuste antes de importar**: nomes de interfaces (ether1/WAN/etc),
IPs e limites variam por router.
