# IAM Roadmap

A hands-on, 16-week path into **Identity and Access Management (IAM)**. Each week I build a real lab, document it with screenshots, and write down what I learned and what went wrong.

**Goal:** IAM Analyst role in India.
**Duration:** 19 Oct 2026 to 7 Feb 2027.

## About me

I'm Tusharkanta Nahak, a computer science graduate (B.Tech, 2025) with one year of IT support experience, including basic Active Directory work such as account creation and password resets. I'm now building deeper IAM skills through labs, and I'm preparing for the Microsoft SC-300 (Identity and Access Administrator) exam.

## Progress

| Week | Topic | What I built | Folder |
|---|---|---|---|
| 1 | Microsoft Entra ID | Cloud directory with 20 users and 5 groups | [week-01-entra-id](week-01-entra-id) |
| 2 | Active Directory | Domain controller (`IAMLAB.local`), OUs, groups, Group Policy, account lockout, Recycle Bin, and a PowerShell joiner/mover/leaver script | [week-02-active-directory](week-02-active-directory) |

New weeks are added to this table as I finish them.

## Highlights so far

- **Same company, two directories.** The same 20 users and 5 department groups exist in both Entra ID (cloud) and Active Directory (on-premises), so I can compare how each handles users, groups, and access.
- **Access through groups, not people.** Folder permissions and policies are given to groups, which makes joiner, mover, and leaver changes simple.
- **Lifecycle automation.** `JML-Automation.ps1` creates users, moves them between departments, and processes leavers, with a preview mode and an audit log. See [Week 2](week-02-active-directory).
- **Troubleshooting write-ups.** Each week includes problems I hit and how I fixed them, such as the logon error 1385 in Week 2.

## Skills and tools

| Area | What I've used |
|---|---|
| Cloud identity | Microsoft Entra ID (users, groups) |
| On-premises identity | Active Directory Domain Services, Group Policy, DNS |
| Scripting | PowerShell (ActiveDirectory module) |
| Access control | Security groups, NTFS and share permissions, account lockout policy |
| Lifecycle | Joiner, mover, leaver processes, Recycle Bin recovery, audit logging |
| Platform | Windows Server 2025, VMware Workstation |

## Repository layout

```
iam-roadmap/
├── README.md
├── week-01-entra-id/
│   ├── README.md
│   └── images/
├── week-02-active-directory/
│   ├── README.md
│   ├── images/
│   └── scripts/
│       └── JML-Automation.ps1
└── week-03-.../
```

Each week folder has its own README with the steps, screenshots, problems solved, and lessons learned.

## A note on the labs

All labs run in isolated virtual machines or a personal test tenant. Passwords shown or used are fake, and no real company data is included.

## Contact

- LinkedIn: _https://www.linkedin.com/in/tusharkanta-nahak-3445a91b0_
