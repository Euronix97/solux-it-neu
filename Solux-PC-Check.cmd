@echo off
setlocal
title Solux PC-Check
set "SOLUX_SELF=%~f0"
set "SOLUX_TMP=%TEMP%\SoluxCheck-%RANDOM%%RANDOM%.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$c = Get-Content -LiteralPath $env:SOLUX_SELF -Raw -Encoding UTF8; $m = '#' + '<SOLUX-PS>'; $i = $c.IndexOf($m); if ($i -ge 0) { Set-Content -LiteralPath $env:SOLUX_TMP -Value $c.Substring($i) -Encoding UTF8 }"
if not exist "%SOLUX_TMP%" (
  echo Der PC-Check konnte nicht gestartet werden. Bitte melden Sie sich bei Solux IT: info@solux-it.de
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SOLUX_TMP%" -Launcher "%~f0" %*
exit /b
#<SOLUX-PS>
<#
  Solux PC-Check (Skript-Variante)
  Solux IT - Marcel Bux - Thalhauser Weg 6 - 51674 Wiehl - info@solux-it.de

  Läuft ohne Installation mit Windows PowerShell 5.1. Das Skript liest nur und ändert nichts.
  Es ist bewusst für den eingeschränkten Sprachmodus (Constrained Language Mode) geschrieben:
  Auf Rechnern mit Smart App Control laufen unsignierte Skripte nur in diesem Modus.
  Deshalb: keine .NET-Methodenaufrufe außer auf Basistypen, kein Add-Type, kein [pscustomobject].

  Aufruf:  Solux-PC-Check.cmd  (Einzeldatei, Doppelklick)  oder  PC-Check starten.cmd + SoluxCheck.ps1
           powershell -NoProfile -ExecutionPolicy Bypass -File SoluxCheck.ps1 [Optionen]
             -OutDir <Ordner>   Zielordner der Berichte (Standard: Dokumente\Solux PC-Check)
             -Technician        Technikermodus: keine Dialoge, kein Upload, Berichte neben dem Skript (z. B. USB-Stick)
             -Quiet             keine Dialoge (für Fernwartung/Automatisierung)
             -NoUpload          Bericht nicht senden
             -NoElevate         nicht nach Adminrechten fragen
             -NoOpen            Bericht nicht öffnen
             -Days 14           Zeitraum für Ereignisse
             -SelfTest          prüft Bewertung und Bericht mit Beispieldaten (kein Windows nötig)
           Einzeiler (Telefon/Fernwartung):  irm https://solux-it.de/check.ps1 | iex
#>
param(
    [string]$OutDir = '',
    [switch]$Elevated,
    [switch]$NoElevate,
    [switch]$NoOpen,
    [switch]$SelfTest,
    [int]$Days = 14,
    [switch]$Technician,
    [switch]$Quiet,
    [switch]$NoUpload,
    [switch]$Accepted,
    [string]$Launcher = '',
    [string]$CustName = '',
    [string]$CustPhone = '',
    [string]$CustCode = '',
    [string]$Symptoms = ''
)

$ErrorActionPreference = 'Continue'
$ScriptVersion = '1.1.4'
$SchemaVersion = 1

# Einstellungen für Verteilung und Rücklauf. Leer = Funktion aus.
$Config = @{
    UploadUrl   = ''                                # z. B. https://n8n.solux-it.de/webhook/pc-check
    UploadToken = ''                                # gemeinsamer Schlüssel, Header X-Solux-Token
    VersionUrl  = ''                                # Textdatei mit aktueller Versionsnummer, z. B. https://solux-it.de/check-version.txt
    SelfUrl     = 'https://solux-it.de/check.ps1'      # Quelle des Skripts für den Einzeiler (für Neustart mit Adminrechten)
    Phone       = '01520 6943576'                   # Telefonnummer für Fenster und Bericht
    MaxUploadKB = 2048
}
$ThermalSamples = 6
$PingCount = 10

$Solux = [ordered]@{
    name    = 'Solux IT'
    people  = 'Marcel Bux'
    street  = 'Thalhauser Weg 6'
    city    = '51674 Wiehl'
    mail    = 'info@solux-it.de'
    web     = 'www.solux-it.de'
}

# Alle Schwellen an einer Stelle. Änderungen hier wirken auf Bewertung und Bericht.
$T = @{
    FreeCritGB        = 5
    FreeWarnGB        = 15
    FreeWarnPct       = 10
    WearWarn          = 70
    WearCrit          = 90
    DiskTempWarn      = 70
    CleanHours        = 8000
    CpuHotLoad        = 90     # °C unter Last (>= 50 %)
    CpuHotIdle        = 70     # °C bei wenig Last (< 30 %)
    GpuHot            = 85
    BattWarn          = 80
    BattCrit          = 60
    BsodWarn          = 2
    BsodCrit          = 4
    TdrWarn           = 2
    AppCrashWarn      = 10
    AppHangWarn       = 5
    StabilityWarn     = 5
    BootWarnSec       = 60
    StartupWarn       = 12
    UptimeDays        = 14
    UpdateAgeDays     = 45
    UpdateFailWarn    = 3
    SigAgeWarn        = 7
    PingLossWarn      = 10
    LatencyWarn       = 80
    JitterWarn        = 30
    DnsWarnMs         = 500
    WlanWeak          = 40
    WlanMedium        = 70
    WlanDropWarn      = 10
    RamLowGB          = 8
    TempJunkGB        = 5
}

# Leistungsbausteine. Preise pflegt Solux; bis dahin "Preis auf Anfrage".
$Services = @{
    clean    = @{ title = 'Innenreinigung und neue Wärmeleitpaste'; price = 'Preis auf Anfrage' }
    disk     = @{ title = 'SSD-Tausch inklusive Datenumzug';        price = 'Preis auf Anfrage' }
    backup   = @{ title = 'Automatische Datensicherung einrichten'; price = 'Preis auf Anfrage' }
    win11    = @{ title = 'Umstieg auf Windows 11 inklusive Daten'; price = 'Preis auf Anfrage' }
    newpc    = @{ title = 'Beratung zum Neugerät';                  price = 'kostenlos' }
    cleanup  = @{ title = 'Systembereinigung und Speicher freigeben'; price = 'Preis auf Anfrage' }
    startup  = @{ title = 'Systemstart beschleunigen';              price = 'Preis auf Anfrage' }
    driver   = @{ title = 'Treiber prüfen und aktualisieren';       price = 'Preis auf Anfrage' }
    updates  = @{ title = 'Windows-Updates reparieren';             price = 'Preis auf Anfrage' }
    security = @{ title = 'Sicherheits-Check und Virenschutz einrichten'; price = 'Preis auf Anfrage' }
    battery  = @{ title = 'Akkutausch';                             price = 'Preis auf Anfrage' }
    ram      = @{ title = 'Arbeitsspeicher aufrüsten';              price = 'Preis auf Anfrage' }
    network  = @{ title = 'WLAN und Internetverbindung optimieren'; price = 'Preis auf Anfrage' }
    stability= @{ title = 'Absturzursache vor Ort eingrenzen';      price = 'Preis auf Anfrage' }
    office   = @{ title = 'Office auf eine unterstützte Version umstellen'; price = 'Preis auf Anfrage' }
}

$Unwanted = @('driver booster','driver easy','drivermax','driver support','driverfix','ccleaner','advanced systemcare','iobit',
    'reimage','restoro','fortect','pc cleaner','pc optimizer','pc accelerate','wise care','segurazo','bytefence',
    'webadvisor','wildtangent','onelaunch','web companion','wave browser','shift browser','pc app store','toolbar',
    'mcafee security scan','avast cleanup','avg tuneup','auslogics','winzip driver','systweak','advanced pc','speedup')
$RemoteTools = @('anydesk','teamviewer','ultraviewer','supremo','alpemix','screenconnect','logmein','rustdesk','aweray','awesun','zoho assist','splashtop','remote utilities','ammyy')
$BackupTools = @('veeam','acronis','macrium','backblaze','synology','carbonite','idrive','aomei','paragon backup','easeus todo','crashplan')

# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------
function R1($x) { if ($null -eq $x) { return $null }; [int]([double]$x * 10) / 10 }
function Num($x) { if ($null -eq $x) { return '' }; ([string]$x) -replace '\.', ',' }
function GB($bytes) { if ($null -eq $bytes) { return $null }; R1 ([double]$bytes / 1GB) }
function Esc($s) {
    if ($null -eq $s) { return '' }
    ([string]$s) -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;'
}
function Has($haystack, $needles) {
    $h = ([string]$haystack).ToLowerInvariant()
    foreach ($n in $needles) { if ($h.Contains($n)) { return $true } }
    return $false
}
function DateDe($d) { if ($null -eq $d) { return '' }; ([datetime]$d).ToString('dd.MM.yyyy') }
function DateTimeDe($d) { if ($null -eq $d) { return '' }; ([datetime]$d).ToString('dd.MM.yyyy HH:mm') }

function Cim($class, $ns, $filter) {
    $p = @{ ClassName = $class; ErrorAction = 'Stop'; OperationTimeoutSec = 20 }
    if ($ns) { $p.Namespace = $ns }
    if ($filter) { $p.Filter = $filter }
    # Komma: Array nicht entpacken. Eine einzelne CimInstance hat in PS 5.1 kein .Count.
    try { return ,@(Get-CimInstance @p) } catch { return ,@() }
}

function RegVal($path, $name) {
    try { (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name } catch { $null }
}

# Ereignisse über wevtutil (XML) statt Get-WinEvent: liefert benannte Datenfelder ohne Methodenaufrufe.
# Ausgabe als UTF-16 in eine Datei: so bleiben Umlaute unabhängig von der Konsolen-Codepage erhalten.
function Get-Ev($log, $xpath, $max) {
    $tmp = Join-Path $env:TEMP ('SoluxEv-' + (Get-Random) + '.xml')
    & cmd.exe /c "wevtutil.exe qe `"$log`" /q:`"$xpath`" /f:xml /c:$max /rd:true /uni:true > `"$tmp`" 2>nul"
    $all = ''
    try { $all = Get-Content -LiteralPath $tmp -Raw -Encoding Unicode -ErrorAction Stop } catch { }
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    if (-not $all) { return }
    foreach ($p in ($all -split '</Event>')) {
        if ($p -notmatch '<EventID[^>]*>(\d+)<') { continue }
        $ev = @{ Id = [int]$Matches[1]; Time = $null; Provider = ''; Level = 0; Data = @{}; Values = @() }
        if ($p -match "SystemTime=['""]([^'""]+)['""]") { try { $ev.Time = [datetime]$Matches[1] } catch { } }
        if ($p -match "Provider Name=['""]([^'""]+)['""]") { $ev.Provider = $Matches[1] }
        if ($p -match '<Level>(\d+)</Level>') { $ev.Level = [int]$Matches[1] }
        foreach ($m in [regex]::Matches($p, "<Data Name=['""]([^'""]+)['""]>([^<]*)</Data>")) { $ev.Data[$m.Groups[1].Value] = $m.Groups[2].Value }
        foreach ($m in [regex]::Matches($p, "<Data(?: Name=['""][^'""]*['""])?>([^<]*)</Data>")) { $ev.Values += $m.Groups[1].Value }
        $ev
    }
}
function Ms($d) { [string]([long]$d * 86400000) }
function XQ($providers, $ids, $days) {
    $idPart = ($ids | ForEach-Object { "EventID=$_" }) -join ' or '
    $prov = ''
    if ($providers) { $prov = '(' + (($providers | ForEach-Object { "@Name='$_'" }) -join ' or ') + ')' ; $prov = "Provider[$prov] and " }
    "*[System[$prov($idPart) and TimeCreated[timediff(@SystemTime) <= $(Ms $days)]]]"
}

function Explain-BugCheck($code) {
    $c = ([string]$code).ToLowerInvariant() -replace '^0x0*', ''
    switch ($c) {
        'a'   { 'IRQL_NOT_LESS_OR_EQUAL (Treiber- oder RAM-Zugriffskonflikt)' }
        '1a'  { 'MEMORY_MANAGEMENT (Arbeitsspeicher- oder Treiberfehler)' }
        '3b'  { 'SYSTEM_SERVICE_EXCEPTION (Absturz in Systemdienst oder Treiber)' }
        '50'  { 'PAGE_FAULT_IN_NONPAGED_AREA (RAM oder fehlerhafter Treiber)' }
        '7a'  { 'KERNEL_DATA_INPAGE_ERROR (Lesefehler von Festplatte/SSD)' }
        '7e'  { 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED (Treiberfehler)' }
        '1000007e' { 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED (Treiberfehler)' }
        '8e'  { 'KERNEL_MODE_EXCEPTION_NOT_HANDLED (Treiberfehler)' }
        '1000008e' { 'KERNEL_MODE_EXCEPTION_NOT_HANDLED (Treiberfehler)' }
        '9f'  { 'DRIVER_POWER_STATE_FAILURE (Treiber hängt beim Energiesparwechsel)' }
        'd1'  { 'DRIVER_IRQL_NOT_LESS_OR_EQUAL (fehlerhafter Gerätetreiber)' }
        'ef'  { 'CRITICAL_PROCESS_DIED (wichtiger Windows-Prozess beendet)' }
        '116' { 'VIDEO_TDR_FAILURE (Grafiktreiber reagiert nicht mehr)' }
        '119' { 'VIDEO_SCHEDULER_INTERNAL_ERROR (Grafikkarte/-treiber)' }
        '124' { 'WHEA_UNCORRECTABLE_ERROR (Hardwarefehler: CPU, RAM, Mainboard oder NVMe)' }
        '133' { 'DPC_WATCHDOG_VIOLATION (Treiber oder SSD-Firmware blockiert)' }
        '139' { 'KERNEL_SECURITY_CHECK_FAILURE (beschädigte Daten, oft Treiber/RAM)' }
        '154' { 'UNEXPECTED_STORE_EXCEPTION (Speicher/SSD)' }
        '1e'  { 'KMODE_EXCEPTION_NOT_HANDLED (Treiberfehler)' }
        'c2'  { 'BAD_POOL_CALLER (Treiberfehler)' }
        default { 'Stop-Code 0x' + $c }
    }
}

function Get-SupportEnd($build, $dv, $edition) {
    if (-not $build) { return $null }
    $ent = ([string]$edition) -match 'Enterprise|Education'
    $v = ([string]$dv).ToUpperInvariant()
    if ($build -lt 22000) { return [datetime]'2025-10-14' }
    if ($v -eq '21H2' -or $build -lt 22621) { if ($ent) { return [datetime]'2024-10-08' } else { return [datetime]'2023-10-10' } }
    if ($v -eq '22H2') { if ($ent) { return [datetime]'2025-10-14' } else { return [datetime]'2024-10-08' } }
    if ($v -eq '23H2') { if ($ent) { return [datetime]'2026-11-10' } else { return [datetime]'2025-11-11' } }
    if ($v -eq '24H2') { if ($ent) { return [datetime]'2027-10-12' } else { return [datetime]'2026-10-13' } }
    if ($v -eq '25H2') { if ($ent) { return [datetime]'2028-10-10' } else { return [datetime]'2027-10-12' } }
    if ($v -eq '26H1') { return [datetime]'2028-03-14' }
    if ($v -eq '26H2') { if ($ent) { return $null } else { return [datetime]'2028-10-10' } }
    return $null
}
$LifecycleCheckedOn = [datetime]'2026-11-13'

# ---------------------------------------------------------------------------
# Datenmodell
# ---------------------------------------------------------------------------
$D = [ordered]@{
    meta     = [ordered]@{}
    system   = [ordered]@{}
    hardware = [ordered]@{}
    storage  = [ordered]@{ volumes = @(); disks = @() }
    thermal  = [ordered]@{}
    battery  = [ordered]@{}
    stability= [ordered]@{}
    updates  = [ordered]@{}
    security = [ordered]@{}
    network  = [ordered]@{}
    software = [ordered]@{}
    backup   = [ordered]@{}
    win11    = [ordered]@{}
    customer = [ordered]@{ name = ''; phone = ''; code = ''; symptoms = @() }
    compare  = $null
    modules  = @()
}
$Findings = @()

function Add-Finding($area, $sev, $title, $detail, $customer, $rec, $urgency) {
    $script:Findings += [ordered]@{
        area = $area; severity = $sev; title = $title; detail = $detail
        customer = $customer; service = $rec; urgency = $urgency
    }
}

$StepNo = 0
$StepTotal = 12
function Run-Module($name, $label, $block) {
    $script:StepNo++
    Write-Host ('   [' + $script:StepNo + '/' + $script:StepTotal + '] ') -ForegroundColor DarkCyan -NoNewline
    Write-Host $label
    $t0 = Get-Date
    $status = 'ok'; $note = ''
    try { & $block } catch { $status = 'fehler'; $note = $_.Exception.Message }
    $ms = [int]((Get-Date) - $t0).TotalMilliseconds
    $script:D.modules += [ordered]@{ name = $name; status = $status; ms = $ms; note = $note }
}

# ---------------------------------------------------------------------------
# Sammler
# ---------------------------------------------------------------------------
function Collect-System {
    $os = (Cim 'Win32_OperatingSystem')[0]
    $cs = (Cim 'Win32_ComputerSystem')[0]
    $bios = (Cim 'Win32_BIOS')[0]
    $prod = (Cim 'Win32_ComputerSystemProduct')[0]
    $enc = (Cim 'Win32_SystemEnclosure')[0]
    $cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $s = $script:D.system
    $s.computerName = $env:COMPUTERNAME
    $s.osName = [string]$os.Caption
    $s.build = [int](RegVal $cv 'CurrentBuildNumber')
    $s.ubr = RegVal $cv 'UBR'
    $s.displayVersion = [string](RegVal $cv 'DisplayVersion')
    $s.edition = [string](RegVal $cv 'EditionID')
    if ($s.build -ge 22000 -and $s.osName -match 'Windows 10') { $s.osName = $s.osName -replace 'Windows 10', 'Windows 11' }
    $s.installDate = $os.InstallDate
    $s.lastBoot = $os.LastBootUpTime
    if ($os.LastBootUpTime) { $s.uptimeDays = R1 (((Get-Date) - $os.LastBootUpTime).TotalDays) }
    $s.fastStartup = (RegVal 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled') -eq 1
    $s.manufacturer = [string]$cs.Manufacturer
    $s.model = [string]$cs.Model
    if ([string]$cs.Manufacturer -match 'LENOVO' -and $prod.Version) { $s.model = [string]$prod.Version + ' (' + $cs.Model + ')' }
    $s.serial = [string]$bios.SerialNumber
    $s.biosVersion = [string]$bios.SMBIOSBIOSVersion
    $s.biosDate = $bios.ReleaseDate
    $laptopTypes = @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32)
    $s.isLaptop = $false
    foreach ($ct in @($enc.ChassisTypes)) { if ($laptopTypes -contains [int]$ct) { $s.isLaptop = $true } }
    $s.supportEnd = Get-SupportEnd $s.build $s.displayVersion $s.edition
    $s.isWin10 = $s.build -gt 0 -and $s.build -lt 22000
    $s.insider = $null -ne (RegVal 'HKLM:\SOFTWARE\Microsoft\WindowsSelfHost\Applicability' 'BranchName')
    $lic = Cim 'SoftwareLicensingProduct' $null "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'"
    $s.activated = $null
    foreach ($l in $lic) { if ([int]$l.LicenseStatus -eq 1) { $s.activated = $true } elseif ($null -eq $s.activated) { $s.activated = $false } }
    $s.pendingReboot = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
                       (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
}

function Collect-Hardware {
    $h = $script:D.hardware
    $cpu = (Cim 'Win32_Processor')[0]
    $h.cpu = ([string]$cpu.Name).Trim()
    $h.cores = $cpu.NumberOfCores
    $h.threads = $cpu.NumberOfLogicalProcessors
    $mods = Cim 'Win32_PhysicalMemory'
    $arr = Cim 'Win32_PhysicalMemoryArray'
    $h.ramModules = @()
    $total = 0
    foreach ($m in $mods) {
        $total += [double]$m.Capacity
        $h.ramModules += [ordered]@{ slot = [string]$m.DeviceLocator; sizeGB = GB $m.Capacity; speed = $m.Speed; configured = $m.ConfiguredClockSpeed; vendor = ([string]$m.Manufacturer).Trim(); part = ([string]$m.PartNumber).Trim() }
    }
    $h.ramGB = GB $total
    $slots = 0; foreach ($a in $arr) { $slots += [int]$a.MemoryDevices }
    $h.ramSlots = $slots
    $h.gpus = @()
    foreach ($g in (Cim 'Win32_VideoController')) {
        $n = [string]$g.Name
        if ($n -match 'Basic Display|Remote|Virtual|Parsec|Mirage') { continue }
        $h.gpus += [ordered]@{ name = $n; driver = [string]$g.DriverVersion; driverDate = $g.DriverDate }
    }
    $h.problemDevices = @()
    foreach ($d in (Cim 'Win32_PnPEntity' $null 'ConfigManagerErrorCode <> 0')) {
        $code = [int]$d.ConfigManagerErrorCode
        $txt = switch ($code) { 10 { 'Gerät kann nicht starten' } 22 { 'deaktiviert' } 28 { 'kein Treiber installiert' } 43 { 'Gerät meldet Fehler' } 45 { 'nicht angeschlossen' } default { 'Fehlercode ' + $code } }
        if ($code -eq 45 -or $code -eq 22) { continue }
        $h.problemDevices += [ordered]@{ name = [string]$d.Name; code = $code; text = $txt }
    }
}

function Collect-Storage {
    $st = $script:D.storage
    foreach ($v in (Cim 'Win32_LogicalDisk' $null 'DriveType = 3')) {
        $size = [double]$v.Size; $free = [double]$v.FreeSpace
        $pct = 0; if ($size -gt 0) { $pct = R1 ($free / $size * 100) }
        $st.volumes += [ordered]@{ drive = [string]$v.DeviceID; label = [string]$v.VolumeName; sizeGB = GB $size; freeGB = GB $free; freePct = $pct; fs = [string]$v.FileSystem }
    }
    $pds = @()
    try { $pds = @(Get-PhysicalDisk -ErrorAction Stop) } catch { }
    foreach ($p in $pds) {
        $disk = [ordered]@{
            name = [string]$p.FriendlyName; serial = ([string]$p.SerialNumber).Trim(); firmware = [string]$p.FirmwareVersion
            media = [string]$p.MediaType; bus = [string]$p.BusType; sizeGB = GB $p.Size; health = [string]$p.HealthStatus
            external = ([string]$p.BusType -eq 'USB'); temp = $null; tempMax = $null; wear = $null; hours = $null; readErrors = $null; startStop = $null
        }
        try {
            $rc = Get-StorageReliabilityCounter -PhysicalDisk $p -ErrorAction Stop
            if ($rc.Temperature -gt 0) { $disk.temp = [int]$rc.Temperature }
            if ($rc.TemperatureMax -gt 0) { $disk.tempMax = [int]$rc.TemperatureMax }
            if ($null -ne $rc.Wear) { $disk.wear = [int]$rc.Wear }
            if ($rc.PowerOnHours -gt 0) { $disk.hours = [int]$rc.PowerOnHours }
            if ($null -ne $rc.ReadErrorsUncorrected) { $disk.readErrors = [long]$rc.ReadErrorsUncorrected }
            if ($null -ne $rc.StartStopCycleCount) { $disk.startStop = [long]$rc.StartStopCycleCount }
        } catch { }
        $st.disks += $disk
    }
    $st.diskEvents = @()
    $ev = @(Get-Ev 'System' (XQ @('disk', 'Ntfs', 'stornvme', 'storahci') @(7, 11, 51, 55, 98, 129, 153, 154) 30) 200)
    $groups = @{}
    foreach ($e in $ev) { $k = $e.Provider + ' ' + $e.Id; if ($groups.ContainsKey($k)) { $groups[$k]++ } else { $groups[$k] = 1 } }
    foreach ($k in $groups.Keys) { $st.diskEvents += [ordered]@{ source = $k; count = $groups[$k] } }
    $st.severeDiskEvents = 0
    foreach ($e in $ev) { if (($e.Provider -eq 'disk' -and @(7, 51, 154) -contains $e.Id) -or ($e.Provider -eq 'Ntfs' -and $e.Id -eq 55)) { $st.severeDiskEvents++ } }
    $tempSize = 0
    try { $tempSize = (Get-ChildItem -Path $env:TEMP -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch { }
    $st.userTempGB = GB $tempSize
    $sd = 0
    try { $sd = (Get-ChildItem -Path "$env:SystemRoot\SoftwareDistribution\Download" -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch { }
    $st.updateCacheGB = GB $sd
    $st.windowsOld = Test-Path "$env:SystemDrive\Windows.old"
}

function Collect-Thermal {
    $th = $script:D.thermal
    $loads = @(); $perf = @(); $temps = @()
    for ($i = 0; $i -lt $script:ThermalSamples; $i++) {
        $p = (Cim 'Win32_PerfFormattedData_PerfOS_Processor' $null "Name='_Total'")
        if ($p.Count -gt 0) { $loads += [int]$p[0].PercentProcessorTime }
        $pi = (Cim 'Win32_PerfFormattedData_Counters_ProcessorInformation' $null "Name='_Total'")
        if ($pi.Count -gt 0 -and $null -ne $pi[0].PercentProcessorPerformance) { $perf += [int]$pi[0].PercentProcessorPerformance }
        $best = $null
        foreach ($z in (Cim 'Win32_PerfFormattedData_Counters_ThermalZoneInformation')) {
            $c = $null
            if ([double]$z.HighPrecisionTemperature -gt 0) { $c = [double]$z.HighPrecisionTemperature / 10 - 273.15 } elseif ([double]$z.Temperature -gt 0) { $c = [double]$z.Temperature - 273.15 }
            if ($null -ne $c -and $c -gt 15 -and $c -lt 115 -and ($null -eq $best -or $c -gt $best)) { $best = $c }
        }
        if ($null -eq $best) {
            foreach ($z in (Cim 'MSAcpi_ThermalZoneTemperature' 'root/WMI')) {
                $c = [double]$z.CurrentTemperature / 10 - 273.15
                if ($c -gt 15 -and $c -lt 115 -and ($null -eq $best -or $c -gt $best)) { $best = $c }
            }
        }
        if ($null -ne $best) { $temps += (R1 $best) }
        Start-Sleep -Seconds 1
    }
    $th.cpuLoadSamples = $loads
    $th.cpuPerfSamples = $perf
    $th.cpuTempSamples = $temps
    $th.cpuTempSource = ''
    if ($temps.Count -gt 0) { $th.cpuTempSource = 'ACPI-Thermalzone' }
    if ($temps.Count -eq 0) {
        $gz = Cim 'LENOVO_GAMEZONE_DATA' 'root/WMI'
        if ($gz.Count -gt 0) {
            try {
                $r = Invoke-CimMethod -InputObject $gz[0] -MethodName GetCPUTemp -ErrorAction Stop
                foreach ($n in @('Data', 'Value', 'Temp')) { if ($r.$n -gt 15 -and $r.$n -lt 115) { $th.cpuTempSamples = @([int]$r.$n); $th.cpuTempSource = 'Lenovo-Sensor'; break } }
                $g = Invoke-CimMethod -InputObject $gz[0] -MethodName GetGPUTemp -ErrorAction Stop
                foreach ($n in @('Data', 'Value', 'Temp')) { if ($g.$n -gt 15 -and $g.$n -lt 115) { $th.gpuTemp = [int]$g.$n; break } }
            } catch { }
        }
    }
    $th.cpuLoadAvg = $null; $th.cpuTempMax = $null; $th.cpuPerfAvg = $null
    if ($loads.Count) { $th.cpuLoadAvg = [int](($loads | Measure-Object -Average).Average) }
    if ($th.cpuTempSamples.Count) { $th.cpuTempMax = ($th.cpuTempSamples | Measure-Object -Maximum).Maximum }
    if ($perf.Count) { $th.cpuPerfAvg = [int](($perf | Measure-Object -Average).Average) }
    $smi = "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
    if (-not (Test-Path $smi)) { $smi = "$env:SystemRoot\System32\nvidia-smi.exe" }
    if (Test-Path $smi) {
        $out = & $smi --query-gpu=name,temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>$null
        if ($out) {
            $parts = ([string](@($out)[0])) -split ','
            if ($parts.Count -ge 3) { $th.gpuName = $parts[0].Trim(); $th.gpuTemp = [int]$parts[1].Trim(); $th.gpuLoad = [int]$parts[2].Trim() }
        }
    }
    $scheme = (& powercfg.exe /getactivescheme 2>$null) -join ' '
    if ($scheme -match '\((.+)\)') { $th.powerPlan = $Matches[1] }
    $th.throttleEvents = @(Get-Ev 'System' (XQ @('Microsoft-Windows-Kernel-Processor-Power') @(37) $Days) 50).Count
    $bat = Cim 'Win32_Battery'
    $th.onBattery = $false
    if ($bat.Count -gt 0) { $th.onBattery = ([int]$bat[0].BatteryStatus -eq 1) }
}

function Collect-Battery {
    $b = $script:D.battery
    $b.present = (Cim 'Win32_Battery').Count -gt 0
    if (-not $b.present) { return }
    $design = 0; $full = 0; $cycles = $null
    foreach ($x in (Cim 'BatteryStaticData' 'root/WMI')) { $design += [double]$x.DesignedCapacity }
    foreach ($x in (Cim 'BatteryFullChargedCapacity' 'root/WMI')) { $full += [double]$x.FullChargedCapacity }
    foreach ($x in (Cim 'BatteryCycleCount' 'root/WMI')) { if ([int]$x.CycleCount -gt 0) { $cycles = [int]$x.CycleCount } }
    # Ohne Adminrechte liefert root/WMI oft nichts: Akkubericht von powercfg geht auch so.
    if ($design -le 0 -or $full -le 0) {
        $tmp = Join-Path $env:TEMP ('SoluxBat-' + (Get-Random) + '.xml')
        & powercfg.exe /batteryreport /xml /output $tmp 2>$null | Out-Null
        $xml = ''
        try { $xml = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8 -ErrorAction Stop } catch { }
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        $d2 = 0; $f2 = 0
        foreach ($m in [regex]::Matches($xml, '<DesignCapacity>(\d+)<')) { $d2 += [double]$m.Groups[1].Value }
        foreach ($m in [regex]::Matches($xml, '<FullChargeCapacity>(\d+)<')) { $f2 += [double]$m.Groups[1].Value }
        if ($d2 -gt 0 -and $f2 -gt 0) { $design = $d2; $full = $f2 }
        if ($null -eq $cycles -and $xml -match '<CycleCount>(\d+)<' -and [int]$Matches[1] -gt 0) { $cycles = [int]$Matches[1] }
    }
    $b.designmWh = $design; $b.fullmWh = $full; $b.cycles = $cycles
    $b.healthPct = $null
    if ($design -gt 0 -and $full -gt 0) { $b.healthPct = R1 ($full / $design * 100) }
}

function Collect-Stability {
    $s = $script:D.stability
    $kp = @(Get-Ev 'System' (XQ @('Microsoft-Windows-Kernel-Power') @(41) $Days) 100)
    $s.kp41 = @()
    $s.powerButton = 0; $s.withBugcheck = 0; $s.inSleep = 0; $s.unexplained = 0
    foreach ($e in $kp) {
        $btn = [long]('0' + $e.Data['PowerButtonTimestamp'])
        $bc = [long]('0' + $e.Data['BugcheckCode'])
        $sl = [string]$e.Data['SleepInProgress']
        $kind = 'unklar'
        if ($btn -ne 0) { $kind = 'Knopf gehalten'; $s.powerButton++ }
        elseif ($bc -ne 0) { $kind = 'Bluescreen'; $s.withBugcheck++ }
        elseif ($sl -ne '' -and $sl -ne '0' -and $sl -ne 'false') { $kind = 'im Standby'; $s.inSleep++ }
        else { $s.unexplained++ }
        $s.kp41 += [ordered]@{ time = $e.Time; kind = $kind }
    }
    $s.unexpected6008 = @(Get-Ev 'System' (XQ @('EventLog') @(6008) $Days) 100).Count
    $bs = @(Get-Ev 'System' (XQ @('Microsoft-Windows-WER-SystemErrorReporting') @(1001) $Days) 50)
    $s.bsods = @()
    foreach ($e in $bs) {
        $code = ''
        $first = ''; if ($e.Values.Count -gt 0) { $first = [string]$e.Values[0] }
        if ($first -match '0x([0-9a-fA-F]+)') { $code = '0x' + $Matches[1] }
        $s.bsods += [ordered]@{ time = $e.Time; code = $code; text = (Explain-BugCheck $code) }
    }
    $wh = @(Get-Ev 'System' (XQ @('Microsoft-Windows-WHEA-Logger') @(1, 17, 18, 19, 20, 47) 30) 100)
    $s.wheaFatal = 0; $s.wheaCorrected = 0
    foreach ($e in $wh) { if ($e.Id -eq 1 -or $e.Id -eq 18 -or $e.Level -le 2) { $s.wheaFatal++ } else { $s.wheaCorrected++ } }
    $s.tdr = @(Get-Ev 'System' (XQ @('Display') @(4101) $Days) 100).Count
    $app = @(Get-Ev 'Application' (XQ @('Application Error') @(1000) $Days) 300)
    $hang = @(Get-Ev 'Application' (XQ @('Application Hang') @(1002) $Days) 300)
    $s.appCrashes = $app.Count; $s.appHangs = $hang.Count
    $byApp = @{}
    foreach ($e in ($app + $hang)) {
        $n = ''; if ($e.Values.Count -gt 0) { $n = [string]$e.Values[0] }
        if (-not $n) { continue }
        if ($byApp.ContainsKey($n)) { $byApp[$n]++ } else { $byApp[$n] = 1 }
    }
    $s.topApps = @()
    foreach ($k in ($byApp.Keys | Sort-Object { $byApp[$_] } -Descending | Select-Object -First 5)) { $s.topApps += [ordered]@{ app = $k; count = $byApp[$k] } }
    $rel = Cim 'Win32_ReliabilityStabilityMetrics'
    $s.stabilityIndex = $null
    if ($rel.Count -gt 0) {
        $last = $rel | Sort-Object TimeGenerated | Select-Object -Last 1
        $s.stabilityIndex = R1 $last.SystemStabilityIndex
    }
    $boot = @(Get-Ev 'Microsoft-Windows-Diagnostics-Performance/Operational' (XQ $null @(100) 30) 10)
    $s.bootSeconds = $null
    if ($boot.Count -gt 0 -and $boot[0].Data['BootTime']) { $s.bootSeconds = [int]([long]$boot[0].Data['BootTime'] / 1000) }
    $s.startupItems = @()
    foreach ($x in (Cim 'Win32_StartupCommand')) { $s.startupItems += [string]$x.Caption }
    $s.memDiag = ''
    $md = @(Get-Ev 'System' (XQ @('Microsoft-Windows-MemoryDiagnostics-Results') @(1201, 1202) 365) 1)
    if ($md.Count -gt 0) { if ($md[0].Id -eq 1201) { $s.memDiag = 'ohne Fehler (' + (DateDe $md[0].Time) + ')' } else { $s.memDiag = 'FEHLER gefunden (' + (DateDe $md[0].Time) + ')' } }
    $cc = RegVal 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' 'CrashDumpEnabled'
    $s.crashDumps = ($null -ne $cc -and [int]$cc -ne 0)
    $s.minidumps = @()
    try { foreach ($f in (Get-ChildItem "$env:SystemRoot\Minidump" -Filter *.dmp -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 10)) { $s.minidumps += [ordered]@{ file = $f.Name; time = $f.LastWriteTime } } } catch { }
}

function Collect-Updates {
    $u = $script:D.updates
    $ok = @(Get-Ev 'System' (XQ @('Microsoft-Windows-WindowsUpdateClient') @(19) 120) 1)
    $u.lastSuccess = $null
    if ($ok.Count -gt 0) { $u.lastSuccess = $ok[0].Time }
    $fail = @(Get-Ev 'System' (XQ @('Microsoft-Windows-WindowsUpdateClient') @(20) 30) 100)
    # Store-Apps (Titel beginnt mit 12-stelliger Produkt-ID) und Defender-Signaturen scheitern oft und holen sich selbst nach: nicht mitzählen.
    $u.failures = 0; $u.ignoredFailures = 0
    $names = @{}
    foreach ($e in $fail) {
        $n = [string]$e.Data['updateTitle']
        if ($n -cmatch '^[0-9A-Z]{12}-' -or $n -match 'KB2267602') { $u.ignoredFailures++; continue }
        $u.failures++
        if ($n) { if ($names.ContainsKey($n)) { $names[$n]++ } else { $names[$n] = 1 } }
    }
    $u.failedUpdates = @(); foreach ($k in $names.Keys) { $u.failedUpdates += [ordered]@{ title = $k; count = $names[$k] } }
    $svc = (Cim 'Win32_Service' $null "Name='wuauserv'")
    $u.serviceStart = ''; if ($svc.Count) { $u.serviceStart = [string]$svc[0].StartMode }
    $u.policyNoAutoUpdate = (RegVal 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate') -eq 1
}

function Collect-Security {
    $s = $script:D.security
    $s.av = @()
    foreach ($a in (Cim 'AntiVirusProduct' 'root/SecurityCenter2')) {
        $st = [int]$a.productState
        $hex = '{0:x6}' -f $st
        $s.av += [ordered]@{ name = [string]$a.displayName; enabled = ($hex.Substring(2, 2) -eq '10' -or $hex.Substring(2, 2) -eq '11'); upToDate = ($hex.Substring(4, 2) -eq '00') }
    }
    $s.defender = $null
    try {
        $m = Get-MpComputerStatus -ErrorAction Stop
        $s.defender = [ordered]@{
            realtime = [bool]$m.RealTimeProtectionEnabled; antivirusEnabled = [bool]$m.AntivirusEnabled
            sigAgeDays = [int]$m.AntivirusSignatureAge; quickScanAgeDays = [int]$m.QuickScanAge
            tamper = [bool]$m.IsTamperProtected; smartAppControl = [string]$m.SmartAppControlState; mode = [string]$m.AMRunningMode
        }
    } catch { }
    $s.threats = @()
    try {
        foreach ($t in (Get-MpThreatDetection -ErrorAction Stop | Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddDays(-30) })) {
            $s.threats += [ordered]@{ time = $t.InitialDetectionTime; id = [string]$t.ThreatID; status = [string]$t.ThreatStatusID }
        }
        $names = @{}
        foreach ($t in (Get-MpThreat -ErrorAction SilentlyContinue)) { $names[[string]$t.ThreatID] = [string]$t.ThreatName }
        foreach ($x in $s.threats) { if ($names.ContainsKey($x.id)) { $x.name = $names[$x.id] } }
    } catch { }
    $s.firewall = @()
    try { foreach ($f in (Get-NetFirewallProfile -ErrorAction Stop)) { $s.firewall += [ordered]@{ profile = [string]$f.Name; enabled = [bool]$f.Enabled } } } catch { }
    $s.uac = (RegVal 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA') -ne 0
    $sb = RegVal 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' 'UEFISecureBootEnabled'
    if ($null -eq $sb) { $s.secureBoot = 'nicht verfügbar (Legacy-BIOS)' } elseif ([int]$sb -eq 1) { $s.secureBoot = 'aktiv' } else { $s.secureBoot = 'aus' }
    $s.uefi = $null -ne $sb
    $tpm = Cim 'Win32_Tpm' 'root/CIMV2/Security/MicrosoftTpm'
    $s.tpm = 'unbekannt (Adminrechte nötig)'
    if ($tpm.Count -gt 0) { $s.tpm = (([string]$tpm[0].SpecVersion) -split ',')[0].Trim() }
    elseif ($script:IsAdmin) { $s.tpm = 'nicht vorhanden' }
    $s.bitlocker = 'unbekannt (Adminrechte nötig)'
    $bl = Cim 'Win32_EncryptableVolume' 'root/CIMV2/Security/MicrosoftVolumeEncryption' "DriveLetter='$env:SystemDrive'"
    if ($bl.Count -gt 0) {
        $conv = [int]$bl[0].ConversionStatus; $prot = [int]$bl[0].ProtectionStatus
        if ($conv -eq 0) { $s.bitlocker = 'nicht verschlüsselt' }
        elseif ($prot -eq 1) { $s.bitlocker = 'verschlüsselt und geschützt' }
        else { $s.bitlocker = 'verschlüsselt, Schutz AUS' }
    }
    $s.rdp = (RegVal 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections') -eq 0
    $s.smb1 = $null
    try { $s.smb1 = [bool](Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol } catch { }
    $s.memoryIntegrity = (RegVal 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled') -eq 1
}

function Collect-Software {
    $sw = $script:D.software
    $paths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
    $names = @()
    foreach ($p in $paths) {
        foreach ($i in (Get-ItemProperty -Path $p -ErrorAction SilentlyContinue)) {
            $n = [string]$i.DisplayName
            if ($n -and -not ($names -contains $n)) { $names += $n }
        }
    }
    $sw.count = $names.Count
    $sw.unwanted = @(); $sw.remote = @(); $sw.backupTools = @(); $sw.office = @()
    foreach ($n in $names) {
        if (Has $n $script:Unwanted) { $sw.unwanted += $n }
        if (Has $n $script:RemoteTools) { $sw.remote += $n }
        if (Has $n $script:BackupTools) { $sw.backupTools += $n }
        if ($n -match 'Microsoft Office .*(2010|2013|2016|2019)' -or $n -match 'Microsoft (Office|Word|Excel) (2010|2013|2016|2019)') { $sw.office += $n }
    }
    $sw.topMemory = @()
    foreach ($p in (Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending | Select-Object -First 5)) {
        $sw.topMemory += [ordered]@{ name = [string]$p.ProcessName; mb = [int]($p.WorkingSet64 / 1MB) }
    }
    $sw.topCpu = @()
    foreach ($p in ((Cim 'Win32_PerfFormattedData_PerfProc_Process') | Where-Object { $_.Name -ne '_Total' -and $_.Name -ne 'Idle' } | Sort-Object PercentProcessorTime -Descending | Select-Object -First 5)) {
        $sw.topCpu += [ordered]@{ name = [string]$p.Name; pct = [int]$p.PercentProcessorTime }
    }
}

function Collect-Backup {
    $b = $script:D.backup
    $docs = [string](RegVal 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders' 'Personal')
    $desk = [string](RegVal 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders' 'Desktop')
    $b.oneDriveSignedIn = $null -ne (RegVal 'HKCU:\Software\Microsoft\OneDrive\Accounts\Personal' 'UserEmail') -or $null -ne (RegVal 'HKCU:\Software\Microsoft\OneDrive\Accounts\Business1' 'UserEmail')
    $b.oneDriveFolders = ($docs -match 'OneDrive') -or ($desk -match 'OneDrive')
    $b.fileHistory = Test-Path "$env:LOCALAPPDATA\Microsoft\Windows\FileHistory\Configuration\Config1.xml"
    $b.tools = $script:D.software.backupTools
    $b.any = $b.oneDriveFolders -or $b.fileHistory -or ($b.tools.Count -gt 0)
}

function Collect-Network {
    $n = $script:D.network
    $gw = $null
    try { $r = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Sort-Object RouteMetric | Select-Object -First 1; $gw = [string]$r.NextHop } catch { }
    $n.gateway = $gw
    $n.adapters = @()
    try {
        foreach ($a in (Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })) {
            $n.adapters += [ordered]@{ name = [string]$a.Name; desc = [string]$a.InterfaceDescription; speed = [string]$a.LinkSpeed; media = [string]$a.PhysicalMediaType; driverDate = $a.DriverDate }
        }
    } catch { }
    $n.pings = @()
    foreach ($target in @($gw, '1.1.1.1')) {
        if (-not $target) { continue }
        $times = @(); $sent = $script:PingCount
        foreach ($p in @(Test-Connection -ComputerName $target -Count $sent -ErrorAction SilentlyContinue)) {
            if ($null -ne $p.ResponseTime -and [int]$p.StatusCode -eq 0) { $times += [int]$p.ResponseTime }
        }
        $avg = $null; $jit = $null
        if ($times.Count -gt 0) {
            $avg = R1 (($times | Measure-Object -Average).Average)
            $sum = 0; foreach ($t in $times) { $sum += ($t - $avg) * ($t - $avg) }
            $jit = R1 (Sqrt ($sum / $times.Count))
        }
        $loss = [int](($sent - $times.Count) * 100 / $sent)
        $kind = 'Internet'; if ($target -eq $gw) { $kind = 'Router' }
        $n.pings += [ordered]@{ target = $target; kind = $kind; avgMs = $avg; jitterMs = $jit; lossPct = $loss }
    }
    $n.dnsMs = $null; $n.dnsOk = $false
    try {
        $sw = Measure-Command { $null = Resolve-DnsName -Name 'www.microsoft.com' -DnsOnly -ErrorAction Stop }
        $n.dnsMs = [int]$sw.TotalMilliseconds; $n.dnsOk = $true
    } catch { }
    $n.dnsServers = @()
    try { foreach ($d in (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.ServerAddresses })) { foreach ($a in $d.ServerAddresses) { if (-not ($n.dnsServers -contains $a)) { $n.dnsServers += [string]$a } } } } catch { }
    $wl = (& netsh.exe wlan show interfaces 2>$null)
    $n.wlan = $null
    if ($wl) {
        $w = [ordered]@{}
        foreach ($line in $wl) {
            $l = [string]$line
            if ($l -match '^\s*Signal\s*:\s*(\d+)\s*%') { $w.signal = [int]$Matches[1] }
            elseif ($l -match '^\s*(Funktyp|Radio type)\s*:\s*(.+)$') { $w.standard = $Matches[2].Trim() }
            elseif ($l -match '^\s*(Band)\s*:\s*(.+)$') { $w.band = $Matches[2].Trim() }
            elseif ($l -match '^\s*(Kanal|Channel)\s*:\s*(\d+)') { $w.channel = [int]$Matches[2] }
            elseif ($l -match '^\s*(Empfangsrate \(MBit/s\)|Receive rate \(Mbps\))\s*:\s*([\d\.,]+)') { $w.rxMbps = $Matches[2] }
            elseif ($l -match '^\s*(Status|State)\s*:\s*(.+)$') { $w.state = $Matches[2].Trim() }
        }
        if ($null -ne $w['signal']) {
            if ($null -eq $w['band'] -and $null -ne $w['channel']) { if ($w.channel -le 14) { $w.band = '2,4 GHz' } else { $w.band = '5 GHz oder höher' } }
            $n.wlan = $w
        }
    }
    $n.wlanDrops = @(Get-Ev 'Microsoft-Windows-WLAN-AutoConfig/Operational' (XQ $null @(8003) $Days) 300).Count
    $n.proxy = $null
    if ((RegVal 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' 'ProxyEnable') -eq 1) { $n.proxy = [string](RegVal 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' 'ProxyServer') }
    $n.hostsEntries = @()
    try {
        foreach ($l in (Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" -ErrorAction Stop)) {
            $t = ([string]$l).Trim()
            if ($t -eq '' -or $t.StartsWith('#')) { continue }
            if ($t -match 'localhost$') { continue }
            $n.hostsEntries += $t
        }
    } catch { }
    $n.printers = @()
    foreach ($p in (Cim 'Win32_Printer')) {
        if ([string]$p.Name -match 'PDF|XPS|OneNote|Fax') { continue }
        $n.printers += [ordered]@{ name = [string]$p.Name; default = [bool]$p.Default; offline = [bool]$p.WorkOffline }
    }
}
function Sqrt($x) {
    # Newton-Verfahren: [math]::Sqrt ist im eingeschränkten Modus nicht aufrufbar.
    $x = [double]$x
    if ($x -le 0) { return 0 }
    $g = $x
    for ($i = 0; $i -lt 30; $i++) { $g = ($g + $x / $g) / 2 }
    $g
}

function Collect-Win11 {
    $w = $script:D.win11
    $sys = $script:D.system
    if (-not $sys.isWin10) { $w.applicable = $false; return }
    $w.applicable = $true
    $cpu = [string]$script:D.hardware.cpu
    $cpuOk = $null
    if ($cpu -match 'Core\(TM\) Ultra|Core Ultra') { $cpuOk = $true }
    elseif ($cpu -match 'i[3579]-(\d{4,5})') { $num = $Matches[1]; if ($num.Length -eq 5) { $gen = [int]$num.Substring(0, 2) } else { $gen = [int]$num.Substring(0, 1) }; $cpuOk = $gen -ge 8 }
    elseif ($cpu -match 'Ryzen \d (PRO )?(\d)\d{3}') { $cpuOk = [int]$Matches[2] -ge 2 }
    elseif ($cpu -match 'Celeron|Pentium|Atom|FX-|A[4-9]-|Phenom|Core\(TM\)2') { $cpuOk = $false }
    $w.cpu = $cpuOk
    $w.tpm2 = $null
    if ($script:D.security.tpm -match '^2') { $w.tpm2 = $true } elseif ($script:D.security.tpm -match '^1|nicht vorhanden') { $w.tpm2 = $false }
    $w.uefi = $script:D.security.uefi
    $w.ram = $script:D.hardware.ramGB -ge 4
    $sysVol = $null; foreach ($v in $script:D.storage.volumes) { if ($v.drive -eq $env:SystemDrive) { $sysVol = $v } }
    $w.disk = $null; if ($sysVol) { $w.disk = $sysVol.sizeGB -ge 64 }
    $w.ready = $null
    if ($w.cpu -eq $false -or $w.tpm2 -eq $false -or $w.uefi -eq $false -or $w.ram -eq $false -or $w.disk -eq $false) { $w.ready = $false }
    elseif ($w.cpu -eq $true -and $w.tpm2 -eq $true -and $w.uefi -eq $true -and $w.ram -and $w.disk) { $w.ready = $true }
}

# ---------------------------------------------------------------------------
# Bewertung
# ---------------------------------------------------------------------------
function Evaluate {
    $script:Findings = @()
    $now = Get-Date
    $sys = $script:D.system; $hw = $script:D.hardware; $st = $script:D.storage; $th = $script:D.thermal
    $bt = $script:D.battery; $sb = $script:D.stability; $up = $script:D.updates; $se = $script:D.security
    $nw = $script:D.network; $sw = $script:D.software; $bk = $script:D.backup; $w11 = $script:D.win11

    # --- Windows-Version
    if ($sys.isWin10) {
        $txt = 'Windows 10 erhält seit 14.10.2025 nur noch mit ESU-Verlängerung Sicherheitsupdates, längstens bis 12.10.2027.'
        if ($w11.ready -eq $true) { $txt += ' Das Gerät erfüllt die Windows-11-Anforderungen.' }
        elseif ($w11.ready -eq $false) { $txt += ' Das Gerät erfüllt die Windows-11-Anforderungen nicht.' }
        else { $txt += ' Windows-11-Fähigkeit nicht vollständig prüfbar.' }
        $svc = 'win11'; if ($w11.ready -eq $false) { $svc = 'newpc' }
        Add-Finding 'Windows' 'warnung' 'Windows 10 läuft aus' $txt 'Ihr Windows 10 bekommt nur noch mit Verlängerung Sicherheitsupdates und spätestens ab Oktober 2027 gar keine mehr.' $svc 'in den nächsten Wochen'
    }
    elseif ($sys.supportEnd) {
        $daysLeft = [int](([datetime]$sys.supportEnd) - $now).TotalDays
        if ($daysLeft -lt 0) {
            Add-Finding 'Windows' 'kritisch' ('Windows-Version ' + $sys.displayVersion + ' ohne Support') ('Support endete am ' + (DateDe $sys.supportEnd) + '. Funktionsupdate installieren.') 'Ihre Windows-Version bekommt keine Sicherheitsupdates mehr. Ein kostenloses Upgrade behebt das.' 'updates' 'jetzt'
        } elseif ($daysLeft -lt 180) {
            Add-Finding 'Windows' 'hinweis' ('Support für ' + $sys.displayVersion + ' endet bald') ('Support endet am ' + (DateDe $sys.supportEnd) + '.') ('Ihre Windows-Version wird noch bis ' + (DateDe $sys.supportEnd) + ' unterstützt.') $null 'bei Gelegenheit'
        }
    }
    if ($sys.insider) { Add-Finding 'Windows' 'hinweis' 'Insider-Build' 'Windows-Insider-Kanal aktiv; Supportdaten gelten nicht.' '' $null '' }
    if ($sys.activated -eq $false) { Add-Finding 'Windows' 'warnung' 'Windows nicht aktiviert' 'Keine aktivierte Windows-Lizenz gefunden.' 'Windows ist nicht aktiviert.' 'security' 'in den nächsten Wochen' }
    if ($sys.uptimeDays -ge $T.UptimeDays) {
        $extra = ''; if ($sys.fastStartup) { $extra = ' Schnellstart ist aktiv: Herunterfahren zählt nicht als Neustart.' }
        Add-Finding 'Windows' 'hinweis' ('Seit ' + (Num $sys.uptimeDays) + ' Tagen kein Neustart') ('Laufzeit seit letztem Kernel-Start.' + $extra) 'Ihr PC wurde lange nicht neu gestartet. Ein Neustart behebt viele kleine Probleme.' $null 'bei Gelegenheit'
    }
    if ($sys.pendingReboot) { Add-Finding 'Updates' 'hinweis' 'Neustart ausstehend' 'Windows Update oder CBS wartet auf einen Neustart.' 'Windows wartet auf einen Neustart, um Updates abzuschließen.' $null 'bei Gelegenheit' }

    # --- Speicher
    foreach ($v in $st.volumes) {
        if ($v.drive -ne $env:SystemDrive -and $v.drive -ne 'C:') { continue }
        if ($v.freeGB -lt $T.FreeCritGB) { Add-Finding 'Speicher' 'kritisch' ('Laufwerk ' + $v.drive + ' fast voll') ('' + (Num $v.freeGB) + ' GB frei von ' + (Num $v.sizeGB) + ' GB.') 'Ihre Festplatte ist fast voll. Updates können scheitern und der PC wird langsam.' 'cleanup' 'jetzt' }
        elseif ($v.freeGB -lt $T.FreeWarnGB -or $v.freePct -lt $T.FreeWarnPct) { Add-Finding 'Speicher' 'warnung' ('Wenig Platz auf ' + $v.drive) ('' + (Num $v.freeGB) + ' GB frei (' + (Num $v.freePct) + ' %).') 'Auf Ihrer Festplatte wird der Platz knapp.' 'cleanup' 'in den nächsten Wochen' }
    }
    foreach ($d in $st.disks) {
        $nm = $d.name; if ($d.external) { $nm += ' (extern)' }
        if ($d.health -and $d.health -ne 'Healthy' -and $d.health -ne 'Fehlerfrei') { Add-Finding 'Datenträger' 'kritisch' ('Laufwerk meldet Problem: ' + $nm) ('HealthStatus: ' + $d.health) 'Ein Laufwerk meldet einen Defekt. Bitte sichern Sie Ihre Daten so bald wie möglich.' 'disk' 'jetzt' }
        if ($null -ne $d.wear) {
            if ($d.wear -ge $T.WearCrit) { Add-Finding 'Datenträger' 'kritisch' ('SSD verschlissen: ' + $nm) ('Verbrauchte Lebensdauer ' + $d.wear + ' %.') 'Ihre SSD hat ihre geplante Lebensdauer fast erreicht.' 'disk' 'jetzt' }
            elseif ($d.wear -ge $T.WearWarn) { Add-Finding 'Datenträger' 'warnung' ('SSD-Verschleiß hoch: ' + $nm) ('Verbrauchte Lebensdauer ' + $d.wear + ' %.') 'Ihre SSD ist stark beansprucht. Ein Austausch sollte eingeplant werden.' 'disk' 'in den nächsten Wochen' }
        }
        if ($d.readErrors -gt 0) { Add-Finding 'Datenträger' 'warnung' ('Lesefehler: ' + $nm) ('' + $d.readErrors + ' nicht korrigierbare Lesefehler.') 'Ein Laufwerk hatte Lesefehler.' 'disk' 'in den nächsten Wochen' }
        # TemperatureMax ist bei NVMe meist der Warn-Grenzwert des Herstellers, kein Messwert: nur die aktuelle Temperatur bewerten.
        if ($d.temp -ge $T.DiskTempWarn) { Add-Finding 'Datenträger' 'hinweis' ('Laufwerk heiß: ' + $nm) ('Aktuell ' + $d.temp + ' °C (Grenzwert laut Laufwerk: ' + (OrUnknown $d.tempMax ' °C') + ').') '' $null '' }
    }
    if ($st.severeDiskEvents -gt 0) {
        $sev = 'warnung'; if ($st.severeDiskEvents -ge 5) { $sev = 'kritisch' }
        Add-Finding 'Datenträger' $sev 'Festplattenfehler im Ereignisprotokoll' ('' + $st.severeDiskEvents + ' schwere Ereignisse (disk 7/51/154, Ntfs 55) in 30 Tagen. Zuordnung zum Laufwerk vor Ort prüfen.') 'Windows hat Fehler beim Lesen oder Schreiben auf ein Laufwerk festgestellt.' 'disk' 'jetzt'
    }
    if ($st.userTempGB -ge $T.TempJunkGB) { Add-Finding 'Speicher' 'hinweis' ('' + (Num $st.userTempGB) + ' GB temporäre Dateien') 'Benutzer-Temp-Ordner.' ('Auf Ihrem PC liegen ' + (Num $st.userTempGB) + ' GB überflüssige Dateien.') 'cleanup' 'bei Gelegenheit' }

    # --- Temperatur
    $load = $th.cpuLoadAvg
    if ($null -ne $th.cpuTempMax -and $null -ne $load) {
        if (($load -ge 50 -and $th.cpuTempMax -ge $T.CpuHotLoad) -or ($load -lt 30 -and $th.cpuTempMax -ge $T.CpuHotIdle)) {
            Add-Finding 'Kühlung' 'warnung' ('Prozessor heiß: ' + (Num $th.cpuTempMax) + ' °C bei ' + $load + ' % Last') ('Quelle: ' + $th.cpuTempSource + '. Lüfter und Kühlkörper prüfen.') 'Ihr PC wird ungewöhnlich warm. Eine Innenreinigung senkt Temperatur und Lautstärke.' 'clean' 'in den nächsten Wochen'
        }
    }
    if ($null -ne $th.cpuPerfAvg -and $null -ne $load -and $load -ge 50 -and $th.cpuPerfAvg -lt 70 -and -not $th.onBattery -and ([string]$th.powerPlan) -notmatch 'Energiespar|saver') {
        Add-Finding 'Kühlung' 'hinweis' 'Prozessor taktet unter Last herunter' ('Leistung im Mittel ' + $th.cpuPerfAvg + ' % bei ' + $load + ' % Last, Netzbetrieb. Mögliche Drosselung, Temperatur vor Ort prüfen.') '' $null ''
    }
    if ($th.gpuTemp -ge $T.GpuHot) { Add-Finding 'Kühlung' 'warnung' ('Grafikkarte heiß: ' + $th.gpuTemp + ' °C') ('Last ' + $th.gpuLoad + ' %.') 'Die Grafikkarte wird sehr warm.' 'clean' 'in den nächsten Wochen' }
    $maxHours = 0; foreach ($d in $st.disks) { if (-not $d.external -and $d.hours -gt $maxHours) { $maxHours = $d.hours } }
    $hasHeatFinding = $false; foreach ($f in $script:Findings) { if ($f.service -eq 'clean') { $hasHeatFinding = $true } }
    if (-not $hasHeatFinding -and $maxHours -ge $T.CleanHours) {
        Add-Finding 'Kühlung' 'hinweis' 'Vorbeugende Innenreinigung' ('Systemlaufwerk ' + $maxHours + ' Betriebsstunden.') ('Ihr PC war schon über ' + $maxHours + ' Stunden in Betrieb. Eine Reinigung beugt Überhitzung vor.') 'clean' 'bei Gelegenheit'
    }

    # --- Akku
    if ($bt.present -and $null -ne $bt.healthPct) {
        if ($bt.healthPct -lt $T.BattCrit) { Add-Finding 'Akku' 'warnung' ('Akku nur noch ' + (Num $bt.healthPct) + ' %') ('Volle Ladung ' + (Num $bt.fullmWh) + ' von ' + (Num $bt.designmWh) + ' mWh.') ('Ihr Akku hat nur noch ' + (Num $bt.healthPct) + ' % seiner ursprünglichen Kapazität.') 'battery' 'in den nächsten Wochen' }
        elseif ($bt.healthPct -lt $T.BattWarn) { Add-Finding 'Akku' 'hinweis' ('Akku bei ' + (Num $bt.healthPct) + ' %') 'Normale Alterung, beobachten.' '' $null '' }
    }

    # --- Stabilität
    if ($sb.powerButton -gt 0) { Add-Finding 'Stabilität' 'hinweis' ('' + $sb.powerButton + '× per Ein/Aus-Taste ausgeschaltet') ('Kernel-Power 41 mit PowerButtonTimestamp in ' + $Days + ' Tagen. Meist hängt der PC vorher.') 'Ihr PC wurde mehrfach durch langes Drücken des Einschaltknopfs ausgeschaltet.' 'stability' 'in den nächsten Wochen' }
    if ($sb.unexplained -ge 2) { Add-Finding 'Stabilität' 'warnung' ('' + $sb.unexplained + '× plötzlich ausgegangen') 'Kernel-Power 41 ohne Bluescreen, ohne Taste, nicht im Standby: Stromversorgung, Netzteil oder Überhitzung prüfen.' 'Ihr PC ist mehrfach ohne Vorwarnung ausgegangen.' 'stability' 'jetzt' }
    $nb = $sb.bsods.Count
    if ($nb -gt 0) {
        $codes = @(); foreach ($b in $sb.bsods) { if (-not ($codes -contains $b.text)) { $codes += $b.text } }
        $sev = 'hinweis'; $title = 'Einmaliger Absturz (Bluescreen)'
        if ($nb -ge $T.BsodCrit) { $sev = 'kritisch'; $title = '' + $nb + ' Bluescreens' } elseif ($nb -ge $T.BsodWarn) { $sev = 'warnung'; $title = '' + $nb + ' Bluescreens' }
        $cust = 'Ihr PC ist abgestürzt (Bluescreen).'; if ($nb -ge 2) { $cust = 'Ihr PC ist in den letzten ' + $Days + ' Tagen ' + $nb + '-mal abgestürzt.' }
        $svc = $null; if ($nb -ge 2) { $svc = 'stability' }
        Add-Finding 'Stabilität' $sev $title ($codes -join '; ') $cust $svc 'jetzt'
    }
    if ($sb.wheaFatal -gt 0) { Add-Finding 'Stabilität' 'kritisch' 'Schwerer Hardwarefehler gemeldet (WHEA)' ('' + $sb.wheaFatal + ' nicht korrigierbare WHEA-Ereignisse in 30 Tagen.') 'Die Hardware hat einen schweren Fehler gemeldet.' 'stability' 'jetzt' }
    elseif ($sb.wheaCorrected -ge 10) { Add-Finding 'Stabilität' 'hinweis' ('' + $sb.wheaCorrected + ' korrigierte Hardwarefehler') 'WHEA 17/19/47; Quelle (PCIe/CPU) im Ereignisprotokoll prüfen.' '' $null '' }
    if ($sb.tdr -ge $T.TdrWarn) { Add-Finding 'Stabilität' 'warnung' ('Grafiktreiber ' + $sb.tdr + '× neu gestartet') 'Display 4101 (TDR).' 'Der Grafiktreiber ist mehrfach abgestürzt; der Bildschirm wird dabei kurz schwarz.' 'driver' 'in den nächsten Wochen' }
    if ($sb.appCrashes -ge $T.AppCrashWarn -or $sb.appHangs -ge $T.AppHangWarn) {
        $top = @(); foreach ($a in $sb.topApps) { $top += ($a.app + ' (' + $a.count + ')') }
        Add-Finding 'Stabilität' 'warnung' ('' + $sb.appCrashes + ' Programmabstürze, ' + $sb.appHangs + ' hängende Programme') ($top -join ', ') 'Programme stürzen häufig ab oder reagieren nicht.' 'stability' 'in den nächsten Wochen'
    }
    if ($null -ne $sb.stabilityIndex -and $sb.stabilityIndex -lt $T.StabilityWarn) { Add-Finding 'Stabilität' 'warnung' ('Zuverlässigkeitsindex ' + (Num $sb.stabilityIndex) + ' von 10') 'Win32_ReliabilityStabilityMetrics, letzter Wert.' 'Windows bewertet die Stabilität Ihres PCs als niedrig.' 'stability' 'in den nächsten Wochen' }
    if ($sb.memDiag -match 'FEHLER') { Add-Finding 'Stabilität' 'kritisch' 'Speicherdiagnose meldet Fehler' $sb.memDiag 'Der Arbeitsspeicher hat einen Test nicht bestanden.' 'ram' 'jetzt' }
    if ($sb.bootSeconds -ge $T.BootWarnSec) { Add-Finding 'Leistung' 'warnung' ('Start dauert ' + $sb.bootSeconds + ' s') ('Diagnostics-Performance 100; ' + $sb.startupItems.Count + ' Autostart-Einträge.') ('Ihr PC braucht ' + $sb.bootSeconds + ' Sekunden zum Starten.') 'startup' 'bei Gelegenheit' }
    elseif ($sb.startupItems.Count -ge $T.StartupWarn) { Add-Finding 'Leistung' 'hinweis' ('' + $sb.startupItems.Count + ' Programme im Autostart') ($sb.startupItems -join ', ') 'Viele Programme starten automatisch mit und bremsen den Start.' 'startup' 'bei Gelegenheit' }
    if ($hw.problemDevices.Count -gt 0) {
        $l = @(); foreach ($p in $hw.problemDevices) { $l += ($p.name + ': ' + $p.text) }
        Add-Finding 'Hardware' 'warnung' ('' + $hw.problemDevices.Count + ' Geräte mit Fehler') ($l -join '; ') 'Mindestens ein Gerät funktioniert nicht richtig.' 'driver' 'in den nächsten Wochen'
    }
    if ($hw.ramGB -and $hw.ramGB -lt $T.RamLowGB) { Add-Finding 'Hardware' 'hinweis' ('Nur ' + $hw.ramGB + ' GB Arbeitsspeicher') 'Für Windows 11 mit Browser und Office knapp.' 'Mehr Arbeitsspeicher würde Ihren PC spürbar beschleunigen.' 'ram' 'bei Gelegenheit' }
    if ($hw.ramModules.Count -eq 1 -and $hw.ramSlots -ge 2) { Add-Finding 'Hardware' 'hinweis' 'Arbeitsspeicher nur einkanalig' ('1 Modul bei ' + $hw.ramSlots + ' Steckplätzen: halbe Speicherbandbreite.') '' 'ram' 'bei Gelegenheit' }

    # --- Updates
    if ($up.serviceStart -eq 'Disabled') { Add-Finding 'Updates' 'kritisch' 'Windows-Update-Dienst deaktiviert' 'wuauserv Starttyp Disabled.' 'Windows Update ist abgeschaltet. Ihr PC bekommt keine Sicherheitsupdates.' 'updates' 'jetzt' }
    if ($up.policyNoAutoUpdate) { Add-Finding 'Updates' 'warnung' 'Automatische Updates per Richtlinie aus' 'NoAutoUpdate = 1.' 'Automatische Updates sind abgeschaltet.' 'updates' 'in den nächsten Wochen' }
    if ($null -eq $up.lastSuccess) { Add-Finding 'Updates' 'warnung' 'Keine erfolgreiche Update-Installation in 120 Tagen' 'Kein WindowsUpdateClient-19-Ereignis gefunden.' 'Auf Ihrem PC wurden seit Monaten keine Updates installiert.' 'updates' 'jetzt' }
    elseif (($now - [datetime]$up.lastSuccess).TotalDays -gt $T.UpdateAgeDays) { Add-Finding 'Updates' 'warnung' ('Letztes Update am ' + (DateDe $up.lastSuccess)) 'Länger als 45 Tage keine Installation.' 'Ihr PC hat länger keine Updates installiert.' 'updates' 'in den nächsten Wochen' }
    if ($up.failures -ge $T.UpdateFailWarn) {
        $l = @(); foreach ($x in $up.failedUpdates) { $l += ($x.title + ' (' + $x.count + '×)') }
        Add-Finding 'Updates' 'warnung' ('' + $up.failures + ' fehlgeschlagene Update-Installationen') ($l -join '; ') 'Updates scheitern wiederholt.' 'updates' 'in den nächsten Wochen'
    }

    # --- Sicherheit
    $active = @(); foreach ($a in $se.av) { if ($a.enabled) { $active += $a } }
    if ($se.av.Count -gt 0 -and $active.Count -eq 0) { Add-Finding 'Sicherheit' 'kritisch' 'Kein aktiver Virenschutz' 'SecurityCenter2 meldet kein aktives Produkt.' 'Ihr PC hat keinen aktiven Virenschutz.' 'security' 'jetzt' }
    if ($active.Count -gt 1) { $l = @(); foreach ($a in $active) { $l += $a.name }; Add-Finding 'Sicherheit' 'warnung' 'Mehrere Virenscanner aktiv' ($l -join ', ') 'Zwei Virenscanner gleichzeitig bremsen den PC und stören sich gegenseitig.' 'security' 'in den nächsten Wochen' }
    foreach ($a in $se.av) { if (-not $a.upToDate -and $a.enabled) { Add-Finding 'Sicherheit' 'warnung' ('Virenschutz veraltet: ' + $a.name) 'productState meldet veraltete Signaturen oder abgelaufene Lizenz.' ('Ihr Virenschutz (' + $a.name + ') ist nicht aktuell.') 'security' 'jetzt' } }
    if ($se.defender -and $se.defender.mode -match 'Normal') {
        if (-not $se.defender.realtime) { Add-Finding 'Sicherheit' 'kritisch' 'Defender-Echtzeitschutz aus' 'RealTimeProtectionEnabled = False.' 'Der Echtzeitschutz von Windows ist ausgeschaltet.' 'security' 'jetzt' }
        if ($se.defender.sigAgeDays -ge 65535) { Add-Finding 'Sicherheit' 'kritisch' 'Defender-Signaturen nie aktualisiert' 'AntivirusSignatureAge = 65535.' 'Der Virenschutz wurde nie aktualisiert.' 'security' 'jetzt' }
        elseif ($se.defender.sigAgeDays -gt $T.SigAgeWarn) { Add-Finding 'Sicherheit' 'warnung' ('Defender-Signaturen ' + $se.defender.sigAgeDays + ' Tage alt') 'AntivirusSignatureAge.' 'Der Virenschutz ist nicht aktuell.' 'security' 'in den nächsten Wochen' }
    }
    if ($se.threats.Count -gt 0) {
        $l = @(); foreach ($t in $se.threats) { $nm = $t.id; if ($t.name) { $nm = $t.name }; $l += ($nm + ' am ' + (DateDe $t.time)) }
        Add-Finding 'Sicherheit' 'warnung' ('' + $se.threats.Count + ' Bedrohungen in 30 Tagen erkannt') ($l -join '; ') 'Der Virenschutz hat Schadsoftware gefunden. Wir prüfen, ob alles entfernt wurde.' 'security' 'jetzt'
    }
    foreach ($f in $se.firewall) { if (-not $f.enabled -and $f.profile -ne 'Domain') { Add-Finding 'Sicherheit' 'warnung' ('Firewall aus (' + $f.profile + ')') 'NetFirewallProfile Enabled = False.' 'Die Windows-Firewall ist teilweise ausgeschaltet.' 'security' 'jetzt' } }
    if (-not $se.uac) { Add-Finding 'Sicherheit' 'warnung' 'Benutzerkontensteuerung aus' 'EnableLUA = 0.' 'Ein wichtiger Windows-Schutz (Benutzerkontensteuerung) ist ausgeschaltet.' 'security' 'jetzt' }
    if ($se.bitlocker -eq 'verschlüsselt, Schutz AUS') { Add-Finding 'Sicherheit' 'warnung' 'BitLocker angehalten oder ungeschützt' 'Laufwerk verschlüsselt, ProtectionStatus 0: Schlüssel liegt ungeschützt vor.' 'Ihre Festplattenverschlüsselung ist pausiert und schützt gerade nicht.' 'security' 'in den nächsten Wochen' }
    if ($se.bitlocker -eq 'verschlüsselt und geschützt') { Add-Finding 'Sicherheit' 'hinweis' 'BitLocker aktiv: Wiederherstellungsschlüssel?' 'Ort des Wiederherstellungsschlüssels mit Kunden klären (Microsoft-Konto, Ausdruck).' 'Ihre Festplatte ist verschlüsselt. Wissen Sie, wo Ihr Wiederherstellungsschlüssel liegt? Ohne ihn sind Daten nach einer Reparatur verloren.' $null 'bei Gelegenheit' }
    if ($se.secureBoot -eq 'aus') { Add-Finding 'Sicherheit' 'hinweis' 'Secure Boot aus' 'UEFI vorhanden, Secure Boot deaktiviert.' '' $null '' }
    if ($se.rdp) { Add-Finding 'Sicherheit' 'hinweis' 'Remotedesktop aktiv' 'fDenyTSConnections = 0.' '' $null '' }
    if ($se.smb1) { Add-Finding 'Sicherheit' 'warnung' 'SMBv1 aktiv' 'Veraltetes Freigabeprotokoll.' '' 'security' 'bei Gelegenheit' }
    if ($sw.remote.Count -gt 0) { Add-Finding 'Sicherheit' 'hinweis' 'Fernwartungsprogramme installiert' ($sw.remote -join ', ') 'Auf Ihrem PC sind Fernwartungsprogramme installiert. Falls Sie diese nicht kennen, sprechen Sie uns bitte an.' 'security' 'bei Gelegenheit' }
    if ($sw.unwanted.Count -gt 0) { Add-Finding 'Software' 'warnung' ('' + $sw.unwanted.Count + ' unerwünschte Programme') ($sw.unwanted -join ', ') 'Es sind Programme installiert, die mehr schaden als nutzen (z. B. „Optimierer“).' 'cleanup' 'in den nächsten Wochen' }
    if ($sw.office.Count -gt 0) { Add-Finding 'Software' 'warnung' 'Office-Version ohne Support' ($sw.office -join ', ') 'Ihre Office-Version bekommt keine Sicherheitsupdates mehr.' 'office' 'in den nächsten Wochen' }

    # --- Datensicherung
    if (-not $bk.any) { Add-Finding 'Datensicherung' 'warnung' 'Keine automatische Datensicherung erkennbar' 'Weder OneDrive-Ordnersicherung noch Dateiversionsverlauf noch bekannte Backup-Software.' 'Wir finden keine automatische Sicherung Ihrer Daten. Bei einem Defekt wären Fotos und Dokumente weg.' 'backup' 'jetzt' }

    # --- Netzwerk
    $gwp = $null; $inet = $null
    foreach ($p in $nw.pings) { if ($p.kind -eq 'Router') { $gwp = $p } else { $inet = $p } }
    if ($gwp -and $gwp.lossPct -ge $T.PingLossWarn) { Add-Finding 'Netzwerk' 'warnung' ('Verbindung zum Router verliert ' + $gwp.lossPct + ' %') 'Paketverlust schon bis zum Gateway: WLAN/LAN-Problem im Haus.' 'Die Verbindung zwischen PC und Router ist instabil.' 'network' 'in den nächsten Wochen' }
    elseif ($inet -and $inet.lossPct -ge $T.PingLossWarn) { Add-Finding 'Netzwerk' 'warnung' ('Internet verliert ' + $inet.lossPct + ' %') 'Gateway stabil, Verlust dahinter: Anschluss oder Provider.' 'Ihre Internetleitung ist instabil; Ihr Heimnetz ist in Ordnung.' 'network' 'in den nächsten Wochen' }
    if ($inet -and $inet.avgMs -ge $T.LatencyWarn) { Add-Finding 'Netzwerk' 'hinweis' ('Hohe Latenz: ' + (Num $inet.avgMs) + ' ms') 'Ping 1.1.1.1.' '' 'network' '' }
    if ($inet -and $inet.jitterMs -ge $T.JitterWarn) { Add-Finding 'Netzwerk' 'hinweis' ('Schwankende Antwortzeiten (' + (Num $inet.jitterMs) + ' ms)') 'Standardabweichung der Pings; erklärt ruckelnde Videoanrufe.' 'Ihre Verbindung schwankt stark, was Videoanrufe stören kann.' 'network' 'bei Gelegenheit' }
    if (-not $nw.dnsOk -and $nw.gateway) { Add-Finding 'Netzwerk' 'warnung' 'Namensauflösung (DNS) fehlgeschlagen' ('DNS-Server: ' + ($nw.dnsServers -join ', ')) 'Internetadressen werden nicht zuverlässig aufgelöst.' 'network' 'jetzt' }
    elseif ($nw.dnsMs -ge $T.DnsWarnMs) { Add-Finding 'Netzwerk' 'hinweis' ('DNS langsam: ' + $nw.dnsMs + ' ms') ('DNS-Server: ' + ($nw.dnsServers -join ', ')) 'Webseiten starten verzögert.' 'network' 'bei Gelegenheit' }
    if ($nw.wlan) {
        if ($nw.wlan.signal -lt $T.WlanWeak) { Add-Finding 'Netzwerk' 'warnung' ('WLAN-Signal schwach: ' + $nw.wlan.signal + ' %') ('Band ' + $nw.wlan.band + ', Kanal ' + $nw.wlan.channel + '.') 'Ihr WLAN-Empfang ist schwach.' 'network' 'in den nächsten Wochen' }
        elseif ($nw.wlan.signal -lt $T.WlanMedium) { Add-Finding 'Netzwerk' 'hinweis' ('WLAN-Signal mäßig: ' + $nw.wlan.signal + ' %') ('Band ' + $nw.wlan.band + '.') '' 'network' '' }
        if ([string]$nw.wlan.band -match '2,4|2\.4') { Add-Finding 'Netzwerk' 'hinweis' 'WLAN im 2,4-GHz-Band' 'Langsameres, störanfälliges Band; 5 GHz prüfen.' '' 'network' '' }
    }
    if ($nw.wlanDrops -ge $T.WlanDropWarn) { Add-Finding 'Netzwerk' 'hinweis' ('' + $nw.wlanDrops + ' WLAN-Trennungen in ' + $Days + ' Tagen') 'WLAN-AutoConfig 8003.' 'Ihr WLAN bricht häufig ab.' 'network' 'bei Gelegenheit' }
    foreach ($a in $nw.adapters) { if ([string]$a.speed -match '^100 ?Mbps' -and [string]$a.media -match '802\.3') { Add-Finding 'Netzwerk' 'hinweis' ('LAN nur mit 100 Mbit/s: ' + $a.name) 'Kabel oder Port prüfen (sollte 1 Gbit/s sein).' '' 'network' '' } }
    if ($nw.proxy) { Add-Finding 'Netzwerk' 'hinweis' 'Proxy eingerichtet' $nw.proxy '' 'security' '' }
    if ($nw.hostsEntries.Count -gt 0) { Add-Finding 'Netzwerk' 'hinweis' ('' + $nw.hostsEntries.Count + ' Einträge in der hosts-Datei') ($nw.hostsEntries -join '; ') '' 'security' '' }
    foreach ($p in $nw.printers) { if ($p.default -and $p.offline) { Add-Finding 'Netzwerk' 'hinweis' ('Standarddrucker offline: ' + $p.name) '' 'Ihr Standarddrucker ist offline.' $null '' } }
}

$AreaRank = @{ 'Datenträger' = 0; 'Stabilität' = 1; 'Sicherheit' = 2; 'Datensicherung' = 3; 'Kühlung' = 4; 'Windows' = 5; 'Updates' = 6; 'Speicher' = 7; 'Akku' = 8; 'Hardware' = 9; 'Leistung' = 10; 'Software' = 11; 'Netzwerk' = 12 }
function Sort-Findings($list) {
    $sr = @{ 'kritisch' = 0; 'warnung' = 1; 'hinweis' = 2 }
    $list | Sort-Object @{ Expression = { $sr[$_.severity] } }, @{ Expression = { $script:AreaRank[$_.area] } }
}

function Get-Verdict {
    $k = 0; $w = 0
    foreach ($f in $script:Findings) { if ($f.severity -eq 'kritisch') { $k++ } elseif ($f.severity -eq 'warnung') { $w++ } }
    if ($k -gt 0) { return [ordered]@{ level = 'kritisch'; title = 'Handlungsbedarf'; text = 'Wir haben Probleme gefunden, die zeitnah behoben werden sollten.' } }
    if ($w -gt 0) { return [ordered]@{ level = 'warnung'; title = 'Wartung empfohlen'; text = 'Ihr PC läuft, aber einige Punkte sollten Sie angehen.' } }
    return [ordered]@{ level = 'ok'; title = 'Alles in Ordnung'; text = 'Wir haben keine nennenswerten Probleme gefunden.' }
}

function Get-Recommendations {
    $rank = @{ 'kritisch' = 0; 'warnung' = 1; 'hinweis' = 2 }
    $seen = @{}; $recs = @()
    foreach ($f in (Sort-Findings $script:Findings)) {
        if (-not $f.service -or $seen.ContainsKey($f.service)) { continue }
        if ($f.severity -eq 'hinweis' -and $f.service -ne 'clean' -and $f.service -ne 'ram') { continue }
        $seen[$f.service] = $true
        $s = $script:Services[$f.service]
        $recs += [ordered]@{ service = $f.service; title = $s.title; price = $s.price; urgency = $f.urgency; because = $f.title }
    }
    $recs
}


# ---------------------------------------------------------------------------
# Kundendialog, Vergleich, Versand
# ---------------------------------------------------------------------------
$SymptomInfo = [ordered]@{
    langsam   = @{ label = 'PC ist langsam';                 areas = @('Leistung', 'Speicher', 'Kühlung', 'Datenträger', 'Software', 'Hardware') }
    absturz   = @{ label = 'stürzt ab oder geht aus';         areas = @('Stabilität', 'Datenträger', 'Kühlung', 'Hardware') }
    heiss     = @{ label = 'laut oder heiß';                 areas = @('Kühlung', 'Leistung') }
    wlan      = @{ label = 'Internet oder WLAN macht Probleme'; areas = @('Netzwerk') }
    updates   = @{ label = 'Updates oder Fehlermeldungen';   areas = @('Updates', 'Windows', 'Sicherheit') }
    sonstiges = @{ label = 'Sonstiges';                      areas = @() }
}

function Clean($s, $max) {
    $t = ([string]$s) -replace '["`$;|&<>]', '' -replace '\s+', ' '
    $t = $t.Trim()
    if ($t.Length -gt $max) { $t = $t.Substring(0, $max) }
    $t
}

function Parse-Symptoms($text) {
    $keys = @($script:SymptomInfo.Keys)
    $out = @()
    foreach ($part in (([string]$text) -split '[,; ]+')) {
        $p = $part.Trim().ToLowerInvariant()
        if ($p -eq '') { continue }
        $k = $null
        if ($p -match '^\d+$') { $n = [int]$p; if ($n -ge 1 -and $n -le $keys.Count) { $k = $keys[$n - 1] } }
        elseif ($keys -contains $p) { $k = $p }
        if ($k -and -not ($out -contains $k)) { $out += $k }
    }
    $out
}

function Line($text, $color) { if ($color) { Write-Host ('   ' + $text) -ForegroundColor $color } else { Write-Host ('   ' + $text) } }

function Write-Banner {
    Write-Host ''
    Write-Host '   ==============================================================' -ForegroundColor DarkCyan
    Write-Host '    SOLUX IT  |  PC-Check' -ForegroundColor Cyan
    Write-Host ('    ' + $Solux.street + ', ' + $Solux.city + '  |  ' + $Solux.mail + $(if ($Config.Phone) { '  |  ' + $Config.Phone } else { '' })) -ForegroundColor Gray
    Write-Host '   ==============================================================' -ForegroundColor DarkCyan
    Write-Host ''
}

function Show-Intro {
    Write-Banner
    Line 'Dieses Programm prüft Ihren PC in etwa einer Minute und erstellt einen Bericht.'
    Line ''
    Line '  - Es liest nur Systeminformationen und verändert nichts.'
    Line '  - Persönliche Dateien, Passwörter und Browserverlauf werden nicht gelesen.'
    Line '  - Der Bericht bleibt auf Ihrem PC. Erst am Ende fragen wir,'
    Line '    ob er an Solux IT gesendet werden soll.'
    Line ''
    $null = Read-Host '   Weiter mit Enter (Abbrechen mit Strg+C)'
}

function Ask-Customer {
    Write-Host ''
    Line 'Damit wir den Bericht zuordnen können (alles freiwillig, Enter = überspringen):' 'Cyan'
    if (-not $script:CustName) { $script:CustName = Clean (Read-Host '   Ihr Name') 60 }
    if (-not $script:CustPhone) { $script:CustPhone = Clean (Read-Host '   Telefon für Rückfragen') 30 }
    if (-not $script:Symptoms) {
        Write-Host ''
        Line 'Was stört Sie an Ihrem PC? (mehrere mit Komma, z. B. 1,3)' 'Cyan'
        $i = 1
        foreach ($k in $script:SymptomInfo.Keys) { Line ('  ' + $i + '  ' + $script:SymptomInfo[$k].label); $i++ }
        $script:Symptoms = (Parse-Symptoms (Read-Host '   Auswahl')) -join ','
    }
}

function Ask-YesNo($question, $default) {
    $hint = '[J/n]'; if (-not $default) { $hint = '[j/N]' }
    $a = ([string](Read-Host ('   ' + $question + ' ' + $hint))).Trim().ToLowerInvariant()
    if ($a -eq '') { return [bool]$default }
    return ($a -eq 'j' -or $a -eq 'ja' -or $a -eq 'y' -or $a -eq 'yes')
}

function Get-SelfCopy {
    # Beim Einzeiler (irm | iex) gibt es keine Skriptdatei. Für den Neustart mit Adminrechten wird eine Kopie geladen.
    if ($PSCommandPath) { return $PSCommandPath }
    if (-not $Config.SelfUrl) { return $null }
    $target = Join-Path $env:TEMP 'SoluxCheck.ps1'
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    try {
        if (Test-Path $curl) { & $curl -sSfL -m 30 -o $target $Config.SelfUrl 2>$null }
        else { Invoke-WebRequest -Uri $Config.SelfUrl -OutFile $target -UseBasicParsing -ErrorAction Stop }
        if (Test-Path $target) {
            # Download ist UTF-8 ohne BOM; Windows PowerShell 5.1 braucht die BOM für Umlaute.
            $txt = Get-Content -LiteralPath $target -Raw -Encoding UTF8
            Set-Content -LiteralPath $target -Value $txt -Encoding UTF8
            return $target
        }
    } catch { }
    return $null
}

function VerParts($v) { $r = @(); foreach ($x in (([string]$v).Trim() -split '\.')) { $n = 0; if ($x -match '^\d+$') { $n = [int]$x }; $r += $n }; while ($r.Count -lt 3) { $r += 0 }; $r }
function Is-Newer($remote, $local) {
    $a = VerParts $remote; $b = VerParts $local
    for ($i = 0; $i -lt 3; $i++) { if ($a[$i] -gt $b[$i]) { return $true }; if ($a[$i] -lt $b[$i]) { return $false } }
    return $false
}
function Check-Version {
    if (-not $Config.VersionUrl) { return }
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (-not (Test-Path $curl)) { return }
    $v = [string](& $curl -sSf -m 5 $Config.VersionUrl 2>$null)
    if ($v -match '^\s*\d+(\.\d+){1,3}\s*$' -and (Is-Newer $v $ScriptVersion)) {
        Line ('Hinweis: Es gibt eine neuere Version (' + $v.Trim() + '). Bitte laden Sie den PC-Check bei Gelegenheit neu herunter.') 'Yellow'
    }
}

function Num0($x) { if ($null -eq $x -or [string]$x -eq '') { return $null }; [double]$x }
function Compare-Previous($dir) {
    $script:D.compare = $null
    if (-not $dir -or -not (Test-Path $dir)) { return }
    $files = @(Get-ChildItem -Path $dir -Filter 'Solux-PC-Check-*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    foreach ($f in $files) {
        $old = $null
        try { $old = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if ($null -eq $old -or $null -eq $old.data -or $old.reportId -eq $script:D.meta.reportId) { continue }
        $os = $old.data.system
        $same = ($os.serial -and [string]$os.serial -eq [string]$script:D.system.serial) -or ([string]$os.computerName -eq [string]$script:D.system.computerName)
        if (-not $same) { continue }
        $rows = @()
        $oldK = 0; $oldW = 0; foreach ($x in @($old.findings)) { if ($x.severity -eq 'kritisch') { $oldK++ } elseif ($x.severity -eq 'warnung') { $oldW++ } }
        $newK = 0; $newW = 0; foreach ($x in $script:Findings) { if ($x.severity -eq 'kritisch') { $newK++ } elseif ($x.severity -eq 'warnung') { $newW++ } }
        $rows += [ordered]@{ what = 'Probleme (kritisch + Warnungen)'; before = ($oldK + $oldW); now = ($newK + $newW); lowerIsBetter = $true; unit = '' }
        $oc = $null; foreach ($v in @($old.data.storage.volumes)) { if ($v.drive -eq 'C:') { $oc = $v.freeGB } }
        $nc = $null; foreach ($v in $script:D.storage.volumes) { if ($v.drive -eq 'C:') { $nc = $v.freeGB } }
        $rows += [ordered]@{ what = 'Freier Speicher C:'; before = (Num0 $oc); now = (Num0 $nc); lowerIsBetter = $false; unit = ' GB' }
        $rows += [ordered]@{ what = 'Temporäre Dateien'; before = (Num0 $old.data.storage.userTempGB); now = (Num0 $script:D.storage.userTempGB); lowerIsBetter = $true; unit = ' GB' }
        $rows += [ordered]@{ what = 'CPU-Temperatur (max)'; before = (Num0 $old.data.thermal.cpuTempMax); now = (Num0 $script:D.thermal.cpuTempMax); lowerIsBetter = $true; unit = ' °C' }
        $rows += [ordered]@{ what = 'Startdauer'; before = (Num0 $old.data.stability.bootSeconds); now = (Num0 $script:D.stability.bootSeconds); lowerIsBetter = $true; unit = ' s' }
        $rows += [ordered]@{ what = 'Programme im Autostart'; before = @($old.data.stability.startupItems).Count; now = $script:D.stability.startupItems.Count; lowerIsBetter = $true; unit = '' }
        $rows += [ordered]@{ what = 'Bluescreens im Zeitraum'; before = @($old.data.stability.bsods).Count; now = $script:D.stability.bsods.Count; lowerIsBetter = $true; unit = '' }
        $rows += [ordered]@{ what = 'Akku-Kapazität'; before = (Num0 $old.data.battery.healthPct); now = (Num0 $script:D.battery.healthPct); lowerIsBetter = $false; unit = ' %' }
        $rows += [ordered]@{ what = 'Zuverlässigkeitsindex'; before = (Num0 $old.data.stability.stabilityIndex); now = (Num0 $script:D.stability.stabilityIndex); lowerIsBetter = $false; unit = '' }
        $keep = @()
        foreach ($r in $rows) {
            if ($null -eq $r.before -or $null -eq $r.now) { continue }
            $r.trend = 'gleich'
            if ([double]$r.now -ne [double]$r.before) {
                $better = ([double]$r.now -lt [double]$r.before)
                if (-not $r.lowerIsBetter) { $better = -not $better }
                if ($better) { $r.trend = 'besser' } else { $r.trend = 'schlechter' }
            }
            $keep += $r
        }
        $when = $null; try { $when = [datetime]$old.data.meta.created } catch { }
        $script:D.compare = [ordered]@{ reportId = [string]$old.reportId; date = $when; verdictBefore = [string]$old.verdict.title; rows = $keep }
        return
    }
}

# Typografische Anführungszeichen sind in PowerShell selbst Quote-Zeichen, daher alle Zeichen per Code.
$AsciiCodes = @(0x00e4, 0x00f6, 0x00fc, 0x00c4, 0x00d6, 0x00dc, 0x00df, 0x00e9, 0x00e8, 0x00e0, 0x00e1, 0x00b0, 0x20ac, 0x2013, 0x2014, 0x201e, 0x201c, 0x201d, 0x201a, 0x2018, 0x2019, 0x00b7, 0x00d7, 0x2265, 0x2264, 0x2026, 0x00b2, 0x00b3, 0x00b5)

function To-AsciiJson($json) {
    # JSON ohne BOM und nur mit ASCII-Zeichen, damit jeder Empfänger (n8n, PHP) es sicher liest.
    $t = [string]$json
    foreach ($c in $script:AsciiCodes) { $t = $t.Replace([string][char]$c, ('\u' + ('{0:x4}' -f $c))) }
    $t -replace '[^\x00-\x7F]', '?'
}

function Build-Payload($verdict, $recs, $html) {
    $c = $script:D.customer
    $p = [ordered]@{
        schemaVersion = $SchemaVersion
        reportId = $script:D.meta.reportId
        created = $script:D.meta.created
        tool = 'SoluxCheck.ps1 ' + $ScriptVersion
        verdict = $verdict
        customer = $c
        device = [ordered]@{ manufacturer = $script:D.system.manufacturer; model = $script:D.system.model; serial = $script:D.system.serial; computerName = $script:D.system.computerName; os = ([string]$script:D.system.osName + ' ' + $script:D.system.displayVersion) }
        findings = $script:Findings
        recommendations = $recs
        report = $script:D
        html = $html
    }
    To-AsciiJson ($p | ConvertTo-Json -Depth 8)
}

function Send-Report($payloadPath) {
    $url = $Config.UploadUrl
    if (-not $url) { return $false }
    $size = (Get-Item -LiteralPath $payloadPath).Length
    if ($size -gt $Config.MaxUploadKB * 1KB) { return $false }
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (Test-Path $curl) {
        $code = [string](& $curl -sS -o NUL -w '%{http_code}' -m 60 -X POST -H ('X-Solux-Token: ' + $Config.UploadToken) -H 'Content-Type: application/json' --data-binary ('@' + $payloadPath) $url 2>$null)
        return ($code -match '^2\d\d$')
    }
    try {
        $null = Invoke-RestMethod -Uri $url -Method Post -InFile $payloadPath -ContentType 'application/json' -Headers @{ 'X-Solux-Token' = $Config.UploadToken } -TimeoutSec 60 -ErrorAction Stop
        return $true
    } catch { return $false }
}

function Open-MailFallback($folder, $selectPath) {
    $id = $script:D.meta.reportId
    $body = 'Hallo Solux-Team,%0D%0A%0D%0Ahier mein PC-Check ' + $id + '.%0D%0ADie Dateien liegen im Ordner: ' + $folder + '%0D%0ABitte beide Dateien (HTML und JSON) in diese Mail ziehen.%0D%0A'
    if ($script:D.customer.name) { $body += '%0D%0A' + $script:D.customer.name }
    if ($script:D.customer.phone) { $body += '%0D%0ATelefon: ' + $script:D.customer.phone }
    $uri = 'mailto:' + $Solux.mail + '?subject=PC-Check%20' + $id + '&body=' + ($body -replace ' ', '%20' -replace '\\', '%5C' -replace '&', '%26')
    try { Start-Process -FilePath $uri } catch { }
    try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"' + $selectPath + '"') } catch { }
}

# PDF über einen Chromium-Browser im Hintergrund: zuerst Edge (fast immer vorhanden), sonst Chrome.
# Eigenes leeres Profil, damit sich der Aufruf nicht an ein offenes Browserfenster des Kunden hängt.
function Export-Pdf($htmlPath, $pdfPath) {
    $candidates = @()
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if ($base) { $candidates += (Join-Path $base 'Microsoft\Edge\Application\msedge.exe') }
    }
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if ($base) { $candidates += (Join-Path $base 'Google\Chrome\Application\chrome.exe') }
    }
    $browser = $null
    foreach ($c in $candidates) { if (Test-Path $c) { $browser = $c; break } }
    if (-not $browser) { return $false }
    $uri = 'file:///' + (($htmlPath -replace '\\', '/') -replace ' ', '%20')
    $profileDir = Join-Path $env:TEMP ('SoluxPdf-' + (Get-Random))
    try {
        $proc = Start-Process -FilePath $browser -ArgumentList @('--headless', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
            ('--user-data-dir="' + $profileDir + '"'), '--no-pdf-header-footer', ('--print-to-pdf="' + $pdfPath + '"'), $uri) -WindowStyle Hidden -PassThru -ErrorAction Stop
        Wait-Process -Id $proc.Id -Timeout 40 -ErrorAction SilentlyContinue
    } catch { return $false }
    finally { Remove-Item -LiteralPath $profileDir -Recurse -Force -ErrorAction SilentlyContinue }
    return (Test-Path $pdfPath)
}

function Get-SymptomFindings {
    $areas = @()
    foreach ($k in $script:D.customer.symptoms) { if ($null -ne $script:SymptomInfo[$k]) { $areas += $script:SymptomInfo[$k].areas } }
    $res = @()
    foreach ($f in (Sort-Findings $script:Findings)) { if ($areas -contains $f.area -and $f.customer) { $res += $f } }
    $res
}

# ---------------------------------------------------------------------------
# Bericht
# ---------------------------------------------------------------------------
$Css = @'
:root{--ink:#14181f;--muted:#5b6472;--line:#d9dde3;--paper:#ffffff;--ok:#1f7a4d;--warn:#b26a00;--crit:#b3261e;--accent:#0b4f8a}
*{box-sizing:border-box}body{margin:0;background:#f3f4f6;color:var(--ink);font:15px/1.5 "Segoe UI",system-ui,sans-serif}
.page{max-width:900px;margin:24px auto;background:var(--paper);padding:40px 48px;border:1px solid var(--line)}
h1,h2,h3{font-family:Bahnschrift,"Segoe UI",sans-serif;font-weight:600;letter-spacing:.01em}
h1{font-size:30px;margin:0 0 4px}h2{font-size:19px;margin:32px 0 10px;padding-bottom:6px;border-bottom:2px solid var(--ink)}h3{font-size:15px;margin:20px 0 6px}
.brand{font-family:Bahnschrift,sans-serif;font-size:12px;letter-spacing:.25em;text-transform:uppercase;color:var(--accent)}
.meta{color:var(--muted);font-size:13px}
.verdict{margin:24px 0;padding:18px 22px;border-left:8px solid var(--ok);background:#f2f8f5}
.verdict.warnung{border-color:var(--warn);background:#fdf6ec}.verdict.kritisch{border-color:var(--crit);background:#fcefee}
.verdict b{font-family:Bahnschrift,sans-serif;font-size:22px;display:block}
.tag{display:inline-block;min-width:74px;text-align:center;font:600 11px Bahnschrift,sans-serif;letter-spacing:.06em;text-transform:uppercase;padding:2px 6px;color:#fff;background:var(--muted)}
.tag.kritisch{background:var(--crit)}.tag.warnung{background:var(--warn)}.tag.hinweis{background:var(--accent)}.tag.ok{background:var(--ok)}
ul.find{list-style:none;padding:0;margin:0}ul.find li{padding:10px 0;border-bottom:1px solid var(--line);display:flex;gap:12px;align-items:baseline}
.rec{border:1px solid var(--line);padding:12px 16px;margin:8px 0}.rec b{display:block}.rec span{color:var(--muted);font-size:13px}
table{width:100%;border-collapse:collapse;margin:6px 0 14px;font-size:13px}th,td{text-align:left;padding:5px 8px;border-bottom:1px solid var(--line);vertical-align:top}th{background:#f6f7f9;font-weight:600}
.foot{margin-top:36px;padding-top:12px;border-top:1px solid var(--line);color:var(--muted);font-size:12px}
.annex{page-break-before:always;margin-top:64px;padding-top:24px;border-top:3px double var(--line)}
@media print{.annex{margin-top:0;padding-top:0;border:0}body{background:#fff}.page{margin:0;border:0;padding:0 8mm;max-width:none}h2{page-break-after:avoid}}
'@

function Row($k, $v) { if ($v -is [double]) { $v = Num $v }; '<tr><th style="width:34%">' + (Esc $k) + '</th><td>' + (Esc $v) + '</td></tr>' }
function JaNein($b) { if ($null -eq $b) { 'unbekannt' } elseif ($b) { 'ja' } else { 'nein' } }
function OrUnknown($v, $suffix) { if ($null -eq $v -or [string]$v -eq '') { 'nicht messbar' } else { [string]$v + $suffix } }

function Build-Html($verdict, $recs) {
    $m = $script:D.meta; $s = $script:D.system; $hw = $script:D.hardware
    $o = @()
    $o += '<!DOCTYPE html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
    $o += '<title>PC-Check ' + (Esc $m.reportId) + '</title><style>' + $script:Css + '</style></head><body><div class="page">'
    $o += '<div class="brand">Solux IT &middot; PC-Check</div><h1>Ihr PC im Check</h1>'
    $o += '<div class="meta">Bericht ' + (Esc $m.reportId) + ' &middot; ' + (Esc (DateTimeDe $m.created)) + ' &middot; ' + (Esc $s.manufacturer) + ' ' + (Esc $s.model) + ' &middot; ' + (Esc $s.osName) + ' ' + (Esc $s.displayVersion) + '</div>'
    $cu = $script:D.customer
    if ($cu.name -or $cu.code) { $o += '<div class="meta">Für: ' + (Esc $cu.name) + $(if ($cu.code) { ' &middot; Kundencode ' + (Esc $cu.code) } else { '' }) + '</div>' }
    $o += '<div class="verdict ' + $verdict.level + '"><b>' + (Esc $verdict.title) + '</b>' + (Esc $verdict.text) + '</div>'
    if ($cu.symptoms.Count -gt 0) {
        $labels = @(); foreach ($k in $cu.symptoms) { if ($null -ne $script:SymptomInfo[$k]) { $labels += $script:SymptomInfo[$k].label } }
        $o += '<h2>Zu Ihrem Anliegen</h2><p>Sie haben angegeben: <b>' + (Esc ($labels -join ', ')) + '</b>.</p>'
        $sf = @(Get-SymptomFindings)
        if ($sf.Count -gt 0) {
            $o += '<p>Dazu passt, was wir gefunden haben:</p><ul class="find">'
            foreach ($f in ($sf | Select-Object -First 5)) { $o += '<li><span class="tag ' + $f.severity + '">' + (Esc $f.severity) + '</span><span>' + (Esc $f.customer) + '</span></li>' }
            $o += '</ul>'
        } else { $o += '<p>Dazu hat die automatische Prüfung keine eindeutige Ursache gefunden. Das kommt bei gelegentlichen Problemen vor; wir schauen es uns gern genauer an.</p>' }
    }
    $cmp = $script:D.compare
    if ($cmp -and $cmp.rows.Count -gt 0) {
        $o += '<h2>Vergleich mit dem letzten Check' + $(if ($cmp.date) { ' vom ' + (Esc (DateDe $cmp.date)) } else { '' }) + '</h2>'
        $o += '<table><tr><th>Wert</th><th>Vorher</th><th>Jetzt</th><th>Entwicklung</th></tr>'
        foreach ($r in $cmp.rows) {
            $cls = 'hinweis'; if ($r.trend -eq 'besser') { $cls = 'ok' } elseif ($r.trend -eq 'schlechter') { $cls = 'warnung' }
            $o += '<tr><td>' + (Esc $r.what) + '</td><td>' + (Esc ((Num $r.before) + $r.unit)) + '</td><td>' + (Esc ((Num $r.now) + $r.unit)) + '</td><td><span class="tag ' + $cls + '">' + (Esc $r.trend) + '</span></td></tr>'
        }
        $o += '</table>'
    }
    $rank = @{ 'kritisch' = 0; 'warnung' = 1; 'hinweis' = 2 }
    $cust = @(); foreach ($f in (Sort-Findings $script:Findings)) { if ($f.customer -and $f.severity -ne 'hinweis') { $cust += $f } }
    foreach ($f in (Sort-Findings $script:Findings)) { if ($f.customer -and $f.severity -eq 'hinweis' -and $cust.Count -lt 6) { $cust += $f } }
    $o += '<h2>Das ist uns aufgefallen</h2>'
    if ($cust.Count -eq 0) { $o += '<p>Keine Auffälligkeiten.</p>' }
    else {
        $o += '<ul class="find">'
        foreach ($f in ($cust | Select-Object -First 10)) { $o += '<li><span class="tag ' + $f.severity + '">' + (Esc $f.severity) + '</span><span>' + (Esc $f.customer) + '</span></li>' }
        $o += '</ul>'
        if ($cust.Count -gt 10) { $o += '<p class="meta">Weitere ' + ($cust.Count - 10) + ' Punkte stehen im technischen Anhang.</p>' }
    }
    $o += '<h2>Unsere Empfehlung</h2>'
    if ($recs.Count -eq 0) { $o += '<p>Aktuell nichts zu tun. Wir empfehlen den nächsten Check in 6 Monaten (ab ' + (DateDe ((Get-Date).AddMonths(6))) + ').</p>' }
    else { foreach ($r in ($recs | Select-Object -First 3)) { $o += '<div class="rec"><b>' + (Esc $r.title) + '</b><span>Wann: ' + (Esc $r.urgency) + ' &middot; Anlass: ' + (Esc $r.because) + ' &middot; ' + (Esc $r.price) + '</span></div>' } }
    $good = @()
    $act = $false; foreach ($a in $script:D.security.av) { if ($a.enabled) { $act = $true } }
    if ($act) { $good += 'Virenschutz ist aktiv.' }
    $diskBad = $false; foreach ($f in $script:Findings) { if ($f.area -eq 'Datenträger' -and $f.severity -ne 'hinweis') { $diskBad = $true } }
    if (-not $diskBad -and $script:D.storage.disks.Count -gt 0) { $good += 'Die Laufwerke melden keine Fehler.' }
    if ($script:D.stability.bsods.Count -eq 0) { $good += 'Keine Bluescreens in den letzten ' + $Days + ' Tagen.' }
    if ($script:D.backup.any) { $good += 'Eine Datensicherung ist eingerichtet.' }
    if ($good.Count -gt 0) { $o += '<h2>Gut zu wissen</h2><ul>'; foreach ($g in $good) { $o += '<li>' + (Esc $g) + '</li>' }; $o += '</ul>' }
    $o += '<div class="foot"><b>' + (Esc $Solux.name) + '</b> &middot; ' + (Esc $Solux.people) + ' &middot; ' + (Esc $Solux.street) + ', ' + (Esc $Solux.city) + ' &middot; ' + (Esc $Solux.mail) + $(if ($Config.Phone) { ' &middot; ' + (Esc $Config.Phone) } else { '' }) + '<br>Automatische Erstdiagnose, ersetzt keine Prüfung vor Ort. Das Programm hat nur gelesen und nichts verändert. Bitte nennen Sie bei Rückfragen die Berichtsnummer ' + (Esc $m.reportId) + '.</div>'

    # Technischer Anhang
    $o += '<div class="annex"><div class="brand">Technischer Anhang</div><h1>Prüfprotokoll</h1>'
    $o += '<div class="meta">Skript ' + (Esc $m.tool) + ' ' + (Esc $m.version) + ' &middot; Sprachmodus ' + (Esc $m.languageMode) + ' &middot; Adminrechte: ' + (JaNein $m.isAdmin) + ' &middot; Dauer ' + (Esc $m.durationSec) + ' s</div>'
    if ($cu.name -or $cu.phone -or $cu.code -or $cu.symptoms.Count) { $o += '<table>' + (Row 'Kunde' $cu.name) + (Row 'Telefon' $cu.phone) + (Row 'Kundencode' $cu.code) + (Row 'Anliegen' ($cu.symptoms -join ', ')) + (Row 'Modus' $m.mode) + '</table>' }
    if (-not $m.isAdmin) { $o += '<p><b>Eingeschränkte Prüfung:</b> Ohne Adminrechte fehlen BitLocker, TPM, SMART-Werte der Laufwerke und Teile der Ereignisprotokolle.</p>' }
    $o += '<h2>Alle Befunde</h2><table><tr><th>Stufe</th><th>Bereich</th><th>Befund</th><th>Details</th></tr>'
    foreach ($f in (Sort-Findings $script:Findings)) { $o += '<tr><td><span class="tag ' + $f.severity + '">' + (Esc $f.severity) + '</span></td><td>' + (Esc $f.area) + '</td><td>' + (Esc $f.title) + '</td><td>' + (Esc $f.detail) + '</td></tr>' }
    $o += '</table>'
    $o += '<h2>System</h2><table>'
    $o += Row 'Gerät' ($s.manufacturer + ' ' + $s.model)
    $o += Row 'Seriennummer' $s.serial
    $o += Row 'BIOS' ($s.biosVersion + ' vom ' + (DateDe $s.biosDate))
    $o += Row 'Windows' ($s.osName + ' ' + $s.displayVersion + ' (Build ' + $s.build + '.' + $s.ubr + ', ' + $s.edition + ')')
    $se = 'unbekannt'; if ($s.supportEnd) { $se = DateDe $s.supportEnd }
    $o += Row 'Support bis' ($se + ' (Tabelle Stand ' + (DateDe $script:LifecycleCheckedOn) + ')')
    $o += Row 'Aktiviert' (JaNein $s.activated)
    $o += Row 'Installiert am' (DateDe $s.installDate)
    $o += Row 'Laufzeit seit Start' ([string]$s.uptimeDays + ' Tage, Schnellstart: ' + (JaNein $s.fastStartup))
    $o += Row 'Prozessor' ($hw.cpu + ' (' + $hw.cores + ' Kerne / ' + $hw.threads + ' Threads)')
    $o += Row 'Arbeitsspeicher' ([string]$hw.ramGB + ' GB, ' + $hw.ramModules.Count + ' von ' + $hw.ramSlots + ' Steckplätzen belegt')
    foreach ($g in $hw.gpus) { $o += Row 'Grafik' ($g.name + ', Treiber ' + $g.driver + ' vom ' + (DateDe $g.driverDate)) }
    $o += Row 'Bauform' $(if ($s.isLaptop) { 'Laptop' } else { 'Desktop/Sonstige' })
    $o += '</table>'
    if ($hw.ramModules.Count -gt 0) {
        $o += '<h3>Speichermodule</h3><table><tr><th>Steckplatz</th><th>Größe</th><th>Takt</th><th>Hersteller</th><th>Teilenummer</th></tr>'
        foreach ($r in $hw.ramModules) { $o += '<tr><td>' + (Esc $r.slot) + '</td><td>' + (Esc $r.sizeGB) + ' GB</td><td>' + (Esc $r.configured) + ' / ' + (Esc $r.speed) + ' MHz</td><td>' + (Esc $r.vendor) + '</td><td>' + (Esc $r.part) + '</td></tr>' }
        $o += '</table>'
    }
    $st = $script:D.storage
    $o += '<h2>Datenträger</h2><table><tr><th>Laufwerk</th><th>Größe</th><th>Zustand</th><th>Verschleiß</th><th>Temp. (Grenze)</th><th>Stunden</th><th>Lesefehler</th></tr>'
    foreach ($d in $st.disks) {
        $nm = $d.name + ' (' + $d.bus + ', ' + $d.media + ')'; if ($d.external) { $nm += ' extern' }
        $o += '<tr><td>' + (Esc $nm) + '<br><span class="meta">SN ' + (Esc $d.serial) + ' &middot; FW ' + (Esc $d.firmware) + '</span></td><td>' + (Esc $d.sizeGB) + ' GB</td><td>' + (Esc $d.health) + '</td><td>' + (Esc (OrUnknown $d.wear ' %')) + '</td><td>' + (Esc (OrUnknown $d.temp ' °C')) + ' (' + (Esc (OrUnknown $d.tempMax ' °C')) + ')</td><td>' + (Esc (OrUnknown $d.hours ' h')) + '</td><td>' + (Esc (OrUnknown $d.readErrors '')) + '</td></tr>'
    }
    $o += '</table><table><tr><th>Volume</th><th>Größe</th><th>Frei</th></tr>'
    foreach ($v in $st.volumes) { $o += '<tr><td>' + (Esc ($v.drive + ' ' + $v.label)) + '</td><td>' + (Esc $v.sizeGB) + ' GB</td><td>' + (Esc $v.freeGB) + ' GB (' + (Esc $v.freePct) + ' %)</td></tr>' }
    $o += '</table>'
    if ($st.diskEvents.Count -gt 0) { $o += '<h3>Datenträger-Ereignisse (30 Tage)</h3><table>'; foreach ($e in $st.diskEvents) { $o += Row $e.source ([string]$e.count + '×') }; $o += '</table>' }
    $o += '<table>' + (Row 'Temp-Ordner Benutzer' ([string]$st.userTempGB + ' GB')) + (Row 'Update-Cache' ([string]$st.updateCacheGB + ' GB')) + (Row 'Windows.old vorhanden' (JaNein $st.windowsOld)) + '</table>'
    $th = $script:D.thermal
    $o += '<h2>Temperatur und Leistung</h2><table>'
    $o += Row 'CPU-Temperatur (max)' ((OrUnknown $th.cpuTempMax ' °C') + ' ' + $th.cpuTempSource)
    $o += Row 'Messreihe CPU-Temperatur' (($th.cpuTempSamples | ForEach-Object { [string]$_ }) -join ' / ')
    $o += Row 'CPU-Last (Mittel)' (OrUnknown $th.cpuLoadAvg ' %')
    $o += Row 'CPU-Leistung (Mittel)' ((OrUnknown $th.cpuPerfAvg ' %') + ' (unter 100 % = Takt reduziert)')
    if ($th.gpuName -or $th.gpuTemp) { $o += Row 'GPU' ([string]$th.gpuName + ' ' + (OrUnknown $th.gpuTemp ' °C') + ', Last ' + (OrUnknown $th.gpuLoad ' %')) }
    $o += Row 'Energieplan' $th.powerPlan
    $o += Row 'Akkubetrieb' (JaNein $th.onBattery)
    $o += Row 'Drossel-Ereignisse (Kernel-Processor-Power 37)' $th.throttleEvents
    $o += '</table>'
    $b = $script:D.battery
    if ($b.present) { $o += '<h2>Akku</h2><table>' + (Row 'Kapazität' ((OrUnknown $b.healthPct ' %') + ' (' + $b.fullmWh + ' von ' + $b.designmWh + ' mWh)')) + (Row 'Ladezyklen' (OrUnknown $b.cycles '')) + '</table>' }
    $sb = $script:D.stability
    $o += '<h2>Stabilität (' + $Days + ' Tage)</h2><table>'
    $o += Row 'Zuverlässigkeitsindex' (OrUnknown $sb.stabilityIndex ' / 10')
    $o += Row 'Unerwartet aus (Kernel-Power 41)' ([string]$sb.kp41.Count + ' gesamt: ' + $sb.powerButton + '× Taste, ' + $sb.withBugcheck + '× Bluescreen, ' + $sb.inSleep + '× im Standby, ' + $sb.unexplained + '× ungeklärt')
    $o += Row 'Unerwartetes Herunterfahren (6008)' $sb.unexpected6008
    $o += Row 'Bluescreens' $sb.bsods.Count
    $o += Row 'WHEA (30 Tage)' ([string]$sb.wheaFatal + ' schwer, ' + $sb.wheaCorrected + ' korrigiert')
    $o += Row 'Grafiktreiber-Neustarts (TDR)' $sb.tdr
    $o += Row 'Programmabstürze / hängend' ([string]$sb.appCrashes + ' / ' + $sb.appHangs)
    $o += Row 'Startdauer' (OrUnknown $sb.bootSeconds ' s')
    $o += Row 'Speicherdiagnose' $(if ($sb.memDiag) { $sb.memDiag } else { 'nicht gelaufen' })
    $o += Row 'Speicherabbilder aktiviert' (JaNein $sb.crashDumps)
    $o += '</table>'
    $events = @()
    foreach ($e in $sb.kp41) { $events += @{ t = $e.time; what = 'Unerwartet aus: ' + $e.kind } }
    foreach ($e in $sb.bsods) { $events += @{ t = $e.time; what = 'Bluescreen ' + $e.code + ': ' + $e.text } }
    if ($events.Count -gt 0) {
        $o += '<h3>Zeitachse</h3><table><tr><th>Zeitpunkt</th><th>Ereignis</th></tr>'
        foreach ($e in ($events | Sort-Object { $_.t } -Descending)) { $o += '<tr><td>' + (Esc (DateTimeDe $e.t)) + '</td><td>' + (Esc $e.what) + '</td></tr>' }
        $o += '</table>'
    }
    if ($sb.topApps.Count -gt 0) { $o += '<h3>Häufigste abstürzende Programme</h3><table>'; foreach ($a in $sb.topApps) { $o += Row $a.app ([string]$a.count + '×') }; $o += '</table>' }
    if ($sb.minidumps.Count -gt 0) { $o += '<h3>Minidumps</h3><table>'; foreach ($x in $sb.minidumps) { $o += Row $x.file (DateTimeDe $x.time) }; $o += '</table>' }
    $u = $script:D.updates
    $o += '<h2>Updates</h2><table>' + (Row 'Letzte erfolgreiche Installation' $(if ($u.lastSuccess) { DateTimeDe $u.lastSuccess } else { 'keine in 120 Tagen' })) + (Row 'Fehlgeschlagen (30 Tage)' $u.failures) + (Row 'Dienst wuauserv' $u.serviceStart) + (Row 'Neustart ausstehend' (JaNein $s.pendingReboot)) + '</table>'
    $se2 = $script:D.security
    $o += '<h2>Sicherheit</h2><table>'
    foreach ($a in $se2.av) { $o += Row ('Virenschutz: ' + $a.name) ('aktiv: ' + (JaNein $a.enabled) + ', aktuell: ' + (JaNein $a.upToDate)) }
    if ($se2.defender) { $o += Row 'Defender' ('Echtzeit: ' + (JaNein $se2.defender.realtime) + ', Signaturen ' + $se2.defender.sigAgeDays + ' Tage, Schnellscan vor ' + $se2.defender.quickScanAgeDays + ' Tagen, Manipulationsschutz: ' + (JaNein $se2.defender.tamper) + ', Smart App Control: ' + $se2.defender.smartAppControl) }
    foreach ($f in $se2.firewall) { $o += Row ('Firewall ' + $f.profile) (JaNein $f.enabled) }
    $o += Row 'Benutzerkontensteuerung' (JaNein $se2.uac)
    $o += Row 'BitLocker (Systemlaufwerk)' $se2.bitlocker
    $o += Row 'TPM' $se2.tpm
    $o += Row 'Secure Boot' $se2.secureBoot
    $o += Row 'Speicherintegrität' (JaNein $se2.memoryIntegrity)
    $o += Row 'Remotedesktop' (JaNein $se2.rdp)
    $o += Row 'SMBv1' (JaNein $se2.smb1)
    $o += '</table>'
    $w = $script:D.win11
    if ($w.applicable) { $o += '<h3>Windows-11-Fähigkeit (Schätzung)</h3><table>' + (Row 'Prozessor' (JaNein $w.cpu)) + (Row 'TPM 2.0' (JaNein $w.tpm2)) + (Row 'UEFI/Secure Boot möglich' (JaNein $w.uefi)) + (Row 'RAM ≥ 4 GB' (JaNein $w.ram)) + (Row 'Systemlaufwerk ≥ 64 GB' (JaNein $w.disk)) + (Row 'Ergebnis' (JaNein $w.ready)) + '</table>' }
    $n = $script:D.network
    $o += '<h2>Netzwerk</h2><table>'
    foreach ($p in $n.pings) { $o += Row ('Ping ' + $p.kind + ' (' + $p.target + ')') ((OrUnknown $p.avgMs ' ms') + ', Schwankung ' + (OrUnknown $p.jitterMs ' ms') + ', Verlust ' + $p.lossPct + ' %') }
    $o += Row 'DNS' ($(if ($n.dnsOk) { [string]$n.dnsMs + ' ms' } else { 'fehlgeschlagen' }) + ' (' + ($n.dnsServers -join ', ') + ')')
    if ($n.wlan) { $o += Row 'WLAN' ('Signal ' + $n.wlan.signal + ' %, ' + $n.wlan.standard + ', Band ' + $n.wlan.band + ', Kanal ' + $n.wlan.channel + ', Empfang ' + $n.wlan.rxMbps + ' Mbit/s') }
    $o += Row ('WLAN-Trennungen (' + $Days + ' Tage)') $n.wlanDrops
    foreach ($a in $n.adapters) { $o += Row ('Adapter ' + $a.name) ($a.desc + ', ' + $a.speed) }
    if ($n.proxy) { $o += Row 'Proxy' $n.proxy }
    foreach ($p in $n.printers) { $o += Row ('Drucker ' + $p.name) ('Standard: ' + (JaNein $p.default) + ', offline: ' + (JaNein $p.offline)) }
    $o += '</table>'
    $sw = $script:D.software; $bk = $script:D.backup
    $o += '<h2>Software und Datensicherung</h2><table>'
    $o += Row 'Installierte Programme' $sw.count
    $o += Row 'Unerwünscht' $(if ($sw.unwanted.Count) { $sw.unwanted -join ', ' } else { 'keine' })
    $o += Row 'Fernwartung' $(if ($sw.remote.Count) { $sw.remote -join ', ' } else { 'keine' })
    $o += Row 'Autostart' ($sb.startupItems -join ', ')
    $o += Row 'OneDrive angemeldet / Ordnersicherung' ((JaNein $bk.oneDriveSignedIn) + ' / ' + (JaNein $bk.oneDriveFolders))
    $o += Row 'Dateiversionsverlauf' (JaNein $bk.fileHistory)
    $o += Row 'Backup-Software' $(if ($bk.tools.Count) { $bk.tools -join ', ' } else { 'keine erkannt' })
    $tm = @(); foreach ($p in $sw.topMemory) { $tm += ($p.name + ' ' + $p.mb + ' MB') }
    $o += Row 'Größte Prozesse (RAM)' ($tm -join ', ')
    $o += '</table>'
    $o += '<h2>Module</h2><table><tr><th>Modul</th><th>Status</th><th>Dauer</th><th>Hinweis</th></tr>'
    foreach ($x in $script:D.modules) { $o += '<tr><td>' + (Esc $x.name) + '</td><td>' + (Esc $x.status) + '</td><td>' + (Esc $x.ms) + ' ms</td><td>' + (Esc $x.note) + '</td></tr>' }
    $o += '</table></div></div></body></html>'
    $o -join "`n"
}

# ---------------------------------------------------------------------------
# Selbsttest (Bewertung + Bericht mit Beispieldaten, ohne Windows)
# ---------------------------------------------------------------------------
function Load-SampleData {
    $script:D.system = [ordered]@{ computerName = 'TEST-PC'; osName = 'Microsoft Windows 10 Pro'; build = 19045; ubr = 5011; displayVersion = '22H2'; edition = 'Professional'; installDate = [datetime]'2019-03-01'; lastBoot = (Get-Date).AddDays(-20); uptimeDays = 20; fastStartup = $true; manufacturer = 'LENOVO'; model = 'ThinkPad T480'; serial = 'PF0TEST1'; biosVersion = 'N24ET70W'; biosDate = [datetime]'2021-05-01'; isLaptop = $true; supportEnd = [datetime]'2025-10-14'; isWin10 = $true; insider = $false; activated = $true; pendingReboot = $true }
    $script:D.hardware = [ordered]@{ cpu = 'Intel(R) Core(TM) i5-8350U CPU @ 1.70GHz'; cores = 4; threads = 8; ramModules = @([ordered]@{ slot = 'ChannelA'; sizeGB = 8; speed = 2400; configured = 2400; vendor = 'Samsung'; part = 'M471A1K43' }); ramGB = 8; ramSlots = 2; gpus = @([ordered]@{ name = 'Intel UHD 620'; driver = '27.20'; driverDate = [datetime]'2020-01-01' }); problemDevices = @([ordered]@{ name = 'Fingerprint <Sensor>'; code = 28; text = 'kein Treiber installiert' }) }
    $script:D.storage = [ordered]@{ volumes = @([ordered]@{ drive = 'C:'; label = 'OS'; sizeGB = 237; freeGB = 9.5; freePct = 4; fs = 'NTFS' }); disks = @([ordered]@{ name = 'Samsung SSD 970'; serial = 'S4X'; firmware = '2B2QEXE7'; media = 'SSD'; bus = 'NVMe'; sizeGB = 256; health = 'Healthy'; external = $false; temp = 41; tempMax = 72; wear = 74; hours = 12000; readErrors = 0; startStop = 3000 }); diskEvents = @([ordered]@{ source = 'disk 153'; count = 3 }); severeDiskEvents = 0; userTempGB = 6.2; updateCacheGB = 1.1; windowsOld = $false }
    $script:D.thermal = [ordered]@{ cpuLoadSamples = @(60, 70, 65); cpuPerfSamples = @(55, 60, 58); cpuTempSamples = @(88, 92, 91); cpuTempSource = 'ACPI-Thermalzone'; cpuLoadAvg = 65; cpuTempMax = 92; cpuPerfAvg = 58; powerPlan = 'Ausbalanciert'; throttleEvents = 2; onBattery = $false }
    $script:D.battery = [ordered]@{ present = $true; designmWh = 57000; fullmWh = 31000; cycles = 512; healthPct = 54.4 }
    $script:D.stability = [ordered]@{ kp41 = @([ordered]@{ time = (Get-Date).AddDays(-3); kind = 'Knopf gehalten' }, [ordered]@{ time = (Get-Date).AddDays(-5); kind = 'Bluescreen' }); powerButton = 1; withBugcheck = 1; inSleep = 0; unexplained = 0; unexpected6008 = 2; bsods = @([ordered]@{ time = (Get-Date).AddDays(-5); code = '0x0000009f'; text = (Explain-BugCheck '0x0000009f') }, [ordered]@{ time = (Get-Date).AddDays(-9); code = '0x00000116'; text = (Explain-BugCheck '0x116') }); wheaFatal = 0; wheaCorrected = 2; tdr = 3; appCrashes = 12; appHangs = 2; topApps = @([ordered]@{ app = 'chrome.exe'; count = 8 }); stabilityIndex = 3.4; bootSeconds = 95; startupItems = @('OneDrive', 'Teams', 'Spotify'); memDiag = ''; crashDumps = $true; minidumps = @() }
    $script:D.updates = [ordered]@{ lastSuccess = (Get-Date).AddDays(-70); failures = 4; failedUpdates = @([ordered]@{ title = 'KB5050 <Test>'; count = 4 }); serviceStart = 'Manual'; policyNoAutoUpdate = $false }
    $script:D.security = [ordered]@{ av = @([ordered]@{ name = 'Windows Defender'; enabled = $true; upToDate = $true }, [ordered]@{ name = 'McAfee'; enabled = $true; upToDate = $false }); defender = [ordered]@{ realtime = $true; antivirusEnabled = $true; sigAgeDays = 2; quickScanAgeDays = 1; tamper = $true; smartAppControl = 'Off'; mode = 'Passive' }; threats = @(); firewall = @([ordered]@{ profile = 'Private'; enabled = $true }, [ordered]@{ profile = 'Public'; enabled = $false }); uac = $true; secureBoot = 'aktiv'; uefi = $true; tpm = '2.0'; bitlocker = 'verschlüsselt, Schutz AUS'; rdp = $false; smb1 = $false; memoryIntegrity = $false }
    $script:D.network = [ordered]@{ gateway = '192.168.178.1'; adapters = @(); pings = @([ordered]@{ target = '192.168.178.1'; kind = 'Router'; avgMs = 4; jitterMs = 2; lossPct = 0 }, [ordered]@{ target = '1.1.1.1'; kind = 'Internet'; avgMs = 31; jitterMs = 45; lossPct = 20 }); dnsMs = 40; dnsOk = $true; dnsServers = @('192.168.178.1'); wlan = [ordered]@{ signal = 35; standard = '802.11n'; band = '2,4 GHz'; channel = 6; rxMbps = '72'; state = 'verbunden' }; wlanDrops = 14; proxy = $null; hostsEntries = @(); printers = @() }
    $script:D.software = [ordered]@{ count = 120; unwanted = @('Driver Booster 9'); remote = @('AnyDesk'); backupTools = @(); office = @('Microsoft Office Professional Plus 2016'); topMemory = @(); topCpu = @() }
    $script:D.backup = [ordered]@{ oneDriveSignedIn = $true; oneDriveFolders = $false; fileHistory = $false; tools = @(); any = $false }
    $script:D.win11 = [ordered]@{ applicable = $true; cpu = $true; tpm2 = $true; uefi = $true; ram = $true; disk = $true; ready = $true }
}

function Assert($cond, $msg) {
    if ($cond) { Write-Host ('  OK    ' + $msg) -ForegroundColor Green; $script:Pass++ }
    else { Write-Host ('  FEHLER ' + $msg) -ForegroundColor Red; $script:Fail++ }
}
function HasFinding($titlePart, $sev) {
    foreach ($f in $script:Findings) { if ($f.title -like ('*' + $titlePart + '*') -and (-not $sev -or $f.severity -eq $sev)) { return $true } }
    return $false
}

function Run-SelfTest {
    $script:Pass = 0; $script:Fail = 0
    Write-Host 'Selbsttest Solux PC-Check (Skript)' -ForegroundColor Cyan
    Write-Host ('  Sprachmodus: ' + $ExecutionContext.SessionState.LanguageMode)
    Load-SampleData
    $script:D.meta = [ordered]@{ reportId = 'SOL-TEST'; created = Get-Date; tool = 'SoluxCheck.ps1'; version = $ScriptVersion; schemaVersion = $SchemaVersion; languageMode = 'Test'; isAdmin = $true; durationSec = 0; days = $Days }
    Evaluate
    Assert (HasFinding 'Windows 10 läuft aus' 'warnung') 'Windows 10 wird gemeldet'
    Assert (HasFinding 'Wenig Platz' 'warnung') 'wenig Speicherplatz (9,5 GB) = Warnung'
    Assert (HasFinding 'SSD-Verschleiß' 'warnung') 'SSD-Verschleiß 74 % = Warnung'
    Assert (HasFinding 'Prozessor heiß' 'warnung') '92 °C bei 65 % Last = heiß'
    Assert (HasFinding 'taktet unter Last' 'hinweis') 'Drosselhinweis bei 58 % Leistung'
    Assert (HasFinding 'Akku nur noch' 'warnung') 'Akku 54 % = Warnung'
    Assert (HasFinding '2 Bluescreens' 'warnung') '2 Bluescreens = Warnung'
    Assert (HasFinding 'Grafiktreiber 3' 'warnung') 'TDR 3× = Warnung'
    Assert (HasFinding 'Zuverlässigkeitsindex' 'warnung') 'Stabilitätsindex 3,4 = Warnung'
    Assert (HasFinding 'Start dauert 95' 'warnung') 'Start 95 s = Warnung'
    Assert (HasFinding 'Firewall aus (Public)' 'warnung') 'Firewall öffentlich aus'
    Assert (HasFinding 'Virenschutz veraltet: McAfee' 'warnung') 'veraltete Fremd-AV'
    Assert (HasFinding 'Mehrere Virenscanner' 'warnung') 'zwei aktive Virenscanner'
    Assert (HasFinding 'BitLocker angehalten' 'warnung') 'BitLocker ohne Schutz'
    Assert (HasFinding 'Keine automatische Datensicherung' 'warnung') 'fehlende Datensicherung'
    Assert (HasFinding 'Internet verliert 20' 'warnung') 'Paketverlust Internet bei stabilem Router'
    Assert (HasFinding 'WLAN-Signal schwach' 'warnung') 'WLAN 35 % = schwach'
    Assert (HasFinding 'Office-Version ohne Support' 'warnung') 'Office 2016 erkannt'
    Assert (-not (HasFinding 'Vorbeugende Innenreinigung' $null)) 'keine doppelte Reinigungsempfehlung bei gemessener Hitze'
    Assert (-not (HasFinding 'Festplattenfehler' $null)) 'disk 153 allein ist kein schwerer Fehler'
    $recs = @(Get-Recommendations)
    $keys = @(); foreach ($r in $recs) { $keys += $r.service }
    Assert ($keys -contains 'backup' -and $keys -contains 'clean') 'Empfehlungen enthalten Datensicherung und Reinigung'
    $dup = $keys | Group-Object | Where-Object { $_.Count -gt 1 }
    Assert (-not $dup) 'keine doppelten Empfehlungen'
    $v = Get-Verdict
    Assert ($v.level -eq 'warnung') 'Gesamturteil Warnung'
    $html = Build-Html $v $recs
    Assert ($html -match '&lt;Sensor&gt;' -and $html -notmatch '<Sensor>') 'HTML-Escaping'
    Assert ($html -match 'Technischer Anhang' -and $html -match 'SOL-TEST') 'Bericht vollständig'
    $json = Build-Json $v $recs
    if ($OutDir) { $html | Out-File -FilePath (Join-Path $OutDir 'selftest.html') -Encoding UTF8; $json | Out-File -FilePath (Join-Path $OutDir 'selftest.json') -Encoding UTF8 }
    Assert ($json -match '"schemaVersion":\s*1') 'JSON mit Schema-Version'
    Assert ((Explain-BugCheck '0x0000009f') -match 'DRIVER_POWER') 'Stop-Code-Lexikon'
    Assert ((Get-SupportEnd 26200 '25H2' 'Professional') -eq [datetime]'2027-10-12') 'Supportdaten 25H2'
    Assert ((Get-SupportEnd 26300 '26H2' 'Core') -eq [datetime]'2028-10-10') 'Supportdaten 26H2'
    Assert ([int](Sqrt 2025) -eq 45) 'Wurzelfunktion'
    # Kundenangaben, Anliegen, Versand-Paket
    Assert ((@(Parse-Symptoms '1, 3 ,9,heiss') -join ',') -eq 'langsam,heiss') 'Anliegen-Auswahl wird gelesen'
    Assert ((Clean 'Max "Muster"; & <x>' 60) -eq 'Max Muster x') 'Kundeneingaben werden bereinigt'
    Assert (Is-Newer '1.2.0' '1.1.9') 'Versionsvergleich neuer'
    Assert (-not (Is-Newer '1.1.0' '1.1.0')) 'Versionsvergleich gleich'
    $script:D.customer = [ordered]@{ name = 'Erika Müller'; phone = '0170 123'; code = 'K123'; symptoms = @('heiss', 'absturz') }
    $sf = @(Get-SymptomFindings)
    Assert ($sf.Count -gt 0 -and ($sf | Where-Object { $_.area -eq 'Kühlung' })) 'Befunde passend zum Anliegen'
    $html2 = Build-Html $v $recs
    Assert ($html2 -match 'Zu Ihrem Anliegen' -and $html2 -match 'Erika Müller') 'Anliegen und Kunde im Bericht'
    $payload = Build-Payload $v $recs $html2
    Assert ($payload -notmatch '[^\x00-\x7F]') 'Versand-Paket nur ASCII'
    $back = $payload | ConvertFrom-Json
    Assert ($back.customer.name -eq 'Erika Müller' -and $back.html -match 'Prüfprotokoll') 'Versand-Paket wieder lesbar (Umlaute erhalten)'
    if ($OutDir) { Build-Json $v $recs | Out-File -FilePath (Join-Path $OutDir 'Solux-PC-Check-SOL-OLD.json') -Encoding UTF8 }
    $script:D.customer = [ordered]@{ name = ''; phone = ''; code = ''; symptoms = @() }

    # Gesundes System: keine Befunde über "hinweis"
    $script:D.system.isWin10 = $false; $script:D.system.build = 26200; $script:D.system.displayVersion = '25H2'; $script:D.system.supportEnd = [datetime]'2027-10-12'; $script:D.system.uptimeDays = 1; $script:D.system.pendingReboot = $false
    $script:D.storage.volumes[0].freeGB = 120; $script:D.storage.volumes[0].freePct = 50; $script:D.storage.disks[0].wear = 3; $script:D.storage.disks[0].temp = 37; $script:D.storage.disks[0].tempMax = 80; $script:D.storage.disks[0].hours = 800; $script:D.storage.userTempGB = 0.4
    $script:D.thermal.cpuTempMax = 47; $script:D.thermal.cpuLoadAvg = 37; $script:D.thermal.cpuPerfAvg = 99
    $script:D.battery.healthPct = 95
    $script:D.stability = [ordered]@{ kp41 = @(); powerButton = 0; withBugcheck = 0; inSleep = 0; unexplained = 0; unexpected6008 = 0; bsods = @(); wheaFatal = 0; wheaCorrected = 0; tdr = 0; appCrashes = 1; appHangs = 0; topApps = @(); stabilityIndex = 9.1; bootSeconds = 25; startupItems = @('OneDrive'); memDiag = ''; crashDumps = $true; minidumps = @() }
    $script:D.hardware.problemDevices = @(); $script:D.hardware.ramModules += [ordered]@{ slot = 'ChannelB'; sizeGB = 8 }; $script:D.hardware.ramGB = 16
    $script:D.updates = [ordered]@{ lastSuccess = (Get-Date).AddDays(-5); failures = 0; failedUpdates = @(); serviceStart = 'Manual'; policyNoAutoUpdate = $false }
    $script:D.security.av = @([ordered]@{ name = 'Windows Defender'; enabled = $true; upToDate = $true }); $script:D.security.defender.mode = 'Normal'; $script:D.security.firewall[1].enabled = $true; $script:D.security.bitlocker = 'nicht verschlüsselt'
    $script:D.network.pings[1].lossPct = 0; $script:D.network.pings[1].jitterMs = 3; $script:D.network.wlan.signal = 85; $script:D.network.wlan.band = '5 GHz'; $script:D.network.wlanDrops = 0
    $script:D.software.unwanted = @(); $script:D.software.remote = @(); $script:D.software.office = @()
    $script:D.backup.any = $true
    Evaluate
    $bad = @(); foreach ($f in $script:Findings) { if ($f.severity -ne 'hinweis') { $bad += $f.title } }
    Assert ($bad.Count -eq 0) ('Gesundes System ohne Warnungen' + $(if ($bad.Count) { ': ' + ($bad -join ', ') } else { '' }))
    Assert (-not (HasFinding 'heiß' $null)) '47 °C bei 37 % gilt nicht als heiß'
    Assert (-not (HasFinding 'Laufwerk heiß' $null)) 'SSD-Grenzwert 80 °C bei 37 °C ist kein Befund'
    $script:D.storage.disks[0].temp = 75; Evaluate
    Assert (HasFinding 'Laufwerk heiß' 'hinweis') 'SSD aktuell 75 °C = Hinweis'
    $script:D.storage.disks[0].temp = 37; Evaluate
    if ($OutDir) {
        $script:D.meta.reportId = 'SOL-NEU'
        Compare-Previous $OutDir
        $c = $script:D.compare
        Assert ($c -and $c.reportId -eq 'SOL-TEST') 'Vorheriger Check wird gefunden'
        $t = @{}; if ($c) { foreach ($r in $c.rows) { $t[$r.what] = $r.trend } }
        Assert ($t['Freier Speicher C:'] -eq 'besser' -and $t['CPU-Temperatur (max)'] -eq 'besser' -and $t['Bluescreens im Zeitraum'] -eq 'besser') 'Vergleich erkennt Verbesserungen'
        $html3 = Build-Html (Get-Verdict) @(Get-Recommendations)
        Assert ($html3 -match 'Vergleich mit dem letzten Check') 'Vergleich im Bericht'
        $html3 | Out-File -FilePath (Join-Path $OutDir 'selftest-nachher.html') -Encoding UTF8
    }
    Write-Host ''
    Write-Host ('  ' + $script:Pass + ' bestanden, ' + $script:Fail + ' fehlgeschlagen') -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
    if ($script:Fail) { exit 1 } else { exit 0 }
}

function Build-Json($verdict, $recs) {
    $out = [ordered]@{
        schemaVersion = $SchemaVersion
        reportId = $script:D.meta.reportId
        verdict = $verdict
        findings = $script:Findings
        recommendations = $recs
        data = $script:D
    }
    $out | ConvertTo-Json -Depth 8
}

# ---------------------------------------------------------------------------
# Ablauf
# ---------------------------------------------------------------------------
if ($SelfTest) { Run-SelfTest }

$IsAdmin = ((& whoami.exe /groups 2>$null) -join ' ') -match 'S-1-16-12288'
$Interactive = -not ($Quiet -or $Technician)
if (-not $CustCode -and $Launcher -match '_([A-Za-z0-9-]{3,24})\.cmd$') { $CustCode = $Matches[1] }
$CustName = Clean $CustName 60; $CustPhone = Clean $CustPhone 30; $CustCode = Clean $CustCode 24

if (-not $OutDir) {
    if ($Technician) {
        $baseDir = ''
        if ($Launcher) { $baseDir = Split-Path -Parent $Launcher } elseif ($PSCommandPath) { $baseDir = Split-Path -Parent $PSCommandPath }
        if (-not $baseDir) { $baseDir = $env:USERPROFILE }
        $OutDir = Join-Path $baseDir 'Berichte'
    } else {
        $docs = [string](RegVal 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders' 'Personal')
        if (-not $docs) { $docs = Join-Path $env:USERPROFILE 'Documents' }
        $OutDir = Join-Path $docs 'Solux PC-Check'
    }
}

if ($Interactive -and -not $Elevated) {
    Show-Intro
    Ask-Customer
}

if (-not $IsAdmin -and -not $NoElevate -and -not $Elevated) {
    $self = Get-SelfCopy
    if ($self) {
        Write-Host ''
        Line 'Für die vollständige Prüfung (Festplatten-Gesundheit, Verschlüsselung, Ereignisse)' 'Cyan'
        Line 'fragt Windows gleich nach Ihrer Erlaubnis. Bitte mit "Ja" bestätigen.' 'Cyan'
        $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $self + '"'), '-Elevated', '-OutDir', ('"' + $OutDir + '"'), '-Days', [string]$Days)
        if ($NoOpen) { $a += '-NoOpen' }
        if ($Technician) { $a += '-Technician' }
        if ($Quiet) { $a += '-Quiet' }
        if ($NoUpload) { $a += '-NoUpload' }
        if ($Launcher) { $a += @('-Launcher', ('"' + $Launcher + '"')) }
        if ($CustName) { $a += @('-CustName', ('"' + $CustName + '"')) }
        if ($CustPhone) { $a += @('-CustPhone', ('"' + $CustPhone + '"')) }
        if ($CustCode) { $a += @('-CustCode', ('"' + $CustCode + '"')) }
        if ($Symptoms) { $a += @('-Symptoms', ('"' + $Symptoms + '"')) }
        try {
            Start-Process -FilePath 'powershell.exe' -ArgumentList ($a -join ' ') -Verb RunAs -ErrorAction Stop
            Line 'Die Prüfung läuft im neuen Fenster weiter.' 'Gray'
            exit 0
        } catch {
            Line 'Ohne Erlaubnis: Es wird eine eingeschränkte Prüfung durchgeführt.' 'Yellow'
        }
    }
}

$D.customer.name = $CustName
$D.customer.phone = $CustPhone
$D.customer.code = $CustCode
$D.customer.symptoms = @(Parse-Symptoms $Symptoms)
if ($D.customer.symptoms -contains 'heiss' -or $D.customer.symptoms -contains 'langsam') { $ThermalSamples = 15 }
if ($D.customer.symptoms -contains 'wlan') { $PingCount = 20 }
if ($D.customer.symptoms -contains 'absturz' -and $Days -lt 30) { $Days = 30 }

$start = Get-Date
$rand = Get-Random -Minimum 1000 -Maximum 9999
$mode = 'Kunde'; if ($Technician) { $mode = 'Techniker' } elseif ($Quiet) { $mode = 'ohne Dialoge' }
$D.meta = [ordered]@{
    reportId = 'SOL-' + $start.ToString('yyyyMMdd-HHmm') + '-' + $rand
    created = $start
    tool = 'SoluxCheck.ps1'
    version = $ScriptVersion
    schemaVersion = $SchemaVersion
    languageMode = [string]$ExecutionContext.SessionState.LanguageMode
    isAdmin = $IsAdmin
    mode = $mode
    launcher = $Launcher
    days = $Days
    durationSec = 0
}

if ($Elevated -or -not $Interactive) { Write-Banner }
Line ('Bericht ' + $D.meta.reportId) 'Cyan'
if (-not $IsAdmin) { Line 'Eingeschränkte Prüfung (ohne Adminrechte).' 'Yellow' }
Line 'Bitte warten Sie, die Prüfung dauert etwa 1 Minute.'
Check-Version
Write-Host ''

Run-Module 'system'    'Windows und Gerät'                  { Collect-System }
Run-Module 'hardware'  'Hardware'                           { Collect-Hardware }
Run-Module 'storage'   'Festplatten und Speicher'           { Collect-Storage }
Run-Module 'thermal'   ('Temperatur und Last (' + $ThermalSamples + ' s)') { Collect-Thermal }
Run-Module 'battery'   'Akku'                               { Collect-Battery }
Run-Module 'stability' 'Abstürze und Ereignisse'            { Collect-Stability }
Run-Module 'updates'   'Windows Update'                     { Collect-Updates }
Run-Module 'security'  'Sicherheit'                         { Collect-Security }
Run-Module 'software'  'Programme'                          { Collect-Software }
Run-Module 'backup'    'Datensicherung'                     { Collect-Backup }
Run-Module 'network'   ('Netzwerk (ca. ' + (2 * $PingCount) + ' s)') { Collect-Network }
Run-Module 'win11'     'Windows-11-Fähigkeit'               { Collect-Win11 }

$D.meta.durationSec = [int]((Get-Date) - $start).TotalSeconds
Evaluate
$verdict = Get-Verdict
$recs = @(Get-Recommendations)
Compare-Previous $OutDir

try { $null = New-Item -ItemType Directory -Path $OutDir -Force -ErrorAction Stop } catch { $OutDir = Join-Path $env:USERPROFILE 'Desktop' }
$base = Join-Path $OutDir ('Solux-PC-Check-' + $D.meta.reportId)
$htmlPath = $base + '.html'
$jsonPath = $base + '.json'
$pdfPath = $base + '.pdf'
$html = Build-Html $verdict $recs
$saved = $true
try {
    $html | Out-File -FilePath $htmlPath -Encoding UTF8 -ErrorAction Stop
    Build-Json $verdict $recs | Out-File -FilePath $jsonPath -Encoding UTF8 -ErrorAction Stop
} catch {
    $saved = $false
    Line ('Bericht konnte nicht gespeichert werden: ' + $_.Exception.Message) 'Red'
}
$pdfOk = $false
if ($saved) { $pdfOk = Export-Pdf $htmlPath $pdfPath }

Write-Host ''
Write-Host '   --------------------------------------------------------------' -ForegroundColor DarkCyan
$col = 'Green'; if ($verdict.level -eq 'warnung') { $col = 'Yellow' } elseif ($verdict.level -eq 'kritisch') { $col = 'Red' }
Line ('Ergebnis: ' + $verdict.title) $col
foreach ($f in (Sort-Findings $Findings)) { if ($f.severity -ne 'hinweis') { Line ('  - ' + $f.title) } }
Write-Host '   --------------------------------------------------------------' -ForegroundColor DarkCyan
if ($saved) {
    Line 'Bericht gespeichert in:' 'Cyan'
    Line ('  ' + $OutDir)
    Write-Host ''
}

$sent = $false
if ($saved -and -not $NoUpload -and -not $Technician) {
    $askSend = $true
    if ($Config.UploadUrl) {
        if ($Interactive -or $Accepted) {
            Line 'Wir senden den Bericht verschlüsselt an Solux IT. Enthalten sind Geräte- und Systemdaten,' 'Gray'
            Line 'die Programmliste und Ihre Angaben oben, aber keine persönlichen Dateien.' 'Gray'
            $askSend = Ask-YesNo 'Bericht jetzt an Solux IT senden?' $true
        } else { $askSend = $false }
        if ($askSend) {
            $payloadPath = $base + '-senden.json'
            try {
                Build-Payload $verdict $recs $html | Out-File -FilePath $payloadPath -Encoding ASCII -ErrorAction Stop
                Line 'Sende ...' 'Gray'
                $sent = Send-Report $payloadPath
            } catch { $sent = $false }
            try { Remove-Item -LiteralPath $payloadPath -ErrorAction SilentlyContinue } catch { }
            if ($sent) { Line ('Gesendet. Ihre Berichtsnummer: ' + $D.meta.reportId) 'Green' }
            else { Line 'Senden hat nicht geklappt. Wir öffnen eine E-Mail an Solux IT und den Ordner mit den Dateien.' 'Yellow' }
        }
    }
    if (-not $sent -and $askSend -and ($Interactive -or $Accepted)) {
        if (-not $Config.UploadUrl) { Line ('Bitte senden Sie die Dateien an ' + $Solux.mail + ' (Berichtsnummer ' + $D.meta.reportId + ').') 'Cyan' }
        Open-MailFallback $OutDir $jsonPath
    }
}
$D.meta.sent = $sent

if ($saved -and -not $NoOpen) { try { Start-Process -FilePath $htmlPath } catch { } }
if ($Technician -and $saved) { try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $OutDir + '"') } catch { } }
Write-Host ''
if ($Elevated -or $Interactive) { $null = Read-Host '   Fertig. Zum Schließen Enter drücken' }
