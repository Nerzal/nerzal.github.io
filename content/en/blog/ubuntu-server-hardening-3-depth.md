---
draft: false
title: "Ubuntu Server Hardening — Part 3: Defense in Depth"
seo_title: "Ubuntu Hardening Part 3: Defense in Depth"
date: 2026-07-30T00:00:00+00:00
tags:
  ["tutorial", "linux", "ubuntu", "security", "hardening", "devops", "server"]
description: "The final hardening layer: mandatory access control with AppArmor, audit logging with auditd, and filesystem integrity monitoring with AIDE."
images: ["img/ubuntu-server-hardening.png"]
featured_image: "img/ubuntu-server-hardening.png"
toc: true
---

[Part 1](/blog/ubuntu-server-hardening-1-essentials/) covered the essential first measures: UFW, Fail2ban, and automatic updates. [Part 2](/blog/ubuntu-server-hardening-2-system/) tightened the system configuration: sysctl, unused services, sudo, and login policies.

This part is different in character. Where the previous two posts were about _preventing_ compromise, the measures here assume that a sufficiently motivated attacker may eventually get in — and focus on **detecting** it, **containing** it, and having **evidence** when it happens.

> **Assumes:** Parts 1 and 2 complete, SSH hardened, non-root sudo user.

---

## 1 — AppArmor: Mandatory Access Control

