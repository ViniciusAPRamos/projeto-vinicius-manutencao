#Requires -Version 5.1
<#
    Atualização automática do TechPulse pelas Releases do GitHub.
      Canal estável: só versões marcadas (tag v2.1.0 → release normal)
      Canal teste:   também as pré-versões geradas a cada push no main (2.1.0.<nº do build>)
    Só age no app INSTALADO (pasta com TechPulse.exe); na pasta de desenvolvimento, não.
    O instalador novo roda em silêncio depois que a janela fecha e reabre o app.
    Depende do nucleo.ps1.
#>

$Script:RepoGitHub = 'ViniciusAPRamos/projeto-vinicius-manutencao'
$Script:PadraoSetup = '^TechPulse-Setup-(\d+\.\d+\.\d+(\.\d+)?)\.exe$'

function ConvertTo-Versao([string]$Texto) {
    try { return [version]$Texto } catch { return [version]'0.0' }
}

# Release mais nova permitida pelo canal (ou $null)
function Get-UltimaVersao([string]$Canal = 'estavel') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $rels = Invoke-RestMethod -Uri "https://api.github.com/repos/$Script:RepoGitHub/releases?per_page=30" -TimeoutSec 15 -ErrorAction Stop `
        -Headers @{ 'User-Agent' = 'TechPulse'; Accept = 'application/vnd.github+json' }
    $melhor = $null
    foreach ($r in $rels) {
        if ($r.draft -or ($r.prerelease -and $Canal -ne 'teste')) { continue }
        foreach ($a in @($r.assets)) {
            if ($a.name -notmatch $Script:PadraoSetup) { continue }
            $v = $Matches[1]
            if ($melhor -and (ConvertTo-Versao $v) -le (ConvertTo-Versao $melhor.Versao)) { continue }
            $i = [ordered]@{}
            $i.Versao = $v
            $i.Titulo = [string]$r.name
            $i.Notas = [string]$r.body
            $i.Url = [string]$a.browser_download_url
            $i.Tamanho = [double]$a.size
            $i.Teste = [bool]$r.prerelease
            $i.Pagina = [string]$r.html_url
            $i.Data = [string]$r.published_at
            $melhor = [pscustomobject]$i
        }
    }
    return $melhor
}

# Devolve a release se for mais nova que a instalada
function Find-Atualizacao([string]$Canal) {
    $u = Get-UltimaVersao $Canal
    if ($u -and (ConvertTo-Versao $u.Versao) -gt (ConvertTo-Versao $Script:Otz.Versao)) { return $u }
    return $null
}

# Baixa o instalador e agenda: espera o app fechar → instala em silêncio → reabre
function Start-Atualizacao($Info, [int]$PidApp) {
    $destino = Join-Path $env:TEMP "TechPulse-Setup-$($Info.Versao).exe"
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Write-Log "Atualização: baixando $($Info.Url)"
    Invoke-WebRequest -Uri $Info.Url -OutFile $destino -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop
    $tam = (Get-Item $destino).Length
    if ($Info.Tamanho -gt 0 -and $tam -ne $Info.Tamanho) { throw "Download incompleto ($tam de $($Info.Tamanho) bytes). Tente de novo." }
    $exe = Join-Path (Split-Path $Script:Otz.SrcDir) 'TechPulse.exe'
    $q = { param($t) "'" + ($t -replace "'", "''") + "'" }
    $cmd = "Wait-Process -Id $PidApp -Timeout 120 -ErrorAction SilentlyContinue; " +
           "Start-Process -FilePath $(& $q $destino) -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -Wait; " +
           "Remove-Item $(& $q $destino) -Force -ErrorAction SilentlyContinue; " +
           "Start-Process -FilePath $(& $q $exe)"
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd
    Write-Log "Atualização para $($Info.Versao) agendada: o app fecha, instala e reabre."
}
