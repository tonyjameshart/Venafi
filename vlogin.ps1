Install-Module VenafiPS -Scope CurrentUser
Import-module Venafips
$server = "venafi.domain.com"
$URI = "HTTPS://$server//VEDauth/Authorize"
$clientID = "admin"
$scope = "@{'certificate'='approve,delete,discover,manage,revoke';'Configuration'='manage'}"

[string]$username = 'username'
[string]$userpassword = 'password'
[securestring]$securePwd = ConvertTo-SecureString $userPassword -AsPlainText -Force
[PSCredential]$VenafiTPPCred = [System.Management.Automation.PSCredential]::new($username, $securePwd)
New-VenafiSession -Server $server -Credential $VenafiTPPCred -ClientId $clientID -Scope $scope