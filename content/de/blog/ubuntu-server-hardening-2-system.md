---
draft: true
title: "Ubuntu Server Hardening — Teil 2: Das System verschärfen"
date: 2026-05-17T00:00:00+00:00
tags: ["tutorial", "linux", "ubuntu", "security", "hardening", "devops", "server"]
description: "Der zweite Hardening-Durchgang: Kernel-Parameter mit sysctl anpassen, Angriffsfläche durch Deaktivierung unnötiger Dienste reduzieren und sudo sowie Login-Richtlinien einschränken."
images: ["img/ubuntu-server-hardening.png"]
featured_image: "img/ubuntu-server-hardening.png"
toc: true
---

[Teil 1](/de/blog/ubuntu-server-hardening-1-essentials/) behandelte die drei Grundlagen, die jeder öffentliche Server benötigt: UFW, Fail2ban und automatische Sicherheitsupdates. Damit sind die häufigsten automatisierten Angriffe bereits abgewehrt.

Dieser Teil konzentriert sich auf die Reduzierung der Angriffsfläche — sowohl auf Kernel-Ebene als auch im Privilege-Modell. Die Maßnahmen hier erfordern etwas mehr Überlegung als Teil 1, aber keine davon setzt zusätzliche Software voraus.

> **Voraussetzungen:** Teil 1 abgeschlossen, SSH abgesichert, Nicht-Root-Sudo-Benutzer.

---

## 1 — Kernel-Hardening mit sysctl

Der Linux-Kernel stellt Laufzeitparameter über `/proc/sys/` bereit. Viele Standardwerte priorisieren Kompatibilität vor Sicherheit. Der Befehl `sysctl` schreibt diese Parameter; eine Konfiguration in `/etc/sysctl.d/` macht sie über Neustarts hinaus persistent.

```bash
sudo nano /etc/sysctl.d/99-hardening.conf
```

```text
# ── Netzwerk ──────────────────────────────────────────────────────────────

# ICMP-Weiterleitungen ablehnen — verhindert Routing-Manipulation/MITM
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Keine ICMP-Weiterleitungen senden — dieser Server ist kein Router
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Source-routed Pakete ablehnen
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Reverse-Path-Filterung — Pakete mit unmöglichen Quelladressen verwerfen
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# SYN-Cookie-Schutz gegen SYN-Flood-Angriffe
net.ipv4.tcp_syncookies = 1

# ICMP-Broadcasts ignorieren (verhindert Smurf-Amplification)
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Pakete mit unmöglichen Adressen protokollieren
net.ipv4.conf.all.log_martians = 1

# ── Kernel ────────────────────────────────────────────────────────────────

# Sichtbarkeit von /proc/[pid] auf den besitzenden Benutzer beschränken
kernel.hidepid = 2

# Kernel-Pointer-Exposition in /proc einschränken (reduziert Informationslecks)
kernel.kptr_restrict = 2

# dmesg nur für Root lesbar
kernel.dmesg_restrict = 1

# Magic SysRq-Taste deaktivieren
kernel.sysrq = 0

# ptrace auf übergeordnete Prozesse beschränken (begrenzt Debugger-Angriffe)
kernel.yama.ptrace_scope = 1

# Core-Dumps für setuid-Programme deaktivieren
fs.suid_dumpable = 0
```

Sofort anwenden:

```bash
sudo sysctl --system
```

Einen bestimmten Wert prüfen:

```bash
sysctl net.ipv4.tcp_syncookies
# net.ipv4.tcp_syncookies = 1
```

> **Hinweis zu `kernel.hidepid = 2`:** Nicht-Root-Benutzer können die Prozesse anderer Benutzer in `/proc` nicht mehr sehen. Falls ein Monitoring-Tool wie `htop` alle Prozesse sehen muss, den entsprechenden Benutzer zur `proc`-Gruppe hinzufügen und `hidepid=2,gid=proc` verwenden.

---

## 2 — Unnötige Dienste deaktivieren

Jeder laufende Dienst ist eine potenzielle Angriffsfläche. Auf einem minimalen VPS laufen standardmäßig mehrere Dienste, die auf einem Desktop sinnvoll sind, auf einem Server aber keinen Zweck erfüllen.

Was aktiv ist auflisten:

```bash
sudo systemctl list-units --type=service --state=running
```

