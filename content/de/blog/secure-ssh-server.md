---
draft: false
title: "SSH-Zugang unter Linux (Ubuntu) absichern"
date: 2026-05-09T00:00:00+00:00
tags: ["tutorial", "linux", "ubuntu", "ssh", "security", "devops"]
description: "Härte den SSH-Zugang deines Ubuntu-Servers ab: SSH-Schlüsselpaar erstellen, Sudo-Nutzer anlegen, Passwort-Login deaktivieren und Root aussperren."
images: ["img/ssh_certificates.png"]
featured_image: "img/ssh_certificates.png"
toc: true
---

Jeder öffentlich erreichbare Linux-Server steht unter konstantem Brute-Force-Druck. Lässt du SSH mit Passwort-Authentifizierung und aktiviertem `root`-Konto offen, ist nicht die Frage, _ob_ ein Angreifer eindringt, sondern nur _wann_. Diese Anleitung führt durch vier konkrete Schritte, die die häufigste Angriffsfläche beseitigen:

1. Auf deinem lokalen Rechner ein **SSH-Schlüsselpaar erstellen**
2. Auf dem Server einen **dedizierten Sudo-Benutzer anlegen**
3. Den **öffentlichen Schlüssel auf den Server übertragen**
4. **`sshd` härten**: Passwort-Login deaktivieren und Root-Login blockieren

Am Ende loggst du dich ausschließlich mit deinem privaten Schlüssel über ein Nicht-Root-Konto ein, das Berechtigungen per `sudo` eskalieren kann.

> **Vorher: Snapshot erstellen.** Falls dein Server bei einem Cloud-Anbieter (Hetzner, DigitalOcean, AWS usw.) läuft, erstelle jetzt einen Snapshot oder ein Backup. Bei den meisten Anbietern geht das mit einem Klick in der Web-Konsole. Mit einem Snapshot stellst du den genauen Zustand der Maschine in Minuten wieder her, falls etwas schiefläuft, zum Beispiel wenn du dich versehentlich aussperrst, bevor du den schlüsselbasierten Login verifiziert hast. Das kostet meist ein paar Cent, und die Beruhigung ist es wert.

---

## Voraussetzungen

- Ein per SSH erreichbarer Linux-Server, in unserem Fall Ubuntu 22.04, 24.04 oder 26.04. Die Schritte sind auf allen dreien gleich; der eine Unterschied (seit 24.04 wird `ssh` per systemd-Socket-Aktivierung über `ssh.socket` gestartet) wird an der passenden Stelle erwähnt. Ubuntu 20.04 hat den Standard-Support verlassen, also vorher upgraden.
- Du kannst dich aktuell als `root` oder als Benutzer mit `sudo`-Rechten einloggen (das brauchst du für die Konfigurationsänderungen)
- Ein OpenSSH-Client auf deinem lokalen Rechner. Er ist in jeder modernen Linux-, macOS- und Windows-10+-Installation enthalten

> **Warnung:** Schließe deine bestehende SSH-Session **nicht**, bis du verifiziert hast, dass der schlüsselbasierte Login funktioniert. Wenn du dich aus einer Cloud-VM aussperrst, benötigst du die Recovery-Konsole des Anbieters.

---

## Schritt 1: SSH-Schlüsselpaar auf dem lokalen Rechner erstellen

Ein SSH-Schlüsselpaar besteht aus zwei mathematisch verknüpften Dateien:

- **Privater Schlüssel** (`id_ed25519`): bleibt auf deinem Rechner und verlässt ihn nie
- **Öffentlicher Schlüssel** (`id_ed25519.pub`): wird auf jeden Server gelegt, auf den du zugreifen möchtest

