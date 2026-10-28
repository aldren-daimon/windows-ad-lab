<#
.SYNOPSIS
    Quick health check of a Windows computer, saved as an HTML report.

.DESCRIPTION
    Collects uptime, CPU load, memory use, disk space, automatic services that are
    not running, and system errors from the last 24 hours. Flags problems:
      - disk free space under 15%
      - memory use over 85%
    Works on any Windows 10/11 PC or Windows Server (no Active Directory needed).

.EXAMPLE
    .\Get-HealthCheck.ps1
    .\Get-HealthCheck.ps1 -ReportPath C:\Reports\pc01.html

.NOTES
    Author : Al-Dren S. Daimon
#>

param(
    [string]$ReportPath = ".\HealthCheck_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmm').html"
)

# --- Collect the data (CIM = the modern way to read Windows system info) ---
$os     = Get-CimInstance -ClassName Win32_OperatingSystem
$uptime = (Get-Date) - $os.LastBootUpTime
$cpu    = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
$memPct = [math]::Round((1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100, 1)

# Local hard disks only (DriveType 3)
$disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
    $freePct = [math]::Round($_.FreeSpace / $_.Size * 100, 1)
    [pscustomobject]@{
        Drive    = $_.DeviceID
        SizeGB   = [math]::Round($_.Size / 1GB, 1)
        FreeGB   = [math]::Round($_.FreeSpace / 1GB, 1)
        FreePct  = $freePct
        Status   = if ($freePct -lt 15) { 'WARNING' } else { 'OK' }
    }
}

# Services set to start automatically but not running right now
$stopped = Get-CimInstance -ClassName Win32_Service -Filter "StartMode='Auto' AND State<>'Running'" |
    Select-Object Name, DisplayName, State

# Last 10 errors (Level 2) in the System log from the past 24 hours
$errors = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 2; StartTime = (Get-Date).AddDays(-1) } `
            -MaxEvents 10 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, ProviderName, Id, @{ n = 'Message'; e = { ($_.Message -split "`n")[0] } }

# --- Summary ---
$summary = [pscustomobject]@{
    Computer     = $env:COMPUTERNAME
    OS           = $os.Caption
    Uptime       = '{0}d {1}h {2}m' -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    CPULoadPct   = $cpu
    MemoryUsePct = $memPct
    MemoryStatus = if ($memPct -gt 85) { 'WARNING' } else { 'OK' }
    CheckedAt    = Get-Date -Format 'yyyy-MM-dd HH:mm'
}

# --- Build the HTML report ---
$style = @'
<style>
 body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #222; }
 h1 { color: #1F3A5F; } h2 { color: #1F3A5F; border-bottom: 2px solid #1F3A5F; }
 table { border-collapse: collapse; margin-bottom: 18px; }
 th, td { border: 1px solid #ccc; padding: 6px 10px; text-align: left; }
 th { background: #eef2f7; }
</style>
'@

$body  = "<h1>Health Check: $($env:COMPUTERNAME)</h1>"
$body += '<h2>Summary</h2>'          + ($summary | ConvertTo-Html -Fragment -As List)
$body += '<h2>Disks</h2>'            + ($disks   | ConvertTo-Html -Fragment)
$body += '<h2>Stopped automatic services</h2>' +
         $(if ($stopped) { $stopped | ConvertTo-Html -Fragment } else { '<p>None</p>' })
$body += '<h2>System errors (last 24h)</h2>' +
         $(if ($errors)  { $errors  | ConvertTo-Html -Fragment } else { '<p>None</p>' })

# Highlight WARNING cells in red
$body = $body -replace '<td>WARNING</td>', '<td style="color:#b00020;font-weight:bold">WARNING</td>'

ConvertTo-Html -Head $style -Body $body -Title "Health Check $($env:COMPUTERNAME)" |
    Out-File -FilePath $ReportPath -Encoding utf8

# --- Show the key numbers on screen too ---
$summary | Format-List
$disks   | Format-Table -AutoSize
Write-Host "Report saved to $ReportPath" -ForegroundColor Green
