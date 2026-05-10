---
draft: true
title: "Ubuntu Server Hardening — Teil 3: Defense in Depth"
date: 2026-05-24T00:00:00+00:00
tags: ["tutorial", "linux", "ubuntu", "security", "hardening", "devops", "server"]
description: "Die letzte Hardening-Schicht: Mandatory Access Control mit AppArmor, Kernel-Level-Audit-Logging mit auditd und kryptografische Datei-Integritätsüberwachung mit AIDE."
images: ["img/ubuntu-server-hardening.png"]
featured_image: "img/ubuntu-server-hardening.png"
toc: true
---

[Teil 1](/de/blog/ubuntu-server-hardening-1-essentials/) behandelte die grundlegenden Maßnahmen: UFW, Fail2ban und automatische Updates. [Teil 2](/de/blog/ubuntu-server-hardening-2-system/) verschärfte die Systemkonfiguration: sysctl, unnötige Dienste, sudo und Login-Richtlinien.

Dieser Teil hat einen anderen Charakter. Während die ersten beiden Posts auf das *Verhindern* von Kompromittierungen ausgerichtet waren, gehen die Maßnahmen hier davon aus, dass ein ausreichend motivierter Angreifer irgendwann eindringen könnte — und konzentrieren sich darauf, es zu **erkennen**, zu **begrenzen** und **Beweise** zu haben wenn es passiert.

> **Voraussetzungen:** Teile 1 und 2 abgeschlossen, SSH abgesichert, Nicht-Root-Sudo-Benutzer.

---

## 1 — AppArmor: Mandatory Access Control

