# Get-VenafiCertificateHistory.ps1
# Purpose: Connect to Venafi API, find certificate by name, and list historical validity dates
# Author: Tony Hart
# Version: 1.0

param (
    [string]$VenafiBaseUrl = "https://your.venafi.instance/vedsdk",
    [string]$AccessToken,  # OAuth or API token
    [string]$CertificateName,
    [string]$LogFile = "VenafiCertHistory.log"
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
    $response = Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers -Body ($Body | ConvertTo-Json -Depth 10)
    return $response
}

# Start
Log "🔍 Searching for certificate: '$CertificateName'"

# Step 1: Search for certificate
$response = Invoke-VenafiApi -Endpoint "certificates?filter=Name=$CertificateName"

if (-not $response.certificates -or $response.certificates.Count -eq 0) {
    Log "❌ Certificate '$CertificateName' not found."
    exit 1
}

$certId = $response.certificates[0].certificateId
Log "✅ Found certificate ID: $certId"

# Step 2: Get historical versions
$history = Invoke-VenafiApi -Endpoint "certificates/$certId/versions"

if (-not $history.versions -or $history.versions.Count -eq 0) {
    Log "⚠️ No historical versions found for '$CertificateName'."
    exit 0
}

Log "📜 Listing historical versions for '$CertificateName':"
foreach ($version in $history.versions) {
    Log "🔹 Version ID: $($version.id)"
    Log "    Valid From: $($version.validFrom)"
    Log "    Valid To:   $($version.validTo)"
    Log "    Thumbprint: $($version.thumbprint)"
    Log "    Serial #:   $($version.serialNumber)"
    Log "------------------------------------------------------------"
}

Log "🏁 Certificate history retrieval complete."