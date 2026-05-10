---
draft: false
title: "SSH-Zugang unter Linux (Ubuntu) absichern"
date: 2026-05-09T00:00:00+00:00
tags: ["tutorial", "linux", "ubuntu", "ssh", "security", "devops"]
description: "Härte den SSH-Zugang deines Ubuntu-Servers Schritt für Schritt ab: Erstelle ein SSH-Schlüsselpaar, lege einen Sudo-Benutzer an, deaktiviere Passwort-Authentifizierung und sperre Root aus."
images: ["img/ssh_certificates.png"]
featured_image: "img/ssh_certificates.png"
toc: true
---

Jeder öffentlich erreichbare Linux-Server steht unter konstantem Brute-Force-Druck. Wer SSH mit Passwort-Authentifizierung und aktiviertem `root`-Konto offen lässt, dem stellt sich nicht die Frage _ob_ ein Angreifer eindringt – sondern nur _wann_. Diese Anleitung führt durch vier konkrete Schritte, die die häufigste Angriffsfläche beseitigen:

1. **SSH-Schlüsselpaar erstellen** auf deinem lokalen Rechner
2. **Dedizierten Sudo-Benutzer erstellen** auf dem Server
3. **Öffentlichen Schlüssel übertragen** auf den Server
4. **`sshd` härten**: Passwort-Login deaktivieren und Root-Login blockieren

Am Ende loggst du dich ausschließlich mit deinem privaten Schlüssel über ein Nicht-Root-Konto ein, das Berechtigungen per `sudo` eskalieren kann.

> **Vorher — Snapshot erstellen.** Falls dein Server bei einem Cloud-Anbieter (Hetzner, DigitalOcean, AWS usw.) läuft, erstelle jetzt sofort einen Snapshot oder ein Backup. Die meisten Anbieter ermöglichen dies mit einem Klick in der Web-Konsole. Ein Snapshot erlaubt es, den genauen Zustand der Maschine in Minuten wiederherzustellen, falls etwas schiefläuft – zum Beispiel wenn du dich versehentlich aussperrst, bevor du den schlüsselbasierten Login verifiziert hast. Die Kosten liegen typischerweise bei ein paar Cent, und die gewonnene Sicherheit ist es wert.

---

## Voraussetzungen

- Ein Linux-Server (in unserem Fall Ubuntu 20.04 / 22.04 / 24.04 — die Schritte sind für alle drei identisch), der per SSH erreichbar ist
- Die aktuelle Möglichkeit, dich als `root` oder als Benutzer mit `sudo`-Rechten einzuloggen (du brauchst dies für die Konfigurationsänderungen)
- OpenSSH-Client auf deinem lokalen Rechner — er ist in jeder modernen Linux-, macOS- und Windows-10+-Installation enthalten

> **Warnung:** Schließe deine bestehende SSH-Session **nicht**, bis du verifiziert hast, dass der schlüsselbasierte Login funktioniert. Wenn du dich aus einer Cloud-VM aussperrst, benötigst du die Recovery-Konsole des Anbieters.

---

## Schritt 1 — SSH-Schlüsselpaar auf dem lokalen Rechner erstellen

Ein SSH-Schlüsselpaar besteht aus zwei mathematisch verknüpften Dateien:

- **Privater Schlüssel** (`id_ed25519`) — bleibt auf deinem Rechner, verlässt ihn nie
- **Öffentlicher Schlüssel** (`id_ed25519.pub`) — wird auf jeden Server gelegt, auf den du zugreifen möchtest

