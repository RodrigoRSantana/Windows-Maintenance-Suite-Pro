#Requires -Version 5.1

param(
    [switch]$Auto,
    [switch]$Advanced,
    [switch]$ExportReport,
    [switch]$HtmlReport,
    [switch]$InstallTask,
    [switch]$RemoveTask,
    [string]$Routine,
    [switch]$PauseAtEnd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Configurar codificação UTF-8 no console para suporte perfeito a caracteres PT-BR
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# =========================================================
# CONFIGURAÇÃO GLOBAL
# =========================================================

$script:AppName = 'Windows Maintenance Suite Pro'
$script:Version = '3.2'
$script:StartTime = Get-Date

$script:BasePath = Join-Path $env:USERPROFILE 'Documents\MaintenanceSuite'
$script:LogPath = Join-Path $script:BasePath 'Maintenance.log'
$script:ReportPath = Join-Path $script:BasePath 'SystemReport.txt'
$script:HtmlReportPath = Join-Path $script:BasePath 'SystemReport.html'
$script:LastHealthSummary = $null

New-Item -Path $script:BasePath -ItemType Directory -Force | Out-Null

# IDs de eventos conhecidos como cosméticos (não indicam falha real no sistema)
$script:CosmeticEventIds = @(
    10005,  # DistributedCOM — serviço não iniciou a tempo
    10010,  # DistributedCOM — servidor DCOM não registrado
    7043,   # Service Control Manager — serviço demorou no desligamento
    7023    # Service Control Manager — serviço encerrou com erro menor
)

# =========================================================
# LOGGING & RETENÇÃO
# =========================================================

function Rotate-Logs {
    try {
        if (Test-Path $script:LogPath) {
            $sizeMB = [math]::Round((Get-Item $script:LogPath).Length / 1MB, 2)

            if ($sizeMB -ge 10) {
                $archive = Join-Path $script:BasePath (
                    'Maintenance_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log'
                )
                Move-Item $script:LogPath $archive -Force
            }
        }

        # Retenção: manter no máximo os 5 logs arquivados mais recentes
        $archives = Get-ChildItem -Path $script:BasePath -Filter 'Maintenance_*.log' -File -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending

        if ($archives -and $archives.Count -gt 5) {
            $archives | Select-Object -Skip 5 | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Host 'Aviso: falha na rotação do log. Verifique permissões da pasta.' -ForegroundColor Yellow
    }
}

Rotate-Logs

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO','WARNING','ERROR')]
        [string]$Level = 'INFO',

        [switch]$Silent
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp [$Level] $Message"

    try {
        Add-Content -Path $script:LogPath -Value $line -Encoding UTF8
    }
    catch {
        if (-not $Silent) {
            Write-Host 'Aviso: não foi possível gravar no arquivo de log.' -ForegroundColor Yellow
        }
    }

    if ($Silent) { return }

    switch ($Level) {
        'INFO'    { Write-Host $Message -ForegroundColor White }
        'WARNING' { Write-Host "WARNING: $Message" -ForegroundColor Yellow }
        'ERROR'   { Write-Host "ERROR: $Message" -ForegroundColor Red }
    }
}

# =========================================================
# SEGURANÇA & AUTO-ELEVAÇÃO
# =========================================================

function Pause-Console {
    if (-not $Auto) {
        Write-Host ''
        Read-Host 'Pressione ENTER para continuar'
    }
}

function Test-Administrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)

        return $principal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )
    }
    catch {
        return $false
    }
}

if (-not (Test-Administrator)) {
    if ([Environment]::UserInteractive) {
        Write-Host ''
        Write-Host 'Este script requer privilégios de Administrador.' -ForegroundColor Yellow
        Write-Host 'Solicitando elevação via UAC...' -ForegroundColor Cyan

        try {
            $scriptFile = $MyInvocation.MyCommand.Definition
            if (-not $scriptFile) { $scriptFile = $PSCommandPath }

            $extraArgs = @()
            if ($PSBoundParameters.Count -gt 0) {
                foreach ($key in $PSBoundParameters.Keys) {
                    $val = $PSBoundParameters[$key]
                    if ($val -is [switch] -and $val.IsPresent) {
                        $extraArgs += "-$key"
                    } elseif ($val -is [bool] -and $val) {
                        $extraArgs += "-$key"
                    } elseif ($val -is [string] -and $val) {
                        $extraArgs += "-$key"
                        $extraArgs += $val
                    }
                }
            }

            # Use array syntax so PowerShell properly handles paths containing spaces
            $argList = @(
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", $scriptFile
            ) + $extraArgs

            Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs
            exit 0
        }
        catch {
            Write-Host "Falha ao solicitar privilégios de Administrador: $_" -ForegroundColor Red
            Pause-Console
            exit 1
        }
    } else {
        Write-Host ''
        Write-Host 'Execute este script como ADMINISTRADOR.' -ForegroundColor Yellow
        Write-Host ''
        exit 1
    }
}

# =========================================================
# UTILITÁRIOS
# =========================================================

function Format-ByteSize {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) {
        return "$([math]::Round($Bytes / 1GB, 2)) GB"
    } elseif ($Bytes -ge 1MB) {
        return "$([math]::Round($Bytes / 1MB, 2)) MB"
    } elseif ($Bytes -ge 1KB) {
        return "$([math]::Round($Bytes / 1KB, 2)) KB"
    } else {
        return "$Bytes Bytes"
    }
}

function Show-Header {
    Clear-Host

    Write-Host ''
    Write-Host '=============================================================' -ForegroundColor Cyan
    Write-Host '              WINDOWS MAINTENANCE SUITE PRO' -ForegroundColor Cyan
    Write-Host '=============================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "Versão : $($script:Version)" -ForegroundColor White
    Write-Host "Início : $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor DarkGray
    Write-Host "Log    : $($script:LogPath)" -ForegroundColor DarkGray
    Write-Host ''
}

function Show-Line {
    Write-Host '-------------------------------------------------------------' -ForegroundColor DarkGray
}

function Show-SectionTitle {
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [ConsoleColor]$Color = 'Cyan'
    )

    Write-Host ''
    Write-Host $Title -ForegroundColor $Color
    Show-Line
}

function Format-Section {
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [object]$Content
    )

    $text = ($Content | Out-String).TrimEnd()

    @(
        "=== $Title ==="
        $text
        ''
    ) -join "`r`n"
}

# ----------------------------------------------------------
# Read-ProcessOutputFile
# Lê arquivos de saída temporários detectando dinamicamente
# a codificação (UTF-16LE sem BOM do SFC, UTF-8 ou OEM/ANSI do DISM).
# Elimina caracteres corrompidos e linhas com espaços.
# ----------------------------------------------------------
function Read-ProcessOutputFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) { return @() }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($null -eq $bytes -or $bytes.Length -eq 0) { return @() }

        # UTF-16LE com BOM (FF FE) ou sem BOM (comum no sfc.exe com bytes nulos intermediários)
        $isUtf16Le = ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or
                     ($bytes.Length -ge 4 -and $bytes[1] -eq 0x00 -and $bytes[3] -eq 0x00)

        if ($isUtf16Le) {
            return [System.Text.Encoding]::Unicode.GetString($bytes) -split "\r?\n"
        }

        # UTF-8 com BOM (EF BB BF)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3) -split "\r?\n"
        }

        # UTF-8 estrito ou fallback para o OEM da máquina
        try {
            $utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
            return $utf8Strict.GetString($bytes) -split "\r?\n"
        }
        catch {
            $oemCodePage = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
            return [System.Text.Encoding]::GetEncoding($oemCodePage).GetString($bytes) -split "\r?\n"
        }
    }
    catch {
        return @()
    }
}

# ----------------------------------------------------------
# Invoke-SafeCommand
# ----------------------------------------------------------
function Invoke-SafeCommand {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$Arguments = @()
    )

    try {
        $output = & $FilePath @Arguments 2>&1

        foreach ($line in $output) {
            $text = "$line".TrimEnd()
            if ($text -ne '') {
                Write-Log $text
            }
        }

        return $LASTEXITCODE
    }
    catch {
        Write-Log "Falha ao executar $FilePath : $_" 'ERROR'
        return -1
    }
}

