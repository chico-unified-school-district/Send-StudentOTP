[cmdletbinding()]
param (
 [Parameter(Mandatory = $True)]
 [Alias('DCs')]
 [string[]]$DomainControllers,
 [Parameter(Mandatory = $True)]
 [System.Management.Automation.PSCredential]$ADCredential,
 [Parameter(Mandatory = $True)]
 [string]$SISServer,
 [Parameter(Mandatory = $True)]
 [string]$SISDatabase,
 [Parameter(Mandatory = $True)]
 [System.Management.Automation.PSCredential]$SISCredential,
 [Parameter(Mandatory = $True)]
 [int[]]$SiteCodes,
 [Parameter(Mandatory = $True)]
 [string]$IntSqlServer,
 [Parameter(Mandatory = $True)]
 [string]$IntSqlDatabase,
 [Parameter(Mandatory = $True)]
 [System.Management.Automation.PSCredential]$IntSqlCredential,
 [Parameter(Mandatory = $True)]
 [string]$IntSqlTable,
 [Parameter(Mandatory = $True)]
 [System.Management.Automation.PSCredential]$EmailCredential,
 [Parameter(Mandatory = $false)]
 [string[]]$Bcc,
 [Parameter(Mandatory = $true)]
 [string[]]$AdminEmail,
 [Parameter(Mandatory = $True)]
 [string]$FormUrl,
 [string]$StopTime = "11:00 PM",
 [Alias('wi')]
 [SWITCH]$WhatIf
)
function Add-OPTEntry ($params, $table, $baseSql) {
 begin {
  $sql = $baseSql -f $table
 }
 process {
  $sqlVars = "id=$($_.stuId)", "num=$($_.stuNum)", "gr=$($_.grade)", "sc=$($_.siteCode)",
  "sam=$($_.samid)", "@email=$($_.email)", "otp=$($_.otp)", "reqDate=$(Get-Date)", "src=$ENV:COMPUTERNAME"
  $sql = $baseSql -f $table
  Write-Host ('{0},[{1}]' -f $MyInvocation.MyCommand.Name, ($sqlVars -join ',')) -F Magenta
  Write-Verbose ('{0},[{1}],[{2}]' -f $MyInvocation.MyCommand.Name, $sql, ($sqlVars -join ','))
  if (!$WhatIf) { New-SqlOperation @params -Query $sql -Parameters $sqlVars }
  $_
 }
}

function Format-OtpEmailObj {
 process {
  $obj = '' | Select-Object stuId, stuNum, siteCode, grade, otp,
  initiator, samid, guid, pwExpires, email, error
  $obj.stuId = $_.id
  $obj.stuNum = $_.sn
  $obj.siteCode = $_.sc
  $obj.grade = $_.gr
  $obj
 }
}

function Format-PwResetObj {
 process {
  $obj = '' | Select-Object id, stuId, stuNum, siteCode, grade, otp,
  samid, guid, pwExpires, email, pw, success, pwGood
  $obj.id = $_.id
  $obj.stuId = $_.permId
  $obj.stuNum = $_.stuNum
  $obj.siteCode = $_.siteCode
  $obj.grade = $_.grade
  $obj.samid = $_.samid
  $obj.pw = $_.newPw
  $obj.pwExpires = if ($_.grade -ge 6) { $true } else { $false }
  $obj.otp = $_.otp
  $obj.email = $_.staffEmail
  $obj
 }
}

function Get-Email {
 process {
  if ($_.initiator.length -lt 1) { return $_ }
  $obj = Get-ADuser -Filter ("SamAccountName -eq '{0}'" -f $_.initiator) -Properties Mail
  if (!$obj) {
   $msg = $MyInvocation.MyCommand.Name, $_.samid, $_.initiator
   Write-Host ('{0},{1},{2},AD Staff obj not found' -f $msg) -F Red
  }
  $_.email = $obj.Mail
  $_
 }
}

function Get-Usr ($params, $sql) {
 process {
  $sqlVars = "id=$($_.stuId)"
  $data = New-SqlOperation @params -Query $sql -Parameters $sqlVars
  $msg = $MyInvocation.MyCommand.Name, $_.stuId
  if ($data.usr.length -lt 1) { Write-Host ('{0},{1},No inititor found in LOG.' -f $msg ) -F Red }
  $_.initiator = $data.usr
  $_
 }
}

