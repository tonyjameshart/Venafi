<#
.SYNOPSIS
    Lists all Venafi devices that have no applications bound to them.

.DESCRIPTION
    Connects to the Venafi REST API (VEDSDK), retrieves all devices,
    checks for linked applications, and returns those with zero apps.
    Includes verbose logging to console and log file.

.NOTES
    Author: Tony Hart
    Requires: API key or OAuth token with sufficient privileges.
#>

param (
    [string]$VenafiBaseUrl = "https://your.venafi.instance/vedsdk",
    [string]$AccessToken,  # OAuth2 or API key
    [string]$LogFile = ".\VenafiDevicesWithoutApps.log"
)

function Log {
    param([string]$Message, [ConsoleColor]$Color = "Gray")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp | $Message" -ForegroundColor $Color
    Add-Content -Path $LogFile -Value "$timestamp | $Message"
}

function Invoke-VenafiApi {
    param (
        [string]$Endpoint,
        [string]$Method = "GET",
        [object]$Body = $null
    )
    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }

    $uri = "$VenafiBaseUrl/$Endpoint"
    if ($Body) {
        $Body = $Body | ConvertTo-Json -Depth 10
    }
    Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers -Body $Body
}

# --- Script Start ---
Log "🚀 Starting Venafi device scan…" "Cyan"

# 1️⃣ Get all devices
Log "📡 Retrieving device inventory…" "Cyan"
$devices = Invoke-VenafiApi -Endpoint "Devices"
Log "📋 Total devices retrieved: $($devices.Devices.Count)" "Yellow"

$devicesWithoutApps = @()

# 2️⃣ For each device, check apps
foreach ($device in $devices.Devices) {
    Log "🔍 Checking apps for device: $($device.DeviceName) [$($device.DeviceId)]" "White"
    $apps = Invoke-VenafiApi -Endpoint "Devices/$($device.DeviceId)/Applications"

    if (-not $apps.Applications -or $apps.Applications.Count -eq 0) {
        Log "⚠️  No apps linked to $($device.DeviceName)" "Red"
        $devicesWithoutApps += $device
    }
    else {
        Log "✅ $($apps.Applications.Count) app(s) linked to $($device.DeviceName)" "Green"
    }
}

# 3️⃣ Output final report
Log "📊 Devices without apps: $($devicesWithoutApps.Count)" "Magenta"
$devicesWithoutApps |
    Select-Object DeviceName,DeviceId,Host,ParentFolder |
    Format-Table -AutoSize

Log "🏁 Device scan complete."