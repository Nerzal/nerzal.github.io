---
draft: false
title: "Ubuntu Server Hardening — Teil 1: Die Grundlagen"
seo_title: "Ubuntu Hardening Teil 1: Die Grundlagen"
date: 2026-05-11T00:00:00+00:00
tags:
  ["tutorial", "linux", "ubuntu", "security", "hardening", "devops", "server"]
description: "Drei Maßnahmen, die jeder öffentliche Ubuntu-Server sofort braucht: UFW-Firewall, Fail2ban-Schutz und automatische Sicherheitsupdates."
images: ["img/ubuntu-server-hardening.png"]
featured_image: "img/ubuntu-server-hardening.png"
toc: true
---

Dies ist der erste Teil einer dreiteiligen Serie zur Absicherung eines öffentlichen Ubuntu-Servers.

Im [vorherigen Beitrag](/de/blog/secure-ssh-server/) haben wir SSH abgesichert: Passwort-Login durch schlüsselbasierte Authentifizierung ersetzt, Root deaktiviert und eingeschränkt, welche Benutzer sich verbinden dürfen. Das allein stoppt den Großteil der Angriffe auf Server, die aus dem Internet erreichbar sind.

SSH ist aber nur eine Schicht. Jeder Teil dieser Serie fügt drei weitere hinzu, geordnet danach, wie schnell man sie umsetzt und wie viel sie bringen. Den Anfang machen diese drei: Sie kosten zusammen weniger als fünfzehn Minuten und schützen vor den häufigsten aktiven Bedrohungen.

> **Voraussetzungen:** Ubuntu 22.04 / 24.04 / 26.04, SSH bereits abgesichert, Nicht-Root-Benutzer mit `sudo`-Zugang.

---

## 1. UFW: Default-Deny-Firewall

Auf einem frisch bereitgestellten Server ist oft jeder Port erreichbar, auf dem ein Dienst lauscht. Die Firewall ändert das: **alles standardmäßig blockieren, nur explizit Erlaubtes durchlassen.**

