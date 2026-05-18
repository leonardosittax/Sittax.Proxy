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

## Findings da última auditoria

`output/findings-2026-05-06.md` — análise completa da saída do audit. Resumo:
18 port-forwards expostos sem ACL, incluindo Redis, SQL Server, PostgreSQL,
RabbitMQ Mgmt e 3 RDPs. Sem queue. RouterOS 6.49.10 com 4.6 MiB de flash
livre. Hipótese de DVR descartada — os hosts ofensores são PCs/servers
Windows; destino do upload coincide com o DNS dinâmico do ISP, sugerindo app
corporativo.

## Mitigações sugeridas (revise antes de aplicar)

* **`mitigations-v2.rsc`** (atualizado, com nomes/IPs reais do audit):
  * F0 — address-list `allowed-mgmt`
  * F1 — restringir port-forwards críticos (Redis/SQL/RDP/...) a `allowed-mgmt`
  * F2 — hardening WAN (drop invalid, ICMP, amplification, SYN flood, default
    drop input)
  * F3 — mangle de tracking dos uploads para 45.65.220.x:8080
  * F4 — opcional: PCQ fairness por host
* `mitigations.rsc` — versão original, mantida como histórico.

**Sempre revise os IPs em `allowed-mgmt` (Fase 0) antes de seguir**.
