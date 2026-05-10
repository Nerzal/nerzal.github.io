---
draft: false
title: "Ubuntu Server Hardening — Teil 1: Die Grundlagen"
date: 2026-05-11T08:00:00+00:00
tags:
  ["tutorial", "linux", "ubuntu", "security", "hardening", "devops", "server"]
description: "Die drei Maßnahmen, die jeder öffentliche Ubuntu-Server innerhalb der ersten Stunde braucht: eine Default-Deny-Firewall mit UFW, Brute-Force-Schutz mit Fail2ban und automatische Sicherheitsupdates."
images: ["img/ubuntu-server-hardening.png"]
featured_image: "img/ubuntu-server-hardening.png"
toc: true
---

Dies ist der erste Teil einer dreiteiligen Serie zur Absicherung eines öffentlichen Ubuntu-Servers.

Im [vorherigen Beitrag](/de/blog/secure-ssh-server/) haben wir SSH abgesichert: Passwort-Login durch schlüsselbasierte Authentifizierung ersetzt, Root deaktiviert und eingeschränkt, welche Benutzer sich verbinden dürfen. Das allein eliminiert den Großteil der Angriffe auf internet-exponierte Server.

Aber SSH ist nur eine Schicht. Diese Serie fügt drei weitere Schichten pro Teil hinzu, geordnet nach Umsetzungsgeschwindigkeit und Impact. Hier anfangen — diese drei kosten zusammen weniger als fünfzehn Minuten und schützen vor den häufigsten aktiven Bedrohungen.

> **Voraussetzungen:** Ubuntu 20.04 / 22.04 / 24.04, SSH bereits abgesichert, Nicht-Root-Benutzer mit `sudo`-Zugang.

---

## 1 — UFW: Default-Deny-Firewall

Ein frisch bereitgestellter Server exponiert oft jeden Port, auf dem ein Dienst lauscht. Die Firewall ändert das: **alles standardmäßig blockieren, nur explizit Erlaubtes durchlassen.**

Ubuntu liefert [UFW](https://help.ubuntu.com/community/UFW) (Uncomplicated Firewall) vorinstalliert mit — ein nutzbares Frontend für `iptables`/`nftables`, das Regeln lesbar hält.

### Mit bereits geöffnetem SSH aktivieren

Der häufigste Weg sich auszusperren: Firewall aktivieren bevor SSH erlaubt wurde. Deshalb immer zuerst:

```bash
# SSH durch die Firewall erlauben, bevor sie aktiviert wird
sudo ufw allow OpenSSH

# Falls ein Webserver läuft: HTTP und HTTPS freigeben
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Jetzt aktivieren
sudo ufw enable

# Prüfen
sudo ufw status verbose
```

Die Ausgabe sollte `Status: active` zeigen und exakt die freigegebenen Ports auflisten. Jeder Port der nicht in dieser Liste steht ist jetzt geschlossen, egal was darauf lauscht.

**Nicht-Standard-SSH-Port:** Falls der SSH-Port geändert wurde, stattdessen diesen Port freigeben:

```bash
sudo ufw allow 2222/tcp comment "SSH"
```

### Verbindungsrate begrenzen

UFW kann eingehende Verbindungen zu einem Port drosseln — nützlich als leichtgewichtige Schicht bevor Fail2ban konfiguriert ist:

```bash
# IPs sperren, die mehr als 6 Verbindungen in 30 Sekunden versuchen
sudo ufw limit OpenSSH
```

### Von der lokalen Maschine prüfen

Vor dem Schließen der Session in einem zweiten Terminal bestätigen, dass SSH noch funktioniert:

```bash
ssh deploy@deine-server-ip
```

```powershell
ssh deploy@deine-server-ip
```

---

## 2 — Fail2ban: Brute-Force-Schutz

Auch mit schlüsselbasiertem SSH können andere Dienste (Webserver, Mailserver, eigene APIs) mit Brute-Force angegriffen werden. [Fail2ban](https://github.com/fail2ban/fail2ban) überwacht Log-Dateien und fügt temporäre Firewall-Sperren für IPs hinzu, die zu viele Fehler produzieren.

```bash
sudo apt install fail2ban -y
```

`/etc/fail2ban/jail.conf` nicht direkt bearbeiten — sie wird bei Updates überschrieben. Stattdessen eine lokale Überschreibung erstellen:

```bash
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo nano /etc/fail2ban/jail.local
```

Im `[DEFAULT]`-Abschnitt am Anfang setzen:

```text
bantime  = 1h
findtime = 10m
maxretry = 5
```

Das sperrt jede IP für eine Stunde, wenn sie innerhalb von zehn Minuten mehr als fünfmal fehlschlägt. `bantime` bei anhaltenden Scannern auf `24h` oder `1w` erhöhen.

Der `[sshd]`-Jail ist standardmäßig aktiv. Prüfen:

```bash
sudo fail2ban-client status sshd
```

Fail2ban starten und aktivieren:

```bash
sudo systemctl enable --now fail2ban
```

### Nützliche Befehle

```bash
# Alle aktiven Jails auflisten
sudo fail2ban-client status

# Gesperrte IPs für einen bestimmten Jail anzeigen
sudo fail2ban-client status sshd

# Eine IP entsperren (falls man sich beim Testen selbst sperrt)
sudo fail2ban-client set sshd unbanip 1.2.3.4

# Fail2ban-Log live beobachten
sudo tail -f /var/log/fail2ban.log
```

---

## 3 — Unattended Upgrades: Automatische Sicherheits-Patches

Ungepatchte Pakete sind eine der häufigsten Ursachen für Server-Kompromittierungen. Automatische Sicherheitsupdates bedeuten, dass man nicht mehr darauf angewiesen ist, manuell `apt upgrade` auszuführen, bevor eine CVE ausgenutzt wird.

```bash
sudo apt install unattended-upgrades apt-listchanges -y
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

Die einzige Frage im Dialog mit **Ja** bestätigen.

Die Konfigurationsdatei prüfen:

```bash
sudo nano /etc/apt/apt.conf.d/50unattended-upgrades
```

Der wichtigste Abschnitt:

```text
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
```

Das beschränkt die automatische Installation auf Sicherheitsupdates — keine Feature-Updates, die etwas kaputt machen könnten.

Zwei weitere Einstellungen die es wert sind zu prüfen:

```text
// Alte Kernel-Pakete entfernen die nicht mehr benötigt werden
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";

// Neu starten falls erforderlich (z.B. nach einem Kernel-Update)
// Nur auf "true" setzen wenn ein Wartungsfenster definiert ist
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
```

Timer-Status prüfen:

```bash
sudo systemctl status apt-daily-upgrade.timer
```

Konfiguration ohne tatsächliche Installation testen:

```bash
sudo unattended-upgrade --dry-run --debug
```

---

## Was diese drei Maßnahmen gemeinsam bewirken

| Maßnahme            | Was sie stoppt                                                  |
| ------------------- | --------------------------------------------------------------- |
| UFW Default-Deny    | Dienste die versehentlich auf unerwarteten Ports exponiert sind |
| Fail2ban            | Automatisiertes Credential-Brute-Forcing                        |
| Unattended Upgrades | Ausnutzung bekannter, gepatchter CVEs                           |

Keine davon ist schwer einzurichten. Sie decken die drei häufigsten Angriffsmuster gegen öffentliche Server ab und dauern zusammen weniger als fünfzehn Minuten.

**Teil 2** behandelt die nächste Schicht: Kernel-Parameter-Hardening, das Deaktivieren unnötiger Dienste und das Verschärfen von sudo- und Login-Richtlinien.
