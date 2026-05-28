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
$script:Version = '2.4'
$script:StartTime = Get-Date

$script:BasePath = Join-Path $env:USERPROFILE 'Documents\MaintenanceSuite'
$script:LogPath = Join-Path $script:BasePath 'Maintenance.log'
$script:ReportPath = Join-Path $script:BasePath 'SystemReport.txt'
$script:LastHealthSummary = $null

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
# Invoke-SafeCommand
# Uso geral: captura output via operador & (funciona para a
# maioria dos executáveis que escrevem no pipeline padrão).
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
# Uso específico para DISM e SFC: esses processos escrevem
# diretamente no buffer do console em UTF-16, o que impede
# o operador & de capturar o output. A solução é redirecionar
# stdout e stderr para arquivos temporários, depois ler,
# exibir e gravar no log. Os temporários são sempre apagados
# ao final, mesmo em caso de erro.
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

        # Exibe e grava no log cada linha do stdout
        foreach ($line in (Get-Content $tmpOut -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            $text = $line.TrimEnd()
            if ($text -ne '') {
                Write-Log $text
            }
        }

        # Exibe e grava no log cada linha do stderr como WARNING
        foreach ($line in (Get-Content $tmpErr -Encoding UTF8 -ErrorAction SilentlyContinue)) {
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
        # Garante remoção dos temporários independente de erro
        Remove-Item $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue
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
        return @(
            Get-WinEvent -FilterHashtable @{
                LogName   = 'System'
                Level     = 1,2
                StartTime = (Get-Date).AddHours(-$Hours)
            } -ErrorAction Stop
        ).Count
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

    if ($null -ne $criticalEvents72h) {
        if ($criticalEvents72h -ge 15) {
            $score -= 25
            $notes.Add('Muitos eventos críticos/erros recentes no Windows.')
        } elseif ($criticalEvents72h -ge 5) {
            $score -= 10
            $notes.Add('Há eventos críticos/erros recentes no Windows.')
        }
    }

    if ($uptime.TotalDays -lt 1) {
        $notes.Add('Sistema reiniciado recentemente.')
    }

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

    if ($Health.Notes.Count -gt 0) {
        Write-Host ''
        Write-Host 'Observações:' -ForegroundColor Cyan
        foreach ($note in $Health.Notes) {
            Write-Host "- $note"
        }
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

    if (-not (Test-Path $Path)) { return }

    $limit = (Get-Date).AddDays(-$OlderThanDays)

    try {
        $items = Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue |
                 Where-Object { $_.LastWriteTime -lt $limit }
    }
    catch {
        Write-Log "Falha ao listar arquivos em $Path" 'WARNING' -Silent
        return
    }

    if ($null -ne $items) {
        foreach ($item in $items) {
            try {
                Remove-Item $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
            catch {
                Write-Log "Falha ao remover item: $($item.FullName)" 'WARNING' -Silent
            }
        }
    }
}

function Clear-TemporaryFiles {
    Show-SectionTitle -Title 'LIMPEZA SEGURA DE TEMPORÁRIOS'

    $paths = @(
        $env:TEMP,
        "$env:SystemRoot\Temp"
    )

    foreach ($path in $paths) {
        if (Test-Path $path) {
            Write-Host "Limpando: $path" -ForegroundColor Green
            Remove-OldFiles -Path $path -OlderThanDays 2
            Write-Host 'OK' -ForegroundColor DarkGreen
        } else {
            Write-Log "Caminho temporário não encontrado: $path" 'WARNING' -Silent
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
    Show-SectionTitle -Title 'OTIMIZAÇÃO DE UNIDADES'

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

    foreach ($volume in $volumes) {
        Write-Host ''
        Write-Host "Unidade: $($volume.DriveLetter):" -ForegroundColor Green

        $mediaType = 'Desconhecido'
        $busType   = 'Desconhecido'

        try {
            $partition = Get-Partition -DriveLetter $volume.DriveLetter -ErrorAction Stop
            $disk      = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop

            if ($disk.MediaType) { $mediaType = $disk.MediaType }
            if ($disk.BusType)   { $busType   = $disk.BusType }
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
            } else {
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
    Show-SectionTitle -Title 'SMART / STORAGE HEALTH'

    try {
        Write-Host 'Discos físicos:' -ForegroundColor Green
        Get-PhysicalDisk |
        Select-Object FriendlyName, MediaType, HealthStatus,
            @{Name='SizeGB';Expression={[math]::Round($_.Size / 1GB, 2)}} |
        Format-Table -AutoSize

        Write-Host ''
        Write-Host 'Contadores de confiabilidade:' -ForegroundColor Green
        Get-PhysicalDisk |
        Get-StorageReliabilityCounter |
        Select-Object Temperature, Wear, PowerOnHours, ReadErrorsTotal, WriteErrorsTotal |
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
}

# =========================================================
# TEMPERATURA GPU NVIDIA
# =========================================================

function Show-GpuTemperature {
    Show-SectionTitle -Title 'TEMPERATURA GPU'

    $nvidiaSmi = @(
        "$env:SystemRoot\System32\nvidia-smi.exe",
        'C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe'
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($nvidiaSmi) {
        try {
            $temp = & $nvidiaSmi --query-gpu=temperature.gpu --format=csv,noheader
            Write-Host "GPU NVIDIA: $($temp.Trim()) °C" -ForegroundColor Green
        }
        catch {
            Write-Log 'Falha ao consultar GPU NVIDIA.' 'WARNING'
        }
    } else {
        Write-Host 'nvidia-smi não encontrado.' -ForegroundColor Yellow
    }
}

# =========================================================
# PROCESSOS PESADOS
# =========================================================

function Show-HeavyProcesses {
    Show-SectionTitle -Title 'PROCESSOS MAIS PESADOS'

    Get-Process |
    Sort-Object WorkingSet64 -Descending |
    Select-Object -First 10 -Property Name, Id, CPU,
        @{Name='RAM_MB';Expression={[math]::Round($_.WorkingSet64 / 1MB, 1)}} |
    Format-Table -AutoSize
}

# =========================================================
# STARTUP APPS
# =========================================================

function Show-StartupAnalysis {
    Show-SectionTitle -Title 'ANÁLISE DE STARTUP'

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
    Show-SectionTitle -Title 'EVENTOS CRÍTICOS RECENTES'

    try {
        Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            Level   = 1,2
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
    Show-SectionTitle -Title 'REPARO PROFUNDO WINDOWS' -Color Magenta

    Write-Host 'Executando DISM (pode demorar)...' -ForegroundColor Green

    # Invoke-ConsoleCommand é usado aqui porque DISM e SFC escrevem
    # diretamente no buffer do console em UTF-16, o que impede o
    # operador & de capturar o output corretamente.
    $dismExit = Invoke-ConsoleCommand `
        -FilePath 'DISM.exe' `
        -Arguments @('/Online','/Cleanup-Image','/RestoreHealth')

    Write-Host ''
    Write-Host "DISM ExitCode: $dismExit"

    Write-Host ''
    Write-Host 'Executando SFC (pode demorar)...' -ForegroundColor Green

    $sfcExit = Invoke-ConsoleCommand `
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
        $health = Get-SystemHealth
        $os = Get-CimInstance Win32_OperatingSystem

        $content = @()
        $content += '================================================='
        $content += 'WINDOWS MAINTENANCE SUITE PRO'
        $content += "Versão        : $($script:Version)"
        $content += "Gerado em     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $content += "Classificação : $($health.Status)"
        $content += "Pontuação     : $($health.Score)/100"
        $content += '================================================='
        $content += ''

        $content += Format-Section -Title 'SISTEMA' -Content @(
            "Computador : $env:COMPUTERNAME"
            "Windows    : $($os.Caption)"
            "Build      : $($os.BuildNumber)"
            "Uptime     : $($health.UptimeDays) dias, $($health.UptimeHours) horas"
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

        $diskContent = Get-Volume |
            Where-Object DriveLetter |
            ForEach-Object {
                $free  = [math]::Round($_.SizeRemaining / 1GB, 2)
                $total = [math]::Round($_.Size / 1GB, 2)
                "$($_.DriveLetter): $free GB livres de $total GB"
            }
        $content += Format-Section -Title 'DISCOS' -Content $diskContent

        try {
            $physicalDisks = Get-PhysicalDisk |
                Select-Object FriendlyName, MediaType, HealthStatus,
                    @{Name='SizeGB';Expression={[math]::Round($_.Size / 1GB, 2)}}
            $content += Format-Section -Title 'DISCOS FÍSICOS' -Content $physicalDisks
        }
        catch {
            $content += Format-Section -Title 'DISCOS FÍSICOS' -Content 'Informações físicas não disponíveis.'
        }

        try {
            $smart = Get-PhysicalDisk |
                Get-StorageReliabilityCounter |
                Select-Object Temperature, Wear, PowerOnHours, ReadErrorsTotal, WriteErrorsTotal
            $content += Format-Section -Title 'SMART / STORAGE HEALTH' -Content $smart
        }
        catch {
            $content += Format-Section -Title 'SMART / STORAGE HEALTH' -Content 'SMART não disponível.'
        }

        $gpuInfo   = 'nvidia-smi não encontrado.'
        $nvidiaSmi = @(
            "$env:SystemRoot\System32\nvidia-smi.exe",
            'C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe'
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ($nvidiaSmi) {
            try {
                $temp    = & $nvidiaSmi --query-gpu=temperature.gpu --format=csv,noheader
                $gpuInfo = "GPU NVIDIA: $($temp.Trim()) °C"
            }
            catch {
                $gpuInfo = 'Falha ao consultar GPU.'
            }
        }

        $content += Format-Section -Title 'TEMPERATURA GPU' -Content $gpuInfo

        $heavyProcesses = Get-Process |
            Sort-Object WorkingSet64 -Descending |
            Select-Object -First 10 -Property Name, Id, CPU,
                @{Name='RAM_MB';Expression={[math]::Round($_.WorkingSet64 / 1MB, 1)}}
        $content += Format-Section -Title 'PROCESSOS MAIS PESADOS' -Content $heavyProcesses

        try {
            $startup = Get-CimInstance Win32_StartupCommand |
                Select-Object Name, User, Location
            $content += Format-Section -Title 'STARTUP APPS' -Content $startup
        }
        catch {
            $content += Format-Section -Title 'STARTUP APPS' -Content 'Falha ao listar startup apps.'
        }

        try {
            $events = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1,2 } -MaxEvents 15 |
                Select-Object TimeCreated, Id, ProviderName, LevelDisplayName
            $content += Format-Section -Title 'EVENTOS CRÍTICOS RECENTES' -Content $events
        }
        catch {
            $content += Format-Section -Title 'EVENTOS CRÍTICOS RECENTES' -Content 'Falha ao consultar eventos.'
        }

        $content -join "`r`n" | Out-File $script:ReportPath -Encoding UTF8

        Write-Host ''
        Write-Host 'Relatório exportado:' -ForegroundColor Green
        Write-Host $script:ReportPath -ForegroundColor Cyan
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
# ROTINA LEVE
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

    if ($script:LastHealthSummary) {
        Show-HealthSummary -Health $script:LastHealthSummary
    }

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
        '1'  { Clear-TemporaryFiles;  Pause-Console }
        '2'  { Optimize-Drives;       Pause-Console }
        '3'  {
            Get-SystemSummary
            if ($script:LastHealthSummary) {
                Show-HealthSummary -Health $script:LastHealthSummary
            }
            Pause-Console
        }
        '4'  { Show-StorageHealth;    Pause-Console }
        '5'  { Show-GpuTemperature;   Pause-Console }
        '6'  { Show-HeavyProcesses;   Pause-Console }
        '7'  { Show-StartupAnalysis;  Pause-Console }
        '8'  { Show-CriticalEvents;   Pause-Console }
        '9'  { Open-WindowsTools;     Pause-Console }
        '10' { Export-SystemReport;   Pause-Console }
        '11' { Invoke-LightMaintenance;    Pause-Console }
        '12' { Invoke-AdvancedDiagnostics; Pause-Console }
        '13' { Repair-WindowsImage;        Pause-Console }
        '0'  { exit 0 }
        default {
            Write-Host 'Opção inválida.' -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }

} while ($true)