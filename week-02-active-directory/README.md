# Week 2: On-Premises Active Directory Lab

Part of my 16-week IAM (Identity and Access Management) learning roadmap. In Week 1 I built a cloud directory in Microsoft Entra ID. In Week 2 I built the on-premises equivalent with Active Directory on Windows Server, then wrote a PowerShell script that automates the joiner, mover, and leaver process.

## What I built

| Item | Details |
|---|---|
| Server | Windows Server 2025 (VMware Workstation), hostname `DC01` |
| Domain | `IAMLAB.local` (new forest) |
| Organizational Units | HR, Finance, IT, Sales, Operations |
| Users | 20 (4 per department), each placed in their department OU |
| Security groups | HR-Team, Finance-Team, IT-Team, Sales-Team, Operations-Team |
| Automation | `scripts/JML-Automation.ps1` (joiner, mover, leaver) |

This matches the 20 users and 5 groups from my Week 1 Entra ID lab, so I can compare the cloud and on-premises versions of the same setup.

## Skills practiced

- Installing Active Directory Domain Services and promoting a server to a domain controller
- Creating OUs, users, and security groups with PowerShell
- Restricting a shared folder to one group
- Group Policy (GPO) linked to an OU
- Account lockout policy, lockout and unlock
- Password reset, disable and enable accounts
- Deleting and restoring a user with the AD Recycle Bin
- Troubleshooting a logon failure (error 1385)
- Automating the joiner, mover, and leaver lifecycle with PowerShell, with an audit log

## Contents

