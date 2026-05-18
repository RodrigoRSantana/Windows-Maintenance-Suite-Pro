#Requires -Version 5.1

param(
    [switch]$Auto,
    [switch]$Advanced,
    [switch]$ExportReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =========================================================
# CONFIGURAÇÃO GLOBAL
# =========================================================

$script:AppName = 'Windows Maintenance Suite Pro'
$script:Version = '2.1'
$script:StartTime = Get-Date

$script:BasePath = Join-Path $env:USERPROFILE 'Documents\MaintenanceSuite'
$script:LogPath = Join-Path $script:BasePath 'Maintenance.log'
$script:ReportPath = Join-Path $script:BasePath 'SystemReport.txt'

New-Item -Path $script:BasePath -ItemType Directory -Force | Out-Null

# =========================================================
# LOGGING
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
    } catch {}
}

Rotate-Logs

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO','WARNING','ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp [$Level] $Message"

    try {
        Add-Content -Path $script:LogPath -Value $line -Encoding UTF8
    } catch {}

    switch ($Level) {
        'INFO' {
            Write-Host $Message -ForegroundColor White
        }

        'WARNING' {
            Write-Host "WARNING: $Message" -ForegroundColor Yellow
        }

        'ERROR' {
            Write-Host "ERROR: $Message" -ForegroundColor Red
        }
    }
}

# =========================================================
# SEGURANÇA
# =========================================================

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
    Write-Host ''
    Write-Host 'Execute este script como ADMINISTRADOR.' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}

# =========================================================
# UTILITÁRIOS
# =========================================================

function Pause-Console {
    if (-not $Auto) {
        Write-Host ''
        Read-Host 'Pressione ENTER para continuar'
    }
}

function Show-Header {
    Clear-Host

    Write-Host ''
    Write-Host '=============================================================' -ForegroundColor Cyan
    Write-Host '        WINDOWS MAINTENANCE SUITE PRO' -ForegroundColor Cyan
    Write-Host '=============================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "Versão : $($script:Version)"
    Write-Host "Log    : $($script:LogPath)"
    Write-Host ''
}

function Show-Line {
    Write-Host '-------------------------------------------------------------' -ForegroundColor DarkGray
}

