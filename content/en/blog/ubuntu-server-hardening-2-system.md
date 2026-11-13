---
draft: false
title: "Ubuntu Server Hardening — Part 2: Tightening the System"
seo_title: "Ubuntu Hardening Part 2: System Tightening"
date: 2026-05-12T00:00:00+00:00
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

### Hiding other users' processes

A setting you will often find in hardening guides is `kernel.hidepid`. **It is not a sysctl** — `sysctl --system` would report it as an unknown key. `hidepid` is a mount option of the `proc` filesystem ([proc(5)](https://man7.org/linux/man-pages/man5/proc.5.html)). With `hidepid=invisible` (the older numeric spelling is `hidepid=2`), non-root users can neither read nor even list other users' `/proc/[pid]` directories, so `ps` and `htop` only show their own processes.

Add this line to `/etc/fstab`:

```text
proc  /proc  proc  defaults,hidepid=invisible  0  0
```

Apply it without a reboot:

```bash
sudo mount -o remount,hidepid=invisible /proc
```

If a monitoring agent needs to see all processes, create a dedicated group (Ubuntu has no `proc` group by default), add the agent's user, and exempt that group with `gid=`:

```bash
sudo groupadd --system procview
sudo usermod -aG procview monitoring
# fstab options then become: defaults,hidepid=invisible,gid=procview
```

> **Caveat:** systemd components such as `systemd-logind` and polkit inspect other processes in `/proc`. On some setups `hidepid` breaks polkit authorization or user sessions. Test it on a staging machine first, and keep a console session open when you apply it. For a single service, systemd's [`ProtectProc=invisible`](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#ProtectProc=) gives the same isolation without touching the global mount.

---

## 2 — Disable Unnecessary Services

Every running service is a potential attack surface. On a minimal VPS, several services that make sense on a desktop are running by default and serve no purpose.

List what is active:

```bash
sudo systemctl list-units --type=service --state=running
```

Common candidates to disable on a headless server — if they exist. A minimal Ubuntu Server install does not ship Avahi, CUPS, or BlueZ at all; they usually appear when a desktop image was used or a package pulled them in. `Unit … not found` simply means there is nothing to do:

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
```

> **About `log_input` / `log_output`:** Many guides add `Defaults log_input, log_output` for full session recording to `/var/log/sudo-io`. Be careful: `log_input` records **every keystroke** typed in a sudo session, including passwords entered into programs such as `sudo passwd` or `sudo mysql -p`, and `log_output` stores everything printed, including secrets. Only enable it if you protect and rotate `/var/log/sudo-io` accordingly ([sudoers(5)](https://www.sudo.ws/docs/man/sudoers.man/)).

If a user only needs to manage one specific service, restrict them to exactly that. Put the rule in its own drop-in file:

```bash
sudo visudo -f /etc/sudoers.d/deploy
```

```text
# 'deploy' may only restart and reload nginx — nothing else
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl reload nginx
```

This rule only restricts anything if `deploy` is **not** also a member of the `sudo` group — otherwise the group's `%sudo ALL=(ALL:ALL) ALL` line still grants full root. Before removing the membership, confirm that another account still has working admin access (open a second SSH session as that user and run `sudo -v`), then:

```bash
sudo gpasswd -d deploy sudo

# Verify: should list only the two nginx commands
sudo -l -U deploy
```

Check for any existing broad wildcard permissions in `/etc/sudoers.d/`:

```bash
sudo ls -la /etc/sudoers.d/
sudo cat /etc/sudoers.d/*
```

---

## 4 — Login and Password Policy

Even with key-only SSH, local accounts can be authenticated through the physical console or out-of-band management interfaces. Setting a password policy limits the impact of weak local credentials.

What a _good_ policy looks like has changed. [NIST SP 800-63B (Revision 4)](https://pages.nist.gov/800-63-4/sp800-63b.html), the reference most compliance frameworks follow, now says verifiers:

- **shall require a minimum length** — 15 characters for passwords used as the only factor,
- **shall compare new passwords against a blocklist** of commonly used, expected, or compromised values,
- **shall not impose composition rules** ("at least one digit, one uppercase, one symbol"),
- **shall not force periodic changes** — only on evidence of compromise.

Forced rotation and composition rules push users towards predictable patterns like `Summer2026!` → `Autumn2026!`. Length plus a blocklist is both stronger and easier to live with.

### Password aging in `/etc/login.defs`

Ubuntu's default `PASS_MAX_DAYS 99999` (no expiry) already matches NIST, so leave it. Note that `login.defs` does not support comments at the end of a value line — a trailing `# …` becomes part of the value and the setting is rejected. Comments always go on their own line:

```bash
sudo nano /etc/login.defs
```

```text
# No forced rotation (NIST SP 800-63B)
PASS_MAX_DAYS   99999
# Prevent cycling through changes to get an old password back
PASS_MIN_DAYS   1
PASS_WARN_AGE   7
```

`login.defs` is only read when an account is **created**. Existing accounts keep their values; inspect and change them with `chage`:

```bash
# Show the aging settings of an existing user
sudo chage -l alice

# Remove forced expiry and set a minimum age of 1 day
sudo chage --maxdays 99999 --mindays 1 alice
```

### Length and blocklist with pwquality

Install `libpam-pwquality`, which hooks into PAM whenever a password is changed with `passwd`:

```bash
sudo apt install libpam-pwquality -y
sudo nano /etc/security/pwquality.conf
```

```text
# Minimum length (NIST: 15 for single-factor passwords)
minlen = 15
# No composition rules: the credit options stay at their default of 0
dcredit = 0
ucredit = 0
lcredit = 0
ocredit = 0
# Reject words found in the cracklib dictionary
dictcheck = 1
# Reject passwords containing the username
usercheck = 1
# Apply the policy to root as well
enforce_for_root
```

`dictcheck` uses the local cracklib word list. It catches common and dictionary-based passwords, but it is not a list of _breached_ passwords. If you need that, check candidates against a breach corpus such as [Have I Been Pwned's Pwned Passwords](https://haveibeenpwned.com/Passwords) — its range API uses k-anonymity, so only the first five characters of the password's SHA-1 hash leave the machine.

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
