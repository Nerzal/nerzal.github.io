---
draft: false
title: "Ubuntu Server Hardening — Part 1: The Essentials"
date: 2026-05-11T08:00:00+00:00
tags:
  ["tutorial", "linux", "ubuntu", "security", "hardening", "devops", "server"]
description: "The three measures every public Ubuntu server needs within the first hour: a default-deny firewall with UFW, brute-force protection with Fail2ban, and automatic security updates."
images: ["img/ubuntu-server-hardening.png"]
featured_image: "img/ubuntu-server-hardening.png"
toc: true
---

This is the first post in a three-part series on hardening a public Ubuntu server.

In the [previous post](/blog/secure-ssh-server/) we secured SSH: replaced password login with key-based authentication, disabled root, and restricted which users can connect at all. That alone eliminates the majority of attacks targeting internet-facing servers.

But SSH is one layer. This series adds three more layers per post, ordered by how quickly you can apply them and how much impact they have. Start here — these three take less than fifteen minutes and protect against the most common active threats.

> **Assumes:** Ubuntu 20.04 / 22.04 / 24.04, SSH already hardened, a non-root user with `sudo` access.

---

## 1 — UFW: Default-Deny Firewall

A freshly provisioned server often exposes every port that has a service listening on it. The firewall changes that: **block everything by default, allow only what you explicitly need.**

Ubuntu ships with [UFW](https://help.ubuntu.com/community/UFW) (Uncomplicated Firewall) pre-installed. It is a usable frontend to `iptables`/`nftables` that keeps rules readable.

### Enable with SSH already open

The most common way to lock yourself out: enable the firewall before allowing SSH. Do this first:

```bash
# Allow SSH through the firewall before activating it
sudo ufw allow OpenSSH

# If you run a web server, allow HTTP and HTTPS too
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Now enable
sudo ufw enable

# Verify
sudo ufw status verbose
```

The output should say `Status: active` and list exactly the ports you opened. Any port not in that list is now closed, regardless of what is listening on it.

**Non-standard SSH port:** if you changed the SSH port from 22, allow that specific port instead:

```bash
sudo ufw allow 2222/tcp comment "SSH"
```

### Rate-limit connections

UFW can throttle incoming connections to a port — useful as a lightweight layer before Fail2ban is configured:

```bash
# Ban IPs that attempt more than 6 connections in 30 seconds
sudo ufw limit OpenSSH
```

### Verify from your local machine

Before closing your session, open a second terminal and confirm SSH still works:

```bash
ssh deploy@your-server-ip
```

```powershell
ssh deploy@your-server-ip
```

---

## 2 — Fail2ban: Brute-Force Protection

Even with key-only SSH, other services (web servers, mail servers, custom APIs) accept connections that can be brute-forced. [Fail2ban](https://github.com/fail2ban/fail2ban) monitors log files and adds a temporary firewall ban for IPs that produce too many failures.

```bash
sudo apt install fail2ban -y
```

Do not edit `/etc/fail2ban/jail.conf` — it gets overwritten on updates. Create a local override instead:

```bash
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo nano /etc/fail2ban/jail.local
```

Find the `[DEFAULT]` section at the top and set:

```text
bantime  = 1h
findtime = 10m
maxretry = 5
```

This bans any IP for one hour if it fails authentication more than five times within ten minutes. Adjust `bantime` to something longer (e.g., `24h` or `1w`) if your logs show persistent scanners.

The `[sshd]` jail is enabled by default. Check that it is active:

```bash
sudo fail2ban-client status sshd
```

Start and enable Fail2ban:

```bash
sudo systemctl enable --now fail2ban
```

### Useful commands

```bash
# List all active jails
sudo fail2ban-client status

# Show banned IPs for a specific jail
sudo fail2ban-client status sshd

# Unban an IP (if you accidentally ban yourself during testing)
sudo fail2ban-client set sshd unbanip 1.2.3.4

# Watch the Fail2ban log live
sudo tail -f /var/log/fail2ban.log
```

---

## 3 — Unattended Upgrades: Automatic Security Patches

Unpatched packages are one of the most common root causes of server compromise. Enabling automatic security updates means you no longer depend on manually running `apt upgrade` before a CVE is exploited.

```bash
sudo apt install unattended-upgrades apt-listchanges -y
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

Answer **Yes** to the single question in the dialog.

Verify the configuration file:

```bash
sudo nano /etc/apt/apt.conf.d/50unattended-upgrades
```

The most relevant section:

```text
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
```

This restricts automatic installation to security updates only — not feature updates that might break things.

Two more settings worth reviewing:

```text
// Remove old kernel packages that are no longer needed
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";

// Reboot if required (e.g. after a kernel update)
// Set to "true" only if you have a defined maintenance window
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
```

Verify the timer is running:

```bash
sudo systemctl status apt-daily-upgrade.timer
```

Test the configuration without actually installing anything:

```bash
sudo unattended-upgrade --dry-run --debug
```

---

## What These Three Measures Do Together

| Measure             | What it stops                                     |
| ------------------- | ------------------------------------------------- |
| UFW default-deny    | Services accidentally exposed on unexpected ports |
| Fail2ban            | Automated credential brute-forcing                |
| Unattended upgrades | Exploitation of known, patched CVEs               |

None of these are difficult to set up. They cover the three most common attack patterns against public servers and take less than fifteen minutes combined.

**Part 2** covers the next layer: kernel parameter hardening, disabling unnecessary services, and tightening sudo and login policies.