Die aktuelle Empfehlung ist **Ed25519**, ein Elliptische-Kurven-Algorithmus, definiert in [RFC 8032](https://datatracker.ietf.org/doc/html/rfc8032). Er erzeugt kürzere Schlüssel als RSA bei gleichwertiger oder besserer Sicherheit und wird von allen modernen OpenSSH-Versionen (≥ 6.5) unterstützt.

**Linux / macOS:**

```bash
ssh-keygen -t ed25519 -C "deine-email@example.com"
```

**Windows (PowerShell):**

```powershell
ssh-keygen -t ed25519 -C "deine-email@example.com"
```

`ssh-keygen` ist Teil des OpenSSH-Clients, der mit Windows 10 (Version 1809) und höher ausgeliefert wird. Bei einer älteren Version kann er über _Optionale Features_ installiert oder [PuTTYgen](https://www.chiark.greenend.org.uk/~sgtatham/putty/) verwendet werden.

Das Tool stellt zwei Fragen:

```bash
Enter file in which to save the key (/home/you/.ssh/id_ed25519):
Enter passphrase (empty for no passphrase):
```

- **Datei-Speicherort**: Enter drücken, um den Standard zu übernehmen (`~/.ssh/id_ed25519` unter Linux/macOS, `%USERPROFILE%\.ssh\id_ed25519` unter Windows).
- **Passphrase**: Wähle eine starke Passphrase. Sie verschlüsselt deinen privaten Schlüssel auf der Festplatte; falls dein Laptop gestohlen wird, kann der Angreifer den Schlüssel ohne die Passphrase nicht nutzen. Ein SSH-Agent (siehe unten) sorgt dafür, dass du sie nur einmal pro Sitzung eingeben musst.

Nach dem Abschluss sind zwei Dateien vorhanden:

```bash
~/.ssh/id_ed25519      # privater Schlüssel — Berechtigungen müssen 600 sein
~/.ssh/id_ed25519.pub  # öffentlicher Schlüssel — sicher zum Teilen
```

### Hinweis zu Post-Quantum-Kryptographie (PQC)

Ed25519 ist heute die richtige Wahl, aber es lohnt sich, das längerfristige Bild zu verstehen.

Sowohl RSA als auch Elliptische-Kurven-Algorithmen (einschließlich Ed25519) basieren auf mathematischen Problemen — ganzzahlige Faktorisierung und das diskrete Logarithmusproblem — die ein ausreichend leistungsstarker Quantencomputer mithilfe von [Shors Algorithmus](https://de.wikipedia.org/wiki/Shor-Algorithmus) in polynomialer Zeit lösen könnte. Ein solcher Computer existiert noch nicht, aber die Bedrohung ist real genug, dass NIST im August 2024 drei Post-Quantum-Kryptographie-Standards finalisierte:

- **[FIPS 203](https://doi.org/10.6028/NIST.FIPS.203)** — ML-KEM (früher CRYSTALS-Kyber): ein Key-Encapsulation-Mechanismus für den Schlüsselaustausch
- **[FIPS 204](https://doi.org/10.6028/NIST.FIPS.204)** — ML-DSA (früher CRYSTALS-Dilithium): ein gitterbaisertes digitales Signaturverfahren
- **[FIPS 205](https://doi.org/10.6028/NIST.FIPS.205)** — SLH-DSA (früher SPHINCS+): ein hashbasiertes digitales Signaturverfahren

**Was OpenSSH bereits tut.** Seit OpenSSH 9.0 (April 2022) ist der Standard-Schlüsselaustausch-Algorithmus `sntrup761x25519-sha512@openssh.com` — ein _Hybrid_, der [NTRU Prime 761](https://ntruprime.cr.yp.to/) (post-quantum) mit X25519 (klassisch) kombiniert. Das schützt die _Sitzungsverschlüsselung_ gegen den sogenannten „Jetzt ernten, später entschlüsseln"-Angriff.

Du kannst prüfen, welchen KEX dein Server aushandelt:

```bash
ssh -vvv deploy@deine-server-ip 2>&1 | grep "kex:"
```

**Was noch in Arbeit ist.** Der hybride KEX schützt die Sitzungsvertraulichkeit, aber _Authentifizierungsschlüssel_ (dein `id_ed25519`) sind in OpenSSH-Mainline noch nicht post-quantum. Die IETF CURDLE Working Group arbeitet daran in [draft-ietf-curdle-ssh-pq-ke](https://datatracker.ietf.org/doc/draft-ietf-curdle-ssh-pq-ke/). Bis diese Arbeit in einer stabilen OpenSSH-Version landet, bleibt Ed25519 die richtige Wahl.

---

### SSH-Agent verwenden, um die Passphrase nicht wiederholt eingeben zu müssen

`ssh-agent` hält deinen entschlüsselten Schlüssel für die Dauer deiner Sitzung im Speicher.

**Linux / macOS:**

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

**Windows (PowerShell) — einmalig ausführen, um den Dienst zu aktivieren:**

> **Administratorrechte erforderlich.** Die ersten beiden Befehle ändern einen Windows-Dienst und müssen in einer **erhöhten (Administrator-)PowerShell-Sitzung** ausgeführt werden. Rechtsklick auf das Startmenü → **Terminal (Administrator)** oder **Windows PowerShell (Administrator)** — oder nach „PowerShell" suchen, Rechtsklick auf das Ergebnis und _Als Administrator ausführen_ wählen. Der dritte Befehl (`ssh-add`) kann danach in einem normalen Terminal ausgeführt werden.

```powershell
Set-Service -Name ssh-agent -StartupType Automatic
Start-Service ssh-agent
ssh-add "$env:USERPROFILE\.ssh\id_ed25519"
```

---

## Schritt 2 — Dedizierten Sudo-Benutzer auf dem Server anlegen

Arbeite nie täglich als `root`. Erstelle einen regulären Benutzer und erteile ihm `sudo`-Zugang. Das begrenzt den Schaden: Eine kompromittierte Sitzung benötigt immer noch das Passwort des Benutzers (oder einen Privilege-Escalation-Exploit), um Root zu werden.

Verbinde dich als Root (dein letztes Root-Login für eine Weile):

```bash
ssh root@deine-server-ip
```

```powershell
ssh root@deine-server-ip
```

### Benutzer erstellen

Ersetze `deploy` durch deinen bevorzugten Benutzernamen.

```bash
adduser deploy
```

`adduser` ist Ubuntus interaktives Frontend zu `useradd`. Es fragt nach einem Passwort und einigen optionalen Profilfeldern. Wähle ein starkes Passwort — du wirst es beim Ausführen von `sudo`-Befehlen benötigen.

### Sudo-Rechte vergeben

```bash
usermod -aG sudo deploy
```

Damit wird `deploy` der `sudo`-Gruppe hinzugefügt. Ubuntus Standard-`sudoers`-Konfiguration gewährt allen Mitgliedern dieser Gruppe die Möglichkeit, jeden Befehl als Root mit dem Präfix `sudo` auszuführen.

### Überprüfen

```bash
su - deploy
sudo whoami
```

`sudo whoami` sollte `root` ausgeben. Wenn ja, ist der Benutzer korrekt konfiguriert.

---

## Schritt 3 — Öffentlichen Schlüssel auf den Server übertragen

Der Server authentifiziert dich, indem er prüft, ob der in `~/.ssh/authorized_keys` gespeicherte öffentliche Schlüssel mit dem privaten Schlüssel übereinstimmt, den du beim Login präsentierst. Dieser Mechanismus ist in [RFC 4252 §7](https://datatracker.ietf.org/doc/html/rfc4252#section-7) definiert.

### Option A — ssh-copy-id (empfohlen unter Linux / macOS)

`ssh-copy-id` automatisiert den Prozess: Es fügt deinen öffentlichen Schlüssel an die Remote-`authorized_keys`-Datei an und setzt die korrekten Berechtigungen.

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub deploy@deine-server-ip
```

### Option B — Manuelles Kopieren (funktioniert überall, einschließlich Windows)

**Linux / macOS:**

```bash
cat ~/.ssh/id_ed25519.pub | ssh deploy@deine-server-ip \
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

**Windows (PowerShell):**

```powershell
$pubKey = Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"
ssh deploy@deine-server-ip "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pubKey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

### Schlüsselbasierten Login verifizieren, bevor du weitermachst

Öffne ein **neues Terminal** (halte die alte Sitzung offen) und teste:

```bash
ssh -i ~/.ssh/id_ed25519 deploy@deine-server-ip
```

```powershell
ssh -i "$env:USERPROFILE\.ssh\id_ed25519" deploy@deine-server-ip
```

Du solltest eingeloggt sein. Wenn du eine Passphrase gesetzt hast, wirst du danach gefragt. Falls der Login fehlschlägt, **fahre nicht mit Schritt 4 fort** — debugge zuerst (überprüfe Dateirechte, Schlüsselplatzierung und `~/.ssh/authorized_keys`-Inhalt auf dem Server).

---

## Schritt 4 — sshd-Konfiguration härten

Alle SSH-Daemon-Einstellungen befinden sich in `/etc/ssh/sshd_config`. Die Datei ist gut kommentiert; wir ändern drei spezifische Direktiven. Sieh die [sshd_config-Manpage](https://man.openbsd.org/sshd_config) für die vollständige Referenz.

Verbinde dich als `deploy` mit dem Server und öffne die Konfigurationsdatei mit erhöhten Rechten:

```bash
sudo nano /etc/ssh/sshd_config
```

### 4.1 — Passwort-Authentifizierung deaktivieren

Suche die Zeile `PasswordAuthentication` (sie kann auskommentiert sein) und setze sie auf `no`:

```text
PasswordAuthentication no
```

Damit wird jeder Client gezwungen, sich mit einem Schlüssel zu authentifizieren. Brute-Force-Angriffe auf Passwörter werden unmöglich, weil der Server diese gar nicht mehr akzeptiert.

### 4.2 — Root-Login deaktivieren

Suche `PermitRootLogin` und setze es auf `no`:

```text
PermitRootLogin no
```

Selbst wenn ein Angreifer gültige Anmeldedaten erhält, kann er sich nicht direkt als `root` einloggen. Alle privilegierten Operationen müssen über `sudo` von einem benannten Konto aus erfolgen, was einen Audit-Trail erzeugt.

### 4.3 — (Optional, aber empfohlen) Einschränken, welche Benutzer sich einloggen dürfen

Füge am Ende der Datei eine Zeile hinzu, die nur deinen neuen Benutzer auf der Whitelist hat:

```text
AllowUsers deploy
```

Jedes andere Konto — einschließlich solcher, die ein Angreifer möglicherweise erstellt — wird vom SSH-Zugang ausgesperrt, unabhängig davon, ob es einen gültigen Schlüssel besitzt.

### Änderungen anwenden

Speichere die Datei und lade `ssh` neu, ohne bestehende Verbindungen zu unterbrechen:

```bash
sudo systemctl reload ssh
```

> `reload` sendet `SIGHUP` an den laufenden Daemon, der die Konfigurationsdatei neu liest, ohne aktive Sitzungen zu beenden. Verwende `restart` nur, wenn `reload` nicht funktioniert.

### Verifizieren

Bestätige von einem **neuen Terminal** auf deinem lokalen Rechner, dass der schlüsselbasierte Login noch funktioniert:

```bash
ssh deploy@deine-server-ip
```

```powershell
ssh deploy@deine-server-ip
```

Dann bestätige, dass Passwort-Authentifizierung abgelehnt wird:

```bash
ssh -o PasswordAuthentication=yes -o PubkeyAuthentication=no deploy@deine-server-ip
```

```powershell
ssh -o PasswordAuthentication=yes -o PubkeyAuthentication=no deploy@deine-server-ip
```

Du solltest `Permission denied (publickey)` sehen — das ist die korrekte Antwort.

Bestätige auch, dass Root-Login blockiert ist:

```bash
ssh root@deine-server-ip
```

```powershell
ssh root@deine-server-ip
```

Erwartetes Ergebnis: `Permission denied (publickey)` — Root-Login ist deaktiviert.

---

## Zusammenfassung der Änderungen

| Was                       | Vorher                  | Nachher                |
| ------------------------- | ----------------------- | ---------------------- |
| Authentifizierungsmethode | Passwort oder Schlüssel | Nur Schlüssel          |
| Root-Login                | Erlaubt                 | Blockiert              |
| Standard-Arbeitsbenutzer  | `root`                  | `deploy` (sudo-fähig)  |
| Privilege Escalation      | Direkte Root-Sitzung    | `sudo` mit Audit-Trail |

---

## Fehlerbehebung

### „Permission denied (publickey)", obwohl ich erwartet werde

1. Überprüfe, ob der öffentliche Schlüssel in `~/.ssh/authorized_keys` auf dem Server exakt mit `~/.ssh/id_ed25519.pub` auf deinem Rechner übereinstimmt (eine Zeile, keine Zeilenumbrüche).
2. Überprüfe die Berechtigungen:

   ```bash
   chmod 700 ~/.ssh
   chmod 600 ~/.ssh/authorized_keys
   ```

3. Führe `ssh` mit ausführlicher Ausgabe aus, um zu sehen, wo die Authentifizierung genau fehlschlägt:

   ```bash
   ssh -vvv deploy@deine-server-ip
   ```

### „Could not load host key" in sshd-Logs

Führe `sudo ssh-keygen -A` auf dem Server aus, um fehlende Host-Schlüssel zu regenerieren, dann `sudo systemctl restart sshd`.

### Ich habe mich ausgesperrt

Falls du bei einem Cloud-Anbieter (AWS, Hetzner, DigitalOcean usw.) bist, nutze die Web-Konsole oder den Recovery-/Rescue-Modus des Anbieters, um die Festplatte des Servers einzubinden und `/etc/ssh/sshd_config` direkt zu bearbeiten. Deshalb musst du den schlüsselbasierten Login verifizieren, bevor du die Passwort-Authentifizierung deaktivierst.

---

## Was kommt als Nächstes?

Mit gehärtetem SSH empfehlen sich diese ergänzenden Maßnahmen:

- **[Fail2ban](https://github.com/fail2ban/fail2ban)** — sperrt IPs, die zu viele fehlgeschlagene Login-Versuche produzieren, und reduziert Log-Rauschen, auch nachdem die Passwort-Authentifizierung deaktiviert ist
- **UFW (Uncomplicated Firewall)** — schränkt eingehenden Traffic auf nur die Ports ein, die du tatsächlich benötigst (`sudo ufw allow OpenSSH && sudo ufw enable`)
- **Zwei-Faktor-Authentifizierung für sudo** — kombiniere `sudo` mit einem TOTP-Token über `libpam-google-authenticator` für eine zusätzliche Schutzschicht
- **Regelmäßige unbeaufsichtigte Upgrades** — `sudo apt install unattended-upgrades` hält Sicherheits-Patches automatisch aktuell
- **Post-Quantum-Authentifizierungsschlüssel** — sobald IETF [draft-ietf-curdle-ssh-pq-ke](https://datatracker.ietf.org/doc/draft-ietf-curdle-ssh-pq-ke/) ausgereift ist und OpenSSH stabilen Support liefert, generiere ein zweites Schlüsselpaar mit einem ML-DSA- oder SLH-DSA-Algorithmus und füge es neben deinem Ed25519-Schlüssel zu `authorized_keys` hinzu

Jedes dieser Themen verdient einen eigenen Beitrag — bleib gespannt.
