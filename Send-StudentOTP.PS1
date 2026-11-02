[cmdletbinding()]
param (
 [Parameter(Mandatory = $True)][Alias('DCs')][string[]]$DomainControllers,
 [Parameter(Mandatory = $True)][System.Management.Automation.PSCredential]$ADCredential,
 [Parameter(Mandatory = $True)] [string]$SISServer,
 [Parameter(Mandatory = $True)][string]$SISDatabase,
 [Parameter(Mandatory = $True)][System.Management.Automation.PSCredential]$SISCredential,
 [Parameter(Mandatory = $True)][int[]]$SiteCodes,
 [Parameter(Mandatory = $True)][string]$IntSqlServer,
 [Parameter(Mandatory = $True)][string]$IntSqlDatabase,
 [Parameter(Mandatory = $True)][System.Management.Automation.PSCredential]$IntSqlCredential,
 [Parameter(Mandatory = $True)][string]$IntSqlTable,
 [Parameter(Mandatory = $True)][int]$TimeOutMinutes,
 [Parameter(Mandatory = $True)][System.Management.Automation.PSCredential]$EmailCredential,
 [Parameter(Mandatory = $false)][string[]]$Bcc,
 [Parameter(Mandatory = $true)][string[]]$AdminEmail,
 [Parameter(Mandatory = $True)][string]$FormUrl,
 [string]$StopTime = '11:00 PM',
 [Alias('wi')][SWITCH]$WhatIf
)
function Add-OTPEntry ($params, $table, $baseSql) {
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

function Format-OTPEmailObj {
 process {
  $obj = '' | Select-Object stuId, stuNum, siteCode, grade, otp,
  initiator, samid, guid, pwExpires, email, emailParams, error
  $obj.stuId = $_.id
  $obj.stuNum = $_.sn
  $obj.siteCode = $_.sc
  $obj.grade = $_.gr
  $obj.emailParams = @{To = $null; Subject = $null; HTML = $null }
  Write-Verbose ('{0},[{1}]' -f $MyInvocation.MyCommand.Name, $obj | Out-String)
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

function Get-Usr ($params, $logSql, $ugnSql) {
 process {
  $logVars = "id=$($_.stuId)"
  $logData = New-SqlOperation @params -Query $logSql -Parameters $logVars
  $msg1 = $MyInvocation.MyCommand.Name, $_.stuId
  if ($logData.usr.length -lt 1) { Write-Host ('{0},{1},No initiator found in LOG.' -f $msg1 ) -F Red }

  $ugnVars = "un=$($logData.USR)"
  $ugnData = New-SqlOperation @params -Query $ugnSql -Parameters $ugnVars
  $msg2 = $MyInvocation.MyCommand.Name, $_.stuId
  if ($ugnData.EM.length -lt 1) { Write-Host ('{0},{1},No email found in UGN table.' -f $msg2 ) -F Red }

  $_.email = $ugnData.EM
  $_
 }
}

function Get-SISPwRequests ($params, $baseSql, $sites) {
 process {
  $mySiteCodes = $sites -join ','
  $sql = $baseSql -replace ('SITE_CODES', $mySiteCodes)
  Write-Verbose ('{0},DB:{1},Sql: [{2}]' -f $MyInvocation.MyCommand.Name, $SISDatabase, $sql)
  New-SqlOperation @params -Query $sql
 }
}

function Get-StuADInfo {
 process {
  if ($global:missingInAD -contains $_.stuId) { return }
  $obj = Get-ADUser -Filter ("EmployeeId -eq '{0}'" -f $_.stuId)
  if (!$obj -or $obj.Enabled -eq $false) {
   $global:missingInAD += $_.stuId
   Write-Host ('{0},{1},AD Student obj not found or disabled' -f $MyInvocation.MyCommand.Name, $_.stuId) -F Red
   return $_
  }
  $_.samid = $obj.SamAccountName
  $_.guid = $obj.ObjectGUID
  $_
 }
}

function New-OTP {
 process {
  $_.otp = Get-Random -Min 111111 -max 999999
  Write-Verbose ('{0},{1},OTP:{2}' -f $MyInvocation.MyCommand.Name, $_.samid, $_.otp)
  $_
 }
}

function Reset-DbEntry ($params, $sql) {
 process {
  $sqlVars = "sc=$($_.siteCode)", "sn=$($_.stuNum)"
  if (!$WhatIf) { New-SqlOperation @params -Query $sql -Parameters $sqlVars }
  Write-Verbose ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $sql, ($sqlVars -join ','))
  $_
 }
}

function Send-OTPMsg ($mins) {
 begin {
  $params = @{
   From       = '{0}' -f $EmailCredential.Username
   SMTPServer = 'smtp.office365.com'
   Cred       = $EmailCredential # use a valid Office365 account with Flow rules in place to prevent SPAM warnings.
   UseSSL     = $True
   Port       = 587
   WhatIf     = $WhatIf
   Suppress   = $True
  }
 }
 process {
  $params.To = $_.emailParams.To
  $params.Subject = $_.emailParams.Subject
  $params.HTML = $_.emailParams.HTML
  Write-Host ('{0},{1},{2},{3}' -f $MyInvocation.MyCommand.Name, $params.Subject, $_.stuId, (Get-Date)) -F Blue
  # TODO : Debug output of email addresses. The AdminEmail array seems to not be working correctly.
  Write-Host ($params.To | Out-String ) -F Blue
  if ( $Bcc ) { $params.Bcc = $Bcc } # Add Bcc to outgoing email messages.
  # Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.Name, ($params.HTML | Out-String))
  Send-EmailMessage @params
  $_
 }
}

function Set-OTPEmailMsgData ($adminAddresses, $resetPageURL, $baseOtpHtml, $baseErrorStuHtml, $baseErrorStaffHtml) {
 process {
  if (!$_.samid) {
   $_.emailParams.To = $adminAddresses, $_.email | Sort-Object -Unique
   $_.emailParams.Subject = '{0} - Error - CUSD Student OTP' -f $_.stuId
   $_.emailParams.HTML = $baseErrorStuHtml -f $_.stuId, $_.grade, $_.initiator
  }
  elseif (!$_.email) {
   $_.emailParams.To = $adminAddresses
   $_.emailParams.Subject = '{0} - Error No Staff Email Found - CUSD Student OTP' -f $_.stuId
   $_.emailParams.HTML = $baseErrorStaffHtml -f $_.stuId, $_.samid, $_.grade
  }
  else {
   $_.emailParams.To = '<{0}>' -f $_.email
   $_.emailParams.Subject = '{0} - CUSD Student OTP' -f $_.samid
   $_.emailParams.HTML = $baseOtpHtml -f $_.samid, $_.otp, $resetPageURL, $_.grade, $mins
  }
  $_
 }
}

function Set-OtpDel ($params, $getExpiredSql, $setExpiredSql) {

 $recentRequests = New-SqlOperation @params -Query $getExpiredSql
 if (!$recentRequests) { return }
 foreach ($req in $recentRequests) {
  Write-Host('{0},{1},{2},{3}' -f $MyInvocation.MyCommand.Name, $req.permId, $req.staffEmail, $req.requestDate ) -f Magenta
 }
 # This 'deletes' entries that are over x minutes old, essentially expiring the OTP/Reset request - Kinda Important!
 Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.Name, $setExpiredSql)
 if (!$WhatIf) { New-SqlOperation @params -Query $setExpiredSql }
}

function Show-Obj { process { Write-Verbose ( '{0},[{1}]' -f $MyInvocation.MyCommand.Name, ($_ | Out-String)) } }

function Skip-OTP ($params, $table, $baseSql, $mins) {
 process {
  $sql = $baseSql -f $table, $mins
  Write-Verbose $sql
  $sqlVars = "id=$($_.stuId)"
  $data = New-SqlOperation @params -Query $sql -Parameters $sqlVars
  # Skip requests older than x minutes. Who needs em!
  if ($data) { return }
  $_
 }
}

function Reset-Pw {
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.samid) -f DarkBlue
  $params = @{
   Identity      = $_.guid
   NewPassword   = (ConvertTo-SecureString $_.pw -AsPlainText -Force)
   Reset         = $true
   ErrorVariable = 'pwResetError'
   Confirm       = $false
   WhatIf        = $WhatIf
  }
  Set-ADAccountPassword @params
  if ($pwResetError) {
   Write-Warning ('{0},{1},Error:{2}' -f $MyInvocation.MyCommand.Name, $_.samid, $pwResetError.Exception.Message)
   $_.success = $false
   $_.pwGood = $pwResetError.Message
  }
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
$global:VerbosePreference = 'SilentlyContinue'
Import-Module -Name CommonScriptFunctions -Cmdlet Show-TestRun, Show-BlockInfo, Connect-ADSession, Clear-SessionData, New-SqlOperation
Import-Module -Name dbatools -Cmdlet Set-DbatoolsConfig, Invoke-DbaQuery, Connect-DbaInstance
Import-Module -Name Mailozaurr -Cmdlet Send-EmailMessage

Show-BlockInfo main
Show-BlockInfo $SISDatabase
Show-BlockInfo $IntSqlTable

if ($WhatIf) { Show-TestRun }

$adCmdLets = 'Get-ADUser', 'Set-ADAccountPassword'

$dbaInstanceSiS = @{
 Server = Connect-DbaInstance -SqlInstance $SISServer -SqlCredential $SISCredential -Database $SISDatabase
}
$dbaInstanceInt = @{
 Server = Connect-DbaInstance -SqlInstance $IntSqlServer -SqlCredential $IntSqlCredential -Database $IntSqlDatabase
}

$otpHtml = Get-Content '.\html\otp-msg.html' -Raw
$studentErrorHtml = Get-Content '.\html\student-missing-msg.html' -Raw
$staffErrorHtml = Get-Content '.\html\staff-email-missing-msg.html' -Raw

$Global:missingInAD = $null

$intClearEntry = (Get-Content -Path '.\sql\int-clear-entry.sql' -Raw) -f $IntSqlTable
$intGetExpiredOTP = (Get-Content -Path '.\sql\int-get-expired-otp.sql' -Raw) -f $IntSqlTable, $TimeOutMinutes
$intGetPwResets = (Get-Content -Path '.\sql\int-get-pw-resets.sql' -Raw) -f $IntSqlTable, $TimeOutMinutes
$intGetRecentOtp = (Get-Content '.\sql\int-get-recent-otp.sql' -Raw) -f $IntSqlTable, $TimeOutMinutes
$intNewOTPEntry = (Get-Content '.\sql\int-insert-otp.sql' -Raw) -f $IntSqlTable
$intSetExpiredOTP = (Get-Content -Path '.\sql\int-update-expired-otp.sql' -Raw) -f $IntSqlTable, $TimeOutMinutes
$sisGetRequest = Get-Content -Path '.\sql\sis-get-request.sql' -Raw
$sisGetStaffUsr = Get-Content -Path '.\sql\sis-get-staff.sql' -Raw
$sisGetUgnEM = Get-Content -Path '.\sql\sis-get-ugn-em.sql' -Raw
$sisResetOTPRequest = Get-Content -Path '.\sql\sis-reset-otp-request.sql' -Raw

do {
 Write-Verbose '========== Update Expired OTP Entries by setting del to 1 ========'
 Set-OtpDel $dbaInstanceInt $intGetExpiredOTP $intSetExpiredOTP

 Connect-ADSession -DomainControllers $DomainControllers -Cmdlets $adCmdLets -Credential $ADCredential

 Write-Verbose '# ========================= Send OTP Email ========================='
 Get-SISPwRequests $dbaInstanceSiS $sisGetRequest $SiteCodes |
  Format-OTPEmailObj |
   Get-StuADInfo |
    Skip-OTP $dbaInstanceInt $IntSqlTable $intGetRecentOtp $TimeOutMinutes |
     New-OTP |
      Get-Usr $dbaInstanceSiS $sisGetStaffUsr $sisGetUgnEM |
       Add-OTPEntry $dbaInstanceInt $IntSqlTable $intNewOTPEntry |
        Set-OTPEmailMsgData $AdminEmail $FormUrl $otpHtml $studentErrorHtml $staffErrorHtml |
         Send-OTPMsg $TimeOutMinutes |
          Reset-DbEntry $dbaInstanceSiS $sisResetOTPRequest |
           Show-Obj

 Write-Verbose '# =========================== Reset PW ============================='
 New-SqlOperation @dbaInstanceInt -Query $intGetPwResets |
  Format-PwResetObj |
   Get-StuADInfo |
    Reset-PW |
     Clear-OTPRequest $dbaInstanceInt $IntSqlTable $intClearEntry |
      Show-Obj

 Clear-SessionData

 if (!$WhatIf) { Start-Sleep 5 }
} until ($WhatIf -or ((Get-Date) -ge (Get-Date $StopTime)))

if ($WhatIf) { Show-TestRun }
Show-BlockInfo end