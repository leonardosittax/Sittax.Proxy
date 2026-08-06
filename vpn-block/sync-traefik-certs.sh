#!/bin/bash
# Espelha os certificados Let's Encrypt do Traefik (.116) para este proxy (.32).
#
# Por que existe: a 443 aqui e TLS passthrough (ssl_preread), entao o nginx nao
# termina TLS e nao consegue devolver HTML. Para mostrar a pagina "conecte-se a
# VPN" a quem vem de fora, o proxy precisa terminar TLS naquele hostname — e
# para isso precisa do certificado. Em vez de um segundo cliente ACME (que
# brigaria com o desafio HTTP-01 do Traefik e gastaria rate limit do LE), este
# script copia os certificados que o Traefik ja emite e renova.
#
# O acesso ao .116 usa uma chave dedicada com comando fixo no authorized_keys:
# ela so consegue ler o acme.json, nada mais.
set -euo pipefail

REMOTE="ubuntu@192.168.2.116"
KEY="/root/.ssh/acme-sync"
CERTDIR="/etc/nginx/certs"
MAPFILE="/etc/nginx/certs_map.conf"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log() { echo "[$(date -Is)] $*"; }

log "buscando acme.json do Traefik"
ssh -i "$KEY" -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=15 \
    "$REMOTE" > "$TMP/acme.json"

[ -s "$TMP/acme.json" ] || { log "ERRO: acme.json vazio, abortando sem tocar em nada"; exit 1; }

log "extraindo certificados validos"
python3 - "$TMP" <<'PY'
import json, base64, os, re, subprocess, sys
tmp = sys.argv[1]
out = os.path.join(tmp, "certs"); os.makedirs(out, exist_ok=True)
data = json.load(open(os.path.join(tmp, "acme.json")))

ok = skipped = 0
for resolver, body in data.items():
    for c in (body.get("Certificates") or []):
        dom = c["domain"]["main"]
        # nome de arquivo seguro — nada de path traversal vindo do json
        if not re.match(r"^[a-z0-9][a-z0-9.-]*$", dom) or ".." in dom:
            skipped += 1; continue
        crt = base64.b64decode(c["certificate"]).decode()
        key = base64.b64decode(c["key"]).decode()
        # descarta o que ja venceu: servir cert vencido e pior que nao servir
        if subprocess.run(["openssl", "x509", "-noout", "-checkend", "0"],
                          input=crt, capture_output=True, text=True).returncode != 0:
            skipped += 1; continue
        open(os.path.join(out, dom + ".crt"), "w").write(crt)
        open(os.path.join(out, dom + ".key"), "w").write(key)
        ok += 1
print(f"validos={ok} descartados={skipped}")
PY

count=$(find "$TMP/certs" -name '*.crt' | wc -l)
[ "$count" -gt 0 ] || { log "ERRO: nenhum certificado valido extraido, abortando"; exit 1; }

# O nginx escolhe o certificado por SNI usando variavel em ssl_certificate, e
# nesse modo quem abre o arquivo e o WORKER (www-data), nao o master (root).
# Por isso o grupo www-data precisa atravessar o diretorio e ler as chaves.
install -d -m 750 -o root -g www-data "$CERTDIR"

# Certificado de ultimo recurso para SNI desconhecido: o nginx precisa de algum
# certificado para completar o handshake e so entao responder a pagina.
if [ ! -f "$CERTDIR/_default.crt" ]; then
    log "gerando certificado autoassinado de fallback"
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$CERTDIR/_default.key" -out "$CERTDIR/_default.crt" \
        -subj "/CN=acesso-restrito.sittax.com.br" >/dev/null 2>&1
    chown root:www-data "$CERTDIR/_default.key" "$CERTDIR/_default.crt"
    chmod 640 "$CERTDIR/_default.key" "$CERTDIR/_default.crt"
fi

changed=0
while IFS= read -r crt; do
    dom="$(basename "$crt" .crt)"
    if ! cmp -s "$crt" "$CERTDIR/$dom.crt"; then changed=1; fi
    install -m 640 -o root -g www-data "$crt" "$CERTDIR/$dom.crt"
    install -m 640 -o root -g www-data "$TMP/certs/$dom.key" "$CERTDIR/$dom.key"
done < <(find "$TMP/certs" -name '*.crt')

# Mapa SNI -> caminho base do certificado. Gerado a partir dos arquivos que
# REALMENTE existem, entao o nginx nunca aponta para um caminho inexistente
# (o que derrubaria o handshake em vez de mostrar a pagina).
{
    echo "# Gerado por sync-traefik-certs.sh — NAO editar a mao."
    echo "# Atualizado em $(date -Is) — $count certificados."
    echo "map \$ssl_server_name \$blockpage_cert {"
    echo "    default                                  ${CERTDIR}/_default;"
    while IFS= read -r crt; do
        dom="$(basename "$crt" .crt)"
        [ "$dom" = "_default" ] && continue
        printf '    %-40s %s;\n' "$dom" "${CERTDIR}/${dom}"
    done < <(find "$CERTDIR" -name '*.crt' | sort)
    echo "}"
} > "$MAPFILE.new"
cmp -s "$MAPFILE.new" "$MAPFILE" || changed=1
mv "$MAPFILE.new" "$MAPFILE"

if [ "$changed" -eq 1 ]; then
    if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx
        log "certificados atualizados ($count) e nginx recarregado"
    else
        log "ERRO: nginx -t falhou, NAO recarreguei — config anterior segue no ar"
        nginx -t 2>&1 | tail -5
        exit 1
    fi
else
    log "nada mudou ($count certificados)"
fi
