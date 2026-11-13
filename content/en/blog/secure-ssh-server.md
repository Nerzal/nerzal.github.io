---
draft: false
title: "How to Secure SSH Access on Linux (Ubuntu)"
date: 2026-05-09T00:00:00+00:00
tags: ["tutorial", "linux", "ubuntu", "ssh", "security", "devops"]
description: "Harden your Ubuntu server's SSH access step by step: create and deploy an SSH key pair, add a sudo user, disable password authentication, and lock out root."
images: ["img/ssh_certificates.png"]
featured_image: "img/ssh_certificates.png"
toc: true
---

Every publicly reachable Linux server is under constant brute-force pressure. If you leave SSH open with password authentication and the `root` account enabled, it is not a question of _if_ an attacker gets in — it is a question of _when_. This guide walks you through four concrete steps that eliminate the most common attack surface:

1. **Create an SSH key pair** on your local machine
2. **Create a dedicated sudo user** on the server
3. **Deploy your public key** to the server
4. **Harden `sshd`**: disable password login and block root login

By the end you will log in exclusively with your private key, through a non-root account that can escalate privileges with `sudo`.

> **Before you start — take a snapshot.** If your server runs on a cloud provider (Hetzner, DigitalOcean, AWS, etc.), create a snapshot or backup of the server right now. Most providers offer this in their web console with one click. A snapshot lets you restore the exact state of the machine in minutes if something goes wrong — for example, if you accidentally lock yourself out before key-based login is verified. The cost is typically a few cents and the peace of mind is worth it.

---

## Prerequisites

- A Linux server reachable via SSH — in our case Ubuntu 22.04, 24.04 or 26.04. The steps are the same on all three; the one difference (since 24.04, `ssh` is started through systemd socket activation via `ssh.socket`) is pointed out where it matters. Ubuntu 20.04 has left standard support, so upgrade it first.
- Your current ability to log in as `root` or a user with `sudo` privileges (you need this to apply the config changes)
- OpenSSH client on your local machine — it ships with every modern Linux, macOS, and Windows 10+ installation

> **Warning:** Do **not** close your existing SSH session until you have verified that key-based login works. If you lock yourself out of a cloud VM, you will need the provider's recovery console.

---

## Step 1 — Create an SSH Key Pair on Your Local Machine

An SSH key pair consists of two mathematically linked files:

- **Private key** (`id_ed25519`) — stays on your machine, never leaves it
- **Public key** (`id_ed25519.pub`) — placed on every server you want to access

