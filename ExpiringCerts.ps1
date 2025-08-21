# Get-VenafiExpiringCerts.ps1
# Purpose: Connect to Venafi API and list certificates expiring within the next 14 days
# Author: Tony Hart
# Version: 1.0

param (
    [string]$VenafiBaseUrl = "https://your.venafi.instance/vedsdk",
    [string]$AccessToken,       # OAuth or API token
    [int]$DaysUntilExpiry = 14, # Change this if needed
    [string]$LogFile = "VenafiExpiringCerts.log"
)

function Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp | $Message"
    Add-Content -Path $LogFile -Value $entry
    Write-Host $entry
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
Log "🚀 Starting Venafi expiring cert check (Next $DaysUntilExpiry days)"

$today = Get-Date
$cutOff = $today.AddDays($DaysUntilExpiry)

Log "📅 Today:   $today"
Log "📅 Cut-off: $cutOff"

# Adjust filter according to your Venafi API schema
$filterDate = $cutOff.ToString("yyyy-MM-ddTHH:mm:ssZ")

$response = Invoke-VenafiApi -Endpoint "certificates?validTo<=$filterDate"

if (-not $response.certificates -or $response.certificates.Count -eq 0) {
    Log "✅ No certificates expiring within $DaysUntilExpiry days."
    exit 0
}

Log "⚠️ Found $($response.certificates.Count) certificate(s) nearing expiration"

foreach ($cert in $response.certificates) {
    $expires = [datetime]$cert.validTo
    if ($expires -le $cutOff) {
        Log "🔹 Name:       $($cert.name)"
        Log "    ID:         $($cert.certificateId)"
        Log "    Valid From: $($cert.validFrom)"
        Log "    Valid To:   $expires"
        Log "    Thumbprint: $($cert.thumbprint)"
        Log "------------------------------------------------------------"
    }
}

Log "🏁 Expiring certificate report complete."