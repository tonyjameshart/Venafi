<#
.SYNOPSIS
    Lists all Venafi certificates missing a contact or approvers.

.DESCRIPTION
    Connects to the Venafi REST API (VEDSDK) using an API token.
    Retrieves all certificates, checks for empty/null Contacts or Approvers fields,
    logs findings to console and file.

.NOTES
    Author: Tony Hart
    Requires: API key or OAuth token with rights to read certificate metadata.
#>

param (
    [string]$VenafiBaseUrl = "https://your.venafi.instance/vedsdk",
    [string]$AccessToken,  # OAuth2 or API key
    [string]$LogFile = ".\VenafiCertsMissingContactsOrApprovers.log"
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
Log "🚀 Starting Venafi certificate metadata scan…" "Cyan"

# 1️⃣ Get all certificates (paging may be required for large inventories)
Log "📡 Retrieving certificates list…" "Cyan"
$certs = Invoke-VenafiApi -Endpoint "Certificates"

if (-not $certs.Certificates) {
    Log "❌ No certificates returned — check API token/permissions." "Red"
    exit 1
}

Log "📋 Total certificates retrieved: $($certs.Certificates.Count)" "Yellow"

$missingList = @()

# 2️⃣ Check each certificate for missing Contact(s) or Approvers
foreach ($cert in $certs.Certificates) {
    $details = Invoke-VenafiApi -Endpoint "Certificates/$($cert.Id)"

    $missingContact = (-not $details.Contact -or $details.Contact.Count -eq 0)
    $missingApprovers = (-not $details.Approver -or $details.Approver.Count -eq 0)

    if ($missingContact -or $missingApprovers) {
        Log "⚠️  Missing info for cert: $($details.Name)" "Red"
        if ($missingContact)  { Log "    - No Contact assigned" "Yellow" }
        if ($missingApprovers){ Log "    - No Approvers assigned" "Yellow" }
        $missingList += [PSCustomObject]@{
            Name       = $details.Name
            Id         = $details.Id
            Missing    = @(
                if ($missingContact)  { "Contact" }
                if ($missingApprovers){ "Approvers" }
            ) -join ", "
        }
    }
}

# 3️⃣ Final Report
if ($missingList.Count -eq 0) {
    Log "✅ All certificates have both contacts and approvers." "Green"
} else {
    Log "📊 Certificates missing Contact/Approvers: $($missingList.Count)" "Magenta"
    $missingList | Format-Table -AutoSize
}

Log "🏁 Scan complete."