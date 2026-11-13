---
draft: false
title: "Ubuntu Server Hardening — Part 1: The Essentials"
seo_title: "Ubuntu Hardening Part 1: The Essentials"
date: 2026-05-11T00:00:00+00:00
tags:
  ["tutorial", "linux", "ubuntu", "security", "hardening", "devops", "server"]
description: "Three measures every public Ubuntu server needs immediately: a default-deny UFW firewall, Fail2ban brute-force protection, and automatic security updates."
images: ["img/ubuntu-server-hardening.png"]
featured_image: "img/ubuntu-server-hardening.png"
toc: true
---

This is the first post in a three-part series on hardening a public Ubuntu server.

In the [previous post](/blog/secure-ssh-server/) we secured SSH: replaced password login with key-based authentication, disabled root, and restricted which users can connect at all. That alone eliminates the majority of attacks targeting internet-facing servers.

But SSH is one layer. This series adds three more layers per post, ordered by how quickly you can apply them and how much impact they have. Start here — these three take less than fifteen minutes and protect against the most common active threats.

> **Assumes:** Ubuntu 22.04 / 24.04 / 26.04, SSH already hardened, a non-root user with `sudo` access.

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
# Deny connections from an IP that opened 6 or more in the last 30 seconds
sudo ufw limit OpenSSH
```

This is a sliding-window throttle, not a ban: per the [ufw man page](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html), UFW denies new connections from an IP once it has attempted 6 or more within 30 seconds. As soon as that IP slows down, it gets through again. Real bans with a configurable duration are what Fail2ban adds in the next section.

### Docker bypasses UFW

If you run Docker on this server, know this before you trust the firewall: ports published with `docker run -p` or `ports:` in Compose are **not** filtered by UFW. Docker inserts its own `iptables` rules, and the traffic is routed to the container before UFW's rules are evaluated — `ufw status` will not even show these ports. See Docker's documentation on [packet filtering and firewalls](https://docs.docker.com/engine/network/packet-filtering-firewalls/). To keep a container port private, bind it to localhost (`-p 127.0.0.1:8080:80`) and put a reverse proxy in front of it.

### Verify from your local machine

Before closing your session, open a second terminal and confirm SSH still works:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
ssh deploy@your-server-ip
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
ssh deploy@your-server-ip
```

{{< /os-tab >}}
{{< /os-tabs >}}

---

## 2 — Fail2ban: Brute-Force Protection

Even with key-only SSH, other services (web servers, mail servers, custom APIs) accept connections that can be brute-forced. [Fail2ban](https://github.com/fail2ban/fail2ban) monitors log files and adds a temporary firewall ban for IPs that produce too many failures.

```bash
sudo apt install fail2ban -y
```

Do not edit `/etc/fail2ban/jail.conf` — it gets overwritten on updates. Fail2ban reads `jail.local` on top of it, so create that file with **only the settings you want to change**. Do not copy the whole `jail.conf` over: a full copy freezes every default at today's values, and improvements that future package updates ship in `jail.conf` would never reach you.

```bash
sudo tee /etc/fail2ban/jail.local > /dev/null <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
EOF
```

The `[DEFAULT]` values ban any IP for one hour if it fails authentication five times within ten minutes. Adjust `bantime` to something longer (e.g., `24h` or `1w`) if your logs show persistent scanners. Ubuntu's package already enables the `[sshd]` jail in `/etc/fail2ban/jail.d/defaults-debian.conf`; setting it here as well makes your intent explicit and independent of that file.

Start and enable Fail2ban:

```bash
sudo systemctl enable --now fail2ban
```

Then check that the `sshd` jail is active:

```bash
sudo fail2ban-client status sshd
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
