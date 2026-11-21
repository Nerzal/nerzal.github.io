---
draft: false
title: "Ubuntu Server Hardening — Teil 2: Das System verbessern"
seo_title: "Ubuntu Hardening Teil 2: System härten"
date: 2026-05-12T00:00:00+00:00
lastmod: 2026-11-13T21:21:38+01:00
tags:
  ["tutorial", "linux", "ubuntu", "security", "hardening", "devops", "server"]
description: "Der zweite Hardening-Durchgang: Kernel-Parameter mit sysctl anpassen, unnötige Dienste deaktivieren und sudo sowie Login-Richtlinien einschränken."
images: ["img/ubuntu-server-hardening.png"]
featured_image: "img/ubuntu-server-hardening.png"
toc: true
---

{{< tldr >}}
- Teil 2 der Ubuntu-Hardening-Serie verbessert das System mit vier Maßnahmen ohne zusätzliche Software: sysctl-Kernel-Parameter, deaktivierte Dienste, sudo-Einschränkungen und eine Passwort-Richtlinie.
- Die Kernel-Einstellungen landen in `/etc/sysctl.d/99-hardening.conf` und greifen mit `sudo sysctl --system`, darunter ICMP-Weiterleitungen, SYN-Cookies, `kptr_restrict` und `ptrace_scope`.
- `hidepid` ist eine Mount-Option des `proc`-Dateisystems in `/etc/fstab` und kein sysctl, und auf manchen Systemen bricht es polkit oder Benutzersitzungen.
- Eine sudoers-Regel, die `deploy` auf nginx-Neustarts beschränkt, wirkt nur, wenn `deploy` nicht mehr in der `sudo`-Gruppe ist, weil `%sudo ALL=(ALL:ALL) ALL` sonst vollen Root-Zugriff gewährt.
- Nach NIST SP 800-63B Rev. 4 verlangt die pwquality-Konfiguration mit `minlen = 15` mindestens 15 Zeichen, ohne Zusammensetzungsregeln und ohne erzwungene Passwort-Rotation.
{{< /tldr >}}

[Teil 1](/de/blog/ubuntu-server-hardening-1-essentials/) behandelte die drei Grundlagen, die jeder öffentliche Server benötigt: UFW, Fail2ban und automatische Sicherheitsupdates. Damit sind die häufigsten automatisierten Angriffe bereits abgewehrt.

Dieser Teil verkleinert die Angriffsfläche, sowohl auf Kernel-Ebene als auch im Privilege-Modell. Die Maßnahmen brauchen etwas mehr Überlegung als Teil 1, keine davon setzt aber zusätzliche Software voraus.

> **Voraussetzungen:** Teil 1 abgeschlossen, SSH abgesichert, Nicht-Root-Sudo-Benutzer.

---

## 1. Kernel-Hardening mit sysctl

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

### Prozesse anderer Benutzer verbergen

