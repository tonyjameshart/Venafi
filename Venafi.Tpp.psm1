# region: Globals
$script:BaseUrl = $null
$script:AccessToken = $null
$script:RefreshToken = $null
$script:SkipCertificateCheck = $false
$script:InvokeTimeoutSec = 30
# endregion

function Set-TppConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [switch]$SkipTlsVerify
    )
    $script:BaseUrl = $BaseUrl.TrimEnd('/')
    $script:SkipCertificateCheck = $SkipTlsVerify.IsPresent
}

function Invoke-TppApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [hashtable]$Body,
        [switch]$NoAuth
    )
    if (-not $script:BaseUrl) { throw "Set-TppConnection first." }
    $url = "$($script:BaseUrl)/$Path"
    $headers = @{}
    if (-not $NoAuth) {
        if (-not $script:AccessToken) { throw "Not authenticated. Call Connect-Tpp first." }
        $headers["Authorization"] = "Bearer $($script:AccessToken)"
    }
    $json = if ($Body) { $Body | ConvertTo-Json -Depth 6 -Compress } else { "{}" }
    if ($script:SkipCertificateCheck) {
        add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) { return true; }
}
"@ -ErrorAction SilentlyContinue
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    }
    Invoke-RestMethod -Uri $url -Method POST -Headers $headers -Body $json -ContentType 'application/json' -TimeoutSec $script:InvokeTimeoutSec
}

# region: Auth
function Connect-Tpp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][string]$Password,
        [string]$Scope = "certificate:manage"
    )
    $body = @{
        client_id  = "tpp"
        username   = $Username
        password   = $Password
        scope      = $Scope
        grant_type = "password"
    }
    $resp = Invoke-TppApi -Path "Authorize/OAuth" -Body $body -NoAuth
    $script:AccessToken  = $resp.access_token
    $script:RefreshToken = $resp.refresh_token
    return $resp
}

function Refresh-TppToken {
    if (-not $script:RefreshToken) { throw "No refresh token available." }
    $body = @{
        client_id     = "tpp"
        grant_type    = "refresh_token"
        refresh_token = $script:RefreshToken
    }
    $resp = Invoke-TppApi -Path "Authorize/OAuth" -Body $body -NoAuth
    $script:AccessToken  = $resp.access_token
    $script:RefreshToken = $resp.refresh_token
    return $resp
}
# endregion

# region: Certificates
function Request-TppCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PolicyDN,
        [Parameter(Mandatory)][string]$ObjectName,
        [Parameter(Mandatory)][string]$CommonName,
        [string[]]$SANs,
        [ValidateSet("RSA","ECC")][string]$KeyAlgorithm = "RSA",
        [int]$KeyBitSize = 2048,
        [string]$CSR
    )
    $body = @{
        PolicyDN        = $PolicyDN
        ObjectName      = $ObjectName
        Subject         = "CN=$CommonName"
        KeyAlgorithm    = $KeyAlgorithm
        KeyBitSize      = $KeyBitSize
        ReusePrivateKey = $false
        PickupID        = $true
        SubjectAltNames = @()
    }
    if ($SANs) { $body.SubjectAltNames = $SANs | ForEach-Object { "DNS:$_" } }
    if ($CSR)  { $body.CSR = $CSR } else { $body.Generate = $true }
    Invoke-TppApi -Path "Certificates/Request" -Body $body
}

function Get-TppCertificateStatus {
    [CmdletBinding()]
    param([string]$CertificateDN,[string]$PickupID)
    $body = @{}
    if ($CertificateDN) { $body.CertificateDN = $CertificateDN }
    if ($PickupID)      { $body.PickupID      = $PickupID }
    Invoke-TppApi -Path "Certificates/Status" -Body $body
}

function Get-TppCertificate {
    [CmdletBinding()]
    param(
        [string]$CertificateDN,
        [string]$PickupID,
        [ValidateSet("PEM","DER","PKCS12")][string]$Format = "PEM",
        [switch]$IncludePrivateKey,
        [string]$Password = ""
    )
    $body = @{
        Format       = $(if ($Format -in @("PEM","PKCS12")) { "Base64" } else { "DER" })
        IncludeChain = $true
        IncludeRoot  = $false
    }
    if ($CertificateDN) { $body.CertificateDN = $CertificateDN }
    if ($PickupID)      { $body.PickupID      = $PickupID }
    if ($IncludePrivateKey) {
        $body.IncludePrivateKey = $true
        $body.Password          = $Password
    }
    $resp = Invoke-TppApi -Path "Certificates/Retrieve" -Body $body
    $b64 = $resp.CertificateData ?? $resp.PKCS12Data
    [Convert]::FromBase64String($b64)
}

function Renew-TppCertificate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CertificateDN,[switch]$ReusePrivateKey)
    $body = @{
        CertificateDN   = $CertificateDN
        ReusePrivateKey = $ReusePrivateKey.IsPresent
        PickupID        = $true
    }
    Invoke-TppApi -Path "Certificates/Renew" -Body $body
}

function Revoke-TppCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CertificateDN,
        [string]$Reason = "cessationOfOperation"
    )
    $body = @{
        CertificateDN = $CertificateDN
        Reason        = $Reason
    }
    Invoke-TppApi -Path "Certificates/Revoke" -Body $body
}
# endregion

# region: Config
function Read-TppConfig {
    param([Parameter(Mandatory)][string]$ObjectDN)
    Invoke-TppApi -Path "Config/Read" -Body @{ ObjectDN = $ObjectDN }
}

function Write-TppConfig {
    param([Parameter(Mandatory)][string]$ObjectDN,[Parameter(Mandatory)][hashtable]$Attributes)
    Invoke-TppApi -Path "Config/Write" -Body @{ ObjectDN = $ObjectDN; Attributes = $Attributes }
}
# endregion

# region: Discovery
function Import-TppDiscovery {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][hashtable]$Settings)
    Invoke-TppApi -Path "Discovery/Import" -Body @{ Name = $Name; Settings = $Settings }
}

function Start-TppDiscovery {
    param([Parameter(Mandatory)][string]$JobDN)
    Invoke-TppApi -Path "Discovery/Start" -Body @{ JobDN = $JobDN }
}

function Get-TppDiscoveryStatus {
    param([Parameter(Mandatory)][string]$JobDN)
    Invoke-TppApi -Path "Discovery/Status" -Body @{ JobDN = $JobDN }
}
# endregion

# region: SSH
function Set-TppSshKey {
    param([Parameter(Mandatory)][string]$DeviceDN,[Parameter(Mandatory)][string]$KeyData)
    Invoke-TppApi -Path "SSH/KeySet" -Body @{ DeviceDN = $DeviceDN; KeyData = $KeyData }
}

function Get-TppSshKey {
    param([Parameter(Mandatory)][string]$DeviceDN)
    Invoke-TppApi -Path "SSH/KeyGet" -Body @{ DeviceDN = $DeviceDN }
}
# endregion

# region: Workflow
function Approve-TppWorkflow {
    param([Parameter(Mandatory)][string]$WorkflowDN)
    Invoke-TppApi -Path "Workflow/Approve" -
