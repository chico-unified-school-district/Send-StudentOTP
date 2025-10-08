## Repo purpose (quick)

This repository runs a scheduled PowerShell job that watches the Student Information System (SIS) for password-reset/OTP requests, emails an OTP to the staff/guardian, and records/clears state in an internal lookup table.

## Big-picture architecture

- Primary runner: `Send-StudentOTP.PS1` — single PowerShell script implementing the pipeline.
- Config / orchestration: `params.ps1` (local/dev values) and `jenkins.ps1` (CI/cron wrapper). Jenkins clones and invokes the main job with environment-driven parameters.
- Templates: `html/otp-msg.html` and `html/otp-error-msg.html` — used for email body formatting.
- Persistence and integration: `sql/` contains parameterized SQL snippets the script loads at runtime and formats with table names, site codes and timeouts. Two databases are involved: the SIS (source of requests) and an internal lookup DB/table (int SQL) used to store OTPs and state.

Why this matters: the script treats SQL snippets as templates (string -f) and expects certain columns/parameters from both SIS and the internal table. Edits to SQL must preserve the named parameters used by the script (e.g. `@id`, `@email`).

## Inputs / outputs / side effects

- Inputs: CLI params or environment-driven `params.ps1`/Jenkins envvars: DomainControllers, AD credentials, SIS server/database/credentials, Int SQL server/database/credentials, IntSqlTable, SiteCodes, TimeOutMinutes, EmailCredential, FormUrl, StopTime, WhatIf/Verbose flags.
- Outputs/Side effects: sends email via Office365 (uses Mailozaurr Send-EmailMessage), writes rows to internal table (`int-insert-otp.sql`), updates/clears entries (`int-update-expired-otp.sql`, `int-clear-entry.sql`), and calls AD cmdlets (Get-ADUser, Set-ADAccountPassword).

## Project-specific conventions & patterns

- PowerShell pipeline design: `Get-SISPwRequests | Format-OTPEmailObj | Get-StuADInfo | ...` — functions accept pipeline input and return objects with properties used downstream. Preserve/return objects when editing functions.
- SQL templating: SQL files contain placeholders like `{0}`, `{1}` and are composed with `-f` in the script. Do not change placeholders unless updating corresponding script code.
- WhatIf mode: Many functions respect a `$WhatIf` switch; keep side-effect checks (`if (!$WhatIf) { ... }`) when adding actions that mutate external systems.
- External modules used: `CommonScriptFunctions`, `dbatools` (Invoke-DbaQuery / Set-DbatoolsConfig), and `Mailozaurr`. New changes that rely on external modules should continue to import them and preserve existing cmdlet usage.

## Developer workflows (how to run / test locally)

- Quick smoke run with verbose/whatif using `params.ps1`: import params and call the main script with the `$global:params` or read the file to see sample values. Example (PowerShell/pwsh):

  # In pwsh

  .\params.ps1
  .\Send-StudentOTP.PS1 @global:params -WhatIf -Verbose

- Jenkins: `jenkins.ps1` clones the repo and calls the job with env-driven parameters. The Jenkins wrapper uses `WhatIf` in test mode — check `jenkins.ps1` for environment variable names.

## Important files to reference when editing

- `Send-StudentOTP.PS1` — main pipeline and helper functions.
- `jenkins.ps1` / `params.ps1` — CI/dev invocation patterns and example parameters.
- `sql/*.sql` — queries treated as templates; keep placeholders and parameter names. Example: `int-insert-otp.sql` expects `@id,@num,@gr,@sc,@sam,@email,@otp,@reqDate,@src`.
- `html/otp-msg.html` and `html/otp-error-msg.html` — email templates using indexed placeholders `{0}`, `{1}`, etc.

## Safety & integration notes

- Email: The script uses an Office365 SMTP account with Flow rules to avoid spam — do not change mail server or credentials handling without confirming with the ops team.
- AD operations: password resets use `Set-ADAccountPassword` with `-WhatIf` supported. When modifying reset logic, maintain `WhatIf` support and logging.
- Database updates: the internal table is the ground truth for request lifecycle. Avoid altering column names or the `del` flag semantics without updating SQL templates and callers.

## Examples of common edits and where to change them

- Add a column to the internal table: update `int-insert-otp.sql`, `int-clear-entry.sql`, `int-get-*` SQL templates, and update `Format-OTPEmailObj` / `Format-PwResetObj` to include the property mapping.
- Change email body: edit `html/otp-msg.html` and ensure indexed placeholders match call sites in `Send-StudentOTP.PS1` (the `-f` formatting order).

## Quick checklist for PRs

- Preserve pipeline object shapes (properties used downstream: id, stuNum/sn, siteCode/sc, grade/gr, samid, otp, email, guid).
- Keep or extend `WhatIf` checks before any external side-effect.
- Update `sql/*.sql` and verify `-f` placeholders and parameter names still match callers.
- Run a local smoke test: `.\params.ps1; .\Send-StudentOTP.PS1 @global:params -WhatIf -Verbose`.

If anything above is unclear or you'd like more examples (e.g., exact object shapes or sample SQL results), tell me which area to expand and I will iterate.