In vielen Hardening-Anleitungen taucht `kernel.hidepid` auf. **Das ist kein sysctl**, und `sysctl --system` würde den Schlüssel als unbekannt melden. `hidepid` ist eine Mount-Option des `proc`-Dateisystems ([proc(5)](https://man7.org/linux/man-pages/man5/proc.5.html)). Mit `hidepid=invisible` (ältere numerische Schreibweise: `hidepid=2`) können Nicht-Root-Benutzer die `/proc/[pid]`-Verzeichnisse anderer Benutzer weder lesen noch auflisten. `ps` und `htop` zeigen dann nur noch die eigenen Prozesse.

Diese Zeile in `/etc/fstab` eintragen:

```text
proc  /proc  proc  defaults,hidepid=invisible  0  0
```

Ohne Neustart anwenden:

```bash
sudo mount -o remount,hidepid=invisible /proc
```

Muss ein Monitoring-Agent alle Prozesse sehen, eine eigene Gruppe anlegen (Ubuntu hat standardmäßig keine `proc`-Gruppe), den Benutzer des Agents hinzufügen und die Gruppe per `gid=` ausnehmen:

```bash
sudo groupadd --system procview
sudo usermod -aG procview monitoring
# Die fstab-Optionen lauten dann: defaults,hidepid=invisible,gid=procview
```

> **Vorsicht:** systemd-Komponenten wie `systemd-logind` und polkit inspizieren andere Prozesse über `/proc`. Auf manchen Systemen bricht `hidepid` die polkit-Autorisierung oder Benutzersitzungen. Zuerst auf einer Staging-Maschine testen und beim Anwenden eine Konsolensitzung offen halten. Für einen einzelnen Dienst bietet systemds [`ProtectProc=invisible`](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#ProtectProc=) dieselbe Isolation, ohne den globalen Mount anzufassen.

---

## 2. Unnötige Dienste deaktivieren

Jeder laufende Dienst vergrößert die Angriffsfläche. Auf einem minimalen VPS laufen standardmäßig mehrere Dienste, die auf einem Desktop sinnvoll sind, auf einem Server aber keinen Zweck erfüllen.

Auflisten, was aktiv ist:

```bash
sudo systemctl list-units --type=service --state=running
```

Das sind häufige Kandidaten zum Deaktivieren auf einem headless Server, sofern vorhanden. Eine minimale Ubuntu-Server-Installation bringt Avahi, CUPS und BlueZ gar nicht erst mit; sie tauchen meist auf, wenn ein Desktop-Image verwendet wurde oder ein Paket sie nachgezogen hat. `Unit … not found` heißt schlicht: nichts zu tun.

```bash
# mDNS — Geräteerkennung, auf einem Server nicht relevant
sudo systemctl disable --now avahi-daemon

# Druckspooler — keine Drucker auf einem Server
sudo systemctl disable --now cups

# Bluetooth — keine Hardware, kein Zweck
sudo systemctl disable --now bluetooth
```

Danach prüfen, welche Ports noch offen sind, und sie den Prozessen zuordnen:

```bash
sudo ss -tlnp
```

Jede Zeile in der Ausgabe sollte einem Dienst entsprechen, den man bewusst nach außen freigegeben hat. Falls ein unbekannter Port erscheint, erst nachforschen und dann schließen. `systemd-resolved` auf `127.0.0.53:53` ist zum Beispiel erwartet.

---

## 3. Sudo-Hardening

Die Standard-`sudo`-Gruppe gewährt uneingeschränkten Root-Zugriff. Für die meisten Aufgaben ist das weiter als nötig.

sudoers nur über `visudo` bearbeiten. Es prüft die Syntax vor dem Speichern, sodass man sich mit einem Tippfehler nicht aus sudo aussperrt:

```bash
sudo visudo
```

Sinnvolle Ergänzungen im `Defaults`-Abschnitt:

```text
# Passwort nach 5 Minuten Inaktivität erneut abfragen (Standard: 15)
Defaults timestamp_timeout=5

# Jeden sudo-Befehl mit Zeitstempel protokollieren
Defaults logfile=/var/log/sudo.log
```

> **Zu `log_input` / `log_output`:** Viele Anleitungen ergänzen `Defaults log_input, log_output` für eine vollständige Sitzungsaufzeichnung nach `/var/log/sudo-io`. Vorsicht: `log_input` zeichnet **jeden Tastendruck** in einer sudo-Sitzung auf, auch Passwörter, die in Programme wie `sudo passwd` oder `sudo mysql -p` eingegeben werden, und `log_output` speichert alles Ausgegebene inklusive Secrets. Nur aktivieren, wenn `/var/log/sudo-io` entsprechend geschützt und rotiert wird ([sudoers(5)](https://www.sudo.ws/docs/man/sudoers.man/)).

Falls ein Benutzer nur einen bestimmten Dienst verwalten muss, ihn auf genau diesen Dienst beschränken. Die Regel kommt in eine eigene Drop-in-Datei:

```bash
sudo visudo -f /etc/sudoers.d/deploy
```

```text
# 'deploy' darf nur nginx neu starten und neu laden — nichts sonst
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl reload nginx
```

Diese Regel schränkt nur dann etwas ein, wenn `deploy` **nicht** zusätzlich Mitglied der `sudo`-Gruppe ist. Sonst gewährt die Zeile `%sudo ALL=(ALL:ALL) ALL` weiterhin vollen Root-Zugriff. Bevor die Mitgliedschaft entfernt wird, sicherstellen, dass ein anderes Konto noch funktionierenden Admin-Zugriff hat (zweite SSH-Sitzung als dieser Benutzer öffnen und `sudo -v` ausführen), dann:

```bash
sudo gpasswd -d deploy sudo

# Prüfen: sollte nur die zwei nginx-Befehle auflisten
sudo -l -U deploy
```

Prüfen, ob in `/etc/sudoers.d/` bereits zu weitreichende Wildcard-Berechtigungen stehen:

```bash
sudo ls -la /etc/sudoers.d/
sudo cat /etc/sudoers.d/*
```

---

## 4. Login- und Passwort-Richtlinien

Auch mit schlüsselbasiertem SSH können lokale Konten über die physische Konsole oder Out-of-Band-Management-Schnittstellen authentifiziert werden. Eine Passwort-Richtlinie begrenzt die Auswirkungen schwacher lokaler Anmeldedaten.

Was eine _gute_ Richtlinie ausmacht, hat sich geändert. [NIST SP 800-63B (Revision 4)](https://pages.nist.gov/800-63-4/sp800-63b.html), die Referenz, an der sich die meisten Compliance-Frameworks orientieren, schreibt für prüfende Systeme inzwischen vor:

- **eine Mindestlänge verlangen**: 15 Zeichen für Passwörter, die der einzige Faktor sind,
- **neue Passwörter gegen eine Blockliste prüfen**, die häufig verwendete, erwartbare oder kompromittierte Werte enthält,
- **keine Zusammensetzungsregeln vorschreiben** ("mindestens eine Ziffer, ein Großbuchstabe, ein Sonderzeichen"),
- **keine periodischen Wechsel erzwingen**, sondern nur bei Hinweisen auf eine Kompromittierung.

Erzwungene Rotation und Zusammensetzungsregeln treiben Benutzer zu vorhersehbaren Mustern wie `Sommer2026!` → `Herbst2026!`. Länge plus Blockliste ist sowohl stärker als auch alltagstauglicher.

### Passwort-Alterung in `/etc/login.defs`

Ubuntus Standard `PASS_MAX_DAYS 99999` (kein Ablauf) entspricht bereits NIST, also so lassen. Wichtig: `login.defs` unterstützt keine Kommentare am Ende einer Wertzeile. Ein angehängtes `# …` wird Teil des Werts, und die Einstellung wird verworfen. Kommentare gehören immer in eine eigene Zeile:

```bash
sudo nano /etc/login.defs
```

```text
# Keine erzwungene Rotation (NIST SP 800-63B)
PASS_MAX_DAYS   99999
# Verhindert, durch schnelle Wechsel zum alten Passwort zurückzukehren
PASS_MIN_DAYS   1
PASS_WARN_AGE   7
```

`login.defs` wird nur beim **Anlegen** eines Kontos gelesen. Bestehende Konten behalten ihre Werte; diese mit `chage` prüfen und ändern:

```bash
# Alterungseinstellungen eines bestehenden Benutzers anzeigen
sudo chage -l alice

# Erzwungenen Ablauf entfernen und Mindestalter von 1 Tag setzen
sudo chage --maxdays 99999 --mindays 1 alice
```

### Länge und Blockliste mit pwquality

`libpam-pwquality` installieren. Es klinkt sich über PAM ein, sobald ein Passwort mit `passwd` geändert wird:

```bash
sudo apt install libpam-pwquality -y
sudo nano /etc/security/pwquality.conf
```

```text
# Mindestlänge (NIST: 15 für Passwörter als einziger Faktor)
minlen = 15
# Keine Zusammensetzungsregeln: die Credit-Optionen bleiben auf dem Standard 0
dcredit = 0
ucredit = 0
lcredit = 0
ocredit = 0
# Wörter aus dem cracklib-Wörterbuch ablehnen
dictcheck = 1
# Passwörter ablehnen, die den Benutzernamen enthalten
usercheck = 1
# Richtlinie auch für root anwenden
enforce_for_root
```

`dictcheck` nutzt die lokale cracklib-Wortliste. Sie fängt gängige und wörterbuchbasierte Passwörter ab, ist aber keine Liste _geleakter_ Passwörter. Wer das braucht, prüft Kandidaten gegen einen Breach-Datenbestand wie [Have I Been Pwned's Pwned Passwords](https://haveibeenpwned.com/Passwords). Dessen Range-API nutzt k-Anonymität, sodass nur die ersten fünf Zeichen des SHA-1-Hashs des Passworts die Maschine verlassen.

---

## Was dieser Durchgang abdeckt

| Maßnahme             | Wirkung                                                 |
| -------------------- | ------------------------------------------------------- |
| sysctl-Hardening     | Schließt Netzwerk-Angriffsvektoren auf Kernel-Ebene     |
| Deaktivierte Dienste | Reduziert die Zahl der Eintrittspunkte, die man absichern muss |
| Sudo-Einschränkungen | Begrenzt den Schaden bei einem kompromittierten Konto   |
| Passwort-Richtlinie  | Erhöht den Aufwand für Brute-Force lokaler Anmeldedaten |

Diese vier Maßnahmen erfordern keine externen Tools und erzeugen keinen Netzwerkverkehr. Alle ändern nur die Konfiguration von Software, die bereits installiert ist.

**Teil 3** behandelt die tiefere Schicht: Mandatory Access Control mit AppArmor, Kernel-Level-Audit-Logging mit `auditd` und Datei-Integritätsüberwachung mit AIDE.
