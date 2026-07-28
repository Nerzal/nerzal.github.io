---
draft: false
title: "Ubuntu Server Hardening — Part 2: Tightening the System"
seo_title: "Ubuntu Hardening Part 2: System Tightening"
date: 2026-05-10T00:00:00+00:00
tags:
  ["tutorial", "linux", "ubuntu", "security", "hardening", "devops", "server"]
description: "The second hardening pass: tuning kernel parameters with sysctl, disabling attack surface you do not use, and restricting sudo and local login policies."
images: ["img/ubuntu-server-hardening.png"]
featured_image: "img/ubuntu-server-hardening.png"
toc: true
---

[Part 1](/blog/ubuntu-server-hardening-1-essentials/) covered the three basics that every public server needs: UFW, Fail2ban, and automatic security updates. With those in place, the most common automated attacks are already mitigated.

This part focuses on reducing attack surface — both at the kernel level and in the privilege model. The measures here require slightly more thought than Part 1 but none of them involve installing additional software.

> **Assumes:** Part 1 complete, SSH hardened, non-root sudo user.

---

## 1 — Kernel Hardening with sysctl

The Linux kernel exposes runtime parameters in `/proc/sys/`. Many defaults favor compatibility over security. The `sysctl` command writes to these parameters; placing configuration in `/etc/sysctl.d/` makes it persist across reboots.

```bash
sudo nano /etc/sysctl.d/99-hardening.conf
```

```text
# ── Network ───────────────────────────────────────────────────────────────

# Refuse ICMP redirects — prevents routing-manipulation MITM attacks
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Do not send ICMP redirects — this server is not a router
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Refuse source-routed packets
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Reverse-path filtering — drop packets with impossible source addresses
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# SYN cookie protection against SYN flood attacks
net.ipv4.tcp_syncookies = 1

# Ignore ICMP broadcasts (prevents Smurf amplification attacks)
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Log packets with impossible source/destination addresses
net.ipv4.conf.all.log_martians = 1

# ── Kernel ────────────────────────────────────────────────────────────────

# Restrict /proc/[pid] visibility to the owning user
kernel.hidepid = 2

# Restrict kernel pointer exposure in /proc (reduces info leakage to non-root)
kernel.kptr_restrict = 2

# dmesg readable by root only
kernel.dmesg_restrict = 1

# Disable magic SysRq key
kernel.sysrq = 0

# ptrace restricted to parent processes (limits debugger-based attacks)
kernel.yama.ptrace_scope = 1

# Disable core dumps for setuid programs
fs.suid_dumpable = 0
```

Apply immediately:

```bash
sudo sysctl --system
```

Verify a specific value:

```bash
sysctl net.ipv4.tcp_syncookies
# net.ipv4.tcp_syncookies = 1
```

> **`kernel.hidepid = 2` note:** Non-root users can no longer see other users' processes in `/proc`. If a monitoring tool like `htop` needs to see all processes, add its user to the `proc` group and use `hidepid=2,gid=proc` instead.

---

## 2 — Disable Unnecessary Services

Every running service is a potential attack surface. On a minimal VPS, several services that make sense on a desktop are running by default and serve no purpose.

List what is active:

```bash
sudo systemctl list-units --type=service --state=running
```

Common candidates to disable on a headless server:

```bash
# mDNS — device discovery, irrelevant on a server
sudo systemctl disable --now avahi-daemon

# Print spooler — no printers on a server
sudo systemctl disable --now cups

# Bluetooth — no hardware, no purpose
sudo systemctl disable --now bluetooth
```

After disabling, check which ports are still open and match them to processes:

```bash
sudo ss -tlnp
```

Every line in the output should correspond to a service you consciously chose to expose. If you see a port you do not recognize, investigate before closing it — `systemd-resolved` listening on `127.0.0.53:53` is expected, for example.

---

## 3 — Sudo Hardening

The default `sudo` group grants unrestricted root access. For most tasks, that is wider than necessary.

Edit sudoers exclusively through `visudo` — it validates syntax before saving and prevents you from locking yourself out of sudo:

```bash
sudo visudo
```

Useful additions to the `Defaults` section:

```text
# Re-prompt for password after 5 minutes of inactivity (default: 15)
Defaults timestamp_timeout=5

# Log every sudo command with timestamps
Defaults logfile=/var/log/sudo.log
Defaults log_input, log_output
```

If a user only needs to manage one specific service, restrict them to exactly that:

```text
# 'deploy' may only restart and reload nginx — nothing else
deploy ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart nginx
deploy ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload nginx
```

Check for any existing broad wildcard permissions in `/etc/sudoers.d/`:

```bash
sudo ls -la /etc/sudoers.d/
sudo cat /etc/sudoers.d/*
```

---

## 4 — Login and Password Policy

Even with key-only SSH, local accounts can be authenticated through the physical console or out-of-band management interfaces. Setting a password policy limits the impact of weak local credentials.

Edit `/etc/login.defs`:

```bash
sudo nano /etc/login.defs
```

```text
PASS_MAX_DAYS   90      # force rotation every 90 days
PASS_MIN_DAYS   1       # prevent immediate re-use after change
PASS_WARN_AGE   7       # warn 7 days before expiry
```

For password complexity, install `libpam-pwquality`:

```bash
sudo apt install libpam-pwquality -y
sudo nano /etc/security/pwquality.conf
```

```text
minlen   = 14     # minimum length
dcredit  = -1     # require at least 1 digit
ucredit  = -1     # require at least 1 uppercase letter
ocredit  = -1     # require at least 1 special character
difok    = 8      # must differ from previous password by at least 8 characters
usercheck = 1     # reject passwords containing the username
```

---

## What This Pass Covers

| Measure           | Effect                                                     |
| ----------------- | ---------------------------------------------------------- |
| sysctl hardening  | Closes network-layer attack vectors at the kernel level    |
| Disabled services | Reduces the number of entry points that need to be secured |
| Sudo restrictions | Limits the blast radius of a compromised account           |
| Password policy   | Raises the cost of brute-forcing local credentials         |

These four measures require no external tools and produce no network traffic — they are pure configuration changes to what is already there.

**Part 3** covers the deeper layer: AppArmor mandatory access control, kernel-level auditing with `auditd`, and filesystem integrity monitoring with AIDE.