The current recommendation is **Ed25519**, an elliptic-curve algorithm defined in [RFC 8032](https://datatracker.ietf.org/doc/html/rfc8032). It produces shorter keys than RSA while offering equivalent or better security, and it is supported by all modern OpenSSH versions (≥ 6.5).

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
ssh-keygen -t ed25519 -C "your-email@example.com"
```

{{< /os-tab >}}
{{< /os-tabs >}}

`ssh-keygen` is part of the OpenSSH client that ships with Windows 10 (version 1809) and later. If you are on an older version, install it via _Optional Features_ or use [PuTTYgen](https://www.chiark.greenend.org.uk/~sgtatham/putty/).

The tool will ask two things:

```text
Enter file in which to save the key (/home/you/.ssh/id_ed25519):
Enter passphrase (empty for no passphrase):
```

- **File location**: press Enter to accept the default (`~/.ssh/id_ed25519` on Linux/macOS, `%USERPROFILE%\.ssh\id_ed25519` on Windows).
- **Passphrase**: enter a strong passphrase. This encrypts your private key on disk; if your laptop is stolen, the attacker still cannot use the key without the passphrase. An SSH agent (see below) means you only have to type it once per session.

After completion you will have two files:

```text
~/.ssh/id_ed25519      # private key — permissions must be 600
~/.ssh/id_ed25519.pub  # public key  — safe to share
```

### A note on Post-Quantum Cryptography (PQC)

Ed25519 is the right choice today, but it is worth understanding the longer-term picture.

Both RSA and elliptic-curve algorithms (including Ed25519) rely on mathematical problems — integer factorization and the discrete logarithm problem — that a sufficiently powerful quantum computer could solve in polynomial time using [Shor's algorithm](https://en.wikipedia.org/wiki/Shor%27s_algorithm). No such computer exists yet, but the threat is real enough that NIST finalized three post-quantum cryptography standards in August 2024:

- **[FIPS 203](https://doi.org/10.6028/NIST.FIPS.203)** — ML-KEM (formerly CRYSTALS-Kyber): a key-encapsulation mechanism for key exchange
- **[FIPS 204](https://doi.org/10.6028/NIST.FIPS.204)** — ML-DSA (formerly CRYSTALS-Dilithium): a lattice-based digital signature scheme
- **[FIPS 205](https://doi.org/10.6028/NIST.FIPS.205)** — SLH-DSA (formerly SPHINCS+): a hash-based digital signature scheme

**What OpenSSH already does.** OpenSSH protects the _key exchange_ (KEX) with hybrid algorithms that combine a post-quantum KEM with classical X25519 — the session stays secure as long as either half holds:

- **OpenSSH 9.0** (April 2022) made `sntrup761x25519-sha512@openssh.com` the default: [Streamlined NTRU Prime 761](https://ntruprime.cr.yp.to/) + X25519. It is now standardized as `sntrup761x25519-sha512` in [RFC 9941](https://www.rfc-editor.org/rfc/rfc9941).
- **OpenSSH 9.9** (September 2024) added `mlkem768x25519-sha256`: ML-KEM-768 from [FIPS 203](https://doi.org/10.6028/NIST.FIPS.203) + X25519. **OpenSSH 10.0** (April 2025) made it the default. It is specified in [RFC 10042](https://www.rfc-editor.org/info/rfc10042/) (formerly draft-ietf-sshm-mlkem-hybrid-kex).

Which one you get depends on the OpenSSH versions on _both_ ends: client and server pick the first algorithm they both support. Either way, this protects the _session encryption_ against the so-called "harvest now, decrypt later" attack: an adversary recording your encrypted traffic today cannot decrypt it retroactively once a quantum computer becomes available.

You can verify which KEX your server negotiates:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
ssh -v deploy@your-server-ip exit 2>&1 | grep "kex: algorithm"
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
ssh -v deploy@your-server-ip exit 2>&1 | Select-String "kex: algorithm"
```

{{< /os-tab >}}
{{< /os-tabs >}}

**What is still in progress.** The hybrid KEX protects session confidentiality, but _authentication keys_ (your `id_ed25519`) are not post-quantum in OpenSSH yet, and there is no standardized ML-DSA or SLH-DSA key type for SSH. Work on SSH protocol extensions happens in the IETF [SSHM working group](https://datatracker.ietf.org/wg/sshm/about/). This is less urgent than the KEX: a recorded login cannot be forged after the fact, so authentication is only at risk once a quantum computer actually exists. Until post-quantum key types land in a stable OpenSSH release and distribution packages, Ed25519 remains the correct choice.

---

### Using ssh-agent to avoid re-typing the passphrase

`ssh-agent` holds your decrypted key in memory for the duration of your session.

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

Run once to enable the service:

> **Administrator rights required.** The first two commands modify a Windows service and must run in an **elevated PowerShell session**. Right-click the Start menu → **Terminal (Admin)** or **Windows PowerShell (Admin)**, or search for "PowerShell", right-click the result, and select _Run as administrator_. The third command (`ssh-add`) can then be run in any regular terminal.

```powershell
Set-Service -Name ssh-agent -StartupType Automatic
Start-Service ssh-agent
ssh-add "$env:USERPROFILE\.ssh\id_ed25519"
```

{{< /os-tab >}}
{{< /os-tabs >}}

---

## Step 2 — Create a Dedicated Sudo User on the Server

Never work as `root` day-to-day. Create a regular user and grant it `sudo` access. This limits blast radius: a compromised session still needs the user's password (or a privilege escalation exploit) to become root.

Connect to your server as root (your last root login for a while):

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
ssh root@your-server-ip
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
ssh root@your-server-ip
```

{{< /os-tab >}}
{{< /os-tabs >}}

### Create the user

Replace `deploy` with whatever username you prefer.

```bash
adduser deploy
```

`adduser` is Ubuntu's interactive frontend to `useradd`. It will prompt for a password and some optional profile fields. Choose a strong password — you will need it when running `sudo` commands.

### Grant sudo privileges

```bash
usermod -aG sudo deploy
```

This adds `deploy` to the `sudo` group. Ubuntu's default `/etc/sudoers` contains the rule `%sudo ALL=(ALL:ALL) ALL`, which grants all members of that group the ability to run any command as root by prefixing it with `sudo`.

### Verify

```bash
su - deploy
sudo whoami
```

`sudo whoami` should print `root`. If it does, the user is correctly configured.

---

## Step 3 — Deploy Your Public Key to the Server

The server authenticates you by checking whether the public key stored in `~/.ssh/authorized_keys` matches the private key you present during login. This mechanism is defined in [RFC 4252 §7](https://datatracker.ietf.org/doc/html/rfc4252#section-7).

### Option A — ssh-copy-id (recommended on Linux / macOS)

`ssh-copy-id` automates the process: it appends your public key to the remote `authorized_keys` file and sets the correct permissions.

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub deploy@your-server-ip
```

### Option B — Manual copy (works everywhere, including Windows)

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
cat ~/.ssh/id_ed25519.pub | ssh deploy@your-server-ip \
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
$pubKey = Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"
ssh deploy@your-server-ip "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pubKey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

{{< /os-tab >}}
{{< /os-tabs >}}

### Verify key-based login before proceeding

Open a **new terminal** (keep the old session open) and test:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
ssh -i ~/.ssh/id_ed25519 deploy@your-server-ip
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
ssh -i "$env:USERPROFILE\.ssh\id_ed25519" deploy@your-server-ip
```

{{< /os-tab >}}
{{< /os-tabs >}}

You should be logged in. If you set a passphrase, you will be prompted for it. If the login fails, **do not proceed to Step 4** — troubleshoot first (check file permissions, key placement, and `~/.ssh/authorized_keys` content on the server).

---

## Step 4 — Harden sshd Configuration

The main SSH daemon config is `/etc/ssh/sshd_config`, but on current Ubuntu releases you should **not** put your changes there. Two rules from the [sshd_config man page](https://man.openbsd.org/sshd_config) explain why:

1. The very first line of Ubuntu's `sshd_config` is `Include /etc/ssh/sshd_config.d/*.conf`, so every drop-in file in that directory is read _before_ the rest of the main file — in lexical order of the file names.
2. For most keywords, "the first obtained value will be used". Later lines for the same keyword are silently ignored.

On many cloud images (AWS, Azure, Hetzner, DigitalOcean …), cloud-init writes `/etc/ssh/sshd_config.d/50-cloud-init.conf` containing `PasswordAuthentication yes`. If you only edit `PasswordAuthentication no` into the main file, that drop-in wins and password login stays **on** — while the config file looks correct. Check whether your server has such a file:

```bash
sudo grep -ri passwordauthentication /etc/ssh/sshd_config.d/
```

The robust fix is a drop-in of your own whose name sorts first, so its values are read before everything else. Connect to the server as `deploy` and create it:

```bash
sudo nano /etc/ssh/sshd_config.d/00-hardening.conf
```

We will put three directives into this file.

### 4.1 — Disable password authentication

```text
PasswordAuthentication no
```

This forces every client to authenticate with a key. Brute-force attacks against passwords become impossible because the server will not accept them at all.

### 4.2 — Disable root login

```text
PermitRootLogin no
```

Even if an attacker obtains valid credentials, they cannot log in as `root` directly. All privileged operations must go through `sudo` from a named account, which creates an audit trail.

### 4.3 — (Optional but recommended) Restrict which users may log in

Add a line that whitelists only your new user:

```text
AllowUsers deploy
```

Any other account — including any that an attacker might create — is denied SSH access regardless of whether it has a valid key.

The complete `00-hardening.conf` now reads:

```text
PasswordAuthentication no
PermitRootLogin no
AllowUsers deploy
```

### Apply the changes

Save the file and let `sshd` check the whole configuration for syntax errors **before** you reload — a broken config is the classic way to lock yourself out:

```bash
sudo sshd -t
```

No output means the configuration is valid. Then reload `ssh` without dropping existing connections:

```bash
sudo systemctl reload ssh
```

> `reload` sends `SIGHUP` to the running daemon, which re-reads the config file without terminating active sessions. Use `sudo systemctl restart ssh` only if `reload` does not work. On Ubuntu the unit is called `ssh`, not `sshd`.
>
> **Ubuntu 24.04 and later:** SSH is socket-activated — `ssh.socket` listens on port 22 and starts `ssh.service` on demand. For the directives in this post, `reload ssh` is all you need. Only if you change `Port` or `ListenAddress` do you also have to run `sudo systemctl daemon-reload && sudo systemctl restart ssh.socket`, because the socket unit is generated from those values. See Ubuntu's [announcement of socket-based activation](https://discourse.ubuntu.com/t/sshd-now-uses-socket-based-activation-ubuntu-22-10-and-later/30189).

Now ask `sshd` which values it _actually_ uses. `sshd -T` prints the effective configuration after all `Include` files have been merged — the only reliable way to rule out an overriding drop-in:

```bash
sudo sshd -T | grep -Ei 'passwordauthentication|permitrootlogin|allowusers'
```

Expected output:

```text
permitrootlogin no
passwordauthentication no
allowusers deploy
```

### Verify

From a **new terminal** on your local machine, confirm that key-based login still works:

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

Then confirm that password authentication is rejected:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
ssh -o PasswordAuthentication=yes -o PubkeyAuthentication=no deploy@your-server-ip
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
ssh -o PasswordAuthentication=yes -o PubkeyAuthentication=no deploy@your-server-ip
```

{{< /os-tab >}}
{{< /os-tabs >}}

You should see `Permission denied (publickey)` — that is the correct response.

Also confirm that root login is blocked:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
ssh root@your-server-ip
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
ssh root@your-server-ip
```

{{< /os-tab >}}
{{< /os-tabs >}}

Expected result: `Permission denied (publickey)` — root login is gone.

---

## Summary of Changes

| What                  | Before              | After                   |
| --------------------- | ------------------- | ----------------------- |
| Authentication method | Password or key     | Key only                |
| Root login            | Allowed             | Blocked                 |
| Default working user  | `root`              | `deploy` (sudo-enabled) |
| Privilege escalation  | Direct root session | `sudo` with audit trail |

---

## Troubleshooting

### "Permission denied (publickey)" when I expect to be let in

1. Check that the public key in `~/.ssh/authorized_keys` on the server matches `~/.ssh/id_ed25519.pub` on your machine exactly (one line, no line breaks).
2. Check permissions:

   ```bash
   chmod 700 ~/.ssh
   chmod 600 ~/.ssh/authorized_keys
   ```

3. Run `ssh` with verbose output to see exactly where authentication fails:

   ```bash
   ssh -vvv deploy@your-server-ip
   ```

### "Could not load host key" in sshd logs

Run `sudo ssh-keygen -A` on the server to regenerate missing host keys, then `sudo systemctl restart ssh`.

### I locked myself out

If you are on a cloud provider (AWS, Hetzner, DigitalOcean, etc.), use the provider's web console or recovery/rescue mode to mount the server's disk and fix or remove `/etc/ssh/sshd_config.d/00-hardening.conf` directly. This is why you must verify key-based login before disabling password auth.

---

## What's Next?

With SSH hardened, consider these complementary measures:

- **[Fail2ban](https://github.com/fail2ban/fail2ban)** — bans IPs that produce too many failed login attempts, reducing log noise even after password auth is off
- **UFW (Uncomplicated Firewall)** — restrict incoming traffic to only the ports you actually need (`sudo ufw allow OpenSSH && sudo ufw enable`)
- **Two-factor authentication for sudo** — pair `sudo` with a TOTP token via `libpam-google-authenticator` for an additional layer of protection
- **Regular unattended upgrades** — `sudo apt install unattended-upgrades` keeps security patches applied automatically
- **Post-quantum authentication keys** — once a post-quantum SSH key type is standardized (watch the IETF [SSHM working group](https://datatracker.ietf.org/wg/sshm/about/)) and OpenSSH ships stable support, generate a second key pair using an ML-DSA or SLH-DSA algorithm ([FIPS 204](https://doi.org/10.6028/NIST.FIPS.204) / [FIPS 205](https://doi.org/10.6028/NIST.FIPS.205)) and add it alongside your Ed25519 key to `authorized_keys` for a hybrid authentication posture

UFW, Fail2ban, and unattended upgrades are covered step by step in [Ubuntu Server Hardening — Part 1: The Essentials](/blog/ubuntu-server-hardening-1-essentials/). Each of these topics deserves its own post — stay tuned.