function Get-SISPwRequests ($params, $baseSql, $sites) {
 process {
  $myValues = '(' + ($sites -join '),(') + ')'
  $sql = $baseSql -replace ('MY_VALUES', $myValues)
  Write-Verbose ('{0},DB:{1},Sql: [{2}]' -f $MyInvocation.MyCommand.Name, $SISDatabase, $sql)
  New-SqlOperation @params -Query $sql
 }
}

function Get-StuADInfo {
 process {
  if ($global:missingInAD -contains $_.stuId) { return }
  $obj = Get-ADuser -Filter ("EmployeeId -eq '{0}'" -f $_.stuId)
  if (!$obj) {
   $global:missingInAD += $_.stuId
   $msg = $MyInvocation.MyCommand.Name, $_.stuId
   return (Write-Host ('{0},{1},AD Student obj not found' -f $msg ) -F Red)
  }
  $_.samid = $obj.SamAccountName
  $_.guid = $obj.ObjectGUID
  $_
 }
}

function New-OTP {
 begin { function New-RandomOTP { Get-Random -Min 111111 -max 999999 } }
 process { $_.otp = (New-RandomOTP); $_ }
}

function Reset-DbEntry ($params, $sql) {
 process {
  $sqlVars = "sc=$($_.siteCode)", "sn=$($_.stuNum)"
  if (!$WhatIf) { New-SqlOperation @params -Query $sql -Parameters $sqlVars }
  Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.Name, $sql, ($sqlVars -join ','))
  $_
 }
}

function Send-OTPMsg ($url) {
 begin {
  $baseHtml = Get-Content '.\html\otp-msg.html' -Raw
  $baseErrorHtml = Get-Content '.\html\otp-error-msg.html' -Raw
  $params = @{
   From       = '<{0}>' -f $EmailCredential.Username
   Subject    = $null
   BodyAsHTML = $True
   Bcc        = $null
   SMTPServer = 'smtp.office365.com'
   Cred       = $EmailCredential # use a valid Office365 account with Flow rules in place to prevent SPAM warnings.
   UseSSL     = $True
   Port       = 587
  }
 }
 process {
  if ($null -eq $_.email) {
   $params.to = $AdminEmail
   $params.subject = 'Error - CUSD Student OTP'
   $params.Body = $baseErrorHtml -f $_.samid, $_.grade, $_.initiator
  }
  else {
   $params.To = '<{0}>' -f $_.email
   $params.subject = 'CUSD Student OTP'
   $params.Body = $baseHtml -f $_.samid, $_.otp, $url , $_.grade
  }
  $msg = $MyInvocation.MyCommand.Name, $params.Subject, ($params.to -join ','), $_.samid, (Get-Date)
  Write-Host ('{0},{1},{2},{3},{4}' -f $msg) -F Blue
  if ( $Bcc ) { $params.Bcc = $Bcc } # Add Bcc to outgoing email messages.
  if (!$WhatIf) {
   try { Send-MailMessage @params } catch {
    $msg = $MyInvocation.MyCommand.Name, $_.samid, $_.siteCode
    Write-Host ('{0},{1},{2},Message did not send. Skipping' -f $msg) -F red
   }
  }
  Write-Verbose ($params.body | out-string)
  $_
 }
}

function Set-OtpDel ($params, $table, $baseSql) {
 $recentRequestsSql = $baseSql -f $table
 $recentRequests = New-SqlOperation @params -Query $recentRequestsSql
 if (!$recentRequests) { return }
 Write-Host('{0},{1},{2},{3}' -f $MyInvocation.MyCommand.Name, $data.id, $data.permId, (Get-Date))
 # This 'deletes' entries that are over 10 minutes old, essentially expiring the OTP/Reset request - Kinda Important!
 $expireRecentSql = "UPDATE {0} SET del = 1 WHERE requestDate < DATEADD(minute, -10, getdate()) AND del IS NULL" -f $table
 if (!$WhatIf) { New-SqlOperation @params -Query $expireRecentSql }
}

function Show-Obj { Process { Write-Verbose ($MyInvocation.MyCommand.Name, $_ | Out-String) } }