Die aktuelle Empfehlung ist **Ed25519**, ein Verfahren auf Basis elliptischer Kurven, definiert in [RFC 8032](https://datatracker.ietf.org/doc/html/rfc8032). Er erzeugt kürzere Schlüssel als RSA bei gleichwertiger oder besserer Sicherheit und wird von allen modernen OpenSSH-Versionen (≥ 6.5) unterstützt.

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
ssh-keygen -t ed25519 -C "deine-email@example.com"
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
ssh-keygen -t ed25519 -C "deine-email@example.com"
```

{{< /os-tab >}}
{{< /os-tabs >}}

`ssh-keygen` ist Teil des OpenSSH-Clients, der mit Windows 10 (Version 1809) und höher ausgeliefert wird. Auf älteren Versionen installierst du ihn über _Optionale Features_ oder nimmst [PuTTYgen](https://www.chiark.greenend.org.uk/~sgtatham/putty/).

Das Tool stellt zwei Fragen:

```text
Enter file in which to save the key (/home/you/.ssh/id_ed25519):
Enter passphrase (empty for no passphrase):
```

- **Datei-Speicherort**: Enter drücken, um den Standard zu übernehmen (`~/.ssh/id_ed25519` unter Linux/macOS, `%USERPROFILE%\.ssh\id_ed25519` unter Windows).
- **Passphrase**: Wähle eine starke Passphrase. Sie verschlüsselt deinen privaten Schlüssel auf der Festplatte; falls dein Laptop gestohlen wird, kann der Angreifer den Schlüssel ohne die Passphrase nicht nutzen. Ein SSH-Agent (siehe unten) sorgt dafür, dass du sie nur einmal pro Sitzung eingeben musst.

Nach dem Abschluss sind zwei Dateien vorhanden:

```text
~/.ssh/id_ed25519      # privater Schlüssel — Berechtigungen müssen 600 sein
~/.ssh/id_ed25519.pub  # öffentlicher Schlüssel — sicher zum Teilen
```

### Hinweis zu Post-Quantum-Kryptographie (PQC)

Ed25519 ist heute die richtige Wahl, aber ein Blick auf die längerfristige Entwicklung lohnt sich.

Sowohl RSA als auch Verfahren auf Basis elliptischer Kurven (einschließlich Ed25519) basieren auf mathematischen Problemen (ganzzahlige Faktorisierung und das diskrete Logarithmusproblem), die ein ausreichend leistungsstarker Quantencomputer mithilfe von [Shors Algorithmus](https://de.wikipedia.org/wiki/Shor-Algorithmus) in polynomialer Zeit lösen könnte. Ein solcher Computer existiert noch nicht, aber die Bedrohung ist real genug, dass NIST im August 2024 drei Post-Quantum-Kryptographie-Standards finalisierte:

- **[FIPS 203](https://doi.org/10.6028/NIST.FIPS.203)**: ML-KEM (früher CRYSTALS-Kyber): ein Key-Encapsulation-Mechanismus für den Schlüsselaustausch
- **[FIPS 204](https://doi.org/10.6028/NIST.FIPS.204)**: ML-DSA (früher CRYSTALS-Dilithium): ein gitterbasiertes digitales Signaturverfahren
- **[FIPS 205](https://doi.org/10.6028/NIST.FIPS.205)**: SLH-DSA (früher SPHINCS+): ein hashbasiertes digitales Signaturverfahren

**Was OpenSSH bereits tut.** OpenSSH schützt den _Schlüsselaustausch_ (KEX) mit hybriden Verfahren, die ein Post-Quantum-KEM mit klassischem X25519 kombinieren. Die Sitzung bleibt sicher, solange eine der beiden Hälften hält:

- **OpenSSH 9.0** (April 2022) machte `sntrup761x25519-sha512@openssh.com` zum Standard: [Streamlined NTRU Prime 761](https://ntruprime.cr.yp.to/) + X25519. Inzwischen ist es als `sntrup761x25519-sha512` in [RFC 9941](https://www.rfc-editor.org/rfc/rfc9941) standardisiert.
- **OpenSSH 9.9** (September 2024) führte `mlkem768x25519-sha256` ein: ML-KEM-768 aus [FIPS 203](https://doi.org/10.6028/NIST.FIPS.203) + X25519. **OpenSSH 10.0** (April 2025) machte es zum Standard. Spezifiziert ist es in [RFC 10042](https://www.rfc-editor.org/info/rfc10042/) (vormals draft-ietf-sshm-mlkem-hybrid-kex).

Welches Verfahren du bekommst, hängt von den OpenSSH-Versionen auf _beiden_ Seiten ab: Client und Server wählen den ersten Algorithmus, den beide unterstützen. In beiden Fällen ist die _Sitzungsverschlüsselung_ gegen den sogenannten „Jetzt ernten, später entschlüsseln"-Angriff geschützt: Wer deinen verschlüsselten Traffic heute aufzeichnet, kann ihn nicht nachträglich entschlüsseln, sobald ein Quantencomputer verfügbar ist.

Du kannst prüfen, welchen KEX dein Server aushandelt:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
ssh -v deploy@deine-server-ip exit 2>&1 | grep "kex: algorithm"
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
ssh -v deploy@deine-server-ip exit 2>&1 | Select-String "kex: algorithm"
```

{{< /os-tab >}}
{{< /os-tabs >}}

**Was noch in Arbeit ist.** Der hybride KEX schützt die Sitzungsvertraulichkeit, aber _Authentifizierungsschlüssel_ (dein `id_ed25519`) sind in OpenSSH noch nicht post-quantum, und es gibt noch keinen standardisierten ML-DSA- oder SLH-DSA-Schlüsseltyp für SSH. Die Arbeit an SSH-Protokollerweiterungen findet in der IETF [SSHM Working Group](https://datatracker.ietf.org/wg/sshm/about/) statt. Das ist weniger dringend als der KEX: Ein aufgezeichneter Login lässt sich nicht nachträglich fälschen, die Authentifizierung ist also erst gefährdet, wenn ein Quantencomputer tatsächlich existiert. Bis Post-Quantum-Schlüsseltypen in einer stabilen OpenSSH-Version und in den Distributionspaketen landen, bleibt Ed25519 die richtige Wahl.

---

### SSH-Agent verwenden, um die Passphrase nicht wiederholt eingeben zu müssen

`ssh-agent` hält deinen entschlüsselten Schlüssel für die Dauer deiner Sitzung im Speicher.

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

Einmalig ausführen, um den Dienst zu aktivieren:

> **Administratorrechte erforderlich.** Die ersten beiden Befehle ändern einen Windows-Dienst und müssen in einer **erhöhten (Administrator-)PowerShell-Sitzung** ausgeführt werden. Rechtsklick auf das Startmenü → **Terminal (Administrator)** oder **Windows PowerShell (Administrator)**, oder nach „PowerShell" suchen, Rechtsklick auf das Ergebnis und _Als Administrator ausführen_ wählen. Der dritte Befehl (`ssh-add`) kann danach in einem normalen Terminal ausgeführt werden.

```powershell
Set-Service -Name ssh-agent -StartupType Automatic
Start-Service ssh-agent
ssh-add "$env:USERPROFILE\.ssh\id_ed25519"
```

{{< /os-tab >}}
{{< /os-tabs >}}

---

## Schritt 2: Dedizierten Sudo-Benutzer auf dem Server anlegen

Arbeite nie täglich als `root`. Erstelle einen regulären Benutzer und erteile ihm `sudo`-Zugang. Das begrenzt den Schaden: Eine kompromittierte Sitzung benötigt immer noch das Passwort des Benutzers (oder einen Privilege-Escalation-Exploit), um Root zu werden.

Verbinde dich als Root (dein letztes Root-Login für eine Weile):

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
ssh root@deine-server-ip
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
ssh root@deine-server-ip
```

{{< /os-tab >}}
{{< /os-tabs >}}

### Benutzer erstellen

Ersetze `deploy` durch deinen bevorzugten Benutzernamen.

```bash
adduser deploy
```

`adduser` ist Ubuntus interaktives Frontend zu `useradd`. Es fragt nach einem Passwort und einigen optionalen Profilfeldern. Wähle ein starkes Passwort, denn du wirst es beim Ausführen von `sudo`-Befehlen benötigen.

### Sudo-Rechte vergeben

```bash
usermod -aG sudo deploy
```

Damit wird `deploy` der `sudo`-Gruppe hinzugefügt. Ubuntus Standard-`/etc/sudoers` enthält die Regel `%sudo ALL=(ALL:ALL) ALL`. Laut dieser Regel darf jedes Mitglied dieser Gruppe jeden Befehl als Root ausführen, indem es `sudo` davorsetzt.

### Überprüfen

```bash
su - deploy
sudo whoami
```

`sudo whoami` sollte `root` ausgeben. Wenn ja, ist der Benutzer korrekt konfiguriert.

---

## Schritt 3: Öffentlichen Schlüssel auf den Server übertragen

Der Server authentifiziert dich, indem er prüft, ob der in `~/.ssh/authorized_keys` gespeicherte öffentliche Schlüssel mit dem privaten Schlüssel übereinstimmt, den du beim Login präsentierst. Dieser Mechanismus ist in [RFC 4252 §7](https://datatracker.ietf.org/doc/html/rfc4252#section-7) definiert.

### Option A: ssh-copy-id (empfohlen unter Linux / macOS)

`ssh-copy-id` automatisiert den Prozess: Es fügt deinen öffentlichen Schlüssel an die Remote-`authorized_keys`-Datei an und setzt die korrekten Berechtigungen.

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub deploy@deine-server-ip
```

### Option B: Manuelles Kopieren (funktioniert überall, einschließlich Windows)

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
cat ~/.ssh/id_ed25519.pub | ssh deploy@deine-server-ip \
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
$pubKey = Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"
ssh deploy@deine-server-ip "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pubKey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

{{< /os-tab >}}
{{< /os-tabs >}}

### Schlüsselbasierten Login verifizieren, bevor du weitermachst

Öffne ein **neues Terminal** (halte die alte Sitzung offen) und teste:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
ssh -i ~/.ssh/id_ed25519 deploy@deine-server-ip
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
ssh -i "$env:USERPROFILE\.ssh\id_ed25519" deploy@deine-server-ip
```

{{< /os-tab >}}
{{< /os-tabs >}}

Du solltest eingeloggt sein. Wenn du eine Passphrase gesetzt hast, wirst du danach gefragt. Falls der Login fehlschlägt, **fahre nicht mit Schritt 4 fort**. Such zuerst den Fehler (prüfe Dateirechte, den Speicherort des Schlüssels und den Inhalt von `~/.ssh/authorized_keys` auf dem Server).

---

## Schritt 4: sshd-Konfiguration härten

Die Hauptkonfiguration des SSH-Daemons ist `/etc/ssh/sshd_config`, aber auf aktuellen Ubuntu-Versionen solltest du deine Änderungen **nicht** dort eintragen. Zwei Regeln aus der [sshd_config-Manpage](https://man.openbsd.org/sshd_config) erklären, warum:

1. Die allererste Zeile von Ubuntus `sshd_config` lautet `Include /etc/ssh/sshd_config.d/*.conf`. Jede Drop-in-Datei in diesem Verzeichnis wird also _vor_ dem Rest der Hauptdatei gelesen, und zwar in lexikalischer Reihenfolge der Dateinamen.
2. Für die meisten Schlüsselwörter gilt: „the first obtained value will be used". Spätere Zeilen für dasselbe Schlüsselwort werden stillschweigend ignoriert.

Auf vielen Cloud-Images (AWS, Azure, Hetzner, DigitalOcean …) schreibt cloud-init die Datei `/etc/ssh/sshd_config.d/50-cloud-init.conf` mit `PasswordAuthentication yes`. Trägst du `PasswordAuthentication no` nur in die Hauptdatei ein, gewinnt dieses Drop-in, und der Passwort-Login bleibt **aktiv**, obwohl die Konfigurationsdatei korrekt aussieht. Prüfe, ob dein Server eine solche Datei hat:

```bash
sudo grep -ri passwordauthentication /etc/ssh/sshd_config.d/
```

Die verlässliche Lösung ist ein eigenes Drop-in, dessen Name zuerst einsortiert wird, sodass seine Werte vor allen anderen gelesen werden. Verbinde dich als `deploy` mit dem Server und lege es an:

```bash
sudo nano /etc/ssh/sshd_config.d/00-hardening.conf
```

In diese Datei schreiben wir drei Direktiven.

### 4.1 Passwort-Authentifizierung deaktivieren

```text
PasswordAuthentication no
```

Damit wird jeder Client gezwungen, sich mit einem Schlüssel zu authentifizieren. Brute-Force-Angriffe auf Passwörter werden unmöglich, weil der Server Passwörter gar nicht mehr annimmt.

### 4.2 Root-Login deaktivieren

```text
PermitRootLogin no
```

Selbst wenn ein Angreifer gültige Anmeldedaten erhält, kann er sich nicht direkt als `root` einloggen. Alle privilegierten Operationen müssen über `sudo` von einem benannten Konto aus erfolgen, was einen Audit-Trail erzeugt.

### 4.3 Einschränken, welche Benutzer sich einloggen dürfen (optional, aber empfohlen)

Füge eine Zeile hinzu, die nur deinen neuen Benutzer zulässt:

```text
AllowUsers deploy
```

Jedes andere Konto, auch eines, das ein Angreifer möglicherweise anlegt, wird vom SSH-Zugang ausgesperrt, unabhängig davon, ob es einen gültigen Schlüssel besitzt.

Die vollständige `00-hardening.conf` lautet jetzt:

```text
PasswordAuthentication no
PermitRootLogin no
AllowUsers deploy
```

### Änderungen anwenden

Speichere die Datei und lass `sshd` die gesamte Konfiguration auf Syntaxfehler prüfen, **bevor** du neu lädst. Eine kaputte Konfiguration ist der klassische Weg, sich auszusperren:

```bash
sudo sshd -t
```

Keine Ausgabe bedeutet: Die Konfiguration ist gültig. Lade `ssh` dann neu, ohne bestehende Verbindungen zu unterbrechen:

```bash
sudo systemctl reload ssh
```

> `reload` sendet `SIGHUP` an den laufenden Daemon, der die Konfigurationsdatei neu liest, ohne aktive Sitzungen zu beenden. Verwende `sudo systemctl restart ssh` nur, wenn `reload` nicht funktioniert. Unter Ubuntu heißt die Unit `ssh`, nicht `sshd`.
>
> **Ubuntu 24.04 und neuer:** SSH ist socket-aktiviert: `ssh.socket` lauscht auf Port 22 und startet `ssh.service` bei Bedarf. Für die Direktiven in diesem Beitrag reicht `reload ssh`. Nur wenn du `Port` oder `ListenAddress` änderst, musst du zusätzlich `sudo systemctl daemon-reload && sudo systemctl restart ssh.socket` ausführen, weil die Socket-Unit aus diesen Werten generiert wird. Siehe Ubuntus [Ankündigung der Socket-Aktivierung](https://discourse.ubuntu.com/t/sshd-now-uses-socket-based-activation-ubuntu-22-10-and-later/30189).

Frag `sshd` jetzt, welche Werte es _tatsächlich_ verwendet. `sshd -T` gibt die effektive Konfiguration aus, nachdem alle `Include`-Dateien zusammengeführt wurden. Das ist der einzig verlässliche Weg, ein überschreibendes Drop-in auszuschließen:

```bash
sudo sshd -T | grep -Ei 'passwordauthentication|permitrootlogin|allowusers'
```

Erwartete Ausgabe:

```text
permitrootlogin no
passwordauthentication no
allowusers deploy
```

### Verifizieren

Bestätige von einem **neuen Terminal** auf deinem lokalen Rechner, dass der schlüsselbasierte Login noch funktioniert:

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

Dann bestätige, dass Passwort-Authentifizierung abgelehnt wird:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
ssh -o PasswordAuthentication=yes -o PubkeyAuthentication=no deploy@deine-server-ip
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
ssh -o PasswordAuthentication=yes -o PubkeyAuthentication=no deploy@deine-server-ip
```

{{< /os-tab >}}
{{< /os-tabs >}}

Du solltest `Permission denied (publickey)` sehen. Das ist die richtige Antwort.

Bestätige auch, dass Root-Login blockiert ist:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
ssh root@deine-server-ip
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
ssh root@deine-server-ip
```

{{< /os-tab >}}
{{< /os-tabs >}}

Erwartetes Ergebnis: `Permission denied (publickey)`. Root-Login ist deaktiviert.

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

### „Permission denied (publickey)", obwohl ich Zugang erwarte

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

Führe `sudo ssh-keygen -A` auf dem Server aus, um fehlende Host-Schlüssel zu regenerieren, dann `sudo systemctl restart ssh`.

### Ich habe mich ausgesperrt

Falls du bei einem Cloud-Anbieter (AWS, Hetzner, DigitalOcean usw.) bist, nutze die Web-Konsole oder den Recovery-/Rescue-Modus des Anbieters, um die Festplatte des Servers einzubinden und `/etc/ssh/sshd_config.d/00-hardening.conf` direkt zu korrigieren oder zu entfernen. Deshalb musst du den schlüsselbasierten Login verifizieren, bevor du die Passwort-Authentifizierung deaktivierst.

---

## Was kommt als Nächstes?

Ist SSH gehärtet, lohnen sich diese ergänzenden Maßnahmen:

- **[Fail2ban](https://github.com/fail2ban/fail2ban)**: sperrt IPs, die zu viele fehlgeschlagene Login-Versuche produzieren, und reduziert Log-Rauschen, auch nachdem die Passwort-Authentifizierung deaktiviert ist
- **UFW (Uncomplicated Firewall)**: lässt eingehenden Traffic nur auf den Ports zu, die du tatsächlich brauchst (`sudo ufw allow OpenSSH && sudo ufw enable`)
- **Zwei-Faktor-Authentifizierung für sudo**: kombiniere `sudo` mit einem TOTP-Token über `libpam-google-authenticator` als zweiten Faktor
- **Regelmäßige unbeaufsichtigte Upgrades**: `sudo apt install unattended-upgrades` hält Sicherheits-Patches automatisch aktuell
- **Post-Quantum-Authentifizierungsschlüssel**: sobald ein Post-Quantum-Schlüsseltyp für SSH standardisiert ist (die IETF [SSHM Working Group](https://datatracker.ietf.org/wg/sshm/about/) im Auge behalten) und OpenSSH stabilen Support liefert, generiere ein zweites Schlüsselpaar mit einem ML-DSA- oder SLH-DSA-Algorithmus ([FIPS 204](https://doi.org/10.6028/NIST.FIPS.204) / [FIPS 205](https://doi.org/10.6028/NIST.FIPS.205)) und füge es neben deinem Ed25519-Schlüssel zu `authorized_keys` hinzu, um eine hybride Authentifizierung einzurichten

UFW, Fail2ban und automatische Updates werden Schritt für Schritt in [Ubuntu Server Hardening — Teil 1: Die Grundlagen](/de/blog/ubuntu-server-hardening-1-essentials/) erklärt. Jedes dieser Themen verdient einen eigenen Beitrag, also bleib gespannt.