[AppArmor](https://apparmor.net/) ist ein Mandatory-Access-Control-Framework (MAC), das in den Linux-Kernel eingebaut ist. Es erzwingt per-Programm-Sicherheitsrichtlinien: Ein Profil definiert genau, welche Dateien ein Prozess lesen, schreiben oder ausführen darf und welche Netzwerkverbindungen er aufbauen darf. Die Richtlinien werden vom Kernel durchgesetzt — ein Prozess kann sich nicht dagegen entscheiden.

Die praktische Konsequenz: Wenn ein Angreifer eine Schwachstelle in nginx ausnutzt und Code-Ausführung unter dem nginx-Prozess erlangt, hält AppArmor ihn auf das beschränkt, was nginx legitim braucht. Er kann `/etc/shadow` nicht lesen, nicht in `/var/spool/cron` schreiben und keine Shells starten.

### Ubuntu liefert AppArmor aktiviert

Aktuellen Status prüfen:

```bash
sudo apparmor_status
```

Profile erscheinen in zwei Modi:
- **enforce** — Verstöße werden blockiert und protokolliert
- **complain** — Verstöße werden protokolliert, aber erlaubt (für die Entwicklung neuer Profile)

Das community-gepflegte Profil-Set installieren und alles erzwingen:

```bash
sudo apt install apparmor-profiles apparmor-profiles-extra apparmor-utils -y

# Profile im Complain-Modus in den Enforce-Modus versetzen
sudo aa-enforce /etc/apparmor.d/*

# Prüfen
sudo apparmor_status | grep "enforce mode"
```

### Ein Profil für eine eigene Anwendung schreiben

`aa-genprof` überwacht einen laufenden Prozess und generiert ein Profil aus seinem beobachteten Verhalten:

```bash
# Tool starten — es fordert auf, die Anwendung in einem anderen Fenster zu starten
sudo aa-genprof /usr/local/bin/meinprogramm

# In einem zweiten Terminal: Anwendung durch den normalen Workflow führen
# Wenn fertig: im aa-genprof-Terminal S drücken um das Log zu scannen
# Jede vorgeschlagene Regel prüfen und annehmen/ablehnen, dann F zum Beenden
```

Das generierte Profil wird in `/etc/apparmor.d/` gespeichert und sofort geladen. Es kann zusammen mit der Anwendung versioniert werden.

### Verweigerungen inspizieren

```bash
# AppArmor-Verweigerungs-Log in Echtzeit
sudo journalctl -f | grep apparmor

# Letzte Verweigerungen zusammenfassen
sudo aa-logprof
```

---

## 2 — auditd: Kernel-Level-Audit-Logging

Das Linux Audit System ([auditd](https://linux.die.net/man/8/auditd)) zeichnet sicherheitsrelevante Ereignisse auf Syscall-Ebene auf. Anders als Anwendungslogs kann es von einem kompromittierten Prozess nicht zum Schweigen gebracht werden — es läuft im Kernel und schreibt direkt in eine dedizierte Log-Datei. Es ist die primäre Evidenzquelle in der Post-Incident-Forensik.

```bash
sudo apt install auditd audispd-plugins -y
sudo systemctl enable --now auditd
```

### Regeln konfigurieren

Regeln kommen nach `/etc/audit/rules.d/`. Ein Hardening-Regelwerk erstellen:

```bash
sudo nano /etc/audit/rules.d/99-hardening.rules
```

```text
# Bestehende Regeln löschen
-D

# Puffergröße — erhöhen falls Ereignisse unter Last verloren gehen
-b 8192

# Regeln bis zum nächsten Neustart sperren (verhindert Manipulation der Audit-Konfiguration)
-e 2

# ── Identitätsdateien ──────────────────────────────────────────────────
-w /etc/passwd  -p wa -k identity
-w /etc/shadow  -p wa -k identity
-w /etc/group   -p wa -k identity

# ── Privilege-Escalation ────────────────────────────────────────────────
-w /etc/sudoers    -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers
-w /usr/bin/sudo   -p x  -k sudo_exec
-w /bin/su         -p x  -k su_exec

# ── SSH-Konfiguration ───────────────────────────────────────────────────
-w /etc/ssh/sshd_config -p wa -k sshd_config

# ── Login-Aktivität ─────────────────────────────────────────────────────
-w /var/log/faillog  -p wa -k login
-w /var/log/lastlog  -p wa -k login
```

Regeln laden:

```bash
sudo augenrules --load

# Bestätigen dass sie aktiv sind
sudo auditctl -l
```

### Das Audit-Log abfragen

```bash
# Alle Ereignisse mit dem Tag 'sudoers' (Konfigurationsänderungen oder sudo-Ausführungen)
sudo ausearch -k sudoers

# Ereignisse der letzten Stunde
sudo ausearch --start recent

# Alle fehlgeschlagenen Login-Versuche
sudo ausearch --message USER_AUTH --success no

# Lesbarer Zusammenfassungsbericht
sudo aureport --summary

# Bericht aller via sudo ausgeführten Befehle des heutigen Tages
sudo aureport --comm --start today
```

---

## 3 — AIDE: Datei-Integritätsüberwachung

[AIDE](https://aide.github.io/) (Advanced Intrusion Detection Environment) erstellt einen kryptografischen Snapshot des Dateisystems in einem bekannt-guten Zustand. Bei nachfolgenden Durchläufen vergleicht es das Live-Dateisystem mit diesem Snapshot und meldet alle Unterschiede: neue Dateien, gelöschte Dateien, geänderte Berechtigungen, geänderter Inhalt.

Wenn ein Angreifer eine Backdoor installiert, eine System-Binary ersetzt oder eine Konfigurationsdatei modifiziert, erkennt AIDE es — auch wenn der Angreifer seine Spuren in Anwendungslogs verwischt.

```bash
sudo apt install aide aide-common -y
```

Die Standardkonfiguration prüfen (welche Verzeichnisse überwacht werden und mit welchen Prüfungen):

```bash
sudo less /etc/aide/aide.conf
```

Die Standards decken bereits `/usr`, `/bin`, `/sbin`, `/etc` und verwandte Verzeichnisse ab. Für die meisten Server ist das ohne Änderungen angemessen.

### Datenbank initialisieren

Das dauert beim ersten Durchlauf einige Minuten — AIDE hasht jede überwachte Datei:

```bash
sudo aideinit
# Ausgabe: The new database will be written to /var/lib/aide/aide.db.new
sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
```

Eine Prüfung ausführen um zu bestätigen dass es keine unerwarteten Unterschiede gibt:

```bash
sudo aide --check
# Bei frischer Einrichtung: "Looks okay, no differences found."
```

### Tägliche Prüfungen automatisieren

```bash
sudo crontab -e
```

```text
# Tägliche AIDE-Integritätsprüfung um 03:00, Ergebnisse per Mail senden
0 3 * * * /usr/bin/aide --check 2>&1 | mail -s "AIDE-Bericht $(hostname)" root
```

Nach System-Updates die Datenbank neu initialisieren, um den neuen Zustand als Baseline zu akzeptieren:

```bash
sudo aideinit
sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
```

---

## Das vollständige Bild

Über die drei Teile hinweg haben wir eine Verteidigung in Schichten aufgebaut, bei der jede Schicht unabhängig arbeitet:

| Schicht | Teil | Schützt gegen |
|---------|------|--------------|
| SSH-Hardening | [SSH-Beitrag](/de/blog/secure-ssh-server/) | Unbefugten Fernzugriff |
| UFW | Teil 1 | Versehentlich exponierte Dienste |
| Fail2ban | Teil 1 | Brute-Force-Angriffe |
| Unattended Upgrades | Teil 1 | Bekannte CVEs in ungepatchten Paketen |
| sysctl | Teil 2 | Netzwerk- und Kernel-Exploits |
| Deaktivierte Dienste | Teil 2 | Angriffsfläche ungenutzter Dienste |
| Sudo-Einschränkung | Teil 2 | Privilege-Escalation-Schaden |
| Login-Richtlinie | Teil 2 | Schwache lokale Anmeldedaten |
| AppArmor | Teil 3 | Laterale Bewegung nach Prozess-Kompromittierung |
| auditd | Teil 3 | Unerkannte Post-Compromise-Aktivität |
| AIDE | Teil 3 | Binary- und Konfigurations-Manipulation |

Keine einzelne Schicht bietet vollständige Sicherheit. Zusammen zwingen sie einen Angreifer dazu, jede unabhängig zu überwinden — und machen dauerhaften Zugang ohne Entdeckung extrem schwierig.

---

## Weiter vertiefen

- **[Lynis](https://cisofy.com/lynis/)** — führt ein bewertetes Audit der Hardening-Posture des Servers durch und generiert eine priorisierte To-do-Liste. `sudo lynis audit system` ist eine nützliche Baseline-Prüfung.
- **[Wazuh](https://wazuh.com/)** — ein SIEM-Agent der auditd, Fail2ban, AppArmor und Anwendungslogs in ein durchsuchbares Dashboard mit Alerting-Regeln zusammenführt.
- **[CIS Ubuntu Benchmarks](https://www.cisecurity.org/cis-benchmarks)** — bewertete Compliance-Benchmarks mit Hunderten von Hardening-Prüfungen. Die kostenlose PDF ist eine Referenz für das, was "vollständig gehärtet" in regulierten Umgebungen bedeutet.

---

## Weiterführende Links

- [Ubuntu Security Guide](https://ubuntu.com/security/certifications/docs/usg)
- [AppArmor GitLab Wiki](https://gitlab.com/apparmor/apparmor/-/wikis/home)
- [Linux Audit Dokumentation](https://linux.die.net/man/8/auditd)
- [AIDE-Handbuch](https://aide.github.io/)
