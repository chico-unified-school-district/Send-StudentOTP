# Send-StudentOTP

Automated PowerShell pipeline that monitors the Student Information System (SIS) for password reset requests, generates one-time passwords (OTPs), emails them to staff/guardians, and manages password resets through Active Directory.

## Overview

This scheduled job provides a secure, automated workflow for student password resets:

1. Polls SIS database for password reset requests flagged with `ADPW = 'Y'`
2. Generates a 6-digit OTP for each request
3. Looks up staff initiator and their email from SIS LOG and UGN tables
4. Sends OTP email to staff/guardian with reset link
5. Monitors internal database for completed reset submissions
6. Applies password changes to student AD accounts
7. Expires/clears OTP entries after timeout period

## Architecture

### Core Components

- **[Send-StudentOTP.PS1](Send-StudentOTP.PS1)** — Main pipeline script with all processing functions
- **[params.ps1](params.ps1)** — Local development parameter configuration (gitignored)
- **[jenkins.ps1](jenkins.ps1)** — CI/scheduled job wrapper with environment-driven parameters (gitignored)

### Templates

- **[html/otp-msg.html](html/otp-msg.html)** — Email body for successful OTP delivery
- **[html/student-missing-msg.html](html/student-missing-msg.html)** — Error email when student account not found/disabled
- **[html/staff-email-missing-msg.html](html/staff-email-missing-msg.html)** — Error email when staff email lookup fails

### SQL Templates

All SQL files use parameterized queries and string formatting placeholders (`{0}`, `{1}`, etc.):

**SIS Queries (Read-only):**

- **[sql/sis-get-request.sql](sql/sis-get-request.sql)** — Fetch pending password reset requests
- **[sql/sis-get-staff.sql](sql/sis-get-staff.sql)** — Lookup staff initiator from LOG table
- **[sql/sis-get-ugn-em.sql](sql/sis-get-ugn-em.sql)** — Get staff email from UGN table
- **[sql/sis-reset-otp-request.sql](sql/sis-reset-otp-request.sql)** — Clear SIS request flag after processing

**Internal Lookup DB (State Management):**

- **[sql/int-insert-otp.sql](sql/int-insert-otp.sql)** — Insert new OTP record
- **[sql/int-get-recent-otp.sql](sql/int-get-recent-otp.sql)** — Skip duplicate recent requests
- **[sql/int-get-expired-otp.sql](sql/int-get-expired-otp.sql)** — Find expired OTP entries
- **[sql/int-update-expired-otp.sql](sql/int-update-expired-otp.sql)** — Mark expired entries with `del = 1`
- **[sql/int-get-pw-resets.sql](sql/int-get-pw-resets.sql)** — Get completed password submissions from web form
- **[sql/int-clear-entry.sql](sql/int-clear-entry.sql)** — Clear processed reset entries

## Pipeline Functions

The script uses a PowerShell pipeline pattern where functions accept objects, enrich them, and pass them downstream:

```powershell
Get-SISPwRequests |
  Format-OTPEmailObj |
  Get-StuADInfo |
  Skip-OTP |
  New-OTP |
  Get-Usr |
  Add-OTPEntry |
  Set-OTPEmailMsgData |
  Send-OTPMsg |
  Reset-DbEntry
```

### Key Functions

- **`Get-SISPwRequests`** — Queries SIS for requests with `ADPW = 'Y'`
- **`Format-OTPEmailObj`** — Creates pipeline object with required properties
- **`Get-StuADInfo`** — Looks up student AD account and GUID
- **`Skip-OTP`** — Filters out duplicate requests within timeout window
- **`New-OTP`** — Generates random 6-digit OTP
- **`Get-Usr`** — Retrieves staff initiator and email from SIS
- **`Add-OTPEntry`** — Inserts OTP record into internal tracking table
- **`Set-OTPEmailMsgData`** — Formats email (success or error template)
- **`Send-OTPMsg`** — Sends email via Office365 SMTP
- **`Reset-DbEntry`** — Clears SIS request flag
- **`Reset-Pw`** — Applies password change to AD account
- **`Clear-OTPRequest`** — Marks internal entry as processed

## Parameters

| Parameter           | Type         | Description                                   |
| ------------------- | ------------ | --------------------------------------------- |
| `DomainControllers` | string[]     | AD domain controller list                     |
| `ADCredential`      | PSCredential | AD service account                            |
| `SISServer`         | string       | SIS database server                           |
| `SISDatabase`       | string       | SIS database name                             |
| `SISCredential`     | PSCredential | SIS database credential                       |
| `SiteCodes`         | int[]        | School site codes to monitor                  |
| `IntSqlServer`      | string       | Internal lookup database server               |
| `IntSqlDatabase`    | string       | Internal database name                        |
| `IntSqlCredential`  | PSCredential | Internal database credential                  |
| `IntSqlTable`       | string       | Tracking table name (e.g., `student_otp`)     |
| `TimeOutMinutes`    | int          | OTP expiration timeout (default: 20)          |
| `EmailCredential`   | PSCredential | Office365 SMTP account                        |
| `AdminEmail`        | string[]     | Admin email(s) for error notifications        |
| `Bcc`               | string[]     | Optional BCC recipients                       |
| `FormUrl`           | string       | Password reset web form URL                   |
| `StopTime`          | string       | Time to stop processing (default: "11:00 PM") |
| `WhatIf`            | switch       | Test mode (no external changes)               |

## Local Development

### Prerequisites