# ----------------------------------------------------------
# Invoke-ConsoleCommand
# Uso específico para DISM e SFC com decodificação resiliente.
# ----------------------------------------------------------
function Invoke-ConsoleCommand {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$Arguments = @()
    )

    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()

    try {
        $process = Start-Process `
            -FilePath $FilePath `
            -ArgumentList $Arguments `
            -Wait `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $tmpOut `
            -RedirectStandardError  $tmpErr

        # Exibe e grava no log cada linha do stdout decodificada corretamente
        foreach ($line in (Read-ProcessOutputFile -Path $tmpOut)) {
            $text = $line.TrimEnd()
            if ($text -ne '') {
                Write-Log $text
            }
        }

        # Exibe e grava no log cada linha do stderr como WARNING
        foreach ($line in (Read-ProcessOutputFile -Path $tmpErr)) {
            $text = $line.TrimEnd()
            if ($text -ne '') {
                Write-Log $text 'WARNING'
            }
        }

        return $process.ExitCode
    }
    catch {
        Write-Log "Falha ao executar $FilePath : $_" 'ERROR'
        return -1
    }
    finally {
        Remove-Item $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue
    }
}

# =========================================================
# REINICIALIZAÇÃO PENDENTE
# =========================================================

function Test-PendingReboot {
    $reboot = $false
    $reasons = New-Object System.Collections.Generic.List[string]
    $appPending = New-Object System.Collections.Generic.List[string]

    # Component Based Servicing (Atualização de sistema operacional)
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $reboot = $true
        $reasons.Add('Component Based Servicing (Atualização do Windows)')
    }

    # Windows Update (Requer reinício do SO)
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $reboot = $true
        $reasons.Add('Windows Update (Reinicialização requerida)')
    }

    # Pending File Rename (Verifica se são arquivos do SO ou apenas apps em segundo plano)
    try {
        $rename = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
        if ($null -ne $rename -and $rename.Length -gt 0) {
            if ($reboot) {
                $reasons.Add('Arquivos de sistema aguardando reinicialização para substituição')
            } else {
                $appPending.Add('Arquivos temporários de aplicativos em fila de substituição (OneDrive/Edge)')
            }
        }
    }
    catch {}

    [PSCustomObject]@{
        IsPending        = $reboot
        Reasons          = @($reasons)
        AppPendingRename = @($appPending)
    }
}

# =========================================================
# SAÚDE DA BATERIA (NOTEBOOK)
# =========================================================

function Get-BatteryHealth {
    try {
        $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
        if (-not $battery) { return $null }

        $xmlPath = Join-Path $env:TEMP ("battery_diag_" + [System.Guid]::NewGuid().ToString('N') + ".xml")
        
        & powercfg.exe /batteryreport /output "$xmlPath" /xml 2>&1 | Out-Null

        if (Test-Path $xmlPath) {
            [xml]$xml = Get-Content $xmlPath -ErrorAction Stop
            Remove-Item $xmlPath -Force -ErrorAction SilentlyContinue

            $batNode = $xml.BatteryReport.Batteries.Battery
            if ($batNode) {
                $design = [long]$batNode.DesignCapacity
                $full   = [long]$batNode.FullChargeCapacity
                $cycle  = [int]$batNode.CycleCount

                $wear = if ($design -gt 0 -and $full -le $design) {
                    [math]::Round((1 - ($full / $design)) * 100, 1)
                } else { 0 }

                return [PSCustomObject]@{
                    HasBattery             = $true
                    DeviceName             = "$($batNode.Manufacturer)"
                    Chemistry              = "$($batNode.Chemistry)"
                    DesignCapacityMWh      = $design
                    FullChargeCapacityMWh  = $full
                    CycleCount             = $cycle
                    WearPercent            = $wear
                    Status                 = "$($battery.Status)"
                    EstimatedChargePercent = $battery.EstimatedChargeRemaining
                }
            }
        }
    }
    catch {
        Write-Log "Diagnóstico de bateria não disponível: $_" 'INFO' -Silent
    }
    finally {
        if ($xmlPath -and (Test-Path $xmlPath)) {
            Remove-Item $xmlPath -Force -ErrorAction SilentlyContinue
        }
    }

    return $null
}

function Show-BatteryStatus {
    Show-SectionTitle -Title 'SAÚDE DA BATERIA (NOTEBOOK)'

    $bat = Get-BatteryHealth
    if ($bat) {
        Write-Host "Dispositivo        : Notebook com Bateria ($($bat.Chemistry))" -ForegroundColor Green
        Write-Host "Carga Atual        : $($bat.EstimatedChargePercent)%"
        Write-Host "Capacidade Projeto : $($bat.DesignCapacityMWh) mWh"
        Write-Host "Capacidade Atual   : $($bat.FullChargeCapacityMWh) mWh"
        Write-Host "Ciclos de Carga    : $($bat.CycleCount)"
        
        $wearColor = if ($bat.WearPercent -ge 30) { 'Red' } elseif ($bat.WearPercent -ge 15) { 'Yellow' } else { 'DarkGreen' }
        Write-Host "Desgaste da Bateria: $($bat.WearPercent)%" -ForegroundColor $wearColor
    } else {
        Write-Host 'Bateria não detectada no sistema (Dispositivo Desktop ou sem suporte ACPI).' -ForegroundColor DarkGray
    }
}

# =========================================================
# SAÚDE DO SISTEMA
# =========================================================

function Get-FreeSystemDrivePercent {
    try {
        $sysDrive = $env:SystemDrive.TrimEnd(':')
        $volume = Get-Volume -DriveLetter $sysDrive -ErrorAction Stop

        if ($volume.Size -gt 0) {
            return [math]::Round(($volume.SizeRemaining / $volume.Size) * 100, 2)
        }
    }
    catch {}

    return $null
}

function Get-RecentCriticalEventCount {
    param([int]$Hours = 72)

    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            Level     = 1,2
            StartTime = (Get-Date).AddHours(-$Hours)
        } -ErrorAction Stop

        return @($events | Where-Object { $_.Id -notin $script:CosmeticEventIds }).Count
    }
    catch {
        return $null
    }
}

function Get-SystemHealth {
    $os = Get-CimInstance Win32_OperatingSystem
    $uptime = (Get-Date) - $os.LastBootUpTime

    $ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $ramFree  = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $ramUsed  = [math]::Round($ramTotal - $ramFree, 2)
    $ramUsedPct = if ($ramTotal -gt 0) {
        [math]::Round(($ramUsed / $ramTotal) * 100, 2)
    } else { 0 }

    $freeSystemDrivePct = Get-FreeSystemDrivePercent
    $criticalEvents72h  = Get-RecentCriticalEventCount -Hours 72
    $pendingReboot      = Test-PendingReboot

    $score = 100
    $notes = New-Object System.Collections.Generic.List[string]

    if ($ramUsedPct -ge 90) {
        $score -= 30
        $notes.Add('Uso de RAM muito alto.')
    } elseif ($ramUsedPct -ge 80) {
        $score -= 15
        $notes.Add('Uso de RAM elevado.')
    }

    if ($null -ne $freeSystemDrivePct) {
        if ($freeSystemDrivePct -le 10) {
            $score -= 30
            $notes.Add('Pouco espaço livre na unidade do sistema.')
        } elseif ($freeSystemDrivePct -le 20) {
            $score -= 15
            $notes.Add('Espaço livre da unidade do sistema em atenção.')
        }
    }

    # Análise de quedas / desligamentos anormais específicos (Kernel-Power 41 / BSOD 1001)
    $unexpectedShutdowns = 0
    try {
        $unexpectedEvents = Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            Id        = 41, 6008, 1001
            StartTime = (Get-Date).AddHours(-72)
        } -ErrorAction SilentlyContinue
        if ($unexpectedEvents) {
            $unexpectedShutdowns = @($unexpectedEvents).Count
        }
    }
    catch {}

    if ($unexpectedShutdowns -gt 0) {
        $score -= [math]::Min(20, $unexpectedShutdowns * 5)
        $notes.Add("Quedas de energia ou desligamentos anormais detectados recentemente ($unexpectedShutdowns ocorrência(s)).")
    }

    if ($null -ne $criticalEvents72h) {
        if ($criticalEvents72h -ge 15) {
            $score -= 20
            $notes.Add('Múltiplos eventos de erro recentes no log do Windows.')
        } elseif ($criticalEvents72h -ge 5) {
            $score -= 10
            $notes.Add('Há eventos de erro recentes no log do Windows.')
        }
    }

    if ($pendingReboot.IsPending) {
        $score -= 5
        $notes.Add("Reinicialização pendente detectada no Windows ($($pendingReboot.Reasons -join '; ')).")
    }

    if ($uptime.TotalDays -lt 1) {
        $notes.Add('Sistema reiniciado recentemente.')
    }

    if ($score -lt 0) { $score = 0 }

    if ($score -ge 85) {
        $status = 'BOM'
        $color  = 'Green'
    } elseif ($score -ge 65) {
        $status = 'ATENÇÃO'
        $color  = 'Yellow'
    } else {
        $status = 'CRÍTICO'
        $color  = 'Red'
    }

    [PSCustomObject]@{
        Score                  = $score
        Status                 = $status
        Color                  = $color
        UptimeDays             = $uptime.Days
        UptimeHours            = $uptime.Hours
        RamTotalGB             = $ramTotal
        RamUsedGB              = $ramUsed
        RamFreeGB              = $ramFree
        RamUsedPercent         = $ramUsedPct
        FreeSystemDrivePercent = $freeSystemDrivePct
        CriticalEvents72h      = $criticalEvents72h
        UnexpectedShutdowns    = $unexpectedShutdowns
        PendingReboot          = $pendingReboot
        Notes                  = @($notes)
    }
}

function Show-HealthSummary {
    param(
        [Parameter(Mandatory)]
        [object]$Health
    )

    Write-Host ''
    Write-Host 'RESUMO FINAL DE SAÚDE DO SISTEMA' -ForegroundColor Magenta
    Show-Line
    Write-Host "Classificação : $($Health.Status)" -ForegroundColor $Health.Color
    Write-Host "Pontuação     : $($Health.Score)/100"
    Write-Host "RAM em uso    : $($Health.RamUsedGB) GB de $($Health.RamTotalGB) GB ($($Health.RamUsedPercent)%)"

    if ($null -ne $Health.FreeSystemDrivePercent) {
        Write-Host "Disco do sistema livre : $($Health.FreeSystemDrivePercent)%"
    } else {
        Write-Host 'Disco do sistema livre : não disponível'
    }

    if ($null -ne $Health.CriticalEvents72h) {
        Write-Host "Eventos críticos 72h   : $($Health.CriticalEvents72h)"
    } else {
        Write-Host 'Eventos críticos 72h   : não disponível'
    }

    if ($Health.PendingReboot.IsPending) {
        Write-Host 'Reinicialização pendente : SIM (recomendado reiniciar)' -ForegroundColor Yellow
    }

    if ($Health.Notes.Count -gt 0) {
        Write-Host ''
        Write-Host 'Observações:' -ForegroundColor Cyan
        foreach ($note in $Health.Notes) {
            Write-Host "- $note"
        }
    }
}

# =========================================================
# LIMPEZA SEGURA COM CONTABILIZAÇÃO DE ESPAÇO
# =========================================================

function Remove-OldFiles {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [int]$OlderThanDays = 2
    )

    if (-not (Test-Path $Path)) { return 0 }

    $limit = (Get-Date).AddDays(-$OlderThanDays)
    [long]$freedBytes = 0

    try {
        $items = Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue |
                 Where-Object { $_.LastWriteTime -lt $limit }
    }
    catch {
        Write-Log "Falha ao listar arquivos em $($Path): $_" 'WARNING' -Silent
        return 0
    }

    if ($null -ne $items) {
        foreach ($item in $items) {
            try {
                $itemSize = 0
                if ($item.PSIsContainer) {
                    $subFiles = Get-ChildItem -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                                Where-Object { -not $_.PSIsContainer }
                    if ($subFiles) {
                        $itemSize = ($subFiles | Measure-Object -Property Length -Sum).Sum
                    }
                } else {
                    $itemSize = $item.Length
                }

                Remove-Item $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
                if (-not (Test-Path $item.FullName)) {
                    if ($itemSize -gt 0) { $freedBytes += $itemSize }
                }
            }
            catch {
                Write-Log "Falha ao remover item: $($item.FullName)" 'WARNING' -Silent
            }
        }
    }

    return $freedBytes
}

function Clear-TemporaryFiles {
    Show-SectionTitle -Title 'LIMPEZA SEGURA DE TEMPORÁRIOS E CACHE'

    [long]$totalFreed = 0

    # 1. Temporários do Usuário e Sistema (> 48 horas)
    $tempTargets = @(
        @{ Path = $env:TEMP; Days = 2; Label = 'Temporários do Usuário' },
        @{ Path = "$env:SystemRoot\Temp"; Days = 2; Label = 'Temporários do Sistema (Windows)' }
    )

    foreach ($target in $tempTargets) {
        if (Test-Path $target.Path) {
            Write-Host "Limpando: $($target.Label) ($($target.Path))..." -ForegroundColor Green
            $freed = Remove-OldFiles -Path $target.Path -OlderThanDays $target.Days
            $totalFreed += $freed
            Write-Host "OK ($([math]::Round($freed / 1MB, 2)) MB liberados)" -ForegroundColor DarkGreen
        }
    }

    # 2. Cache de downloads do Windows Update (> 7 dias)
    $wuDownload = "$env:SystemRoot\SoftwareDistribution\Download"
    if (Test-Path $wuDownload) {
        Write-Host "Limpando: Cache de downloads do Windows Update..." -ForegroundColor Green
        $freedWU = Remove-OldFiles -Path $wuDownload -OlderThanDays 7
        $totalFreed += $freedWU
        Write-Host "OK ($([math]::Round($freedWU / 1MB, 2)) MB liberados)" -ForegroundColor DarkGreen
    }

    # 3. Crash Dumps de aplicativos (> 7 dias)
    $crashDumps = "$env:LOCALAPPDATA\CrashDumps"
    if (Test-Path $crashDumps) {
        Write-Host "Limpando: Dumps de travamento de aplicativos..." -ForegroundColor Green
        $freedCrash = Remove-OldFiles -Path $crashDumps -OlderThanDays 7
        $totalFreed += $freedCrash
        Write-Host "OK ($([math]::Round($freedCrash / 1MB, 2)) MB liberados)" -ForegroundColor DarkGreen
    }

    # 4. Relatórios de erro do Windows (WER)
    $werArchive = "$env:ProgramData\Microsoft\Windows\WER\ReportArchive"
    $werQueue   = "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"
    foreach ($wer in @($werArchive, $werQueue)) {
        if (Test-Path $wer) {
            $freedWer = Remove-OldFiles -Path $wer -OlderThanDays 7
            $totalFreed += $freedWer
        }
    }

    # 5. Cache de Otimização de Entrega
    if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
        try {
            Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue | Out-Null
            Write-Host 'Cache de Otimização de Entrega limpo.' -ForegroundColor DarkGreen
        }
        catch {}
    }

    # 6. Lixeira
    try {
        $shell = New-Object -ComObject Shell.Application
        $itemCount = $shell.Namespace(0xa).Items().Count

        if ($itemCount -gt 0) {
            Clear-RecycleBin -Force -ErrorAction Stop
            Write-Host "Lixeira esvaziada ($itemCount item(s) removido(s))." -ForegroundColor DarkGreen
        } else {
            Write-Host 'Lixeira já estava vazia.' -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Log 'Falha ao verificar ou limpar lixeira.' 'WARNING'
    }

    # 7. Verificação de Alerta: Pasta WinSxS\Temp (InFlight / PendingDeletes)
    $winsxsTemp = "$env:SystemRoot\WinSxS\Temp"
    if (Test-Path $winsxsTemp) {
        $wsFiles = Get-ChildItem -Path $winsxsTemp -Recurse -File -Force -ErrorAction SilentlyContinue
        if ($wsFiles) {
            $wsBytes = ($wsFiles | Measure-Object -Property Length -Sum).Sum
            $wsGB = [math]::Round($wsBytes / 1GB, 2)
            if ($wsGB -ge 2.0) {
                Write-Host ''
                Write-Host "AVISO: A pasta WinSxS\Temp está acumulando $wsGB GB!" -ForegroundColor Yellow
                Write-Host 'Recomendação: Execute a opção 19 no menu (Limpeza de Componentes WinSxS).' -ForegroundColor DarkYellow
                Write-Log "Alerta: Pasta WinSxS\Temp está com $wsGB GB." 'WARNING'
            }
        }
    }

    Write-Host ''
    Write-Host "Limpeza concluída! Espaço total liberado: $(Format-ByteSize $totalFreed)" -ForegroundColor Cyan
    Write-Log "Limpeza segura concluída. Espaço liberado: $(Format-ByteSize $totalFreed)" 'INFO'
}

# =========================================================
# OTIMIZAÇÃO SSD (TRIM) / HDD
# =========================================================

function Optimize-Drives {
    Show-SectionTitle -Title 'OTIMIZAÇÃO INTELIGENTE DE UNIDADES'

    try {
        $trimStatus = fsutil behavior query DisableDeleteNotify
        Write-Host ''
        Write-Host 'Status do TRIM:' -ForegroundColor Green
        Write-Host $trimStatus
    }
    catch {
        Write-Log 'Falha ao consultar status do TRIM.' 'WARNING'
    }

    try {
        $volumes = Get-Volume | Where-Object {
            $_.DriveLetter -and $_.DriveType -eq 'Fixed'
        }
    }
    catch {
        Write-Log 'Falha ao enumerar volumes locais.' 'ERROR'
        return
    }

    # Pré-carregar discos físicos para consulta resiliente
    $physDisks = @()
    try {
        $physDisks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
    } catch {}

    foreach ($volume in $volumes) {
        Write-Host ''
        Write-Host "Unidade: $($volume.DriveLetter):" -ForegroundColor Green

        $mediaType = 'Desconhecido'
        $busType   = 'Desconhecido'
        $isSsd     = $false
        $diskNum   = $null

        try {
            $partition = Get-Partition -DriveLetter $volume.DriveLetter -ErrorAction Stop
            $diskNum   = $partition.DiskNumber
            $disk      = Get-Disk -Number $diskNum -ErrorAction Stop

            if ($disk.MediaType) { $mediaType = "$($disk.MediaType)" }
            if ($disk.BusType)   { $busType   = "$($disk.BusType)" }

            # Qualquer unidade com barramento NVMe é garantidamente SSD
            if ($busType -eq 'NVMe' -or $mediaType -eq 'SSD') {
                $isSsd = $true
                if ($mediaType -eq 'Desconhecido' -or [string]::IsNullOrWhiteSpace($mediaType)) {
                    $mediaType = if ($busType -eq 'NVMe') { 'SSD (NVMe)' } else { 'SSD' }
                }
            }
        }
        catch {
            Write-Log "Aviso ao consultar partição/disco $($volume.DriveLetter): $_" 'WARNING' -Silent
        }

        # Fallback para Get-PhysicalDisk se ainda não confirmado
        if (-not $isSsd -and $null -ne $diskNum) {
            $phys = $physDisks | Where-Object { $_.DeviceId -eq $diskNum } | Select-Object -First 1
            if ($phys) {
                if ($phys.MediaType -eq 'SSD' -or $phys.BusType -eq 'NVMe') {
                    $isSsd = $true
                    $mediaType = if ($phys.BusType -eq 'NVMe') { 'SSD (NVMe)' } else { 'SSD' }
                }
                if ($busType -eq 'Desconhecido' -and $phys.BusType) {
                    $busType = "$($phys.BusType)"
                }
            }
        }

        Write-Host "Mídia  : $mediaType"
        Write-Host "Bus    : $busType"

        try {
            if ($isSsd) {
                Write-Host 'Enviando comando TRIM (ReTrim)...' -ForegroundColor DarkGray
                Optimize-Volume -DriveLetter $volume.DriveLetter -ReTrim -ErrorAction Stop | Out-Null
                Write-Host 'TRIM executado com sucesso.' -ForegroundColor DarkGreen
                Write-Log "TRIM executado com sucesso no disco $($volume.DriveLetter):" 'INFO'
            } else {
                Write-Host 'Executando desfragmentação/otimização padrão...' -ForegroundColor DarkGray
                Optimize-Volume -DriveLetter $volume.DriveLetter -ErrorAction Stop | Out-Null
                Write-Host 'Otimização padrão executada com sucesso.' -ForegroundColor DarkGreen
                Write-Log "Otimização padrão executada no disco $($volume.DriveLetter):" 'INFO'
            }
        }
        catch {
            Write-Log "Falha ao otimizar unidade $($volume.DriveLetter): $_" 'ERROR'
        }
    }
}

# =========================================================
# SMART / SSD HEALTH
# =========================================================

function Show-StorageHealth {
    Show-SectionTitle -Title 'SMART / STORAGE HEALTH'

    try {
        Write-Host 'Discos físicos:' -ForegroundColor Green
        Get-PhysicalDisk |
        Select-Object FriendlyName, MediaType, BusType, HealthStatus,
            @{Name='SizeGB';Expression={[math]::Round($_.Size / 1GB, 2)}} |
        Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host $_.TrimEnd() }

        Write-Host ''
        Write-Host 'Contadores de confiabilidade (SMART):' -ForegroundColor Green
        
        $counters = Get-PhysicalDisk | ForEach-Object {
            $disk = $_
            $rc = $disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
            if ($rc) {
                [PSCustomObject]@{
                    Disco            = $disk.FriendlyName
                    Temperatura_C    = if ($null -ne $rc.Temperature) { $rc.Temperature } else { 'N/A' }
                    Desgaste_Wear    = if ($null -ne $rc.Wear) { "$($rc.Wear)%" } else { '0%' }
                    Horas_Ligado     = if ($null -ne $rc.PowerOnHours) { $rc.PowerOnHours } else { 'N/A' }
                    Erros_Leitura    = if ($null -ne $rc.ReadErrorsTotal) { $rc.ReadErrorsTotal } else { 0 }
                    Erros_Gravacao   = if ($null -ne $rc.WriteErrorsTotal) { $rc.WriteErrorsTotal } else { 0 }
                }
            }
        }

        if ($counters) {
            $counters | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host $_.TrimEnd() }
        } else {
            Write-Host 'Métricas de confiabilidade SMART não fornecidas pela controladora.' -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host 'SMART não disponível neste sistema.' -ForegroundColor Yellow
    }
}

# =========================================================
# RELATÓRIO SISTEMA
# =========================================================

function Get-SystemSummary {
    Show-SectionTitle -Title 'RELATÓRIO DO SISTEMA'

    $health = Get-SystemHealth
    $script:LastHealthSummary = $health

    Write-Host ''
    Write-Host 'STATUS GERAL:' -ForegroundColor Green
    Write-Host "$($health.Status) ($($health.Score)/100)" -ForegroundColor $health.Color

    Write-Host ''
    Write-Host 'UPTIME:' -ForegroundColor Green
    Write-Host "$($health.UptimeDays) dias, $($health.UptimeHours) horas"

    Write-Host ''
    Write-Host 'MEMÓRIA:' -ForegroundColor Green
    Write-Host "RAM Total : $($health.RamTotalGB) GB"
    Write-Host "RAM Usada : $($health.RamUsedGB) GB"
    Write-Host "RAM Livre : $($health.RamFreeGB) GB"
    Write-Host "Uso RAM   : $($health.RamUsedPercent)%"

    Write-Host ''
    Write-Host 'DISCOS:' -ForegroundColor Green
    Get-Volume |
    Where-Object DriveLetter |
    ForEach-Object {
        $free  = [math]::Round($_.SizeRemaining / 1GB, 2)
        $total = [math]::Round($_.Size / 1GB, 2)
        Write-Host "$($_.DriveLetter): $free GB livres de $total GB"
    }

    if ($health.PendingReboot.IsPending) {
        Write-Host ''
        Write-Host 'ATENÇÃO:' -ForegroundColor Yellow
        Write-Host "Reinicialização pendente: $($health.PendingReboot.Reasons -join '; ')" -ForegroundColor Yellow
    }
}

# =========================================================
# PLACAS DE VÍDEO (MULTI-GPU & TEMPERATURA)
# =========================================================

function Show-GpuInformation {
    Show-SectionTitle -Title 'PLACA DE VÍDEO (GPU)'

    try {
        $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
        if ($gpus) {
            foreach ($gpu in $gpus) {
                $ramGB = if ($gpu.AdapterRAM -and $gpu.AdapterRAM -gt 0) {
                    "$([math]::Round($gpu.AdapterRAM / 1GB, 1)) GB"
                } else { "Compartilhada / N/A" }

                Write-Host "GPU     : $($gpu.Name)" -ForegroundColor Green
                Write-Host "Driver  : $($gpu.DriverVersion)"
                Write-Host "VRAM    : $ramGB"
                Write-Host "Status  : $($gpu.Status)"
                Write-Host ''
            }
        }
    }
    catch {
        Write-Log 'Falha ao consultar adaptadores de vídeo.' 'WARNING' -Silent
    }

    # Sensor térmico NVIDIA (se existir)
    $nvidiaSmi = @(
        "$env:SystemRoot\System32\nvidia-smi.exe",
        'C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe'
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($nvidiaSmi) {
        try {
            $temp = & $nvidiaSmi --query-gpu=temperature.gpu --format=csv,noheader
            if ($temp) {
                Write-Host "Temperatura NVIDIA : $($temp.Trim()) °C" -ForegroundColor DarkGreen
            }
        }
        catch {
            Write-Log 'Falha ao consultar GPU NVIDIA.' 'WARNING' -Silent
        }
    }
}

# =========================================================
# PROCESSOS PESADOS
# =========================================================

function Show-HeavyProcesses {
    Show-SectionTitle -Title 'PROCESSOS MAIS PESADOS (TOP 10)'

    Get-Process |
    Sort-Object WorkingSet64 -Descending |
    Select-Object -First 10 -Property Name, Id, CPU,
        @{Name='RAM_MB';Expression={[math]::Round($_.WorkingSet64 / 1MB, 1)}} |
    Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host $_.TrimEnd() }
}

# =========================================================
# STARTUP APPS
# =========================================================

function Show-StartupAnalysis {
    Show-SectionTitle -Title 'APLICATIVOS DE INICIALIZAÇÃO'

    try {
        $startups = Get-CimInstance Win32_StartupCommand -ErrorAction Stop
        if ($startups) {
            $startups |
            Select-Object @{Name='Nome';Expression={$_.Name}},
                          @{Name='Usuario';Expression={$_.User}},
                          @{Name='Local';Expression={
                              if ($_.Location.Length -gt 45) { $_.Location.Substring(0, 42) + '...' } else { $_.Location }
                          }} |
            Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host $_.TrimEnd() }
        } else {
            Write-Host 'Nenhum aplicativo de inicialização registrado.' -ForegroundColor DarkGreen
        }
    }
    catch {
        Write-Log 'Falha ao listar startup apps.' 'WARNING'
    }
}

# =========================================================
# EVENTOS CRÍTICOS (FILTRADOS)
# =========================================================

function Show-CriticalEvents {
    Show-SectionTitle -Title 'EVENTOS CRÍTICOS RECENTES (ÚLTIMAS 72H)'

    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            Level     = 1,2
            StartTime = (Get-Date).AddHours(-72)
        } -MaxEvents 60 -ErrorAction Stop |
        Where-Object { $_.Id -notin $script:CosmeticEventIds } |
        Select-Object -First 15

        if ($events -and @($events).Count -gt 0) {
            $events |
            Select-Object TimeCreated, Id, ProviderName, LevelDisplayName |
            Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host $_.TrimEnd() }
        } else {
            Write-Host 'Nenhum evento crítico relevante encontrado nas últimas 72 horas.' -ForegroundColor DarkGreen
        }
    }
    catch {
        Write-Host 'Nenhum evento crítico recente encontrado nas últimas 72 horas.' -ForegroundColor DarkGreen
    }
}

# =========================================================
# REPARO PROFUNDO & COMPONENT STORE
# =========================================================

function Repair-WindowsImage {
    Show-SectionTitle -Title 'REPARO PROFUNDO WINDOWS (DISM + SFC)' -Color Magenta

    Write-Host '1/2 Executando DISM /RestoreHealth (pode demorar)...' -ForegroundColor Green
    $dismExit = Invoke-ConsoleCommand `
        -FilePath 'DISM.exe' `
        -Arguments @('/Online','/Cleanup-Image','/RestoreHealth')

    Write-Host ''
    Write-Host "DISM ExitCode: $dismExit"

    Write-Host ''
    Write-Host '2/2 Executando SFC /scannow (pode demorar)...' -ForegroundColor Green
    $sfcExit = Invoke-ConsoleCommand `
        -FilePath 'sfc.exe' `
        -Arguments @('/scannow')

    Write-Host ''
    Write-Host "SFC ExitCode: $sfcExit"

    Write-Host ''
    Write-Host 'Reparo concluído.' -ForegroundColor Cyan
}

function Cleanup-ComponentStore {
    Show-SectionTitle -Title 'LIMPEZA DO ARMAZENAMENTO DE COMPONENTES (WINSXS)' -Color Magenta

    Write-Host 'Executando DISM /StartComponentCleanup...' -ForegroundColor Green
    Write-Host 'Isso remove com segurança arquivos substituídos de atualizações antigas.' -ForegroundColor DarkGray

    # Medir tamanho de WinSxS\Temp antes
    $winsxsTemp = "$env:SystemRoot\WinSxS\Temp"
    $sizeBefore = 0
    if (Test-Path $winsxsTemp) {
        $filesBefore = Get-ChildItem -Path $winsxsTemp -Recurse -File -Force -ErrorAction SilentlyContinue
        if ($filesBefore) {
            $sizeBefore = ($filesBefore | Measure-Object -Property Length -Sum).Sum
        }
    }

    $exitCode = Invoke-ConsoleCommand `
        -FilePath 'DISM.exe' `
        -Arguments @('/Online','/Cleanup-Image','/StartComponentCleanup')

    Write-Host ''
    Write-Host "DISM Cleanup ExitCode: $exitCode"

    if (Test-Path $winsxsTemp) {
        $filesAfter = Get-ChildItem -Path $winsxsTemp -Recurse -File -Force -ErrorAction SilentlyContinue
        $sizeAfter = if ($filesAfter) { ($filesAfter | Measure-Object -Property Length -Sum).Sum } else { 0 }
        $freedWinSxS = [math]::Max(0, $sizeBefore - $sizeAfter)
        if ($freedWinSxS -gt 0) {
            Write-Host "Espaço liberado em WinSxS\Temp: $(Format-ByteSize $freedWinSxS)" -ForegroundColor DarkGreen
        }
    }

    if ($exitCode -eq 0) {
        Write-Host 'Limpeza da pasta WinSxS concluída com sucesso.' -ForegroundColor Green
        Write-Log 'Limpeza de componentes WinSxS concluída com sucesso.' 'INFO'
    } elseif ($exitCode -eq 1726) {
        Write-Host 'Aviso: Falha na chamada de procedimento remoto (Erro 1726).' -ForegroundColor Yellow
        Write-Host 'Isso ocorre quando alguma versão antiga registrada no catálogo de atualização está com pasta ausente.' -ForegroundColor Yellow
        Write-Host 'Dica: Execute a opção 18 (DISM RestoreHealth) para sincronizar o catálogo.' -ForegroundColor Cyan
        Write-Log 'DISM StartComponentCleanup falhou com código 1726.' 'WARNING'
    } else {
        Write-Host "Limpeza da pasta WinSxS finalizada com código $exitCode." -ForegroundColor Yellow
        Write-Log "DISM StartComponentCleanup finalizado com código $exitCode." 'WARNING'
    }
}

function Clear-DriverStore {
    Show-SectionTitle -Title 'LIMPEZA DE DRIVERS OBSOLETOS (DRIVERSTORE)' -Color Magenta

    # Verificar se o Driver Store Explorer (RAPR) está disponível
    $rapr = Get-ChildItem -Path "$env:USERPROFILE\Downloads" -Filter "Rapr.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($rapr) {
        Write-Host "Driver Store Explorer (RAPR) detectado em: $($rapr.FullName)" -ForegroundColor Cyan
        $choice = Read-Host "Deseja abrir o Driver Store Explorer com interface gráfica? (S/N) [Padrão: S]"
        if (-not $choice -or $choice -match '^[sS]') {
            Start-Process -FilePath $rapr.FullName -Verb RunAs
            Write-Host "Driver Store Explorer iniciado com sucesso." -ForegroundColor Green
            return
        }
    }

    Write-Host 'Verificando pacotes de drivers obsoletos no repositório...' -ForegroundColor Green
    Write-Host 'Nota: Drivers atualmente em uso por qualquer dispositivo NUNCA são removidos.' -ForegroundColor DarkGray
    Write-Host ''

    $deletedCount = 0
    $failedCount = 0

    try {
        $driverList = Get-WindowsDriver -Online -All -ErrorAction Stop |
                      Where-Object { $_.Driver -match '^oem\d+\.inf$' }

        $grouped = $driverList | Group-Object -Property OriginalFileName, ClassName | Where-Object { $_.Count -gt 1 }

        if (-not $grouped -or $grouped.Count -eq 0) {
            Write-Host 'Nenhum driver duplicado ou obsoleto encontrado no DriverStore.' -ForegroundColor DarkGreen
            Write-Log 'DriverStore verificado: nenhum driver obsoleto encontrado.' 'INFO'
            return
        }

        Write-Host "Encontrados $($grouped.Count) grupos de drivers com versões múltiplas." -ForegroundColor Yellow

        foreach ($group in $grouped) {
            $sorted = $group.Group | Sort-Object {
                if ($_.Date) { [datetime]$_.Date } else { [version]($_.Version -replace '[^\d\.]', '') }
            }

            # Todos menos a versão mais recente
            $oldDrivers = $sorted[0..($sorted.Count - 2)]

            foreach ($old in $oldDrivers) {
                Write-Host "Tentando remover driver obsoleto: $($old.Driver) ($($old.OriginalFileName) v$($old.Version))..." -NoNewline

                $res = pnputil.exe /delete-driver $old.Driver 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host ' [REMOVIDO]' -ForegroundColor Green
                    Write-Log "Driver obsoleto removido: $($old.Driver) ($($old.OriginalFileName))" 'INFO'
                    $deletedCount++
                } else {
                    Write-Host ' [EM USO / MANTIDO]' -ForegroundColor DarkGray
                    $failedCount++
                }
            }
        }

        Write-Host ''
        Write-Host "Concluído: $deletedCount pacote(s) de driver antigo(s) removido(s)." -ForegroundColor Cyan
        Write-Log "Limpeza de DriverStore concluída. Removidos: $deletedCount, Mantidos: $failedCount" 'INFO'
    }
    catch {
        Write-Host "Aviso ao verificar DriverStore: $_" -ForegroundColor Yellow
        Write-Log "Falha ao limpar DriverStore: $_" 'WARNING'
    }
}

function Show-VirtualDisksAndLargeCaches {
    Show-SectionTitle -Title 'VARREDURA DE DISCOS VIRTUAIS E GRANDES CACHES' -Color Cyan

    Write-Host 'Analisando discos virtuais (.vhdx), WSL e caches de desenvolvimento...' -ForegroundColor Green
    Write-Host ''

    $foundLarge = $false

    # 1. Discos VHDX no perfil do usuário (WSL / Hyper-V / Docker)
    $searchPaths = @(
        "$env:LOCALAPPDATA\wsl",
        "$env:LOCALAPPDATA\Packages",
        "$env:USERPROFILE\.docker",
        "$env:ProgramData\Microsoft\Windows\Virtual Hard Disks"
    )

    $vhdxFiles = @()
    foreach ($sp in $searchPaths) {
        if (Test-Path $sp) {
            $found = Get-ChildItem -Path $sp -Filter "*.vhdx" -Recurse -Depth 4 -Force -ErrorAction SilentlyContinue
            if ($found) { $vhdxFiles += $found }
        }
    }

    if ($vhdxFiles -and $vhdxFiles.Count -gt 0) {
        Write-Host 'Discos Virtuais (.vhdx) Detectados:' -ForegroundColor Yellow
        foreach ($vhd in ($vhdxFiles | Sort-Object -Property FullName -Unique)) {
            $sizeGB = [math]::Round($vhd.Length / 1GB, 2)
            if ($sizeGB -ge 1.0) {
                $foundLarge = $true
                Write-Host "  * $($vhd.FullName)" -ForegroundColor White
                Write-Host "    Tamanho: $sizeGB GB | Última modificação: $($vhd.LastWriteTime.ToString('dd/MM/yyyy HH:mm'))" -ForegroundColor DarkYellow
            }
        }
        Write-Host ''
    }

    # 2. Verificar pasta WinSxS\Temp
    $winsxsTemp = "$env:SystemRoot\WinSxS\Temp"
    if (Test-Path $winsxsTemp) {
        $tempFiles = Get-ChildItem -Path $winsxsTemp -Recurse -File -Force -ErrorAction SilentlyContinue
        if ($tempFiles) {
            $tempBytes = ($tempFiles | Measure-Object -Property Length -Sum).Sum
            $tempGB = [math]::Round($tempBytes / 1GB, 2)
            if ($tempGB -ge 2.0) {
                $foundLarge = $true
                Write-Host "Aviso: Pasta WinSxS\Temp está acumulando $tempGB GB!" -ForegroundColor Yellow
                Write-Host "  Caminho: $winsxsTemp" -ForegroundColor White
                Write-Host "  Recomendação: Execute a opção 19 (Limpeza de Componentes WinSxS) para liberar." -ForegroundColor DarkGray
                Write-Host ''
            }
        }
    }

    # 3. Caches de ferramentas de desenvolvimento comuns
    $devCaches = @(
        @{ Label = 'Cache de Usuário (.cache)'; Path = "$env:USERPROFILE\.cache" },
        @{ Label = 'Cache do Gradle (.gradle)'; Path = "$env:USERPROFILE\.gradle\caches" },
        @{ Label = 'Cache do Pip (.pip / pip cache)'; Path = "$env:LOCALAPPDATA\pip\cache" },
        @{ Label = 'Cache do NPM (npm-cache)'; Path = "$env:APPDATA\npm-cache" }
    )

    Write-Host 'Status de Caches de Ferramentas / Desenvolvimento:' -ForegroundColor Green
    foreach ($dc in $devCaches) {
        if (Test-Path $dc.Path) {
            $dcFiles = Get-ChildItem -Path $dc.Path -Recurse -File -Force -ErrorAction SilentlyContinue
            if ($dcFiles) {
                $dcBytes = ($dcFiles | Measure-Object -Property Length -Sum).Sum
                $dcMB = [math]::Round($dcBytes / 1MB, 2)
                if ($dcMB -ge 100) {
                    Write-Host "  * $($dc.Label): $([math]::Round($dcMB / 1024, 2)) GB ($($dc.Path))" -ForegroundColor White
                }
            }
        }
    }

    if (-not $foundLarge) {
        Write-Host 'Nenhum disco virtual ou cache anormalmente grande detectado.' -ForegroundColor DarkGreen
    }
    Write-Host ''
}

# =========================================================
# PONTO DE RESTAURAÇÃO & REDE
# =========================================================

function New-MaintenanceRestorePoint {
    Show-SectionTitle -Title 'CRIAR PONTO DE RESTAURAÇÃO'

    try {
        Write-Host 'Criando ponto de restauração do sistema...' -ForegroundColor Green
        Checkpoint-Computer -Description "Windows Maintenance Suite Pro Backup" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Host 'Ponto de restauração criado com sucesso.' -ForegroundColor DarkGreen
        Write-Log 'Ponto de restauração criado com sucesso.' 'INFO'
    }
    catch {
        Write-Host "Aviso: Não foi possível criar ponto de restauração ($($_))." -ForegroundColor Yellow
        Write-Host 'Verifique se a Proteção do Sistema está ativada na unidade C:.' -ForegroundColor DarkGray
        Write-Log "Aviso ao criar ponto de restauração: $_" 'WARNING'
    }
}

function Clear-NetworkCache {
    Show-SectionTitle -Title 'LIMPEZA DE CACHE DNS E REDE'

    try {
        Clear-DnsClientCache -ErrorAction Stop
        Write-Host 'Cache de resolução DNS limpo com sucesso.' -ForegroundColor DarkGreen
        Write-Log 'Cache DNS limpo com sucesso.' 'INFO'
    }
    catch {
        Write-Log "Falha ao limpar cache DNS: $_" 'WARNING'
    }
}

# =========================================================
# GERENCIAMENTO DE TAREFAS AGENDADAS
# =========================================================

function Install-MaintenanceTask {
    Show-SectionTitle -Title 'CONFIGURAR AGENDAMENTO AUTOMÁTICO'

    $taskName = 'WindowsMaintenanceSuite'
    $scriptFile = $PSCommandPath
    if (-not $scriptFile -and $PSScriptRoot) { $scriptFile = Join-Path $PSScriptRoot 'Manutencao.ps1' }
    if (-not $scriptFile) { $scriptFile = 'C:\Scripts Manutenção\Manutencao.ps1' }

    try {
        $action = New-ScheduledTaskAction `
            -Execute 'powershell.exe' `
            -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptFile`" -Auto -ExportReport -HtmlReport"

        # Execução semanal aos Domingos às 03:00 da manhã
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am

        $principal = New-ScheduledTaskPrincipal `
            -UserId $env:USERNAME `
            -LogonType Interactive `
            -RunLevel Highest

        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries:$false `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -WakeToRun:$false

        Register-ScheduledTask `
            -TaskName $taskName `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Settings $settings `
            -Description 'Rotina semanal automática do Windows Maintenance Suite Pro.' `
            -Force | Out-Null

        Write-Host "Tarefa '$taskName' agendada com sucesso!" -ForegroundColor DarkGreen
        Write-Host 'Frequência: Semanalmente aos Domingos às 03:00 (execução invisível).' -ForegroundColor White
        Write-Log "Tarefa agendada '$taskName' registrada com sucesso." 'INFO'
    }
    catch {
        Write-Host "Falha ao agendar tarefa: $_" -ForegroundColor Red
        Write-Log "Falha ao registrar tarefa agendada: $_" 'ERROR'
    }
}