[AppArmor](https://apparmor.net/) is a mandatory access control (MAC) framework built into the Linux kernel. It enforces per-program security policies: a profile defines exactly which files a process may read, write, or execute, and which network connections it may make. Policies are enforced by the kernel — a process cannot opt out.

The practical consequence: if an attacker exploits a vulnerability in nginx and gains code execution under the nginx process, AppArmor keeps them confined to what nginx legitimately needs. They cannot read `/etc/shadow`, write to `/var/spool/cron`, or spawn shells.

### Ubuntu ships AppArmor enabled

Check the current status:

```bash
sudo apparmor_status
```

Profiles appear in two modes:

- **enforce** — violations are blocked and logged
- **complain** — violations are logged but allowed (used for developing new profiles)

Install the community-maintained profile set and enforce everything:

```bash
sudo apt install apparmor-profiles apparmor-profiles-extra apparmor-utils -y

# Move any complain-mode profiles to enforce
sudo aa-enforce /etc/apparmor.d/*

# Verify
sudo apparmor_status | grep "enforce mode"
```

### Writing a profile for your own application

`aa-genprof` monitors a running process and generates a profile from its observed behavior:

```bash
# Start the tool — it will ask you to run your application in another window
sudo aa-genprof /usr/local/bin/myapp

# In a second terminal, run your application through its normal workflow
# When done, return to the aa-genprof terminal and press S to scan the log
# Review and accept/reject each proposed rule, then F to finish
```

The generated profile is saved to `/etc/apparmor.d/` and loaded immediately. It can be version-controlled alongside your application.

### Inspecting denials

```bash
# Real-time AppArmor denial log
sudo journalctl -f | grep apparmor

# Summarize recent denials
sudo aa-logprof
```

---

## 2 — auditd: Kernel-Level Audit Logging

The Linux Audit System ([auditd](https://linux.die.net/man/8/auditd)) records security-relevant events at the syscall level. Unlike application logs, it cannot be silenced by a compromised process — it runs in the kernel and writes directly to a dedicated log file. It is the primary source of evidence in post-incident forensics.

```bash
sudo apt install auditd audispd-plugins -y
sudo systemctl enable --now auditd
```

### Configuring rules

Rules go in `/etc/audit/rules.d/`. Create a hardening ruleset:

```bash
sudo nano /etc/audit/rules.d/99-hardening.rules
```

```text
# Flush existing rules
-D

# Buffer size — increase if events are dropped under load
-b 8192

# Lock rules until next reboot (prevents tampering with audit config)
-e 2

# ── Identity files ─────────────────────────────────────────────────────
-w /etc/passwd  -p wa -k identity
-w /etc/shadow  -p wa -k identity
-w /etc/group   -p wa -k identity

# ── Privilege escalation ────────────────────────────────────────────────
-w /etc/sudoers    -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers
-w /usr/bin/sudo   -p x  -k sudo_exec
-w /bin/su         -p x  -k su_exec

# ── SSH configuration ───────────────────────────────────────────────────
-w /etc/ssh/sshd_config -p wa -k sshd_config

# ── Login activity ──────────────────────────────────────────────────────
-w /var/log/faillog  -p wa -k login
-w /var/log/lastlog  -p wa -k login
```

Load the rules:

```bash
sudo augenrules --load

# Confirm they are active
sudo auditctl -l
```

### Querying the audit log

```bash
# All events tagged with 'sudoers' (config changes or sudo executions)
sudo ausearch -k sudoers

# Events from the last hour
sudo ausearch --start recent

# All failed login attempts
sudo ausearch --message USER_AUTH --success no

# Human-readable summary report
sudo aureport --summary

# Report of all commands run via sudo in the last 24 hours
sudo aureport --comm --start today
```

---

## 3 — AIDE: Filesystem Integrity Monitoring

[AIDE](https://aide.github.io/) (Advanced Intrusion Detection Environment) takes a cryptographic snapshot of the filesystem at a known-good state. On subsequent runs, it compares the live filesystem against that snapshot and reports any differences: new files, deleted files, changed permissions, changed content.

If an attacker installs a backdoor, replaces a system binary, or modifies a configuration file, AIDE detects it — even if the attacker covers their tracks in application logs.

```bash
sudo apt install aide aide-common -y
```

Review the default configuration (which directories to monitor and with what checks):

```bash
sudo less /etc/aide/aide.conf
```

The defaults already cover `/usr`, `/bin`, `/sbin`, `/etc`, and related directories. For most servers this is appropriate without changes.

### Initialize the database

This takes a few minutes on the first run — AIDE hashes every monitored file:

```bash
sudo aideinit
# Output: The new database will be written to /var/lib/aide/aide.db.new
sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
```

Run a check to confirm there are no unexpected differences:

```bash
sudo aide --check
# On a fresh setup: "Looks okay, no differences found."
```

### Automating daily checks

```bash
sudo crontab -e
```

```text
# Daily AIDE integrity check at 03:00, send results by email
0 3 * * * /usr/bin/aide --check 2>&1 | mail -s "AIDE report $(hostname)" root
```

After system updates, reinitialize the database to accept the new state as the baseline:

```bash
sudo aideinit
sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
```

---

## The Complete Picture

Across the three posts, we built a layered defense where each layer operates independently:

| Layer               | Post                                 | Protects against                          |
| ------------------- | ------------------------------------ | ----------------------------------------- |
| SSH hardening       | [SSH post](/blog/secure-ssh-server/) | Unauthorized remote access                |
| UFW                 | Part 1                               | Unexpectedly exposed services             |
| Fail2ban            | Part 1                               | Brute-force attacks                       |
| Unattended upgrades | Part 1                               | Known CVEs in unpatched packages          |
| sysctl              | Part 2                               | Network and kernel exploits               |
| Disabled services   | Part 2                               | Attack surface from unused services       |
| Sudo restriction    | Part 2                               | Privilege escalation blast radius         |
| Login policy        | Part 2                               | Weak local credentials                    |
| AppArmor            | Part 3                               | Lateral movement after process compromise |
| auditd              | Part 3                               | Undetected post-compromise activity       |
| AIDE                | Part 3                               | Binary and configuration tampering        |

No single layer provides complete security. Together, they force an attacker to bypass each one independently and make sustained access without detection extremely difficult.

---

## Going Further

- **[Lynis](https://cisofy.com/lynis/)** — runs a scored audit of your server's hardening posture and generates a prioritized to-do list. `sudo lynis audit system` is a useful baseline check.
- **[Wazuh](https://wazuh.com/)** — a SIEM agent that aggregates auditd, Fail2ban, AppArmor, and application logs into a searchable dashboard with alerting rules.
- **[CIS Ubuntu Benchmarks](https://www.cisecurity.org/cis-benchmarks)** — scored compliance benchmarks covering hundreds of hardening checks. The free PDF is a reference for what "fully hardened" looks like in regulated environments.

---

## Further Reading

- [Ubuntu Security Guide](https://ubuntu.com/security/certifications/docs/usg)
- [AppArmor GitLab Wiki](https://gitlab.com/apparmor/apparmor/-/wikis/home)
- [Linux Audit Documentation](https://linux.die.net/man/8/auditd)
- [AIDE manual](https://aide.github.io/)
