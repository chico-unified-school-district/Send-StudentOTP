function New-ADSession ($dc, $adUser, $cmdlets) {
 $session = New-PSSession -ComputerName $dc -Credential $adUser
 Import-PSSession -Session $session -Module ActiveDirectory -CommandName $cmdlets -AllowClobber | Out-Null
 $msgVars = $MyInvocation.MyCommand.Name, $dc, ($cmdLets -join ',')
 Write-Verbose ('{0},{1}' -f $msgVars)
}