Häufige Kandidaten zum Deaktivieren auf einem headless Server:

```bash
# mDNS — Geräteerkennung, auf einem Server nicht relevant
sudo systemctl disable --now avahi-daemon

# Druckspooler — keine Drucker auf einem Server
sudo systemctl disable --now cups

# Bluetooth — keine Hardware, kein Zweck
sudo systemctl disable --now bluetooth
```

Danach prüfen, welche Ports noch offen sind und sie den Prozessen zuordnen:

```bash
sudo ss -tlnp
```

Jede Zeile in der Ausgabe sollte einem Dienst entsprechen, den man bewusst exponiert hat. Falls ein unbekannter Port erscheint: erst nachforschen, dann schließen — `systemd-resolved` auf `127.0.0.53:53` ist beispielsweise erwartet.

---

## 3 — Sudo-Hardening

Die Standard-`sudo`-Gruppe gewährt uneingeschränkten Root-Zugriff. Für die meisten Aufgaben ist das weiter als nötig.

sudoers ausschließlich über `visudo` bearbeiten — es prüft die Syntax vor dem Speichern und verhindert, dass man sich aus sudo aussperrt:

```bash
sudo visudo
```

Sinnvolle Ergänzungen im `Defaults`-Abschnitt:

```text
# Passwort nach 5 Minuten Inaktivität erneut abfragen (Standard: 15)
Defaults timestamp_timeout=5

# Jeden sudo-Befehl mit Zeitstempel protokollieren
Defaults logfile=/var/log/sudo.log
Defaults log_input, log_output
```

Falls ein Benutzer nur einen bestimmten Dienst verwalten muss, ihn auf genau das beschränken:

```text
# 'deploy' darf nur nginx neu starten und neu laden — nichts sonst
deploy ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart nginx
deploy ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload nginx
```

Auf bestehende zu weitreichende Wildcard-Berechtigungen in `/etc/sudoers.d/` prüfen:

```bash
sudo ls -la /etc/sudoers.d/
sudo cat /etc/sudoers.d/*
```

---

## 4 — Login- und Passwort-Richtlinien

Auch mit schlüsselbasiertem SSH können lokale Konten über die physische Konsole oder Out-of-Band-Management-Schnittstellen authentifiziert werden. Eine Passwort-Richtlinie begrenzt die Auswirkungen schwacher lokaler Anmeldedaten.

`/etc/login.defs` bearbeiten:

```bash
sudo nano /etc/login.defs
```

```text
PASS_MAX_DAYS   90      # Rotation alle 90 Tage erzwingen
PASS_MIN_DAYS   1       # Sofortiges Wiederverwenden nach Änderung verhindern
PASS_WARN_AGE   7       # 7 Tage vor Ablauf warnen
```

Für Passwortkomplexität `libpam-pwquality` installieren:

```bash
sudo apt install libpam-pwquality -y
sudo nano /etc/security/pwquality.conf
```

```text
minlen   = 14     # Mindestlänge
dcredit  = -1     # Mindestens 1 Ziffer erforderlich
ucredit  = -1     # Mindestens 1 Großbuchstabe erforderlich
ocredit  = -1     # Mindestens 1 Sonderzeichen erforderlich
difok    = 8      # Muss sich von vorigem Passwort in mindestens 8 Zeichen unterscheiden
usercheck = 1     # Passwörter die den Benutzernamen enthalten ablehnen
```

---

## Was dieser Durchgang abdeckt

| Maßnahme | Wirkung |
|----------|---------|
| sysctl-Hardening | Schließt Netzwerk-Angriffsvektoren auf Kernel-Ebene |
| Deaktivierte Dienste | Reduziert die Anzahl der Eintrittspunkte |
| Sudo-Einschränkungen | Begrenzt den Schaden bei einem kompromittierten Konto |
| Passwort-Richtlinie | Erhöht den Aufwand für Brute-Force lokaler Anmeldedaten |

Diese vier Maßnahmen erfordern keine externen Tools und erzeugen keinen Netzwerkverkehr — es sind reine Konfigurationsänderungen am bereits Vorhandenen.

**Teil 3** behandelt die tiefere Schicht: Mandatory Access Control mit AppArmor, Kernel-Level-Audit-Logging mit `auditd` und Datei-Integritätsüberwachung mit AIDE.
