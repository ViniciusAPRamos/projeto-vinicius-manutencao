#Requires -Version 5.1
<#
    Manutenção agendada do Otimizador Vinicius v2.0
    Cria uma tarefa no Agendador de Tarefas do Windows que roda o
    otimizador SEM JANELA (-Manutencao <config.json>) no dia/hora escolhidos.
    Depende do nucleo.ps1 e do diagnostico.ps1.
#>

$Script:NomeTarefaManut = 'Otimizador Vinicius - Manutencao'

# O que cada opção da tela executa (ids do catálogo)
$Script:TarefasManut = [ordered]@{
    temp    = @{ Nome = 'Apagar arquivos temporários'; Id = 'limpeza.temp' }
    dns     = @{ Nome = 'Limpar cache de DNS';         Id = 'limpeza.dns' }
    lixeira = @{ Nome = 'Esvaziar a Lixeira';          Id = 'limpeza.lixeira' }
}

function Get-ArqConfigManut { return (Join-Path $Script:Otz.Dados 'manutencao.json') }

function Get-ConfigManutencao {
    $arq = Get-ArqConfigManut
    $padrao = [pscustomobject]@{ Frequencia = 'semanal'; Dia = 'Sunday'; Hora = '12:00'; Tarefas = @('temp', 'dns'); Verificar = $true }
    if (-not (Test-Path $arq)) { return $padrao }
    try { return ([IO.File]::ReadAllText($arq, [Text.Encoding]::UTF8) | ConvertFrom-Json) } catch { return $padrao }
}

# Conta que vai rodar a tarefa: a do usuário logado (não a do admin, se forem diferentes)
function Get-UsuarioTarefa {
    if ($Script:Otz.SidAlvo) { return (Get-NomeConta $Script:Otz.SidAlvo) }
    return [Security.Principal.WindowsIdentity]::GetCurrent().Name
}

function Save-ConfigManutencao($Config) {
    $arq = Get-ArqConfigManut
    [IO.File]::WriteAllText($arq, (ConvertTo-Json -InputObject $Config -Depth 4), (New-Object Text.UTF8Encoding $false))
    return $arq
}

function Register-Manutencao($Config) {
    $arq = Save-ConfigManutencao $Config
    $gui = Join-Path $Script:Otz.SrcDir 'Otimizador-Vinicius-GUI.ps1'
    $acao = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$gui`" -Manutencao `"$arq`""
    $hora = [datetime]::ParseExact($Config.Hora, 'HH:mm', $null)
    $gatilho = if ($Config.Frequencia -eq 'diaria') { New-ScheduledTaskTrigger -Daily -At $hora }
               else { New-ScheduledTaskTrigger -Weekly -DaysOfWeek $Config.Dia -At $hora }
    $principal = New-ScheduledTaskPrincipal -UserId (Get-UsuarioTarefa) -LogonType Interactive -RunLevel Highest
    # StartWhenAvailable: se o PC estava desligado no horário, roda assim que der
    $ajustes = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    Register-ScheduledTask -TaskName $Script:NomeTarefaManut -TaskPath '\' -Action $acao -Trigger $gatilho -Principal $principal -Settings $ajustes `
        -Description 'Limpeza e verificação automáticas criadas pelo Otimizador Vinicius. Para remover, use o próprio otimizador (Ferramentas > Manutenção automática).' -Force | Out-Null
    Write-Log "Manutenção agendada: $($Config.Frequencia) $($Config.Dia) $($Config.Hora) - tarefas: $(@($Config.Tarefas) -join ', ') - verificar: $($Config.Verificar)"
}

function Unregister-Manutencao {
    Unregister-ScheduledTask -TaskName $Script:NomeTarefaManut -Confirm:$false -ErrorAction Stop
    Write-Log 'Manutenção agendada removida.'
}

function Get-StatusManutencao {
    $t = Get-ScheduledTask -TaskName $Script:NomeTarefaManut -ErrorAction SilentlyContinue
    $ultimo = $null
    $arqUlt = Join-Path $Script:Otz.Dados 'manutencao-ultima.json'
    if (Test-Path $arqUlt) { try { $ultimo = [IO.File]::ReadAllText($arqUlt, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { } }
    if (-not $t) { return [pscustomobject]@{ Ativa = $false; Proxima = $null; Ultima = $null; Resultado = $ultimo } }
    $i = Get-ScheduledTaskInfo -TaskName $Script:NomeTarefaManut -ErrorAction SilentlyContinue
    $prox = $null; if ($i -and $i.NextRunTime) { $prox = $i.NextRunTime }
    return [pscustomobject]@{ Ativa = $true; Proxima = $prox; Ultima = $i.LastRunTime; Resultado = $ultimo }
}

# O que a tarefa executa (sem janela)
function Invoke-ManutencaoAgendada([string]$ArqConfig) {
    $cfg = [IO.File]::ReadAllText($ArqConfig, [Text.Encoding]::UTF8) | ConvertFrom-Json
    Write-Log "===== Manutenção automática iniciada ====="
    $ids = @(@($cfg.Tarefas) | ForEach-Object { $Script:TarefasManut[[string]$_].Id } | Where-Object { $_ })
    $res = @()
    if ($ids.Count) { $res = @(Invoke-Plano -Ids $ids -Modo aplicar -CriarPonto $false) }
    $nota = $null
    if ($cfg.Verificar) {
        $n = Measure-NotaPc
        Save-Verificacao $n.Nota $n.Ajustes $n.Problemas 'automática'
        $nota = $n.Nota
        Write-Log "Manutenção: nota do PC = $($n.Nota)"
    }
    $erros = @($res | Where-Object Status -eq 'erro').Count
    $resumo = [ordered]@{
        Data    = (Get-Date).ToString('s')
        Itens   = @($res | ForEach-Object { [ordered]@{ Nome = $_.Nome; Status = $_.Status; Mensagem = $_.Mensagem } })
        Nota    = $nota
        Erros   = $erros
    }
    [IO.File]::WriteAllText((Join-Path $Script:Otz.Dados 'manutencao-ultima.json'), (ConvertTo-Json -InputObject $resumo -Depth 5), (New-Object Text.UTF8Encoding $false))
    Write-Log "===== Manutenção automática concluída ($erros erro(s)) ====="
    return @{ Erros = $erros; Nota = $nota }
}
