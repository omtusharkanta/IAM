<#
.SYNOPSIS
    Automates common joiner, mover, and leaver tasks in the IAMLAB.local domain.

.DESCRIPTION
    Joiner creates one account. BulkJoiner creates accounts from a CSV with
    FirstName, LastName, and Department columns. Mover updates a user's
    department, group membership, and OU. Leaver disables the account, removes
    its group memberships, and moves it to the Disabled Users OU.

.EXAMPLE
    .\JML-Automation.ps1 -Action Joiner -FirstName Asha -LastName Menon -Department IT

.EXAMPLE
    .\JML-Automation.ps1 -Action BulkJoiner -CsvPath C:\IAM\new-hires.csv

.EXAMPLE
    .\JML-Automation.ps1 -Action Mover -Username nikhil.bose -Department Sales

.EXAMPLE
    .\JML-Automation.ps1 -Action Leaver -Username nikhil.bose

.EXAMPLE
    .\JML-Automation.ps1 -Action Leaver -Username nikhil.bose -WhatIf

.NOTES
    Run in PowerShell as Administrator on the domain controller.
    Requires the ActiveDirectory module, the 5 department OUs, and the groups
    HR-Team, Finance-Team, IT-Team, Sales-Team, Operations-Team.
#>

#Requires -Modules ActiveDirectory

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Joiner', 'BulkJoiner', 'Mover', 'Leaver')]
    [string]$Action,

    [string]$FirstName,
    [string]$LastName,

    # SamAccountName, for example nikhil.bose (Mover and Leaver)
    [string]$Username,

    # Department for a Joiner, or the NEW department for a Mover
    [ValidateSet('HR', 'Finance', 'IT', 'Sales', 'Operations')]
    [string]$Department,

    # CSV file for BulkJoiner
    [string]$CsvPath,

    # Starting password for new users. If left out, you are asked for it once.
    [SecureString]$InitialPassword
)

# Domain and logging settings
$Departments = 'HR', 'Finance', 'IT', 'Sales', 'Operations'
$Domain      = Get-ADDomain
$BaseDN      = $Domain.DistinguishedName
$DnsRoot     = $Domain.DNSRoot
$DisabledOU  = "OU=Disabled Users,$BaseDN"
$LogFile     = 'C:\IAM-Logs\jml-log.csv'