function Uninstall-MaintenanceTask {
    Show-SectionTitle -Title 'REMOVER TAREFA AGENDADA'

    $taskName = 'WindowsMaintenanceSuite'
    try {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false | Out-Null
            Write-Host "Tarefa '$taskName' desinstalada com sucesso." -ForegroundColor DarkGreen
            Write-Log "Tarefa agendada '$taskName' desinstalada." 'INFO'
        } else {
            Write-Host "A tarefa '$taskName' não está registrada no sistema." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Falha ao remover tarefa agendada: $_" -ForegroundColor Red
        Write-Log "Falha ao desinstalar tarefa agendada: $_" 'ERROR'
    }
}

# =========================================================
# EXPORTAÇÃO DE RELATÓRIOS (TXT & HTML MODERNO)
# =========================================================

function Export-SystemReport {
    try {
        $health = Get-SystemHealth
        $os = Get-CimInstance Win32_OperatingSystem
        $bat = Get-BatteryHealth
        $dateStr = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

        # ---------------- TXT REPORT ----------------
        $content = @()
        $content += '================================================='
        $content += 'WINDOWS MAINTENANCE SUITE PRO'
        $content += "Versão        : $($script:Version)"
        $content += "Gerado em     : $dateStr"
        $content += "Classificação : $($health.Status)"
        $content += "Pontuação     : $($health.Score)/100"
        $content += '================================================='
        $content += ''

        $content += Format-Section -Title 'SISTEMA' -Content @(
            "Computador : $env:COMPUTERNAME"
            "Windows    : $($os.Caption)"
            "Build      : $($os.BuildNumber)"
            "Uptime     : $($health.UptimeDays) dias, $($health.UptimeHours) horas"
            $(if ($health.PendingReboot.IsPending) { "Reboot Pendente: SIM ($($health.PendingReboot.Reasons -join '; '))" } else { "Reboot Pendente: Não" })
        )

        $content += Format-Section -Title 'SAÚDE DO SISTEMA' -Content @(
            "Status                  : $($health.Status)"
            "Pontuação               : $($health.Score)/100"
            "Uso de RAM              : $($health.RamUsedPercent)%"
            "Espaço livre disco sist.: $($health.FreeSystemDrivePercent)%"
            "Eventos críticos (72h)  : $($health.CriticalEvents72h)"
            'Observações:'
            $(if ($health.Notes.Count -gt 0) {
                $health.Notes | ForEach-Object { "- $_" }
            } else {
                '- Nenhuma observação crítica.'
            })
        )

        if ($bat) {
            $content += Format-Section -Title 'SAÚDE DA BATERIA' -Content @(
                "Química da Bateria     : $($bat.Chemistry)"
                "Carga Atual            : $($bat.EstimatedChargePercent)%"
                "Capacidade de Projeto  : $($bat.DesignCapacityMWh) mWh"
                "Capacidade Carga Máx.  : $($bat.FullChargeCapacityMWh) mWh"
                "Ciclos de Carga        : $($bat.CycleCount)"
                "Desgaste (Wear Level)  : $($bat.WearPercent)%"
            )
        }

        $diskContent = Get-Volume |
            Where-Object DriveLetter |
            ForEach-Object {
                $free  = [math]::Round($_.SizeRemaining / 1GB, 2)
                $total = [math]::Round($_.Size / 1GB, 2)
                "$($_.DriveLetter): $free GB livres de $total GB"
            }
        $content += Format-Section -Title 'DISCOS' -Content $diskContent

        $physicalDisks = @()
        try {
            $physicalDisks = @(Get-PhysicalDisk |
                Select-Object FriendlyName, MediaType, BusType, HealthStatus,
                    @{Name='SizeGB';Expression={[math]::Round($_.Size / 1GB, 2)}})
            $content += Format-Section -Title 'DISCOS FÍSICOS' -Content $physicalDisks
        }
        catch {
            $content += Format-Section -Title 'DISCOS FÍSICOS' -Content 'Informações físicas não disponíveis.'
        }

        $counters = @()
        try {
            $counters = @(Get-PhysicalDisk | ForEach-Object {
                $d = $_
                $rc = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
                if ($rc) {
                    [PSCustomObject]@{
                        Disco       = $d.FriendlyName
                        Temp_C      = if ($null -ne $rc.Temperature) { $rc.Temperature } else { 'N/A' }
                        Desgaste    = if ($null -ne $rc.Wear) { "$($rc.Wear)%" } else { '0%' }
                        Erros_Total = ($rc.ReadErrorsTotal + $rc.WriteErrorsTotal)
                    }
                }
            })
            $content += Format-Section -Title 'SMART / STORAGE HEALTH' -Content $counters
        }
        catch {
            $content += Format-Section -Title 'SMART / STORAGE HEALTH' -Content 'SMART não disponível.'
        }

        $gpus = @()
        try {
            $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
                    Select-Object Name, DriverVersion, Status)
            $content += Format-Section -Title 'ADAPTADORES DE VÍDEO (GPU)' -Content $gpus
        }
        catch {}

        $heavyProcesses = @()
        try {
            $heavyProcesses = @(Get-Process |
                Sort-Object WorkingSet64 -Descending |
                Select-Object -First 10 -Property Name, Id, CPU,
                    @{Name='RAM_MB';Expression={[math]::Round($_.WorkingSet64 / 1MB, 1)}})
            $content += Format-Section -Title 'PROCESSOS MAIS PESADOS' -Content $heavyProcesses
        }
        catch {}

        try {
            $startup = Get-CimInstance Win32_StartupCommand |
                Select-Object Name, User, Location
            $content += Format-Section -Title 'STARTUP APPS' -Content $startup
        }
        catch {
            $content += Format-Section -Title 'STARTUP APPS' -Content 'Falha ao listar startup apps.'
        }

        $criticalEvents = @()
        try {
            $criticalEvents = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1,2; StartTime = (Get-Date).AddHours(-72) } -MaxEvents 60 |
                Where-Object { $_.Id -notin $script:CosmeticEventIds } |
                Select-Object -First 15 |
                Select-Object TimeCreated, Id, ProviderName, LevelDisplayName)
            $content += Format-Section -Title 'EVENTOS CRÍTICOS RECENTES' -Content $criticalEvents
        }
        catch {
            $content += Format-Section -Title 'EVENTOS CRÍTICOS RECENTES' -Content 'Nenhum evento relevante recente.'
        }

        $content -join "`r`n" | Out-File $script:ReportPath -Encoding UTF8

        # ---------------- HTML REPORT ----------------
        $badgeClass = switch ($health.Status) {
            'BOM'     { 'status-good' }
            'ATENÇÃO' { 'status-warning' }
            default   { 'status-critical' }
        }

        $notesHtml = ''
        if ($health.Notes.Count -gt 0) {
            $notesHtml = "<ul>" + (($health.Notes | ForEach-Object { "<li>$_</li>" }) -join '') + "</ul>"
        } else {
            $notesHtml = "<p style='color: var(--text-muted);'>Nenhuma anomalia crítica observada no sistema.</p>"
        }

        $batteryCard = ''
        if ($bat) {
            $batteryCard = @"
            <div class="card">
                <div class="card-title">BATERIA (NOTEBOOK)</div>
                <div class="stat-row"><span>Carga Atual:</span><strong>$($bat.EstimatedChargePercent)%</strong></div>
                <div class="stat-row"><span>Capacidade Carga:</span><strong>$($bat.FullChargeCapacityMWh) / $($bat.DesignCapacityMWh) mWh</strong></div>
                <div class="stat-row"><span>Ciclos de Carga:</span><strong>$($bat.CycleCount)</strong></div>
                <div class="stat-row"><span>Desgaste (Wear):</span><strong style="color: $(if($bat.WearPercent -ge 20){'#ef4444'}else{'#10b981'});">$($bat.WearPercent)%</strong></div>
            </div>
"@
        }

        $rebootAlert = ''
        if ($health.PendingReboot.IsPending) {
            $rebootAlert = "<div class='alert-banner'>⚠️ Reinicialização Pendente: $($health.PendingReboot.Reasons -join '; ')</div>"
        }

        # HTML Tabelas
        $gpuRows = ($gpus | ForEach-Object { "<tr><td><strong>$($_.Name)</strong></td><td>$($_.DriverVersion)</td><td>$($_.Status)</td></tr>" }) -join ''
        $diskRows = ($physicalDisks | ForEach-Object { "<tr><td><strong>$($_.FriendlyName)</strong></td><td>$($_.MediaType)</td><td>$($_.BusType)</td><td>$($_.SizeGB) GB</td><td>$($_.HealthStatus)</td></tr>" }) -join ''
        $processRows = ($heavyProcesses | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.Id)</td><td><strong>$($_.RAM_MB) MB</strong></td><td>$($_.CPU)</td></tr>" }) -join ''
        
        $eventRows = ''
        if ($criticalEvents -and $criticalEvents.Count -gt 0) {
            $eventRows = ($criticalEvents | ForEach-Object {
                $levelClass = if ($_.LevelDisplayName -eq 'Crítico' -or $_.Id -eq 41) { 'style="color: var(--red); font-weight: bold;"' } else { 'style="color: var(--yellow);"' }
                "<tr><td>$($_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))</td><td>$($_.Id)</td><td>$($_.ProviderName)</td><td $levelClass>$($_.LevelDisplayName)</td></tr>"
            }) -join ''
        } else {
            $eventRows = "<tr><td colspan='4' style='text-align:center; color: var(--green);'>Nenhum evento de erro relevante nas últimas 72 horas.</td></tr>"
        }

        $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Windows Maintenance Suite Pro - Relatório</title>
    <style>
        :root {
            --bg: #0b0f19;
            --card-bg: #111827;
            --border: #1f2937;
            --text-main: #f3f4f6;
            --text-muted: #9ca3af;
            --accent-cyan: #06b6d4;
            --green: #10b981;
            --yellow: #f59e0b;
            --red: #ef4444;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; }
        body { background: var(--bg); color: var(--text-main); padding: 32px 16px; display: flex; justify-content: center; }
        .container { max-width: 1050px; width: 100%; }
        header { border-bottom: 1px solid var(--border); padding-bottom: 20px; margin-bottom: 28px; display: flex; justify-content: space-between; align-items: flex-end; flex-wrap: wrap; gap: 16px; }
        h1 { font-size: 24px; color: #fff; font-weight: 700; letter-spacing: -0.5px; }
        .meta { font-size: 13px; color: var(--text-muted); margin-top: 4px; }
        .alert-banner { background: rgba(245, 158, 11, 0.15); border: 1px solid var(--yellow); color: var(--yellow); padding: 12px 16px; border-radius: 8px; margin-bottom: 24px; font-weight: 500; font-size: 14px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 16px; margin-bottom: 28px; }
        .card { background: var(--card-bg); border: 1px solid var(--border); border-radius: 12px; padding: 20px; }
        .card-title { font-size: 12px; font-weight: 600; color: var(--text-muted); letter-spacing: 0.08em; text-transform: uppercase; margin-bottom: 12px; }
        .score-box { display: flex; align-items: center; justify-content: space-between; }
        .score-val { font-size: 38px; font-weight: 800; color: #fff; }
        .status-badge { padding: 4px 12px; border-radius: 9999px; font-size: 12px; font-weight: 700; text-transform: uppercase; }
        .status-good { background: rgba(16, 185, 129, 0.2); color: var(--green); border: 1px solid var(--green); }
        .status-warning { background: rgba(245, 158, 11, 0.2); color: var(--yellow); border: 1px solid var(--yellow); }
        .status-critical { background: rgba(239, 68, 68, 0.2); color: var(--red); border: 1px solid var(--red); }
        .stat-row { display: flex; justify-content: space-between; font-size: 14px; margin-bottom: 8px; }
        .stat-row span { color: var(--text-muted); }
        .progress-bar { width: 100%; height: 8px; background: #1f2937; border-radius: 4px; overflow: hidden; margin-top: 8px; }
        .progress-fill { height: 100%; background: var(--accent-cyan); border-radius: 4px; }
        .section-box { background: var(--card-bg); border: 1px solid var(--border); border-radius: 12px; padding: 24px; margin-bottom: 24px; }
        .section-box h2 { font-size: 16px; margin-bottom: 16px; color: var(--accent-cyan); font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; }
        ul { padding-left: 20px; font-size: 14px; line-height: 1.6; color: #e5e7eb; }
        table { width: 100%; border-collapse: collapse; font-size: 13px; text-align: left; }
        th { background: #1f2937; color: var(--text-muted); padding: 10px 12px; font-weight: 600; border-bottom: 1px solid var(--border); }
        td { padding: 10px 12px; border-bottom: 1px solid rgba(255,255,255,0.05); color: #d1d5db; }
        tr:last-child td { border-bottom: none; }
        footer { text-align: center; font-size: 12px; color: var(--text-muted); margin-top: 36px; border-top: 1px solid var(--border); padding-top: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <div>
                <h1>🛠️ Windows Maintenance Suite Pro</h1>
                <div class="meta">Relatório de Diagnóstico e Saúde do Sistema | Versão $($script:Version)</div>
            </div>
            <div class="meta" style="text-align: right;">
                Computador: <strong>$env:COMPUTERNAME</strong><br>
                Gerado em: $dateStr
            </div>
        </header>

        $rebootAlert

        <div class="grid">
            <div class="card">
                <div class="card-title">PONTUAÇÃO DE SAÚDE</div>
                <div class="score-box">
                    <div class="score-val">$($health.Score)<span style="font-size: 18px; color: var(--text-muted);">/100</span></div>
                    <div class="status-badge $badgeClass">$($health.Status)</div>
                </div>
                <div class="progress-bar" style="margin-top: 14px;">
                    <div class="progress-fill" style="width: $($health.Score)%; background: $(if($health.Score -ge 85){'#10b981'}elseif($health.Score -ge 65){'#f59e0b'}else{'#ef4444'});"></div>
                </div>
            </div>

            <div class="card">
                <div class="card-title">MEMÓRIA RAM</div>
                <div class="stat-row"><span>Uso Total:</span><strong>$($health.RamUsedPercent)%</strong></div>
                <div class="stat-row"><span>Em Uso:</span><strong>$($health.RamUsedGB) GB</strong></div>
                <div class="stat-row"><span>Livre:</span><strong>$($health.RamFreeGB) GB de $($health.RamTotalGB) GB</strong></div>
                <div class="progress-bar">
                    <div class="progress-fill" style="width: $($health.RamUsedPercent)%;"></div>
                </div>
            </div>

            <div class="card">
                <div class="card-title">DISCO DO SISTEMA (C:)</div>
                <div class="stat-row"><span>Espaço Livre:</span><strong>$($health.FreeSystemDrivePercent)%</strong></div>
                <div class="stat-row"><span>Uptime:</span><strong>$($health.UptimeDays)d $($health.UptimeHours)h</strong></div>
                <div class="stat-row"><span>Erros Críticos (72h):</span><strong>$($health.CriticalEvents72h)</strong></div>
                <div class="progress-bar">
                    <div class="progress-fill" style="width: $(100 - $health.FreeSystemDrivePercent)%; background: #06b6d4;"></div>
                </div>
            </div>

            $batteryCard
        </div>

        <div class="section-box">
            <h2>OBSERVAÇÕES E ALERTAS TÉCNICOS</h2>
            $notesHtml
        </div>

        <div class="section-box">
            <h2>ADAPTADORES DE VÍDEO (GPU)</h2>
            <table>
                <thead>
                    <tr><th>Placa de Vídeo</th><th>Versão do Driver</th><th>Status</th></tr>
                </thead>
                <tbody>
                    $gpuRows
                </tbody>
            </table>
        </div>

        <div class="section-box">
            <h2>DISCOS FÍSICOS & ARMAZENAMENTO</h2>
            <table>
                <thead>
                    <tr><th>Dispositivo</th><th>Tipo de Mídia</th><th>Barramento</th><th>Capacidade</th><th>Status</th></tr>
                </thead>
                <tbody>
                    $diskRows
                </tbody>
            </table>
        </div>

        <div class="section-box">
            <h2>PROCESSOS MAIS PESADOS (TOP 10)</h2>
            <table>
                <thead>
                    <tr><th>Nome</th><th>PID</th><th>Memória RAM</th><th>Tempo CPU</th></tr>
                </thead>
                <tbody>
                    $processRows
                </tbody>
            </table>
        </div>

        <div class="section-box">
            <h2>EVENTOS CRÍTICOS & ERROS RECENTES (ÚLTIMAS 72H)</h2>
            <table>
                <thead>
                    <tr><th>Data / Hora</th><th>Event ID</th><th>Origem / Provedor</th><th>Nível</th></tr>
                </thead>
                <tbody>
                    $eventRows
                </tbody>
            </table>
        </div>

        <footer>
            Windows Maintenance Suite Pro v$($script:Version) • Relatório gerado automaticamente em $dateStr
        </footer>
    </div>
</body>
</html>
"@

        $html | Out-File $script:HtmlReportPath -Encoding UTF8

        Write-Host ''
        Write-Host 'Relatórios exportados com sucesso:' -ForegroundColor Green
        Write-Host "Texto : $script:ReportPath" -ForegroundColor Cyan
        Write-Host "HTML  : $script:HtmlReportPath" -ForegroundColor Cyan
    }
    catch {
        Write-Log "Falha ao exportar relatório: $_" 'ERROR'
    }
}

# =========================================================
# FERRAMENTAS WINDOWS
# =========================================================

function Open-WindowsTools {
    Show-SectionTitle -Title 'ABRINDO FERRAMENTAS WINDOWS'

    $tools = @(
        'ms-settings:storage',
        'ms-settings:startupapps',
        'ms-settings:powersleep'
    )

    foreach ($tool in $tools) {
        try { Start-Process $tool }
        catch { Write-Log "Falha ao abrir ferramenta: $tool" 'WARNING' -Silent }
    }

    try { Start-Process 'perfmon' -ArgumentList '/rel' }
    catch { Write-Log 'Falha ao abrir Monitor de Confiabilidade.' 'WARNING' -Silent }

    try { Start-Process 'cleanmgr.exe' }
    catch { Write-Log 'Falha ao abrir cleanmgr.exe.' 'WARNING' -Silent }
}

# =========================================================
# ROTINAS DE AUTOMAÇÃO
# =========================================================

function Invoke-LightMaintenance {
    Show-Header

    Write-Host 'ROTINA LEVE DE MANUTENÇÃO' -ForegroundColor Magenta

    Clear-TemporaryFiles
    Optimize-Drives
    Get-SystemSummary

    if ($script:LastHealthSummary) {
        Show-HealthSummary -Health $script:LastHealthSummary
    }

    Write-Host ''
    Write-Host 'Rotina concluída.' -ForegroundColor Cyan
}

function Invoke-AdvancedDiagnostics {
    Show-Header

    Write-Host 'DIAGNÓSTICO AVANÇADO COMPLETO' -ForegroundColor Magenta

    Get-SystemSummary
    Show-StorageHealth
    Show-GpuInformation
    Show-BatteryStatus
    Show-HeavyProcesses
    Show-StartupAnalysis
    Show-CriticalEvents
    Show-VirtualDisksAndLargeCaches

    if ($script:LastHealthSummary) {
        Show-HealthSummary -Health $script:LastHealthSummary
    }

    if ($ExportReport -or $HtmlReport) {
        Export-SystemReport
    }

    Write-Host ''
    Write-Host 'Diagnóstico concluído.' -ForegroundColor Cyan
}

# =========================================================
# EXECUÇÃO AUTOMÁTICA & CLI
# =========================================================

if ($InstallTask) {
    Install-MaintenanceTask
    exit 0
}

if ($RemoveTask) {
    Uninstall-MaintenanceTask
    exit 0
}

if ($Routine) {
    switch ($Routine) {
        '1'  { Clear-TemporaryFiles }
        '2'  { Optimize-Drives }
        '3'  { Clear-NetworkCache }
        '4'  { Get-SystemSummary; if ($script:LastHealthSummary) { Show-HealthSummary -Health $script:LastHealthSummary } }
        '5'  { Show-StorageHealth }
        '6'  { Show-GpuInformation }
        '7'  { Show-BatteryStatus }
        '8'  { Show-HeavyProcesses }
        '9'  { Show-StartupAnalysis }
        '10' { Show-CriticalEvents }
        '11' { Export-SystemReport }
        '12' { Open-WindowsTools }
        '13' { New-MaintenanceRestorePoint }
        '14' { Invoke-LightMaintenance }
        '15' { Invoke-AdvancedDiagnostics }
        '18' { Repair-WindowsImage }
        '19' { Cleanup-ComponentStore }
        '20' { Clear-DriverStore }
        '21' { Show-VirtualDisksAndLargeCaches }
        default {
            Write-Host "Rotina '$Routine' não reconhecida. Executando rotina 14 (Manutenção Leve)." -ForegroundColor Yellow
            Invoke-LightMaintenance
        }
    }

    if ($PauseAtEnd) {
        Write-Host ''
        Read-Host 'Rotina finalizada. Pressione ENTER para fechar'
    }
    exit 0
}

if ($Auto) {
    Invoke-LightMaintenance

    if ($Advanced) {
        Invoke-AdvancedDiagnostics
    }

    if ($ExportReport -or $HtmlReport) {
        Export-SystemReport
    }

    exit 0
}

# =========================================================
# MENU PRINCIPAL
# =========================================================

Do {
    Show-Header

    Write-Host '--- MANUTENÇÃO & OTIMIZAÇÃO ---' -ForegroundColor Cyan
    Write-Host '1   Limpeza segura de temporários e cache'
    Write-Host '2   Otimização inteligente SSD (TRIM) / HDD'
    Write-Host '3   Limpeza de cache DNS e Rede'
    Write-Host ''
    Write-Host '--- DIAGNÓSTICO & HARDWARE ---' -ForegroundColor Green
    Write-Host '4   Relatório geral de saúde do sistema'
    Write-Host '5   Saúde de armazenamento (SMART / SSD)'
    Write-Host '6   Placas de vídeo (Multi-GPU & Temperatura)'
    Write-Host '7   Saúde da bateria (Notebook)'
    Write-Host '8   Processos mais pesados (RAM / CPU)'
    Write-Host '9   Aplicativos de inicialização (Startup)'
    Write-Host '10  Eventos críticos e desligamentos anormais'
    Write-Host ''
    Write-Host '--- RELATÓRIOS & FERRAMENTAS ---' -ForegroundColor White
    Write-Host '11  Exportar relatório técnico (TXT + HTML)'
    Write-Host '12  Abrir ferramentas nativas do Windows'
    Write-Host '13  Criar ponto de restauração do sistema'
    Write-Host ''
    Write-Host '--- AUTOMAÇÃO & AGENDAMENTO ---' -ForegroundColor Yellow
    Write-Host '14  Executar rotina leve de manutenção'
    Write-Host '15  Executar diagnóstico avançado completo'
    Write-Host '16  Instalar tarefa semanal no Agendador do Windows'
    Write-Host '17  Remover tarefa do Agendador do Windows'
    Write-Host ''
    Write-Host '--- REPARO PROFUNDO & SISTEMA ---' -ForegroundColor Magenta
    Write-Host '18  Reparo de imagem e integridade (DISM + SFC)'
    Write-Host '19  Limpeza do armazenamento de componentes (WinSxS)'
    Write-Host '20  Limpeza de drivers obsoletos (DriverStore - GPU/Sistema)'
    Write-Host '21  Varredura de discos virtuais e grandes caches (.vhdx / WSL)'
    Write-Host ''
    Write-Host '0   Sair'
    Write-Host ''

    $option = Read-Host 'Escolha uma opção'

    switch ($option) {
        '1'  { Clear-TemporaryFiles;             Pause-Console }
        '2'  { Optimize-Drives;                  Pause-Console }
        '3'  { Clear-NetworkCache;               Pause-Console }
        '4'  {
            Get-SystemSummary
            if ($script:LastHealthSummary) {
                Show-HealthSummary -Health $script:LastHealthSummary
            }
            Pause-Console
        }
        '5'  { Show-StorageHealth;               Pause-Console }
        '6'  { Show-GpuInformation;              Pause-Console }
        '7'  { Show-BatteryStatus;               Pause-Console }
        '8'  { Show-HeavyProcesses;              Pause-Console }
        '9'  { Show-StartupAnalysis;             Pause-Console }
        '10' { Show-CriticalEvents;              Pause-Console }
        '11' { Export-SystemReport;              Pause-Console }
        '12' { Open-WindowsTools;                Pause-Console }
        '13' { New-MaintenanceRestorePoint;      Pause-Console }
        '14' { Invoke-LightMaintenance;          Pause-Console }
        '15' { Invoke-AdvancedDiagnostics;       Pause-Console }
        '16' { Install-MaintenanceTask;          Pause-Console }
        '17' { Uninstall-MaintenanceTask;        Pause-Console }
        '18' { Repair-WindowsImage;              Pause-Console }
        '19' { Cleanup-ComponentStore;           Pause-Console }
        '20' { Clear-DriverStore;                Pause-Console }
        '21' { Show-VirtualDisksAndLargeCaches;  Pause-Console }
        '0'  { exit 0 }
        default {
            Write-Host 'Opção inválida.' -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }

} while ($true)
