function New-ADSession ($dcs, $adUser, $cmdlets) {
 for ($i = 0; $i -lt 30; $i++) {
  foreach ($server in $dcs) {
   # At least one dc is on at all times unless catastrophe
   Write-Verbose ('{0},Checking [{1}]' -f $MyInvocation.MyCommand.Name, $server)
   if (Test-Connection $server -Count 1 -Quiet) { $global:dc = $server; return }
  }
  Start-Sleep 10 # If connections to all dcs fail then wait before trying again
 }
 $session = New-PSSession -ComputerName $adDC -Credential $adUser
 Import-PSSession -Session $session -Module ActiveDirectory -CommandName $cmdlets -AllowClobber | Out-Null
 $msgVars = $MyInvocation.MyCommand.Name, $dc, ($cmdLets -join ',')
 Write-Verbose ('{0},{1}' -f $msgVars)
}