Ubuntu liefert [UFW](https://help.ubuntu.com/community/UFW) (Uncomplicated Firewall) vorinstalliert mit. Es ist ein handliches Frontend für `iptables`/`nftables`, mit dem die Regeln lesbar bleiben.

### Mit bereits geöffnetem SSH aktivieren

Der häufigste Weg, sich auszusperren: die Firewall aktivieren, bevor SSH erlaubt wurde. Deshalb immer zuerst:

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

Die Ausgabe sollte `Status: active` zeigen und exakt die freigegebenen Ports auflisten. Jeder Port, der nicht in dieser Liste steht, ist jetzt geschlossen, egal was darauf lauscht.

**Nicht-Standard-SSH-Port:** Falls der SSH-Port von 22 auf einen anderen geändert wurde, stattdessen diesen Port freigeben:

```bash
sudo ufw allow 2222/tcp comment "SSH"
```

### Verbindungsrate begrenzen

UFW kann eingehende Verbindungen zu einem Port drosseln. Das ist eine nützliche, leichtgewichtige Schicht, solange Fail2ban noch nicht konfiguriert ist:

```bash
# Verbindungen einer IP ablehnen, die 6 oder mehr in den letzten 30 Sekunden geöffnet hat
sudo ufw limit OpenSSH
```

Das ist eine Drosselung mit gleitendem Zeitfenster, keine Sperre: Laut [ufw-Manpage](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html) lehnt UFW neue Verbindungen einer IP ab, sobald sie innerhalb von 30 Sekunden 6 oder mehr versucht hat. Wird die IP langsamer, kommt sie wieder durch. Echte Sperren mit einstellbarer Dauer liefert erst Fail2ban im nächsten Abschnitt.

### Docker umgeht UFW

Wer Docker auf dem Server betreibt, sollte das wissen, bevor er der Firewall vertraut: Ports, die mit `docker run -p` oder `ports:` in Compose veröffentlicht werden, filtert UFW **nicht**. Docker legt eigene `iptables`-Regeln an, und der Traffic wird zum Container geroutet, bevor die UFW-Regeln greifen. Deshalb zeigt `ufw status` diese Ports nicht einmal an. Siehe Dockers Dokumentation zu [Packet Filtering und Firewalls](https://docs.docker.com/engine/network/packet-filtering-firewalls/). Soll ein Container-Port privat bleiben, ihn an localhost binden (`-p 127.0.0.1:8080:80`) und einen Reverse Proxy davorsetzen.

### Von der lokalen Maschine prüfen

Vor dem Schließen der Session ein zweites Terminal öffnen und bestätigen, dass SSH noch funktioniert:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
ssh deploy@deine-server-ip
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
ssh deploy@deine-server-ip
```

{{< /os-tab >}}
{{< /os-tabs >}}

---

## 2. Fail2ban: Brute-Force-Schutz

Auch mit schlüsselbasiertem SSH können andere Dienste (Webserver, Mailserver, eigene APIs) mit Brute-Force angegriffen werden. [Fail2ban](https://github.com/fail2ban/fail2ban) überwacht Log-Dateien und fügt temporäre Firewall-Sperren für IPs hinzu, die zu viele Fehler produzieren.

```bash
sudo apt install fail2ban -y
```

`/etc/fail2ban/jail.conf` nicht direkt bearbeiten, denn sie wird bei Updates überschrieben. Fail2ban liest `jail.local` zusätzlich darüber, also diese Datei **nur mit den Einstellungen anlegen, die man ändern will**. Nicht die ganze `jail.conf` kopieren: Eine vollständige Kopie friert alle Standardwerte auf dem heutigen Stand ein, und Verbesserungen, die künftige Paket-Updates in `jail.conf` mitbringen, kämen nie an.

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

Die `[DEFAULT]`-Werte sperren jede IP für eine Stunde, wenn sie innerhalb von zehn Minuten fünfmal bei der Authentifizierung scheitert. Zeigen die Logs hartnäckige Scanner, `bantime` auf einen längeren Wert erhöhen (z. B. `24h` oder `1w`). Ubuntus Paket aktiviert den `[sshd]`-Jail bereits in `/etc/fail2ban/jail.d/defaults-debian.conf`. Wer ihn hier trotzdem setzt, macht die Absicht explizit und ist nicht von dieser Datei abhängig.

Fail2ban starten und aktivieren:

```bash
sudo systemctl enable --now fail2ban
```

Danach prüfen, ob der `sshd`-Jail aktiv ist:

```bash
sudo fail2ban-client status sshd
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

## 3. Unattended Upgrades: Automatische Sicherheits-Patches

Ungepatchte Pakete sind eine der häufigsten Ursachen für Server-Kompromittierungen. Mit automatischen Sicherheitsupdates ist man nicht mehr darauf angewiesen, `apt upgrade` von Hand auszuführen, bevor eine CVE ausgenutzt wird.

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

Das beschränkt die automatische Installation auf Sicherheitsupdates. Feature-Updates, die etwas kaputt machen könnten, bleiben außen vor.

Zwei weitere Einstellungen, die einen Blick wert sind:

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
| UFW Default-Deny    | Dienste, die versehentlich auf unerwarteten Ports exponiert sind |
| Fail2ban            | Automatisiertes Credential-Brute-Forcing                        |
| Unattended Upgrades | Ausnutzung bekannter, gepatchter CVEs                           |

Keine davon ist schwer einzurichten. Sie decken die drei häufigsten Angriffsmuster gegen öffentliche Server ab und dauern zusammen weniger als fünfzehn Minuten.

**Teil 2** behandelt die nächste Schicht: Kernel-Parameter-Hardening, das Deaktivieren unnötiger Dienste und das Verschärfen von sudo- und Login-Richtlinien.