1. [Users, OUs and groups](#1-users-ous-and-groups)
2. [Daily admin tasks](#2-daily-admin-tasks)
3. [Shared folder restricted to one group](#3-shared-folder-restricted-to-one-group)
4. [Group Policy](#4-group-policy)
5. [Account lockout and unlock](#5-account-lockout-and-unlock)
6. [Problem solved: logon error 1385](#6-problem-solved-logon-error-1385)
7. [Delete and restore with the Recycle Bin](#7-delete-and-restore-with-the-recycle-bin)
8. [Automation: joiner, mover, leaver script](#8-automation-joiner-mover-leaver-script)

---

## 1. Users, OUs and groups

The IT OU holds its four users and the `IT-Team` security group. The group's Members tab shows the same four users.

![IT OU and IT-Team members](images/01-it-ou-and-group-members.png)

## 2. Daily admin tasks

**Password reset.** Reset a user's password and required a change at next logon.

![Reset password](images/02-reset-password.png)

**Disable an account.** Disabled a user, as done when someone leaves or is suspended.

![Disable account](images/03-disable-account.png)

## 3. Shared folder restricted to one group

I created `IT-Documents` and shared it as `\\DC01\IT-Documents`. Access is given to the `IT-Team` group instead of to individual people, so adding or removing someone from the group changes their access without touching the folder.

![Folder sharing](images/05-folder-sharing.png)

Security tab permissions: SYSTEM, Administrators, and IT-Team (Modify). Inherited permissions were removed so other users have no access.

![Folder permissions](images/07-folder-permissions.png)

## 4. Group Policy

I created `IT-Desktop-Policy` and linked it to the IT OU. It enables **Prevent changing desktop background** under User Configuration, so the policy affects only users in the IT OU.

![GPO editor](images/08-gpo-editor.png)

![GPO setting enabled](images/09-gpo-enabled.png)

## 5. Account lockout and unlock

I set the account lockout threshold to **3 invalid attempts** in the Default Domain Policy.

![Lockout threshold](images/10-lockout-threshold.png)

After 3 wrong passwords, the next attempt returned error 1909: the account is locked out.

![Locked out in runas](images/11-lockout-runas.png)

`Search-ADAccount -LockedOut` confirmed the account was locked.

![Locked account](images/12-search-lockedout.png)

I unlocked it with `Unlock-ADAccount`, and the locked list came back empty. (My first attempt failed because I typed `arjunkapoor` without the dot. The username is `arjun.kapoor`.)

![Unlock](images/13-unlock.png)

## 6. Problem solved: logon error 1385

**Problem:** A normal IT user could not sign in on the domain controller. `runas` returned *1385: Logon failure: the user has not been granted the requested logon type at this computer.*

**Cause:** By default, only administrators and a few operator groups can log on locally to a domain controller. I had first added `IT-Team` to "Allow log on locally" in the **Default Domain Policy**, which a domain controller does not use for this right.

![Wrong policy](images/14-wrong-policy.png)

**Fix:** I exported the effective setting with `secedit /export` and confirmed `IT-Team` was missing from `SeInteractiveLogonRight`. Then I added `IAMLAB\IT-Team` to **Allow log on locally** in the **Default Domain Controllers Policy**, kept the existing default entries, and ran `gpupdate /force`.

![Default Domain Controllers Policy scope](images/16-gpo-dc-scope.png)

![Correct policy](images/15-correct-policy.png)

**Result:** `runas /user:IAMLAB\arjun.kapoor cmd` now opens a command prompt running as that user.

![Successful logon](images/17-runas-success.png)

**Lesson:** In a real company, users sign in on client PCs, not on the domain controller. I allowed it here for lab testing only.

## 7. Delete and restore with the Recycle Bin

I enabled the AD Recycle Bin (this cannot be undone), deleted the user `arjun.kapoor`, confirmed the account was gone, and restored it.

![Recycle Bin enabled and user deleted](images/18-recycle-bin-delete.png)

![User not found after deletion](images/19-user-not-found.png)

![User restored](images/20-restore.png)

## 8. Automation: joiner, mover, leaver script

Doing these tasks by hand works for a lab, but a real company repeats them every week. I wrote **[`scripts/JML-Automation.ps1`](scripts/JML-Automation.ps1)** to handle the three events in the identity lifecycle.

| Action | What the script does |
|---|---|
| **Joiner** | Creates the user in the department OU with a `user@IAMLAB.local` login, forces a password change at first sign-in, and adds them to the department group |
| **BulkJoiner** | Creates many users from a CSV file (`FirstName,LastName,Department`) |
| **Mover** | Moves the user to the new department's OU, removes the old department group, adds the new one, and updates the Department field |
| **Leaver** | Disables the account, removes all group memberships, moves it to a `Disabled Users` OU, and records the date and former department in the description |

### Usage

Run it in PowerShell as Administrator on the domain controller.

```powershell
# Joiner: new employee
.\JML-Automation.ps1 -Action Joiner -FirstName Asha -LastName Menon -Department IT

# Bulk joiners from a CSV file
.\JML-Automation.ps1 -Action BulkJoiner -CsvPath C:\IAM\new-hires.csv

# Mover: department change
.\JML-Automation.ps1 -Action Mover -Username asha.menon -Department Sales

# Leaver: employee leaves
.\JML-Automation.ps1 -Action Leaver -Username asha.menon

# Preview any action without changing anything
.\JML-Automation.ps1 -Action Leaver -Username asha.menon -WhatIf
```

Example CSV for `BulkJoiner`:

```csv
FirstName,LastName,Department
Asha,Menon,IT
Dev,Rao,Sales
```

### Design decisions

- **Groups give access, not individuals.** A mover changes group membership, so access follows the person's department automatically.
- **Leavers are disabled, not deleted.** The account is kept in a `Disabled Users` OU, a common practice so the account can be investigated or restored.
- **Audit log.** Every change is written to `C:\IAM-Logs\jml-log.csv` with the time, admin, action, and user. For leavers it also records the groups removed, so access can be restored if the person returns.
- **Safe by default.** `-WhatIf` previews every change. The script stops with a clear message if an OU or group is missing, skips users that already exist, and never stores a password in the script or the log (the starting password is typed at a prompt).
- **Known limit.** Usernames are `first.last`, so two people with the same name would clash. The script skips the duplicate with a warning. A real company would add a number or an employee ID.

<!-- Add after you run the script in the lab:
### Test run
1. Joiner: created asha.menon in IT
2. Mover: moved her to Sales
3. Leaver: disabled her and moved her to Disabled Users
4. Audit log: C:\IAM-Logs\jml-log.csv

![Joiner](images/21-jml-joiner.png)
![Mover](images/22-jml-mover.png)
![Leaver](images/23-jml-leaver.png)
![Audit log](images/24-jml-log.png)
-->

---

## What I learned

- An **OU** organizes users and lets policies apply to a set of people. A **group** gives access. A user sits in one OU but can be in many groups.
- Giving permissions to groups, not people, makes joiner, mover, and leaver work much simpler, and it is what makes automating them possible.
- A domain controller is protected on purpose, so normal users are blocked from logging on to it by default.
- Account policies such as lockout go in the Default Domain Policy, while the log-on right for a domain controller goes in the Default Domain Controllers Policy.
- Turning on the AD Recycle Bin before you need it makes recovering deleted accounts much easier.
- Keeping an audit log of identity changes is part of the job, not an extra.

## Tools

Windows Server 2025, Active Directory Domain Services, Group Policy Management, PowerShell (ActiveDirectory module), VMware Workstation.

## Next

Week 3 continues the IAM roadmap.

> All passwords in this lab are fake and used only in an isolated virtual machine.