```powershell
Install-Module -Name CommonScriptFunctions
Install-Module -Name dbatools
Install-Module -Name Mailozaurr
```

### Test Run

1. Create a local `params.ps1` with your test parameters:

```powershell
$global:params = @{
    DomainControllers = 'dc1.domain.local', 'dc2.domain.local'
    ADCredential      = Get-Credential
    SISServer         = 'sisserver.local'
    SISDatabase       = 'SIS_Test'
    SISCredential     = Get-Credential
    SiteCodes         = 1, 2, 3
    IntSqlServer      = 'lookupserver.local'
    IntSqlDatabase    = 'Lookups'
    IntSqlCredential  = Get-Credential
    IntSqlTable       = 'student_otp_sandbox'
    TimeOutMinutes    = 20
    EmailCredential   = Get-Credential
    AdminEmail        = 'admin@domain.org'
    FormUrl           = 'https://forms.domain.org/otp-student'
    StopTime          = '11:00 PM'
}
```

2. Run in WhatIf mode:

```powershell
.\params.ps1
.\Send-StudentOTP.PS1 @global:params -WhatIf -Verbose
```

## CI/Scheduled Execution

The [jenkins.ps1](jenkins.ps1) wrapper is used by Jenkins for scheduled runs:

- Clones repository
- Loads parameters from environment variables
- Executes main script
- Uses `-WhatIf` in test jobs

## Database Schema

### Internal Tracking Table

Expected columns in `student_otp` table:

| Column        | Type     | Description                            |
| ------------- | -------- | -------------------------------------- |
| `id`          | int      | Auto-increment primary key             |
| `permId`      | varchar  | Student permanent ID                   |
| `stuNum`      | varchar  | Student number                         |
| `grade`       | int      | Grade level                            |
| `siteCode`    | int      | School site code                       |
| `samid`       | varchar  | AD SAM account name                    |
| `staffEmail`  | varchar  | Staff/guardian email                   |
| `otp`         | int      | 6-digit OTP                            |
| `requestDate` | datetime | Request timestamp                      |
| `source`      | varchar  | Source machine name                    |
| `newPw`       | varchar  | Submitted password (from web form)     |
| `resetPw`     | bit      | Flag indicating reset ready            |
| `del`         | bit      | Soft delete flag (1 = expired/cleared) |
| `dts`         | datetime | Last update timestamp                  |

## Email Flow

1. **Success Path:**

   - Email sent to `staffEmail` (from UGN table)
   - Contains 6-digit OTP
   - Includes link to password reset form: `{FormUrl}?grade={gr}&otp={otp}`
   - OTP valid for `TimeOutMinutes`

2. **Error: Student Not Found/Disabled:**

   - Email sent to `AdminEmail` + original `staffEmail`
   - Uses [html/student-missing-msg.html](html/student-missing-msg.html)

3. **Error: Staff Email Not Found:**
   - Email sent to `AdminEmail` only
   - Uses [html/staff-email-missing-msg.html](html/staff-email-missing-msg.html)

## Security Notes

- Email uses Office365 SMTP with Flow rules to prevent spam flagging
- AD operations use `Set-ADAccountPassword` with `-WhatIf` support
- OTPs expire after `TimeOutMinutes` (soft-deleted with `del = 1`)
- Duplicate requests within timeout window are skipped
- All credentials passed as `PSCredential` objects

## Common Maintenance Tasks

### Add a Column to Tracking Table

1. Update SQL schema in database
2. Modify [sql/int-insert-otp.sql](sql/int-insert-otp.sql) to include new column
3. Update [sql/int-clear-entry.sql](sql/int-clear-entry.sql) if needed
4. Update `Format-OTPEmailObj` or `Format-PwResetObj` in [Send-StudentOTP.PS1](Send-StudentOTP.PS1)

### Change Email Template

1. Edit [html/otp-msg.html](html/otp-msg.html)
2. Verify placeholder order: `{0}` (samid), `{1}` (otp), `{2}` (form URL), `{3}` (grade), `{4}` (timeout minutes)
3. Update call to `Set-OTPEmailMsgData` if placeholders change

### Modify Timeout Period

Update `TimeOutMinutes` parameter in [params.ps1](params.ps1) or Jenkins environment variables.

## Troubleshooting

**No emails sent:**

- Check `EmailCredential` and Office365 Flow rules
- Verify `AdminEmail` and staff emails in UGN table
- Run with `-Verbose` to see email parameters

**Students not found:**

- Check `Get-StuADInfo` output with `-Verbose`
- Verify `EmployeeId` attribute populated in AD
- Check `$global:missingInAD` array for cached misses

**OTP not expiring:**

- Verify `Set-OtpDel` executes at loop start
- Check [sql/int-update-expired-otp.sql](sql/int-update-expired-otp.sql) query
- Confirm `TimeOutMinutes` parameter

**Passwords not resetting:**

- Check `int-get-pw-resets.sql` returns rows with `resetPw = 1` and `newPw IS NOT NULL`
- Verify AD account has permissions for `Set-ADAccountPassword`
- Review `Reset-Pw` function with `-Verbose`

## Contributing

When submitting changes:

- [ ] Preserve pipeline object properties (id, stuNum, siteCode, grade, samid, otp, email, guid)
- [ ] Maintain `WhatIf` support for external side effects
- [ ] Update SQL templates and verify `-f` placeholders
- [ ] Test with: `.\params.ps1; .\Send-StudentOTP.PS1 @global:params -WhatIf -Verbose`
- [ ] Update this README if adding/removing files or changing parameter schema

## License