function Invoke-SafeCommand {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$Arguments = @()
    )

    try {
        $process = Start-Process `
            -FilePath $FilePath `
            -ArgumentList $Arguments `
            -Wait `
            -NoNewWindow `
            -PassThru

        return $process.ExitCode
    }
    catch {
        Write-Log "Falha ao executar $FilePath" 'ERROR'
        return -1
    }
}

# =========================================================
# LIMPEZA SEGURA
# =========================================================

function Remove-OldFiles {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [int]$OlderThanDays = 2
    )

    if (-not (Test-Path $Path)) {
        return
    }

    $limit = (Get-Date).AddDays(-$OlderThanDays)

    # Ignora totalmente pastas protegidas ou arquivos em uso, sem disparar erro no console
    $items = Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue |
             Where-Object { $_.LastWriteTime -lt $limit }

    if ($null -ne $items) {
        foreach ($item in $items) {
            try {
                Remove-Item $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
            catch {}
        }
    }
}

function Clear-TemporaryFiles {

    Write-Host ''
    Write-Host 'LIMPEZA SEGURA DE TEMPORÁRIOS' -ForegroundColor Cyan
    Show-Line

    $paths = @(
        $env:TEMP,
        "$env:SystemRoot\Temp"
    )

    foreach ($path in $paths) {

        if (Test-Path $path) {
            Write-Host "Limpando: $path" -ForegroundColor Green
            Remove-OldFiles -Path $path -OlderThanDays 2
            Write-Host 'OK' -ForegroundColor DarkGreen
        }
    }

    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Host 'Lixeira esvaziada.' -ForegroundColor DarkGreen
    }
    catch {
        Write-Log 'Falha ao limpar lixeira.' 'WARNING'
    }

    Write-Host ''
    Write-Host 'Limpeza concluída.' -ForegroundColor Cyan
}

# =========================================================
# OTIMIZAÇÃO SSD / HDD
# =========================================================

function Optimize-Drives {

    Write-Host ''
    Write-Host 'OTIMIZAÇÃO DE UNIDADES' -ForegroundColor Cyan
    Show-Line

    try {
        $trimStatus = fsutil behavior query DisableDeleteNotify

        Write-Host ''
        Write-Host 'Status do TRIM:' -ForegroundColor Green
        Write-Host $trimStatus
    }
    catch {}

    $volumes = Get-Volume | Where-Object {
        $_.DriveLetter -and $_.DriveType -eq 'Fixed'
    }

    foreach ($volume in $volumes) {

        Write-Host ''
        Write-Host "Unidade: $($volume.DriveLetter):" -ForegroundColor Green

        $mediaType = 'Desconhecido'
        $busType = 'Desconhecido'

        # Tenta descobrir o tipo de disco. Se a controladora NVMe negar, não tem problema.
        try {
            $partition = Get-Partition -DriveLetter $volume.DriveLetter -ErrorAction Stop
            $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
            
            if ($disk.MediaType) { $mediaType = $disk.MediaType }
            if ($disk.BusType)   { $busType = $disk.BusType }
        }
        catch {
            Write-Log "Aviso: Leitura física bloqueada pela controladora no disco $($volume.DriveLetter)." 'WARNING'
        }

        Write-Host "Mídia  : $mediaType"
        Write-Host "Bus    : $busType"

        try {
            if ($mediaType -eq 'SSD') {
                Optimize-Volume -DriveLetter $volume.DriveLetter -ReTrim -ErrorAction Stop | Out-Null
                Write-Host 'TRIM executado com sucesso.' -ForegroundColor DarkGreen
            }
            else {
                # Se for HDD ou Desconhecido, o próprio Windows decide sozinho o melhor método na hora de otimizar
                Optimize-Volume -DriveLetter $volume.DriveLetter -ErrorAction Stop | Out-Null
                Write-Host 'Otimização padrão executada com sucesso.' -ForegroundColor DarkGreen
            }
        }
        catch {
            Write-Log "Falha ao otimizar $($volume.DriveLetter). (Pode estar em uso ou bloqueado)" 'ERROR'
        }
    }
}

# =========================================================
# SMART / SSD HEALTH
# =========================================================

function Show-StorageHealth {

    Write-Host ''
    Write-Host 'SMART / STORAGE HEALTH' -ForegroundColor Cyan
    Show-Line

    try {
        Get-PhysicalDisk |
        Get-StorageReliabilityCounter |
        Select-Object -Property Temperature, Wear, PowerOnHours, ReadErrorsTotal, WriteErrorsTotal |
        Format-Table -AutoSize
    }
    catch {
        Write-Host 'SMART não disponível neste sistema.' -ForegroundColor Yellow
    }
}

# =========================================================
# RELATÓRIO SISTEMA
# =========================================================

function Get-SystemSummary {

    Write-Host ''
    Write-Host 'RELATÓRIO DO SISTEMA' -ForegroundColor Cyan
    Show-Line

    $os = Get-CimInstance Win32_OperatingSystem

    $uptime = (Get-Date) - $os.LastBootUpTime

    Write-Host ''
    Write-Host 'UPTIME:' -ForegroundColor Green
    Write-Host "$($uptime.Days) dias, $($uptime.Hours) horas"

    Write-Host ''
    Write-Host 'MEMÓRIA:' -ForegroundColor Green

    $ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $ramFree = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $ramUsed = [math]::Round($ramTotal - $ramFree, 2)

    Write-Host "RAM Total : $ramTotal GB"
    Write-Host "RAM Usada : $ramUsed GB"
    Write-Host "RAM Livre : $ramFree GB"

    Write-Host ''
    Write-Host 'DISCOS:' -ForegroundColor Green

    Get-Volume |
    Where-Object DriveLetter |
    ForEach-Object {

        $free = [math]::Round($_.SizeRemaining / 1GB, 2)
        $total = [math]::Round($_.Size / 1GB, 2)

        Write-Host "$($_.DriveLetter): $free GB livres de $total GB"
    }
}

# =========================================================
# TEMPERATURA GPU NVIDIA
# =========================================================

function Show-GpuTemperature {

    Write-Host ''
    Write-Host 'TEMPERATURA GPU' -ForegroundColor Cyan
    Show-Line

    $nvidiaSmi = "$env:SystemRoot\System32\nvidia-smi.exe"

    if (Test-Path $nvidiaSmi) {

        try {
            $temp = & $nvidiaSmi `
                --query-gpu=temperature.gpu `
                --format=csv,noheader

            Write-Host "GPU NVIDIA: $($temp.Trim()) °C" -ForegroundColor Green
        }
        catch {
            Write-Host 'Falha ao consultar GPU NVIDIA.' -ForegroundColor Yellow
        }
    }
    else {
        Write-Host 'nvidia-smi não encontrado.' -ForegroundColor Yellow
    }
}

# =========================================================
# PROCESSOS PESADOS
# =========================================================

function Show-HeavyProcesses {

    Write-Host ''
    Write-Host 'PROCESSOS MAIS PESADOS' -ForegroundColor Cyan
    Show-Line

    Get-Process |
    Sort-Object WorkingSet64 -Descending |
    Select-Object -First 10 -Property Name, Id, CPU, @{Name='RAM_MB';Expression={[math]::Round($_.WorkingSet64 / 1MB, 1)}} |
    Format-Table -AutoSize
}

# =========================================================
# STARTUP APPS
# =========================================================

function Show-StartupAnalysis {

    Write-Host ''
    Write-Host 'ANÁLISE DE STARTUP' -ForegroundColor Cyan
    Show-Line

    try {

        Get-CimInstance Win32_StartupCommand |
        Select-Object Name, User, Location |
        Format-Table -AutoSize
    }
    catch {
        Write-Log 'Falha ao listar startup apps.' 'WARNING'
    }
}

# =========================================================
# EVENTOS CRÍTICOS
# =========================================================

function Show-CriticalEvents {

    Write-Host ''
    Write-Host 'EVENTOS CRÍTICOS RECENTES' -ForegroundColor Cyan
    Show-Line

    try {

        Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            Level = 1,2
        } -MaxEvents 15 |
        Select-Object TimeCreated, Id, ProviderName, LevelDisplayName |
        Format-Table -AutoSize
    }
    catch {
        Write-Log 'Falha ao consultar eventos críticos.' 'WARNING'
    }
}

# =========================================================
# REPARO PROFUNDO
# =========================================================

function Repair-WindowsImage {

    Write-Host ''
    Write-Host 'REPARO PROFUNDO WINDOWS' -ForegroundColor Magenta
    Show-Line

    Write-Host 'Executando DISM (pode demorar)...' -ForegroundColor Green

    $dismExit = Invoke-SafeCommand `
        -FilePath 'DISM.exe' `
        -Arguments @('/Online','/Cleanup-Image','/RestoreHealth')

    Write-Host ''
    Write-Host "DISM ExitCode: $dismExit"

    Write-Host ''
    Write-Host 'Executando SFC (pode demorar)...' -ForegroundColor Green

    $sfcExit = Invoke-SafeCommand `
        -FilePath 'sfc.exe' `
        -Arguments @('/scannow')

    Write-Host ''
    Write-Host "SFC ExitCode: $sfcExit"

    Write-Host ''
    Write-Host 'Reparo concluído.' -ForegroundColor Cyan
}

# =========================================================
# EXPORTAÇÃO RELATÓRIO
# =========================================================

function Export-SystemReport {

    try {

        $report = @()

        $report += '================================================='
        $report += 'WINDOWS MAINTENANCE SUITE PRO'
        $report += '================================================='
        $report += ''
        $report += "Gerado em: $(Get-Date)"
        $report += ''

        $os = Get-CimInstance Win32_OperatingSystem

        $report += '=== SISTEMA ==='
        $report += "Computador : $env:COMPUTERNAME"
        $report += "Windows    : $($os.Caption)"
        $report += "Build      : $($os.BuildNumber)"
        $report += ''

        $report += '=== PROCESSOS ==='

        Get-Process |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First 10 -Property Name, @{Name='RAM_MB';Expression={[math]::Round($_.WorkingSet64 / 1MB, 1)}} |
        Out-String |
        ForEach-Object {
            $report += $_
        }

        $report | Out-File $script:ReportPath -Encoding UTF8

        Write-Host ''
        Write-Host "Relatório exportado:" -ForegroundColor Green
        Write-Host $script:ReportPath -ForegroundColor Cyan
    }
    catch {
        Write-Log 'Falha ao exportar relatório.' 'ERROR'
    }
}

# =========================================================
# FERRAMENTAS WINDOWS
# =========================================================

function Open-WindowsTools {

    Write-Host ''
    Write-Host 'ABRINDO FERRAMENTAS WINDOWS' -ForegroundColor Cyan
    Show-Line

    $tools = @(
        'ms-settings:storage',
        'ms-settings:startupapps',
        'ms-settings:powersleep'
    )

    foreach ($tool in $tools) {

        try {
            Start-Process $tool
        }
        catch {}
    }

    try {
        Start-Process 'perfmon' -ArgumentList '/rel'
    }
    catch {}

    try {
        Start-Process 'cleanmgr.exe'
    }
    catch {}
}

# =========================================================
# ROTINA LEVE
# =========================================================

function Invoke-LightMaintenance {

    Show-Header

    Write-Host 'ROTINA LEVE DE MANUTENÇÃO' -ForegroundColor Magenta

    Clear-TemporaryFiles
    Optimize-Drives
    Get-SystemSummary

    Write-Host ''
    Write-Host 'Rotina concluída.' -ForegroundColor Cyan
}

# =========================================================
# DIAGNÓSTICO AVANÇADO
# =========================================================

function Invoke-AdvancedDiagnostics {

    Show-Header

    Write-Host 'DIAGNÓSTICO AVANÇADO' -ForegroundColor Magenta

    Get-SystemSummary
    Show-StorageHealth
    Show-GpuTemperature
    Show-HeavyProcesses
    Show-StartupAnalysis
    Show-CriticalEvents

    if ($ExportReport) {
        Export-SystemReport
    }

    Write-Host ''
    Write-Host 'Diagnóstico concluído.' -ForegroundColor Cyan
}

# =========================================================
# EXECUÇÃO AUTOMÁTICA
# =========================================================

if ($Auto) {

    Invoke-LightMaintenance

    if ($Advanced) {
        Invoke-AdvancedDiagnostics
    }

    exit 0
}

# =========================================================
# MENU PRINCIPAL
# =========================================================

Do {

    Show-Header

    Write-Host '1  Limpeza segura de temporários'
    Write-Host '2  Otimização SSD / HDD'
    Write-Host '3  Relatório do sistema'
    Write-Host '4  SMART / SSD Health'
    Write-Host '5  Temperatura GPU'
    Write-Host '6  Processos pesados'
    Write-Host '7  Startup apps'
    Write-Host '8  Eventos críticos Windows'
    Write-Host '9  Abrir ferramentas Windows'
    Write-Host '10 Exportar relatório técnico'
    Write-Host ''
    Write-Host '--- AUTOMAÇÃO ---' -ForegroundColor Yellow
    Write-Host '11 Executar rotina leve'
    Write-Host '12 Executar diagnóstico avançado'
    Write-Host ''
    Write-Host '--- REPARO PROFUNDO ---' -ForegroundColor Magenta
    Write-Host '13 DISM + SFC'
    Write-Host ''
    Write-Host '0  Sair'
    Write-Host ''

    $option = Read-Host 'Escolha'

    switch ($option) {

        '1' {
            Clear-TemporaryFiles
            Pause-Console
        }

        '2' {
            Optimize-Drives
            Pause-Console
        }

        '3' {
            Get-SystemSummary
            Pause-Console
        }

        '4' {
            Show-StorageHealth
            Pause-Console
        }

        '5' {
            Show-GpuTemperature
            Pause-Console
        }

        '6' {
            Show-HeavyProcesses
            Pause-Console
        }

        '7' {
            Show-StartupAnalysis
            Pause-Console
        }

        '8' {
            Show-CriticalEvents
            Pause-Console
        }

        '9' {
            Open-WindowsTools
            Pause-Console
        }

        '10' {
            Export-SystemReport
            Pause-Console
        }

        '11' {
            Invoke-LightMaintenance
            Pause-Console
        }

        '12' {
            Invoke-AdvancedDiagnostics
            Pause-Console
        }

        '13' {
            Repair-WindowsImage
            Pause-Console
        }

        '0' {
            exit 0
        }

        default {
            Write-Host 'Opção inválida.' -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }

} while ($true)