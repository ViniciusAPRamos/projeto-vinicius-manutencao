#Requires -Version 5.1
<#
    Desinstalar programas por completo (Otimizador Vinicius v2.0)
      1. Roda o desinstalador OFICIAL do programa (sem janelas quando o
         programa permite: MSI, Inno Setup ou QuietUninstallString).
      2. Procura sobras: pastas, chaves de registro, itens de inicialização,
         tarefas agendadas, serviços e a entrada órfã na lista de programas.
      3. O usuário confere e apaga: pastas vão para a Lixeira e o registro
         ganha backup .reg em Documentos\OtimizadorVinicius\Backups.
    Apps da Microsoft Store: Remove-AppxPackage e, com administrador, para
    todos os usuários e sem reinstalar em contas novas (provisionado).
    Depende do nucleo.ps1 e do ferramentas.ps1 (Get-ItensInicializacao).
#>

# Apps que nunca aparecem (o Windows depende deles; a Store reinstala os demais)
$Script:AppsEssenciais = '^Microsoft\.(WindowsStore|DesktopAppInstaller|StorePurchaseApp|SecHealthUI|VCLibs|NET\.|UI\.Xaml|WindowsAppRuntime|Services\.Store|LanguageExperiencePack|Winget)|^MicrosoftWindows\.|^Windows\.|^MicrosoftCorporationII\.WinAppRuntime'
# Nomes que nunca viram "sobra" sozinhos (pastas e chaves compartilhadas)
$Script:NomesGenericos = @('microsoft', 'windows', 'common files', 'google', 'intel', 'nvidia', 'nvidia corporation', 'amd', 'realtek', 'packages', 'temp', 'programs',
    'microsoft corporation', 'classes', 'policies', 'wow6432node', 'mozilla', 'apple', 'adobe', 'dell', 'hp', 'lenovo', 'asus', 'oracle', 'java', 'steam', 'program files')

# Nome sem versão/arquitetura: "Radmin VPN 2.1.1" → "Radmin VPN"
function Get-NomeBase([string]$Nome) {
    $n = $Nome -replace '\(.*?\)', '' -replace '\s+v?\d+(\.\d+)+.*$', '' -replace '\s+(x64|x86|64-bit|32-bit)\b', '' -replace '[™®©]', ''
    return $n.Trim(' ', '-', '_')
}

function Test-NomeUtil([string]$Nome) {
    return $Nome -and $Nome.Length -ge 4 -and ($Script:NomesGenericos -notcontains $Nome.ToLowerInvariant())
}

# Pastas AppData da conta que usa o PC (se o admin for outra conta)
function Get-PastasUsuarioAlvo {
    $r = @{ Roaming = $env:APPDATA; Local = $env:LOCALAPPDATA }
    if ($Script:Otz.SidAlvo) {
        $perfil = (Read-RegValor "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($Script:Otz.SidAlvo)" 'ProfileImagePath').Valor
        if ($perfil) { $r.Roaming = Join-Path $perfil 'AppData\Roaming'; $r.Local = Join-Path $perfil 'AppData\Local' }
    }
    return $r
}

