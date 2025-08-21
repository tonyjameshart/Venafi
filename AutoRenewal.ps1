<# 
.SYNOPSIS
    Lists all certificates in Venafi TPP that are set to automatically renew,
    including their associated contact(s).

.DESCRIPTION
    This script uses the Venafi TPP REST API to retrieve all certificates 
    with automatic renewal enabled (AutoRenew = true) and outputs their DN
    along with the configured contact(s).
#>

param (
    [string]$TPPUrl = "https://tpp.example.com/vedsdk",   # Base URL for Venafi TPP REST API
    [string]$Username,                                   # TPP Username
    [string]$Password                                    # TPP Password
)

# Ignore SSL validation if using self-signed certs
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

# Authenticate
$body = @{
    Username = $Username
    Password = $Password
}
$session = Invoke-RestMethod -Method Post -Uri "$TPPUrl/authorize" -Body $body -ContentType "application/json"

if (-not $session.APIKey) {
    Write-Host "❌ Failed to authenticate to TPP" -ForegroundColor Red
    exit
}

$headers = @{ "Authorization" = "Bearer $($session.APIKey)" }

Write-Host "`n✅ Authenticated to Venafi TPP" -ForegroundColor Green

# Search for certificates with AutoRenew enabled
Write-Host "`n🔍 Searching for certificates with auto-renew enabled..." -ForegroundColor Cyan
$searchBody = @{
    "Expression" = @{
        "Field" = "AutoRenew"
        "Operator" = "eq"
        "Value" = $true
    }
    "IncludeDetails" = $true   # Ensures contacts and other fields are returned
}
$searchResults = Invoke-RestMethod -Method Post -Uri "$TPPUrl/Certificates/Retrieve" -Headers $headers -Body ($searchBody | ConvertTo-Json -Depth 5) -ContentType "application/json"

if ($null -eq $searchResults.Certificates -or $searchResults.Certificates.Count -eq 0) {
    Write-Host "⚠️ No certificates found with auto-renew enabled." -ForegroundColor Yellow
} else {
    Write-Host "`n📋 Certificates with auto-renew enabled:`n" -ForegroundColor Green
    foreach ($cert in $searchResults.Certificates) {
        $contacts = if ($cert.Contacts -and $cert.Contacts.Count -gt 0) {
            ($cert.Contacts -join ", ")
        } else {
            "No contacts assigned"
        }

        Write-Host " - $($cert.DN)" -ForegroundColor White
        Write-Host "     Contacts: $contacts" -ForegroundColor Cyan
    }
}
