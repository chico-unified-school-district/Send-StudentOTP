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
  process {
    $mail = $_.email
    $myDate = Get-Date
    $src = $ENV:COMPUTERNAME
    $sqlData = $table, $_.stuId, $_.stuNum, $_.grade, $_.siteCode, $_.samid, $mail, $_.otp, $myDate, $src
    $sql = $baseSql -f $sqlData
    Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.Name, $sql)
    if (!$WhatIf) { Invoke-Sqlcmd @params -Query $sql }
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
    samid, guid, pwExpires, email, pw, success
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

function Get-Usr ($params, $baseSql) {
  process {
    $sql = $baseSql -f $_.stuId
    $data = Invoke-Sqlcmd @params -Query $sql
    $msg = $MyInvocation.MyCommand.Name, $_.stuId
    if ($data.usr.length -lt 1) { Write-Host ('{0},{1},No inititor found in LOG.' -f $msg ) -F Red }
    $_.initiator = $data.usr
    $_
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

function Reset-DbEntry ($params, $baseSql) {
  process {
    $siteCode = $_.siteCode
    $stuNum = $_.stuNum
    $sql = $baseSql -f $siteCode, $stuNum
    if (!$WhatIf) { Invoke-Sqlcmd @params -Query $sql }
    Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.Name, $sql)
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
    if (!$WhatIf) { Send-MailMessage @params }
    Write-Verbose ($params.body | out-string)
    $_
  }
}

function Set-OtpDel ($params, $table, $baseSql) {
  $sql = $baseSql -f $table
  $data = Invoke-Sqlcmd @params -Query $sql
  if (!$data) { return }
  Write-Host('{0},{1},{2},{3}' -f $MyInvocation.MyCommand.Name, $data.id, $data.permId, (Get-Date))
  $updateSql = "UPDATE {0} SET del = 1 WHERE requestDate < DATEADD(minute, -10, getdate()) AND del IS NULL" -f $table
  if (!$WhatIf) { Invoke-Sqlcmd @params -Query $updateSql }
}

function Show-Obj { Process { Write-Verbose ($MyInvocation.MyCommand.Name, $_ | Out-String) } }

function Skip-OTP ($params, $table, $baseSql) {
  process {
    $id = $_.stuId
    $sql = $baseSql -f $table, $id
    $data = Invoke-SqlCmd @params -Query $sql
    # Skip entries older than 10 minutes
    if ($data) { return }
    $_
  }
}

function Test-ADSession {
  # AD Domain Controller Session
  if (($global:dc) -and (Test-ComputerSecureChannel -Server $global:dc)) { return }
  Clear-SessionData
  $global:dc = Select-DomainController $DomainControllers
  $adCmdLets = 'Get-ADUser', 'Set-ADUser', 'Set-ADAccountPassword', 'Remove-ADGroupMember', 'Add-ADGroupMember'
  New-ADSession -dc $dc -cmdlets $adCmdLets -cred $ADCredential
}

function Reset-Pw {
  process {
    Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.samid)
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
    $sql = $baseSql -f $table, $_.id
    Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.Name, $sql)
    if ($WhatIf) { return }
    Invoke-Sqlcmd @params -Query $sql
  }
}

# =============================== Main ==================================
# Imported Functions
. .\lib\Clear-SessionData.ps1
. .\lib\Load-Module.ps1
. .\lib\New-ADSession.ps1
. .\lib\Select-DomainController.ps1
. .\lib\Show-TestRun.ps1

Show-TestRun

'SqlServer' | Load-Module

$sqlParamsSIS = @{
  Server                 = $SISServer
  Database               = $SISDatabase
  Credential             = $SISCredential
  TrustServerCertificate = $true
}

$sqlParamsInt = @{
  Server                 = $IntSqlServer
  Database               = $IntSqlDatabase
  Credential             = $IntSqlCredential
  TrustServerCertificate = $true
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
  # ========== Update Expired OTP Entries by setting del to 1 ========
  Set-OtpDel $sqlParamsInt $IntSqlTable $delExpiredOTPInt

  Test-ADSession

  # ========================= Send OTP Email =========================
  Invoke-SqlCmd @sqlParamsSIS -Query ($getSISRequest -f ($SiteCodes -join ',')) |
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

  # =========================== Reset PW =============================
  Invoke-SqlCmd @sqlParamsInt -Query ($getPwResets -f $IntSqlTable) |
  Format-PwResetObj |
  Get-StuADInfo |
  Reset-PW |
  Clear-OTPRequest $sqlParamsInt $IntSqlTable $clearIntEntry |
  Show-Obj

  if (!$WhatIf) { Start-Sleep 5 }
} until ($WhatIf -or ((Get-Date) -ge (Get-Date $StopTime)))