# ---------------------------------------------------------------
#  Lista
# ---------------------------------------------------------------
function Get-ProgramasInstalados {
    $lista = New-Object System.Collections.Generic.List[object]
    $raizes = @(
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $vistos = @{}
    foreach ($raiz in $raizes) {
        $rr = Get-RegRaiz $raiz
        $k = $rr.Base.OpenSubKey($rr.Sub)
        if (-not $k) { continue }
        try {
            foreach ($sub in $k.GetSubKeyNames()) {
                $e = $k.OpenSubKey($sub)
                if (-not $e) { continue }
                try {
                    $nome = [string]$e.GetValue('DisplayName')
                    $desinst = [string]$e.GetValue('UninstallString')
                    if (-not $nome -or -not $desinst) { continue }
                    if ([int]$e.GetValue('SystemComponent', 0) -eq 1 -or $e.GetValue('ParentKeyName') -or ([string]$e.GetValue('ReleaseType')) -match 'Update|Hotfix') { continue }
                    $chaveVisto = "$nome|$([string]$e.GetValue('DisplayVersion'))"
                    if ($vistos.ContainsKey($chaveVisto)) { continue }
                    $vistos[$chaveVisto] = $true
                    $data = $null
                    $d = [string]$e.GetValue('InstallDate')
                    if ($d -match '^\d{8}$') { try { $data = [datetime]::ParseExact($d, 'yyyyMMdd', $null) } catch { } }
                    $r = [ordered]@{}
                    $r.Id = "reg:$raiz\$sub"
                    $r.Tipo = 'programa'
                    $r.Nome = $nome
                    $r.Editor = [string]$e.GetValue('Publisher')
                    $r.Versao = [string]$e.GetValue('DisplayVersion')
                    $r.Data = $data
                    $r.Bytes = [double]$e.GetValue('EstimatedSize', 0) * 1KB
                    $r.Desinstalar = $desinst
                    $r.Silencioso = [string]$e.GetValue('QuietUninstallString')
                    $r.Pasta = ([string]$e.GetValue('InstallLocation')).Trim('"', ' ')
                    $r.Icone = ([string]$e.GetValue('DisplayIcon')) -replace ',\s*-?\d+$', '' -replace '"', ''
                    $r.Chave = "$raiz\$sub"
                    $r.Msi = ($sub -match '^\{[0-9A-Fa-f-]{36}\}$') -and ([int]$e.GetValue('WindowsInstaller', 0) -eq 1 -or $desinst -match '(?i)msiexec')
                    $r.Guid = if ($sub -match '^\{[0-9A-Fa-f-]{36}\}$') { $sub } else { '' }
                    $r.Pacote = ''
                    $lista.Add([pscustomobject]$r)
                } finally { $e.Close() }
            }
        } finally { $k.Close() }
    }
    # Apps da Microsoft Store (só os que dá para remover)
    foreach ($p in @(Get-AppxPackage -ErrorAction SilentlyContinue)) {
        if ($p.IsFramework -or $p.NonRemovable -or [string]$p.SignatureKind -eq 'System' -or $p.Name -match $Script:AppsEssenciais) { continue }
        $nome = ''
        try {
            $m = [xml][IO.File]::ReadAllText((Join-Path $p.InstallLocation 'AppxManifest.xml'))
            $nome = [string]$m.Package.Properties.DisplayName
        } catch { }
        if (-not $nome -or $nome -like 'ms-resource:*') { $nome = ($p.Name -split '\.', 2)[-1] }
        $r = [ordered]@{}
        $r.Id = "appx:$($p.Name)"
        $r.Tipo = 'app'
        $r.Nome = $nome
        $r.Editor = ([string]$p.Publisher -replace '^CN=([^,]+).*$', '$1')
        $r.Versao = [string]$p.Version
        $r.Data = $null
        $r.Bytes = 0.0
        $r.Desinstalar = ''; $r.Silencioso = ''; $r.Pasta = [string]$p.InstallLocation; $r.Icone = ''
        $r.Chave = ''; $r.Msi = $false; $r.Guid = ''
        $r.Pacote = $p.Name
        $lista.Add([pscustomobject]$r)
    }
    return @($lista | Sort-Object Nome)
}

# ---------------------------------------------------------------
#  Desinstalar
# ---------------------------------------------------------------
# Separa "C:\x\unins000.exe" /args em executável + argumentos
function Split-Comando([string]$Linha) {
    $l = [Environment]::ExpandEnvironmentVariables($Linha.Trim())
    if ($l -match '^"([^"]+)"\s*(.*)$') { return @{ Exe = $Matches[1]; Args = $Matches[2] } }
    if ($l -match '^(.+?\.exe)\s*(.*)$') { return @{ Exe = $Matches[1]; Args = $Matches[2] } }
    return @{ Exe = $l; Args = '' }
}

# Escolhe o comando: silencioso só quando é garantido (MSI, Inno Setup, QuietUninstallString)
function Get-ComandoDesinstalar($Prog, [bool]$Silencioso) {
    if ($Prog.Msi -and $Prog.Guid) {
        $modo = if ($Silencioso) { '/qb /norestart' } else { '' }
        return @{ Exe = "$env:SystemRoot\System32\msiexec.exe"; Args = "/x $($Prog.Guid) $modo".Trim(); Silencioso = $Silencioso; Tipo = 'MSI' }
    }
    if ($Silencioso -and $Prog.Silencioso) {
        $c = Split-Comando $Prog.Silencioso
        return @{ Exe = $c.Exe; Args = $c.Args; Silencioso = $true; Tipo = 'silencioso do programa' }
    }
    $c = Split-Comando $Prog.Desinstalar
    if ($Silencioso -and (Split-Path $c.Exe -Leaf) -match '^unins\d{3}\.exe$') {
        return @{ Exe = $c.Exe; Args = "$($c.Args) /VERYSILENT /SUPPRESSMSGBOXES /NORESTART".Trim(); Silencioso = $true; Tipo = 'Inno Setup' }
    }
    return @{ Exe = $c.Exe; Args = $c.Args; Silencioso = $false; Tipo = 'janela do programa' }
}

function Invoke-DesinstalarPrograma($Prog, [bool]$Silencioso, [bool]$TodosUsuarios) {
    if ($Prog.Tipo -eq 'app') {
        try {
            if ($TodosUsuarios) {
                Get-AppxPackage -AllUsers -Name $Prog.Pacote -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction Stop
                Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object DisplayName -eq $Prog.Pacote |
                    Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
            } else {
                Get-AppxPackage -Name $Prog.Pacote -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction Stop
            }
            Write-Log "Desinstalado (app): $($Prog.Nome) [$($Prog.Pacote)] todos os usuários: $TodosUsuarios"
            $msg = if ($TodosUsuarios) { 'Removido de todas as contas e não volta em contas novas.' } else { 'Removido.' }
            return @{ Status = 'ok'; Mensagem = "$msg Para reinstalar, use a Microsoft Store." }
        } catch { return @{ Status = 'erro'; Mensagem = $_.Exception.Message } }
    }
    $cmd = Get-ComandoDesinstalar $Prog $Silencioso
    if (-not (Test-Path -LiteralPath $cmd.Exe)) {
        return @{ Status = 'erro'; Mensagem = "O desinstalador não existe mais ($($cmd.Exe)). Use 'Procurar sobras' para limpar o que ficou."; Orfao = $true }
    }
    Write-Log "Desinstalando $($Prog.Nome): `"$($cmd.Exe)`" $($cmd.Args)"
    try {
        $p = if ($cmd.Args) { Start-Process -FilePath $cmd.Exe -ArgumentList $cmd.Args -PassThru -Wait } else { Start-Process -FilePath $cmd.Exe -PassThru -Wait }
        $codigo = $p.ExitCode
    } catch { return @{ Status = 'erro'; Mensagem = $_.Exception.Message } }
    # Vários desinstaladores (NSIS, por exemplo) se copiam para a pasta Temp e o primeiro processo
    # sai na hora: espera a entrada sumir da lista de programas por até 10 minutos
    $limite = (Get-Date).AddMinutes(10)
    while ((Test-RegChave $Prog.Chave) -and (Get-Date) -lt $limite) { Start-Sleep -Seconds 2 }
    if (Test-RegChave $Prog.Chave) {
        if ($codigo -eq 1602) { return @{ Status = 'aviso'; Mensagem = 'Desinstalação cancelada.' } }
        return @{ Status = 'aviso'; Mensagem = "O desinstalador terminou (código $codigo), mas o programa continua na lista. Foi cancelado?" }
    }
    $msg = "Desinstalado ($($cmd.Tipo))."
    if ($codigo -eq 3010 -or $codigo -eq 1641) { $msg += ' Reinicie o PC para concluir.' }
    Write-Log "Desinstalado: $($Prog.Nome) (código $codigo)"
    return @{ Status = 'ok'; Mensagem = $msg }
}

# ---------------------------------------------------------------
#  Sobras
# ---------------------------------------------------------------
function Get-TamanhoPasta([string]$Pasta) {
    $t = 0.0
    try { foreach ($f in [IO.Directory]::EnumerateFiles($Pasta, '*', 'AllDirectories')) { try { $t += ([IO.FileInfo]$f).Length } catch { } } } catch { }
    return $t
}

# Pastas onde OUTROS programas instalados moram (para nunca apagar uma pasta compartilhada,
# como C:\Program Files\Epic Games, que guarda o launcher E os jogos)
function Get-LocaisOutrosProgramas($Prog) {
    $locais = New-Object System.Collections.Generic.List[string]
    foreach ($o in @(Get-ProgramasInstalados)) {
        if ($o.Id -eq $Prog.Id -or $o.Tipo -ne 'programa') { continue }
        foreach ($c in @($o.Pasta, $(if ($o.Icone) { Split-Path $o.Icone -Parent }), $(if ($o.Desinstalar) { Split-Path (Split-Comando $o.Desinstalar).Exe -Parent }))) {
            if ($c -and $c -match '^[A-Za-z]:\\') { $locais.Add($c.TrimEnd('\')) }
        }
    }
    return $locais.ToArray()
}

function Test-PastaCompartilhada([string]$Pasta, [string[]]$Locais) {
    foreach ($l in $Locais) {
        if ($l -ieq $Pasta -or $l.StartsWith($Pasta + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Find-SobrasPrograma($Prog) {
    $sobras = New-Object System.Collections.Generic.List[object]
    $vistos = @{}
    $locais = @()
    if ($Prog.Tipo -eq 'programa') { $locais = Get-LocaisOutrosProgramas $Prog }
    # Bloco (e não função aninhada): no PS 5.1, função aninhada + @(lista) dá 'Os tipos de argumento não correspondem'
    $addSobra = { param([string]$Tipo, [string]$Alvo, [string]$Texto, [bool]$Certeza, [double]$Bytes = 0)
        $k = "$Tipo|$Alvo".ToLowerInvariant()
        if ($vistos.ContainsKey($k)) { return }
        if ($Tipo -eq 'pasta') {
            if (Test-PastaCompartilhada $Alvo $locais) { return }
            # Pasta grande: pode ter jogos ou arquivos do usuário; vem desmarcada
            if ($Bytes -gt 5GB) { $Certeza = $false; $Texto += ' (grande: confira se não guarda jogos ou arquivos seus)' }
        }
        $vistos[$k] = $true
        $sobras.Add([pscustomobject]@{ Tipo = $Tipo; Alvo = $Alvo; Texto = $Texto; Certeza = $Certeza; Bytes = $Bytes; Programa = $Prog.Nome })
    }
    if ($Prog.Tipo -eq 'app') {
        $u = Get-PastasUsuarioAlvo
        foreach ($p in @(Get-ChildItem (Join-Path $u.Local 'Packages') -Directory -Filter "$($Prog.Pacote)_*" -ErrorAction SilentlyContinue)) {
            & $addSobra 'pasta' $p.FullName 'Dados do app que ficaram' $true (Get-TamanhoPasta $p.FullName)
        }
        return $sobras.ToArray()
    }

    $base = Get-NomeBase $Prog.Nome
    $editor = (Get-NomeBase $Prog.Editor) -replace '[,.]?\s+(Inc|LLC|Ltd|GmbH|Corp|Corporation|Co)\.?$', ''
    $nomes = @($base, ($base -replace '\s', '')) | Where-Object { Test-NomeUtil $_ } | Select-Object -Unique
    $u = Get-PastasUsuarioAlvo
    $raizes = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $u.Roaming, $u.Local, (Join-Path $u.Local 'Programs')) | Where-Object { $_ } | Select-Object -Unique

    # Pasta de instalação e pasta do ícone (fora do Windows e não sendo uma raiz)
    foreach ($cand in @($Prog.Pasta, $(if ($Prog.Icone) { Split-Path $Prog.Icone -Parent }))) {
        if (-not $cand -or -not (Test-Path -LiteralPath $cand -PathType Container)) { continue }
        $cheio = (Resolve-Path -LiteralPath $cand).Path.TrimEnd('\')
        if ($raizes -contains $cheio -or $cheio.StartsWith($env:SystemRoot, [StringComparison]::OrdinalIgnoreCase) -or $cheio.Length -le 3) { continue }
        $folha = Split-Path $cheio -Leaf
        if (-not (Test-NomeUtil $folha)) { continue }
        # Pasta com o nome do fabricante costuma ser compartilhada: só entra se tiver o nome do programa
        if ($editor -and $folha -ieq $editor -and $folha -ine $base) { continue }
        & $addSobra 'pasta' $cheio 'Pasta de instalação' $true (Get-TamanhoPasta $cheio)
    }
    # Pastas com o nome do programa (direto ou dentro da pasta do fabricante)
    foreach ($r in $raizes) {
        foreach ($n in $nomes) {
            foreach ($c in @((Join-Path $r $n), $(if (Test-NomeUtil $editor) { Join-Path (Join-Path $r $editor) $n }))) {
                if ($c -and (Test-Path -LiteralPath $c -PathType Container)) { & $addSobra 'pasta' $c 'Pasta com o nome do programa' $true (Get-TamanhoPasta $c) }
            }
        }
    }
    # Chaves de registro com o nome do programa
    foreach ($hive in 'HKCU\Software', 'HKLM\SOFTWARE', 'HKLM\SOFTWARE\WOW6432Node') {
        foreach ($n in $nomes) {
            foreach ($c in @("$hive\$n", $(if (Test-NomeUtil $editor) { "$hive\$editor\$n" }))) {
                if ($c -and (Test-RegChave $c)) { & $addSobra 'registro' $c 'Configurações do programa no registro' $true }
            }
        }
    }
    # Entrada que ficou na lista de programas (desinstalador já não existe)
    if ($Prog.Chave -and -not $Prog.Msi -and (Test-RegChave $Prog.Chave)) {
        $c = Split-Comando $Prog.Desinstalar
        if ($c.Exe -match '^[A-Za-z]:\\' -and -not (Test-Path -LiteralPath $c.Exe)) { & $addSobra 'registro' $Prog.Chave 'Entrada órfã na lista de programas instalados' $true }
    }
    # Inicialização, tarefas e serviços que apontam para o programa
    $pastasProg = New-Object System.Collections.Generic.List[string]
    foreach ($x in $sobras) { if ($x.Tipo -eq 'pasta') { $pastasProg.Add($x.Alvo) } }
    $dentro = { param($exe) foreach ($pp in $pastasProg) { if ($exe -and $exe.StartsWith($pp, [StringComparison]::OrdinalIgnoreCase)) { return $true } }; return $false }
    foreach ($e in @(Get-ItensInicializacao)) {
        $exe = [Environment]::ExpandEnvironmentVariables([string]$e.Exe)
        $sumiu = $exe -and -not (Test-Path -LiteralPath $exe)
        $nomeBate = @($nomes | Where-Object { [string]$e.Nome -like "*$_*" }).Count -gt 0
        if ((& $dentro $exe) -or ($sumiu -and $nomeBate)) {
            $origem = if ($e.Aprovado -match 'StartupFolder') { 'pasta Inicializar' } else { 'registro Run' }
            & $addSobra 'inicio' "$($e.Aprovado)|$($e.Nome)|$($e.Comando)" "Abre com o Windows ($origem): $($e.Nome)" ([bool]$sumiu)
        }
    }
    foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' })) {
        $exe = [Environment]::ExpandEnvironmentVariables(([string]@($t.Actions)[0].Execute).Trim('"'))
        $sumiu = $exe -and -not (Test-Path -LiteralPath $exe)
        $nomeBate = @($nomes | Where-Object { $t.TaskName -like "*$_*" }).Count -gt 0
        if ((& $dentro $exe) -or ($sumiu -and $nomeBate)) { & $addSobra 'tarefa' "$($t.TaskPath)$($t.TaskName)" "Tarefa agendada: $($t.TaskName)" ([bool]$sumiu) }
    }
    foreach ($s in @(Get-Service -ErrorAction SilentlyContinue)) {
        $img = [string](Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.Name)" -ErrorAction SilentlyContinue).ImagePath
        if (-not $img -or $img -match 'svchost\.exe') { continue }
        $exe = (Split-Comando $img).Exe
        if ((& $dentro $exe) -and -not (Test-Path -LiteralPath $exe)) { & $addSobra 'servico' $s.Name "Serviço que ficou registrado: $($s.DisplayName)" $true }
    }
    return $sobras.ToArray()
}

# Apaga as sobras escolhidas: pastas para a Lixeira, registro com backup .reg
function Remove-Sobras($Sobras) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $pastaBkp = Join-Path $Script:Otz.Dados ("Backups\desinstalacao_" + (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
    $res = New-Object System.Collections.Generic.List[object]
    $n = 0
    foreach ($s in @($Sobras | Sort-Object @{ Expression = { if ($_.Tipo -eq 'pasta') { 1 } else { 0 } } })) {
        $n++
        try {
            switch ($s.Tipo) {
                'pasta' {
                    if (Test-Path -LiteralPath $s.Alvo) {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($s.Alvo, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
                        # Pasta do fabricante que ficou vazia
                        $pai = Split-Path $s.Alvo -Parent
                        if ((Test-NomeUtil (Split-Path $pai -Leaf)) -and (Test-Path -LiteralPath $pai) -and -not (Get-ChildItem -LiteralPath $pai -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $pai -Force -ErrorAction SilentlyContinue }
                    }
                    $msg = 'Enviada para a Lixeira.'
                }
                'registro' {
                    if (-not (Test-Path $pastaBkp)) { New-Item -ItemType Directory -Path $pastaBkp -Force | Out-Null }
                    $arq = Join-Path $pastaBkp ("chave_$n.reg")
                    $alvoReg = $s.Alvo
                    if ($Script:Otz.SidAlvo -and $alvoReg -like 'HKCU\*') { $alvoReg = "HKU\$($Script:Otz.SidAlvo)\" + $alvoReg.Substring(5) }
                    $saida = & reg.exe export $alvoReg $arq /y 2>&1
                    if ($LASTEXITCODE -ne 0) { throw "backup falhou: $($saida -join ' ')" }
                    $r = Get-RegRaiz $s.Alvo
                    $r.Base.DeleteSubKeyTree($r.Sub, $false)
                    $msg = "Apagada (backup em $arq)."
                }
                'inicio' {
                    $apr, $nome, $cmd = $s.Alvo -split '\|', 3
                    if ($apr -match 'StartupFolder') {
                        if (Test-Path -LiteralPath $cmd) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($cmd, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin) }
                    } else {
                        $run = $apr -replace '\\Explorer\\StartupApproved\\Run32$', '\Run' -replace '\\Explorer\\StartupApproved\\Run$', '\Run'
                        if ($apr -match 'Run32$') { $run = 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' }
                        Remove-RegValor $run $nome
                    }
                    Remove-RegValor $apr $nome
                    $msg = 'Removido da inicialização.'
                }
                'tarefa' {
                    $pasta = $s.Alvo.Substring(0, $s.Alvo.LastIndexOf('\') + 1)
                    $nomeT = $s.Alvo.Substring($s.Alvo.LastIndexOf('\') + 1)
                    Unregister-ScheduledTask -TaskPath $pasta -TaskName $nomeT -Confirm:$false -ErrorAction Stop
                    $msg = 'Tarefa removida.'
                }
                'servico' {
                    $saida = & sc.exe delete $s.Alvo 2>&1
                    if ($LASTEXITCODE -ne 0) { throw ($saida -join ' ') }
                    $msg = 'Serviço removido.'
                }
            }
            Write-Log "Sobra removida ($($s.Tipo)): $($s.Alvo)"
            $res.Add([pscustomobject]@{ Titulo = $s.Texto; Texto = $msg; Nivel = 'ok' })
        } catch {
            $res.Add([pscustomobject]@{ Titulo = $s.Texto; Texto = "Não foi possível: $($_.Exception.Message)"; Nivel = 'erro' })
        }
    }
    return $res.ToArray()
}
