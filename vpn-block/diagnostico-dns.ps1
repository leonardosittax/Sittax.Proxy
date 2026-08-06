<#
    Diagnostico de resolucao DNS na VPN - Sittax

    Roda na maquina do dev e coleta tudo que explica por que um dominio de
    homologacao nao resolve para o proxy interno (192.168.2.32) mesmo com a
    VPN ligada.

    SOMENTE LEITURA - nao altera nenhuma configuracao.

    Como rodar (PowerShell normal ja serve; como Administrador coleta mais):
        powershell -ExecutionPolicy Bypass -File .\diagnostico-dns.ps1

    A saida tambem vai para um .txt na Area de Trabalho, pronto para enviar.
#>

$ErrorActionPreference = 'SilentlyContinue'

$Alvo        = 'token.stage.sittax.com.br'
$AlvoApex    = 'stage.sittax.com.br'
$IpEsperado  = '192.168.2.32'
$DnsInterno  = '192.168.2.32'
$DnsPublico  = '1.1.1.1'

$saida = Join-Path ([Environment]::GetFolderPath('Desktop')) `
                   ("diagnostico-dns-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
Start-Transcript -Path $saida -Force | Out-Null

function Secao($t) {
    Write-Host ""
    Write-Host ("=" * 78)
    Write-Host "  $t"
    Write-Host ("=" * 78)
}

$ehAdmin = ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Secao "CONTEXTO"
Write-Host "  Maquina........: $env:COMPUTERNAME"
Write-Host "  Usuario........: $env:USERNAME"
Write-Host "  Data...........: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')"
Write-Host "  Windows........: $((Get-CimInstance Win32_OperatingSystem).Caption) build $((Get-CimInstance Win32_OperatingSystem).BuildNumber)"
Write-Host "  Elevado........: $(if($ehAdmin){'sim'}else{'NAO (algumas checagens ficam limitadas)'})"

# -----------------------------------------------------------------------------
Secao "1. NETBIRD"
$nb = Get-Command netbird -ErrorAction SilentlyContinue
if ($nb) {
    Write-Host "  binario: $($nb.Source)"
    Write-Host "  --- netbird status --detail ---"
    & netbird status --detail 2>&1 | ForEach-Object { "    $_" }
} else {
    Write-Host "  !! comando 'netbird' nao encontrado no PATH"
    Get-Service -Name '*netbird*' | ForEach-Object { "    servico: $($_.Name) = $($_.Status)" }
}

# -----------------------------------------------------------------------------
Secao "2. RESOLUCAO - quem responde o que"
# O ponto central: comparar a resposta do resolvedor do SISTEMA com a do DNS
# interno e a do publico. Se a do sistema bate com a publica, o split-DNS nao
# esta sendo aplicado nesta maquina.
foreach ($nome in @($Alvo, $AlvoApex, 'google.com')) {
    Write-Host ""
    Write-Host "  --- $nome ---"

    $sis = Resolve-DnsName -Name $nome -Type A -DnsOnly -ErrorAction SilentlyContinue |
           Where-Object { $_.QueryType -eq 'A' }
    $ipsSis = ($sis | Select-Object -ExpandProperty IPAddress -Unique) -join ', '
    Write-Host ("    resolvedor do sistema : {0}" -f $(if($ipsSis){$ipsSis}else{'(sem resposta)'}))

    $int = Resolve-DnsName -Name $nome -Type A -Server $DnsInterno -DnsOnly -ErrorAction SilentlyContinue |
           Where-Object { $_.QueryType -eq 'A' }
    $ipsInt = ($int | Select-Object -ExpandProperty IPAddress -Unique) -join ', '
    Write-Host ("    DNS interno ($DnsInterno) : {0}" -f $(if($ipsInt){$ipsInt}else{'(nao respondeu - VPN/rota podem estar fora)'}))

    $pub = Resolve-DnsName -Name $nome -Type A -Server $DnsPublico -DnsOnly -ErrorAction SilentlyContinue |
           Where-Object { $_.QueryType -eq 'A' }
    $ipsPub = ($pub | Select-Object -ExpandProperty IPAddress -Unique) -join ', '
    Write-Host ("    DNS publico ($DnsPublico)  : {0}" -f $(if($ipsPub){$ipsPub}else{'(sem resposta)'}))

    if ($nome -ne 'google.com') {
        if ($ipsSis -eq $ipsInt -and $ipsSis) {
            Write-Host "    => OK: o sistema esta usando o DNS interno"
        } elseif ($ipsSis -and $ipsSis -eq $ipsPub) {
            Write-Host "    => PROBLEMA: o sistema esta resolvendo pelo DNS PUBLICO"
        } elseif (-not $ipsSis) {
            Write-Host "    => PROBLEMA: o sistema nao resolveu"
        }
    }
}

# -----------------------------------------------------------------------------
Secao "3. NRPT - as regras de split-DNS que o NetBird cria"
# Sem regra NRPT para o dominio, o Windows nao sabe que aquele sufixo deve ir
# para o resolvedor da VPN.
$nrpt = Get-DnsClientNrptPolicy -ErrorAction SilentlyContinue
if ($nrpt) {
    $nrpt | Select-Object Namespace, NameServers, DnsSecEnabled |
        Format-Table -AutoSize | Out-String -Width 200 | ForEach-Object { $_.TrimEnd() }
    $temStage = $nrpt | Where-Object { $_.Namespace -match 'sittax' }
    Write-Host ""
    if ($temStage) { Write-Host "  => existem regras NRPT para sittax" }
    else           { Write-Host "  => PROBLEMA: NENHUMA regra NRPT para sittax (split-DNS nao aplicado)" }
} else {
    Write-Host "  (nenhuma regra NRPT, ou sem permissao para ler)"
}
Write-Host ""
Write-Host "  --- NRPT vindas de GPO (podem sobrepor as do NetBird) ---"
$gpo = Get-DnsClientNrptRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
if ($gpo) { $gpo | Format-Table Name, Namespace, NameServers -AutoSize | Out-String -Width 200 }
else      { Write-Host "    (nenhuma)" }

# -----------------------------------------------------------------------------
Secao "4. SMART MULTI-HOMED NAME RESOLUTION"
# No Windows 10 o resolvedor dispara a consulta em TODAS as interfaces e aceita
# a primeira resposta. Se a publica chegar antes, o split-DNS perde a corrida.
$chaves = @(
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient',
    'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters'
)
foreach ($c in $chaves) {
    $v = Get-ItemProperty -Path $c -ErrorAction SilentlyContinue
    if ($v) {
        Write-Host "  $c"
        foreach ($p in 'DisableSmartNameResolution','DisableParallelAandAAAA','EnableMultiHomedNameResolution') {
            if ($null -ne $v.$p) { Write-Host "    $p = $($v.$p)" }
        }
    }
}
$dsnr = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -ErrorAction SilentlyContinue).DisableSmartNameResolution
if ($dsnr -ne 1) {
    Write-Host "  => ATENCAO: multi-homed NAO esta desabilitado (DisableSmartNameResolution != 1)."
    Write-Host "     No Windows 10 essa e a causa mais comum de split-DNS intermitente."
}

# -----------------------------------------------------------------------------
Secao "5. INTERFACES, DNS E METRICA"
# Metrica pior na interface da VPN faz o Windows preferir outro resolvedor.
Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.ServerAddresses } |
    Select-Object InterfaceAlias, @{n='DNS';e={$_.ServerAddresses -join ', '}} |
    Format-Table -AutoSize | Out-String -Width 200 | ForEach-Object { $_.TrimEnd() }
Write-Host ""
Write-Host "  --- metrica das interfaces (menor = preferida) ---"
Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.ConnectionState -eq 'Connected' } |
    Sort-Object InterfaceMetric |
    Select-Object InterfaceAlias, InterfaceMetric, Dhcp |
    Format-Table -AutoSize | Out-String -Width 200 | ForEach-Object { $_.TrimEnd() }

# -----------------------------------------------------------------------------
Secao "6. DNS OVER HTTPS NO NAVEGADOR"
# Com DoH ligado o navegador ignora o resolvedor do sistema - o nslookup acerta
# e mesmo assim o site vai para o IP publico.
$doh = @(
    @{ n='Chrome (politica)'; p='HKLM:\SOFTWARE\Policies\Google\Chrome';          k='DnsOverHttpsMode' },
    @{ n='Edge (politica)';   p='HKLM:\SOFTWARE\Policies\Microsoft\Edge';         k='DnsOverHttpsMode' }
)
foreach ($d in $doh) {
    $v = (Get-ItemProperty -Path $d.p -ErrorAction SilentlyContinue).($d.k)
    Write-Host ("  {0,-20} {1}" -f $d.n, $(if($v){"DnsOverHttpsMode = $v"}else{'sem politica (usa o padrao do navegador - DoH pode estar LIGADO)'}))
}
Write-Host "  Obs.: sem politica corporativa, Chrome/Edge podem usar DoH automatico."
Write-Host "        Verificar manualmente em: Configuracoes > Privacidade > Usar DNS seguro."

# -----------------------------------------------------------------------------
Secao "7. HOSTS E CACHE"
$hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
$linhas = Get-Content $hosts -ErrorAction SilentlyContinue |
          Where-Object { $_ -match 'sittax' -and $_ -notmatch '^\s*#' }
if ($linhas) { Write-Host "  => entradas fixas no hosts (sobrepoem o DNS):"; $linhas | ForEach-Object { "    $_" } }
else         { Write-Host "  nenhuma entrada de sittax no hosts" }
Write-Host ""
Write-Host "  --- cache DNS atual para sittax ---"
$cache = Get-DnsClientCache -ErrorAction SilentlyContinue | Where-Object { $_.Entry -match 'sittax' }
if ($cache) { $cache | Select-Object Entry, Data | Format-Table -AutoSize | Out-String -Width 200 | ForEach-Object { $_.TrimEnd() } }
else        { Write-Host "    (vazio)" }

# -----------------------------------------------------------------------------
Secao "8. ALCANCE DO PROXY PELA VPN"
# Se a rota 192.168.2.32/32 nao chegou, nem o DNS nem o acesso funcionam.
Write-Host "  --- rota para $IpEsperado ---"
Find-NetRoute -RemoteIPAddress $IpEsperado -ErrorAction SilentlyContinue |
    Select-Object -First 2 InterfaceAlias, NextHop, @{n='Rota';e={$_.DestinationPrefix}} |
    Format-Table -AutoSize | Out-String -Width 200 | ForEach-Object { $_.TrimEnd() }
foreach ($porta in 53, 443) {
    $r = Test-NetConnection -ComputerName $IpEsperado -Port $porta -WarningAction SilentlyContinue
    Write-Host ("  TCP {0}:{1} -> {2}" -f $IpEsperado, $porta, $(if($r.TcpTestSucceeded){'ABERTA'}else{'sem resposta'}))
}

# -----------------------------------------------------------------------------
Secao "9. OUTROS AGENTES QUE MEXEM EM DNS"
# Outro cliente de VPN ou agente de seguranca pode sequestrar a resolucao.
$suspeitos = 'zscaler|forticlient|globalprotect|anyconnect|openvpn|wireguard|tailscale|pulse|checkpoint|sophos|umbrella|cloudflare warp|nordvpn|expressvpn'
$svc = Get-Service -ErrorAction SilentlyContinue |
       Where-Object { $_.DisplayName -match $suspeitos -or $_.Name -match $suspeitos }
if ($svc) { $svc | Select-Object Name, DisplayName, Status | Format-Table -AutoSize | Out-String -Width 200 }
else      { Write-Host "  nenhum agente conhecido de VPN/DNS alem do NetBird" }
Write-Host ""
Write-Host "  --- adaptadores virtuais ativos ---"
Get-NetAdapter -ErrorAction SilentlyContinue |
    Where-Object { $_.Status -eq 'Up' } |
    Select-Object Name, InterfaceDescription, LinkSpeed |
    Format-Table -AutoSize | Out-String -Width 200 | ForEach-Object { $_.TrimEnd() }

# -----------------------------------------------------------------------------
Secao "RESUMO"
$sisFinal = (Resolve-DnsName -Name $Alvo -Type A -DnsOnly -ErrorAction SilentlyContinue |
             Where-Object { $_.QueryType -eq 'A' } |
             Select-Object -ExpandProperty IPAddress -Unique) -join ', '
Write-Host "  $Alvo resolve para: $(if($sisFinal){$sisFinal}else{'(nada)'})"
Write-Host "  esperado pela VPN.: $IpEsperado"
if ($sisFinal -eq $IpEsperado) {
    Write-Host ""
    Write-Host "  A resolucao do SISTEMA esta correta."
    Write-Host "  Se o navegador ainda vai para o IP publico, a causa e DoH (secao 6)."
} else {
    Write-Host ""
    Write-Host "  A resolucao do sistema NAO esta usando o DNS interno."
    Write-Host "  Olhar, nesta ordem: secao 3 (NRPT), 4 (multi-homed), 8 (rota), 7 (hosts/cache)."
}

Stop-Transcript | Out-Null
Write-Host ""
Write-Host "Arquivo gerado: $saida"
Write-Host "Envie esse arquivo para a infraestrutura."
