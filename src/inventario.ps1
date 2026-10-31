#Requires -Version 5.1
<#
    Inventário de vários PCs (Otimizador Vinicius v2.0)
    Cada PC grava <NOME-DO-PC>.json numa pasta (de rede, por exemplo) e
    a tela Ferramentas > Vários PCs junta todos numa tabela.
      Sem janela:  Inventario-PC.bat \\servidor\pasta
    Depende do nucleo.ps1, ferramentas.ps1, diagnostico.ps1 e analise.ps1.
#>

$Script:FormatoInventario = 'otimizador-vinicius-inventario'

function Get-InventarioPC {
    $info = Get-InfoPC
    $nota = Measure-NotaPc
    $est = Get-Estabilidade 30
    $r = [ordered]@{}
    $r.Formato = $Script:FormatoInventario
    $r.Versao = 1
    $r.Data = (Get-Date).ToString('s')
    $r.Computador = $env:COMPUTERNAME
    $r.Usuario = $env:USERNAME
    $r.Windows = "$($info.WinNome) $($info.VersaoWin) (build $($info.Build))"
    $r.Cpu = $info.Cpu
    $r.RamGB = $info.RamGB
    $r.Pentes = @($info.Pentes).Count
    $r.GpuNome = $info.GpuNome
    $r.DiscoTipo = $info.DiscoTipo
    $r.DiscoLivreGB = $info.DiscoLivreGB
    $r.DiscoLivrePct = $info.DiscoLivre
    $r.Tier = $info.Tier
    $r.Notebook = $info.Notebook
    $r.PlacaMae = $info.PlacaMae
    $r.Bios = $info.Bios
    $r.Nota = $nota.Nota
    $r.Problemas = $nota.Problemas
    $r.Estabilidade = $est.Indice
    $r.Desligamentos30d = $est.Desligamentos
    $r.TelasAzuis30d = $est.TelasAzuis
    $r.UptimeDias = [math]::Round($info.Uptime.TotalDays, 1)
    $r.Alertas = [string[]]@($info.Alertas | Where-Object { $_.Nivel -ne 'info' } | ForEach-Object Texto)
    return [pscustomobject]$r
}

function Save-InventarioPC([string]$Pasta) {
    if (-not (Test-Path $Pasta)) { New-Item -ItemType Directory -Path $Pasta -Force | Out-Null }
    $inv = Get-InventarioPC
    $arq = Join-Path $Pasta "$($env:COMPUTERNAME).json"
    [IO.File]::WriteAllText($arq, (ConvertTo-Json -InputObject $inv -Depth 4), (New-Object Text.UTF8Encoding $false))
    Write-Log "Inventário salvo em $arq (nota $($inv.Nota))"
    return $arq
}

function Get-InventarioPasta([string]$Pasta) {
    $lista = New-Object System.Collections.Generic.List[object]
    foreach ($f in @(Get-ChildItem $Pasta -Filter *.json -File -ErrorAction SilentlyContinue)) {
        try {
            $o = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($o.Formato -eq $Script:FormatoInventario) { $lista.Add($o) }
        } catch { }
    }
    return @($lista | Sort-Object Nota)
}

# Planilha para o Excel (separador ";" e UTF-8 com BOM, como o Excel em português espera)
function Export-InventarioCsv([string]$Pasta, [string]$Destino) {
    $linhas = foreach ($o in Get-InventarioPasta $Pasta) {
        [pscustomobject][ordered]@{
            PC = $o.Computador; Usuario = $o.Usuario; Atualizado = $o.Data; Windows = $o.Windows; Processador = $o.Cpu; 'RAM (GB)' = $o.RamGB
            Pentes = $o.Pentes; 'Placa de video' = $o.GpuNome; Disco = $o.DiscoTipo; 'Livre (GB)' = $o.DiscoLivreGB; Classe = $o.Tier; Nota = $o.Nota
            Estabilidade = $o.Estabilidade; 'Desligamentos 30d' = $o.Desligamentos30d; 'Telas azuis 30d' = $o.TelasAzuis30d; 'Ligado (dias)' = $o.UptimeDias
            Alertas = (@($o.Alertas) -join ' | ')
        }
    }
    $linhas | Export-Csv -Path $Destino -Delimiter ';' -NoTypeInformation -Encoding UTF8
    return $Destino
}