# Shared helpers
function Write-JmlLog {
    param(
        [string]$Event,
        [string]$User,
        [string]$Details
    )

    $logDirectory = Split-Path $LogFile
    if (-not (Test-Path $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory | Out-Null
    }

    [pscustomobject]@{
        Time    = Get-Date -Format 's'
        Admin   = $env:USERNAME
        Action  = $Event
        User    = $User
        Details = $Details
    } | Export-Csv -Path $LogFile -Append -NoTypeInformation
}

function Assert-DepartmentReady {
    param([string]$Dept)

    if ($Departments -notcontains $Dept) {
        throw "Unknown department '$Dept'. Use one of: $($Departments -join ', ')"
    }

    $null = Get-ADOrganizationalUnit -Identity "OU=$Dept,$BaseDN" -ErrorAction Stop
    $null = Get-ADGroup -Identity "$Dept-Team" -ErrorAction Stop
}

# Create a user and grant access through the department group.
function New-Joiner {
    param(
        [string]$First,
        [string]$Last,
        [string]$Dept,
        [SecureString]$Password
    )

    Assert-DepartmentReady -Dept $Dept

    $username = ("$First.$Last").ToLower() -replace '\s', ''
    if ($username.Length -gt 20) {
        Write-Warning "Username '$username' is longer than 20 characters, which AD does not allow. Skipped."
        return
    }
    if (Get-ADUser -Filter "SamAccountName -eq '$username'") {
        Write-Warning "User '$username' already exists. Skipped."
        return
    }

    $group = Get-ADGroup -Identity "$Dept-Team"

    New-ADUser `
        -Name "$First $Last" `
        -GivenName $First `
        -Surname $Last `
        -SamAccountName $username `
        -UserPrincipalName "$username@$DnsRoot" `
        -Path "OU=$Dept,$BaseDN" `
        -Department $Dept `
        -AccountPassword $Password `
        -Enabled $true `
        -ChangePasswordAtLogon $true

    if ($WhatIfPreference) {
        Write-Host "What if: would add '$username' to group '$($group.Name)'."
    }
    else {
        Add-ADGroupMember -Identity $group -Members $username
        Write-Host "Joiner done: $username created in OU=$Dept and added to $($group.Name)." -ForegroundColor Green
        Write-JmlLog -Event 'Joiner' -User $username -Details "Created in $Dept, added to $($group.Name)"
    }
}

# Update a user's department, group membership, and OU.
function Move-Employee {
    param(
        [string]$Sam,
        [string]$NewDept
    )

    Assert-DepartmentReady -Dept $NewDept

    $user = Get-ADUser -Identity $Sam -Properties Department, MemberOf, Enabled -ErrorAction Stop

    if (-not $user.Enabled) {
        Write-Warning "User '$Sam' is disabled. A mover should be an active employee. Skipped."
        return
    }
    if ($user.Department -eq $NewDept) {
        Write-Warning "User '$Sam' is already in $NewDept. Nothing to do."
        return
    }

    $oldDept  = $user.Department
    $newGroup = Get-ADGroup -Identity "$NewDept-Team"

    foreach ($departmentName in $Departments) {
        if ($departmentName -eq $NewDept) {
            continue
        }

        $departmentGroup = Get-ADGroup -Identity "$departmentName-Team" -ErrorAction SilentlyContinue
        if ($departmentGroup -and ($user.MemberOf -contains $departmentGroup.DistinguishedName)) {
            Remove-ADGroupMember -Identity $departmentGroup -Members $user -Confirm:$false
            Write-Host "Removed $Sam from $($departmentGroup.Name)."
        }
    }

    if ($user.MemberOf -notcontains $newGroup.DistinguishedName) {
        Add-ADGroupMember -Identity $newGroup -Members $user
        Write-Host "Added $Sam to $($newGroup.Name)."
    }

    Set-ADUser -Identity $user -Department $NewDept

    # Moving the account changes its distinguished name, so do this last.
    Move-ADObject -Identity $user.DistinguishedName -TargetPath "OU=$NewDept,$BaseDN"

    Write-Host "Mover done: $Sam moved from '$oldDept' to '$NewDept'." -ForegroundColor Green
    if (-not $WhatIfPreference) {
        Write-JmlLog -Event 'Mover' -User $Sam -Details "From $oldDept to $NewDept"
    }
}

# Disable a leaver and keep the account for future reference.
function Remove-Employee {
    param([string]$Sam)

    $user = Get-ADUser -Identity $Sam -Properties Department, MemberOf, Enabled -ErrorAction Stop

    if (-not $user.Enabled -and $user.DistinguishedName -like "*$DisabledOU") {
        Write-Warning "User '$Sam' is already a processed leaver. Nothing to do."
        return
    }

    $oldGroups = @(
        foreach ($groupDn in $user.MemberOf) {
            (Get-ADGroup -Identity $groupDn).Name
        }
    )

    Disable-ADAccount -Identity $user

    foreach ($groupDn in $user.MemberOf) {
        Remove-ADGroupMember -Identity $groupDn -Members $user -Confirm:$false
    }

    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$DisabledOU'")) {
        New-ADOrganizationalUnit -Name 'Disabled Users' -Path $BaseDN
        Write-Host "Created OU 'Disabled Users'."
    }

    $note = "Disabled $(Get-Date -Format 'yyyy-MM-dd') - leaver (was in $($user.Department))"
    Set-ADUser -Identity $user -Description $note
    Move-ADObject -Identity $user.DistinguishedName -TargetPath $DisabledOU

    Write-Host "Leaver done: $Sam disabled, removed from $($oldGroups.Count) group(s), moved to Disabled Users." -ForegroundColor Green
    if (-not $WhatIfPreference) {
        Write-JmlLog -Event 'Leaver' -User $Sam -Details "Disabled. Removed from: $($oldGroups -join ', ')"
    }
}

# Run the requested lifecycle action.
try {
    switch ($Action) {

        'Joiner' {
            if (-not ($FirstName -and $LastName -and $Department)) {
                throw 'Joiner needs -FirstName, -LastName and -Department.'
            }
            if (-not $InitialPassword) {
                $InitialPassword = Read-Host 'Initial password for the new user' -AsSecureString
            }
            New-Joiner -First $FirstName -Last $LastName -Dept $Department -Password $InitialPassword
        }

        'BulkJoiner' {
            if (-not $CsvPath -or -not (Test-Path $CsvPath)) {
                throw 'BulkJoiner needs a valid -CsvPath.'
            }
            if (-not $InitialPassword) {
                $InitialPassword = Read-Host 'Initial password for the new users' -AsSecureString
            }

            foreach ($row in (Import-Csv -Path $CsvPath)) {
                try {
                    New-Joiner `
                        -First $row.FirstName.Trim() `
                        -Last $row.LastName.Trim() `
                        -Dept $row.Department.Trim() `
                        -Password $InitialPassword
                }
                catch {
                    Write-Warning "Row '$($row.FirstName) $($row.LastName)' failed: $($_.Exception.Message)"
                }
            }
        }

        'Mover' {
            if (-not ($Username -and $Department)) {
                throw 'Mover needs -Username and -Department (the new one).'
            }
            Move-Employee -Sam $Username -NewDept $Department
        }

        'Leaver' {
            if (-not $Username) {
                throw 'Leaver needs -Username.'
            }
            Remove-Employee -Sam $Username
        }
    }
}
catch {
    Write-Error $_.Exception.Message
}
