# Ticket 03 – S: drive not showing

| | |
|---|---|
| Reported by | Mohammed Alotaibi (Finance) |
| Symptom | "I don't have the S: drive like the rest of Finance." |
| Priority | Medium |

## How I reproduced it
I moved `malotaibi` from the Finance OU to the Operations OU, then logged in on CLIENT01.

## Investigation
On CLIENT01, as the user:

```powershell
gpupdate /force
gpresult /r      # "Finance - Map S drive" is NOT in the Applied GPOs list
whoami /groups   # still a member of Finance-Staff, so share access is fine
```

On DC01:

```powershell
Get-ADUser malotaibi | Select-Object DistinguishedName   # OU=Operations  <- wrong OU
```

![gpresult](../screenshots/t03-gpresult.png)

## Root cause
The drive map GPO is linked to the Finance OU. GPOs apply by where the object sits in AD, not by group membership, so the user didn't get the policy.

## Fix
```powershell
Get-ADUser malotaibi | Move-ADObject -TargetPath "OU=Finance,DC=dre,DC=lab"
```
Then on the client: `gpupdate /force`, sign out and in again. The S: drive appeared.

## Lesson
For "policy not applying" tickets, check `gpresult /r` first, then the object's OU, then security filtering on the GPO.
