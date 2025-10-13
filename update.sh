# /bin/sh
rm -f /etc/nginx/nginx.conf
cp ./nginx.conf /etc/nginx/nginx.conf


# Testa a configuração do NGINX
echo ">>    🔍 Testando a configuração do NGINX..."
nginx -t
if [ $? -ne 0 ]; then
    echo ">>    ❌ Erro na configuração do NGINX. Corrija antes de reiniciar."
    exit 1
fi

# Confirmação antes de reiniciar
echo ">>    ✅ Configuração válida."
read -p "systemctl restart nginx? (y/n): " confirm
confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')

if [ "$confirm" = "y" ] || [ "$confirm" = "yes" ]; then
    echo ">>    🔄 Reiniciando o NGINX..."
    systemctl restart nginx
    if [ $? -eq 0 ]; then
        echo ">>    ✅ NGINX reiniciado com sucesso."
    else
        echo ">>    ❌ Falha ao reiniciar o NGINX."
    fi
else
    echo ">>    ⏹ Reinício cancelado."
fi
