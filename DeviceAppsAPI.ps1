<#
.SYNOPSIS
    Provides a reconciliation report for Devices and apps using Venafi TPP REST API.

.DESCRIPTION
    This PowerShell script compares devices from a CSV file to devices in Venafi TPP policy folders.
    It queries the TPP REST API directly (no VenafiPS module).  
    Generates an Excel reconciliation report.

.NOTES
    Author      : Tony Hart
    Last Updated: 8/21/2025
    Version     : 1.0
#>

###### Modules ######
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Install-Module -Name ImportExcel -Scope CurrentUser
}
Import-Module ImportExcel

###### Hashtable Variables ######
$Appdetail = @()
$Policy    = @()
$Devices   = @()
$detailed  = @()

###### Authentication ######
$baseUri = "https://venafi.humana.com/vedsdk"

Write-Host "API Integration Values `n"
Write-Host "The ClientID must have a scope of " -NoNewline
Write-Host "certificate:discover,manage;Configuration:manage" -ForegroundColor Yellow -BackgroundColor Red -NoNewline
Write-Host " or more. `nAnd the user must have access"

[string]$clientID = Read-Host "`n Enter ClientID"
[PSCredential]$VenafitppCred = Get-Credential

# Get OAuth token
$body = @{
    username   = $VenafitppCred.UserName
    password   = $VenafitppCred.GetNetworkCredential().Password
    client_id  = $clientID
    scope      = "certificate:discover,manage;configuration:manage"
    state      = "randomstate"
    redirect_uri = "urn:InstalledApplication"
    response_type = "token"
}
$auth = Invoke-RestMethod -Method Post -Uri "$baseUri/authorize/oauth" -Body $body
$token = $auth.access_token

$headers = @{
    Authorization = "Bearer $token"
}

###### Policy folder Name and App Type ######
$polname = Read-Host "Policy Folders Name"
$apptype = Read-Host "Type of App"

###### Set file locations ######
Write-Host "`n`nCSV must contain a column named 'DeviceName'" -ForegroundColor Yellow -BackgroundColor Red
[string]$CsvPath = Read-Host "`nInput full path of the csv file with devices"
$CsvPath = $CsvPath -replace '"',''

while (-not (Test-Path $CsvPath)) {
    Write-Host "Could not find file..."
    $CsvPath = Read-Host "`nInput full path of the csv file"
}
Write-Host "`n$CsvPath File found!`n"

[string]$OutPutPath = Read-Host "`nInput full path of the Excel results file"
$OutPutPath = $OutPutPath -replace '"',''
Write-Host "`nThe results file path is `n $OutPutPath`n"

###### Query Venafi ######
Write-Host "Getting policy objects..."
$policySearch = Invoke-RestMethod -Method Post -Uri "$baseUri/Config/FindObjects" -Headers $headers -Body (@{ 
    Class   = "Policy"; 
    Pattern = "*$polname*"; 
    Recursive = $true 
} | ConvertTo-Json -Depth 3)

$policies = $policySearch.Objects
foreach ($p in $policies) {
    $policyPath = $p.DN
    $deviceSearch = Invoke-RestMethod -Method Post -Uri "$baseUri/Config/FindObjects" -Headers $headers -Body (@{ 
        Class   = "Device"; 
        Pattern = "*"; 
        Recursive = $true; 
        ObjectDN = $policyPath
    } | ConvertTo-Json -Depth 3)

    $Devices += $deviceSearch.Objects
}

# Original Venafi device names
$venafiDeviceNames = $Devices.Name
$venafiDeviceCount = $venafiDeviceNames.Count
$venafiShortNames = $venafiDeviceNames | ForEach-Object { ($_ -split '\.')[0].ToLower() }
Write-Host "`nFound $venafiDeviceCount device(s) in Venafi."

# Import CSV
$csvDevices = Import-Csv -Path $CsvPath
if (-not ($csvDevices | Get-Member -Name DeviceName -MemberType NoteProperty)) {
    Write-Error "CSV must contain a column named 'DeviceName'"
    exit
}
$csvDeviceNames = $csvDevices.DeviceName | ForEach-Object { $_.ToLower() }
$csvDeviceCount = $csvDeviceNames.Count
Write-Host "CSV contains $csvDeviceCount device(s)."

# Compare
$inVenafiNotCsv = $venafiShortNames | Where-Object { $_ -notin $csvDeviceNames }
$inCsvNotVenafi = $csvDeviceNames | Where-Object { $_ -notin $venafiShortNames }
$inBoth         = $csvDeviceNames | Where-Object { $_ -in $venafiShortNames }

$summary = [PSCustomObject]@{
    Policy              = $polname
    Venafi_Devices      = $venafiDeviceCount
    CSV_Devices         = $csvDeviceCount
    InVenafiNotCsvCount = $inVenafiNotCsv.Count
    InCsvNotVenafiCount = $inCsvNotVenafi.Count
    InBothCount         = $inBoth.Count
}

Write-Host "`n----- Reconciliation Report -----"
$summary | Format-List
Write-Host "---------------------------------"

###### Detailed reconciliation ######
foreach ($dev in $Devices) {
    $fqdn  = $dev.Name
    $short = ($fqdn -split '\.')[0].ToLower()
    $status = if ($csvDeviceNames -contains $short) { "In Both" } else { "Only in Venafi" }

    $detailed += [PSCustomObject]@{
        DeviceName = $fqdn
        Path       = $dev.DN
        Source     = $status
    }
}

foreach ($dev in $inCsvNotVenafi) {
    $detailed += [PSCustomObject]@{
        DeviceName = $dev
        Path       = "Not in Venafi"
        Source     = "Only in CSV"
    }
}

###### Export reconciliation report ######
Write-Host "`nExporting reconciliation report to $OutPutPath..."
$summary  | Export-Excel -Path $OutPutPath -WorksheetName Report
$detailed | Export-Excel -Path $OutPutPath -WorksheetName List

###### Get apps for each device ######
foreach ($d in $Devices) {
    Write-Host "`nGetting apps for $($d.Name)..."

    $apps = Invoke-RestMethod -Method Post -Uri "$baseUri/Config/Enumerate" -Headers $headers -Body (@{
        ObjectDN = $d.DN
        Recursive = $true
    } | ConvertTo-Json -Depth 3)

    $datapowerApps = $apps.Objects | Where-Object { $_.ClassName -like "*$apptype*" }

    if ($datapowerApps.Count -gt 0) {
        foreach ($app in $datapowerApps) {
            $certAttr = Invoke-RestMethod -Method Post -Uri "$baseUri/Config/Read" -Headers $headers -Body (@{
                ObjectDN = $app.DN
                AttributeName = "Certificate"
            } | ConvertTo-Json -Depth 3)

            $Appdetail += [PSCustomObject]@{
                APPName     = $app.Name
                Path        = $app.DN
                Certificate = $certAttr.Values -join ";"
            }
        }
        $Appdetail | Export-Excel -Path $OutPutPath -WorksheetName $d.Name
    }
}

Write-Host "`nDevice export complete."
Start-Process $OutPutPath
