function Test-ADSession {
 [cmdletbinding()]
 param (
  [string[]]$DomainControllers
  , [System.Management.Automation.PSCredential]$ADCred
  , $Cmdlets
 )

 $maxRetries = 30

 function Select-DomainController([string[]]$myDCs) {
  foreach ($dc in $myDCs) {
   Write-Verbose ('Checking {0},{1}' -f $MyInvocation.MyCommand.Name, $dc)
   if (Test-Connection -ComputerName $dc -Quiet -ErrorAction SilentlyContinue) {
    Write-Host ('{0},Current Domain Controller {1}' -f $MyInvocation.MyCommand.Name, $dc)
    return $dc
   }
  }
  $msgVars = $MyInvocation.MyCommand.Name, ($myDCs -join ',')
  Write-Host ('{0},{1},No Controller is reachalbe at this time. Waiting a bit.' -f $msgVars)
  Start-Sleep 30
  Select-DomainController $myDCs
 }

 function New-ADSession ($adDC, [System.Management.Automation.PSCredential]$cred, $adCmdlets) {
  $msgVars = $MyInvocation.MyCommand.Name, $adDC, ($cmdLets -join ',')
  Write-Verbose ('{0},{1}' -f $msgVars)
  $adSession = New-PSSession -ComputerName $adDC -Credential $cred
  Import-PSSession -Session $adSession -Module ActiveDirectory -CommandName $adCmdLets -AllowClobber | Out-Null
 }

 if (!$global:dc) { $global:dc = Select-DomainController $DomainControllers }
 if (!(Test-ComputerSecureChannel -Server $global:dc -ErrorAction SilentlyContinue)) {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $global:dc)
  New-ADSession  $global:dc $ADCred $Cmdlets
 }
 if ((!(Test-ComputerSecureChannel -Server $global:dc -ErrorAction SilentlyContinue)) -and ($i -lt $maxRetries)) {
  $i += 1
  Start-Sleep 30
  Test-ADSession $DomainControllers $ADCred $Cmdlets
 }
}