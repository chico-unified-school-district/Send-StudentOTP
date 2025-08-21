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
 [int]$TimeOutMinutes,
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
  $obj = Get-ADuser -Filter ("EmployeeId -eq '{0}'" -f $_.stuId)
  if (!$obj) {
   $global:missingInAD += $_.stuId
   $msg = $MyInvocation.MyCommand.Name, $_.stuId
   (Write-Host ('{0},{1},AD Student obj not found' -f $msg ) -F Red)
   return $_
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

function Send-OTPMsg ($url, $mins) {
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
  if (!$_.email -or !$_.samid) {
   $params.to = $AdminEmail, $_.email
   $params.subject = '{0} - Error - CUSD Student OTP' -f $_.stuId
   $params.Body = $baseErrorHtml -f $_.stuId, $_.samid, $_.grade, $_.initiator
  }
  else {
   $params.To = '<{0}>' -f $_.email
   $params.subject = '{0} - CUSD Student OTP' -f $_.samid
   $params.Body = $baseHtml -f $_.samid, $_.otp, $url, $_.grade, $mins
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

function Set-OtpDel ($params, $getExpiredSql, $setExpiredSql) {

 $recentRequests = New-SqlOperation @params -Query $getExpiredSql
 if (!$recentRequests) { return }
 foreach ($req in $recentRequests) {
  Write-Host('{0},{1},{2},{3}' -f $MyInvocation.MyCommand.Name, $req.samid, $req.staffEmail, $req.requestDate ) -f Magenta
 }
 # This 'deletes' entries that are over x minutes old, essentially expiring the OTP/Reset request - Kinda Important!
 Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.Name, $setExpiredSql)
 if (!$WhatIf) { New-SqlOperation @params -Query $setExpiredSql }
}

function Show-Obj { Process { Write-Verbose ($MyInvocation.MyCommand.Name, $_ | Out-String) } }

function Skip-OTP ($params, $table, $baseSql, $mins) {
 process {
  $sql = $baseSql -f $table, $mins
  Write-Verbose $sql
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
Show-BlockInfo $SISDatabase

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
 Set-OtpDel $sqlParamsInt $intGetExpiredOTP $intSetExpiredOTP

 Connect-ADSession -DomainControllers $DomainControllers -Cmdlets $adCmdLets -Credential $ADCredential

 Write-Verbose '# ========================= Send OTP Email ========================='
 Get-SISPwRequests $sqlParamsSIS $sisGetRequest $SiteCodes |
  Format-OtpEmailObj |
   Get-StuADInfo |
    Skip-OTP $sqlParamsInt $IntSqlTable $intGetRecentOtp $TimeOutMinutes |
     New-OTP |
      Get-Usr $sqlParamsSIS $sisGetStaffUsr $sisGetUgnEM |
       # Get-Email |
       Add-OTPEntry $sqlParamsInt $IntSqlTable $intNewOTPEntry |
        Send-OTPMsg $FormUrl $TimeOutMinutes |
         Reset-DbEntry $sqlParamsSIS $sisResetOTPRequest |
          Show-Obj

 Write-Verbose '# =========================== Reset PW ============================='
 New-SqlOperation @sqlParamsInt -Query $intGetPwResets |
  Format-PwResetObj |
   Get-StuADInfo |
    Reset-PW |
     Clear-OTPRequest $sqlParamsInt $IntSqlTable $intClearEntry |
      Show-Obj

 Clear-SessionData

 if (!$WhatIf) { Start-Sleep 5 }
} until ($WhatIf -or ((Get-Date) -ge (Get-Date $StopTime)))

if ($WhatIf) { Show-TestRun }
Show-BlockInfo end