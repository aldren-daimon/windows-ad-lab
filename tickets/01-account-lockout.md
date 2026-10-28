# Ticket 01 – User locked out

| | |
|---|---|
| Reported by | Sara Alharbi (HR) |
| Symptom | "My account is locked, I can't log in." |
| Priority | High – user can't work |

## How I reproduced it
On CLIENT01, I typed a wrong password for `salharbi` 5 times.

## Investigation
On DC01:

```powershell
Search-ADAccount -LockedOut | Select-Object Name, SamAccountName
Get-ADUser salharbi -Properties LockedOut, BadLogonCount, LastBadPasswordAttempt
# Which computer caused the lockout (Security log, Event ID 4740):
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4740} -MaxEvents 5 |
  Select-Object TimeCreated, @{n='Details';e={$_.Message.Split("`n")[0..12] -join ' '}}
```

![Locked out](../screenshots/t01-locked-out.png)

## Root cause
The lockout policy (5 attempts, 15 minutes) worked as designed. Event 4740 showed the lockout came from CLIENT01, which matched the user's own PC, so it wasn't an attack.

## Fix
```powershell
Unlock-ADAccount -Identity salharbi
Set-ADAccountPassword -Identity salharbi -Reset -NewPassword (Read-Host -AsSecureString 'New password')
Set-ADUser -Identity salharbi -ChangePasswordAtLogon $true
```
I verified the user's identity first, then unlocked the account and reset the password with change-at-next-logon.

## Prevention
If Event 4740 had shown an unknown computer, I would treat it as a possible brute-force attempt and escalate to security.
