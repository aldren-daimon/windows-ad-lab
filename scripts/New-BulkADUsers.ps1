<#
.SYNOPSIS
    Creates Active Directory users in bulk from a CSV file.

.DESCRIPTION
    Reads users.csv, builds a username for each person (first initial + last name),
    creates the department OU if it is missing, creates the user, adds them to a group,
    and writes a CSV report of what happened.
    The initial password is typed in at run time (never stored in the script),
    and every user must change it at first logon.

.EXAMPLE
    # Dry run first: shows what WOULD happen, changes nothing
    .\New-BulkADUsers.ps1 -CsvPath .\users.csv -WhatIf

    # Real run
    .\New-BulkADUsers.ps1 -CsvPath .\users.csv

.NOTES
    Author : Al-Dren S. Daimon
    Lab    : Windows Server 2025 domain controller (VirtualBox)
    Needs  : ActiveDirectory module (installed on a domain controller / RSAT)
#>

[CmdletBinding(SupportsShouldProcess)]          # gives the script -WhatIf and -Confirm for free
param(
    [Parameter(Mandatory)]
    [string]$CsvPath,                           # path to the CSV with the new users

    [string]$ParentOU                           # where department OUs live; default = domain root
)

Import-Module ActiveDirectory -ErrorAction Stop  # stop right away if the AD module is missing

$domain = Get-ADDomain                          # info about the current domain (name, DN)
if (-not $ParentOU) { $ParentOU = $domain.DistinguishedName }

# Ask for the starting password securely; it is never shown or saved in the file
$securePwd = Read-Host -Prompt 'Initial password for the new users' -AsSecureString

$users = Import-Csv -Path $CsvPath               # each CSV row becomes an object with properties

$results = foreach ($u in $users) {

    # Username: first initial + last name, lower case, letters/numbers only, max 20 chars
    $sam = ($u.FirstName.Substring(0,1) + $u.LastName).ToLower() -replace '[^a-z0-9]', ''
    if ($sam.Length -gt 20) { $sam = $sam.Substring(0,20) }

    $ouPath = "OU=$($u.Department),$ParentOU"
    $status = ''
    $note   = ''

    try {
        # 1) Skip people who already have an account
        if (Get-ADUser -Filter "SamAccountName -eq '$sam'") {
            $status = 'Skipped'
            $note   = 'User already exists'
        }
        else {
            # 2) Create the department OU if it does not exist yet
            if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouPath'")) {
                if ($PSCmdlet.ShouldProcess($ouPath, 'Create OU')) {
                    New-ADOrganizationalUnit -Name $u.Department -Path $ParentOU -ErrorAction Stop
                }
            }

            # 3) Build all user settings in one place ("splatting")
            $params = @{
                Name                  = "$($u.FirstName) $($u.LastName)"
                GivenName             = $u.FirstName
                Surname               = $u.LastName
                SamAccountName        = $sam
                UserPrincipalName     = "$sam@$($domain.DNSRoot)"
                Department            = $u.Department
                Title                 = $u.Title
                Path                  = $ouPath
                AccountPassword       = $securePwd
                Enabled               = $true
                ChangePasswordAtLogon = $true          # user must set their own password
                ErrorAction           = 'Stop'
            }

            if ($PSCmdlet.ShouldProcess($sam, 'Create AD user')) {
                New-ADUser @params

                # 4) Add to the group from the CSV (if one was given)
                if ($u.Group) {
                    # Create the group (Global Security group in the department OU) if it does not exist
                    if (-not (Get-ADGroup -Filter "Name -eq '$($u.Group)'")) {
                        New-ADGroup -Name $u.Group -GroupScope Global -GroupCategory Security -Path $ouPath -ErrorAction Stop
                    }
                    Add-ADGroupMember -Identity $u.Group -Members $sam -ErrorAction Stop
                }
                $status = 'Created'
            }
            else {
                $status = 'WhatIf'
                $note   = 'Dry run - nothing changed'
            }
        }
    }
    catch {
        $status = 'Failed'
        $note   = $_.Exception.Message                # keep the real error for the report
    }

    # One result row per CSV line
    [pscustomobject]@{
        Username   = $sam
        Name       = "$($u.FirstName) $($u.LastName)"
        Department = $u.Department
        Group      = $u.Group
        Status     = $status
        Note       = $note
    }
}

# Show results on screen and save a report next to the script
$results | Format-Table -AutoSize
$reportPath = ".\BulkUsers_Report_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
$results | Export-Csv -Path $reportPath -NoTypeInformation
Write-Host "Report saved to $reportPath" -ForegroundColor Green