function Skip-OTP ($params, $table, $baseSql) {
 process {
  $sql = $baseSql -f $table, $id
  $sqlVars = "id=$($_.stuId)"
  $data = New-SqlOperation @params -Query $sql -Parameters $sqlVars
  # Skip requests older than 10 minutes. Who needs em!
  if ($data) { return }
  $_
 }
}

function Reset-Pw {
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.samid) -f DarkBlue
  $pw = (ConvertTo-SecureString $_.pw -AsPlainText -force)
  try {
   Set-ADAccountPassword -Identity $_.guid -NewPassword $pw -Reset -Confirm:$false -Whatif:$WhatIf
  }
  catch { $_.success = $false }
  if (!$WhatIf) { Start-Sleep 3 }
  $_
 }
}

function Clear-OTPRequest ($params, $table, $baseSql) {
 process {
  $sql = $baseSql -f $table
  $sqlVars = "id=$($_.id)"
  Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.Name, $sql, ($sqlVars -join ','))
  if (!$WhatIf) { New-SqlOperation @params -Query $sql -Parameters $sqlVars }
 }
}

# =============================== Main ==================================

# ============================================================================================
$SaveVerbosePreference = $global:VerbosePreference
$global:VerbosePreference = 'SilentlyContinue'
Import-Module -Name CommonScriptFunctions, dbatools
$global:VerbosePreference = $SaveVerbosePreference

Show-BlockInfo main

if ($WhatIf) { Show-TestRun }

$adCmdLets = 'Get-ADUser', 'Set-ADAccountPassword'

$sqlParamsSIS = @{
 Server     = $SISServer
 Database   = $SISDatabase
 Credential = $SISCredential
}

$sqlParamsInt = @{
 Server     = $IntSqlServer
 Database   = $IntSqlDatabase
 Credential = $IntSqlCredential
}

$Global:missingInAD = $null

$clearIntEntry = Get-Content -Path '.\sql\clear-int-entry.sql' -Raw
$delExpiredOTPInt = Get-Content -Path '.\sql\del-expired-otp.sql' -Raw
$getPwResets = Get-Content -Path '.\sql\get-pw-resets.sql' -Raw
$getRecentOtpInt = Get-Content '.\sql\get-recent-otp.sql' -Raw
$getSISRequest = Get-Content -Path '.\sql\get-sis-request.sql' -Raw
$getStaffUsr = Get-Content -Path '.\sql\get-sis-staff.sql' -Raw
$newOTPEntryInt = Get-Content '.\sql\insert-otp.sql' -Raw
$resetSISOTPRequest = Get-Content -Path '.\sql\reset-otp-request.sql' -Raw

do {
 Write-Verbose '========== Update Expired OTP Entries by setting del to 1 ========'
 Set-OtpDel $sqlParamsInt $IntSqlTable $delExpiredOTPInt

 Connect-ADSession -DomainControllers $DomainControllers -Cmdlets $adCmdLets -Credential $ADCredential

 Write-Verbose '# ========================= Send OTP Email ========================='
 Get-SISPwRequests $sqlParamsSIS $getSISRequest $SiteCodes |
  Format-OtpEmailObj |
   Get-StuADInfo |
    Skip-OTP $sqlParamsInt $IntSqlTable $getRecentOtpInt |
     New-OTP |
      Get-Usr $sqlParamsSIS $getStaffUsr |
       Get-Email |
        Add-OPTEntry $sqlParamsInt $IntSqlTable $newOTPEntryInt |
         Send-OTPMsg $FormUrl |
          Reset-DbEntry $sqlParamsSIS $resetSISOTPRequest |
           Show-Obj

 Write-Verbose '# =========================== Reset PW ============================='
 New-SqlOperation @sqlParamsInt -Query ($getPwResets -f $IntSqlTable) |
  Format-PwResetObj |
   Get-StuADInfo |
    Reset-PW |
     Clear-OTPRequest $sqlParamsInt $IntSqlTable $clearIntEntry |
      Show-Obj

 Clear-SessionData

 if (!$WhatIf) { Start-Sleep 5 }
} until ($WhatIf -or ((Get-Date) -ge (Get-Date $StopTime)))

if ($WhatIf) { Show-TestRun }
Show-BlockInfo end