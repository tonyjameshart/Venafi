# Get-VenafiExpiredCerts.ps1
# Purpose: Connect to Venafi API and list all expired certificates
# Author: Tony's AI Copilot
# Version: 1.0

param (
    [string]$VenafiBaseUrl = "https://your.venafi.instance/vedsdk",
    [string]$AccessToken,  # OAuth or API token
    [string]$LogFile = "VenafiExpiredCerts.log"
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
Log "🚀 Starting Venafi expired certificate check"

$now = Get-Date
$filterDate = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")

Log "📅 Current date/time: $now"

# Filter for certificates with a ValidTo before 'now'
$response = Invoke-VenafiApi -Endpoint "certificates?validTo<=$filterDate"

if (-not $response.certificates -or $response.certificates.Count -eq 0) {
    Log "✅ No expired certificates found."
    exit 0
}

Log "⚠️ Found $($response.certificates.Count) expired certificate(s)"

foreach ($cert in $response.certificates) {
    $expires = [datetime]$cert.validTo
    if ($expires -lt $now) {
        Log "🔹 Name:       $($cert.name)"
        Log "    ID:         $($cert.certificateId)"
        Log "    Valid From: $($cert.validFrom)"
        Log "    Valid To:   $expires"
        Log "    Thumbprint: $($cert.thumbprint)"
        Log "------------------------------------------------------------"
    }
}

Log "🏁 Expired certificate report complete."