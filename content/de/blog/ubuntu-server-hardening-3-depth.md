---
draft: true
title: "Ubuntu Server Hardening — Teil 3: Defense in Depth"
seo_title: "Ubuntu Hardening Teil 3: Defense in Depth"
date: 2026-07-30T00:00:00+00:00
tags:
  ["tutorial", "linux", "ubuntu", "security", "hardening", "devops", "server"]
description: "Die letzte Hardening-Schicht: Mandatory Access Control mit AppArmor, Audit-Logging mit auditd und Datei-Integritätsüberwachung mit AIDE."
images: ["img/ubuntu-server-hardening.png"]
featured_image: "img/ubuntu-server-hardening.png"
toc: true
---

[Teil 1](/de/blog/ubuntu-server-hardening-1-essentials/) behandelte die grundlegenden Maßnahmen: UFW, Fail2ban und automatische Updates. [Teil 2](/de/blog/ubuntu-server-hardening-2-system/) verschärfte die Systemkonfiguration: sysctl, unnötige Dienste, sudo und Login-Richtlinien.

Dieser Teil hat einen anderen Charakter. Während die ersten beiden Posts auf das _Verhindern_ von Kompromittierungen ausgerichtet waren, gehen die Maßnahmen hier davon aus, dass ein ausreichend motivierter Angreifer irgendwann eindringen könnte — und konzentrieren sich darauf, es zu **erkennen**, zu **begrenzen** und **Beweise** zu haben wenn es passiert.

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

Das community-gepflegte Profil-Set und die Verwaltungswerkzeuge installieren:

```bash
sudo apt install apparmor-profiles apparmor-profiles-extra apparmor-utils -y
```

**Nicht** `aa-enforce /etc/apparmor.d/*` ausführen. Seit Ubuntu 24.04 liegen in `/etc/apparmor.d/` auch Dutzende Profile mit dem Flag `unconfined`, die nur dazu da sind, bestimmten Anwendungen unprivilegierte User-Namespaces zu erlauben, dazu experimentelle Profile, die absichtlich im Complain-Modus ausgeliefert werden. Alle in den Enforce-Modus zu zwingen, kann Dienste auf schwer nachvollziehbare Weise kaputt machen. Stattdessen die Profile im Complain-Modus auflisten und nur die für tatsächlich genutzte Software erzwingen:

```bash
# Listet die geladenen Profile, gruppiert nach Enforce- und Complain-Modus
sudo aa-status

# Ein bestimmtes Profil erzwingen, z. B. für dnsmasq
sudo aa-enforce /etc/apparmor.d/usr.sbin.dnsmasq

# Prüfen: das Profil erscheint jetzt unter "profiles are in enforce mode"
sudo aa-status
```

Nach jeder Umstellung eine Weile das Verweigerungs-Log (nächster Abschnitt) beobachten. Geht etwas kaputt, macht `sudo aa-complain <profil>` die Änderung rückgängig.

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

Wo Verweigerungen landen, hängt davon ab, ob `auditd` (nächster Abschnitt) installiert ist. Ohne auditd gehen sie ins Kernel-Log; mit auditd übernimmt dieser sie und schreibt sie stattdessen nach `/var/log/audit/audit.log`:

```bash
# Ohne auditd: Verweigerungen in Echtzeit aus dem Kernel-Log
sudo journalctl -k -f | grep 'apparmor="DENIED"'

# Mit auditd: Verweigerungen der letzten zehn Minuten
sudo ausearch -m AVC --start recent -i
```

Für eine Zusammenfassung liest `aa-notify` (Paket `apparmor-notify`) das jeweils genutzte Log:

```bash
sudo apt install apparmor-notify -y

# Zusammenfassung der Verweigerungen des letzten Tages, ausführlich
sudo aa-notify -s 1 -v
```

`aa-logprof` ist das Werkzeug für den nächsten Schritt: Es geht die protokollierten Verweigerungen interaktiv durch und bietet an, die **Profile zu erweitern**, damit sie erlaubt werden. Nur Regeln annehmen, die man versteht — jedes "Allow" lockert die Einschränkung.

---

## 2 — auditd: Kernel-Level-Audit-Logging

Das Linux Audit System zeichnet sicherheitsrelevante Ereignisse auf Syscall-Ebene auf. Es besteht aus zwei Teilen: Das **Audit-Subsystem im Kernel** erzeugt die Ereignisse anhand der geladenen Regeln, und der Userspace-Daemon [auditd](https://man7.org/linux/man-pages/man8/auditd.8.html) nimmt sie entgegen und schreibt sie nach `/var/log/audit/audit.log`. Anders als Anwendungslogs kann ein unprivilegierter kompromittierter Prozess es nicht zum Schweigen bringen — die Ereignisse entstehen im Kernel, nicht im Prozess. Ein Angreifer mit Root-Rechten kann den Daemon zwar stoppen, aber genau das wird protokolliert (`DAEMON_END`), und mit gesperrten Regeln (`-e 2`, siehe unten) lassen sich die Regeln ohne Neustart nicht ändern. Damit ist es die primäre Evidenzquelle in der Post-Incident-Forensik.

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
-w /usr/bin/su     -p x  -k su_exec

# ── SSH-Konfiguration ───────────────────────────────────────────────────
-w /etc/ssh/sshd_config   -p wa -k sshd_config
-w /etc/ssh/sshd_config.d/ -p wa -k sshd_config

# ── Authentifizierungs-Konfiguration ────────────────────────────────────
-w /etc/pam.d/                  -p wa -k pam
-w /etc/security/faillock.conf  -p wa -k pam
```

Ältere Anleitungen überwachen auch `/var/log/faillog` und `/var/log/lastlog`. Die kann man weglassen: `faillog` wurde von den ausgemusterten Modulen `pam_tally`/`pam_tally2` geschrieben und fehlt auf aktuellem Ubuntu meist (`pam_faillock` hält seine Zähler in `/var/run/faillock/`), und ab Ubuntu 25.04 ist `lastlog` durch `lastlog2` mit einer SQLite-Datenbank ersetzt — diese Watches würden schlicht nie auslösen. Man braucht sie ohnehin nicht: PAM meldet jede Anmeldung bereits als `USER_AUTH`-, `USER_LOGIN`- und `USER_START`-Ereignis an das Audit-Subsystem (siehe Abfragen unten).

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

# Bericht aller Anmeldungen
sudo aureport --login --start today

# Lesbarer Zusammenfassungsbericht
sudo aureport --summary

# Jede Ausführung von sudo heute (aus dem sudo_exec-Watch)
sudo ausearch -k sudo_exec --start today -i

# Bericht aller Befehle, die in heutigen Audit-Ereignissen auftauchen (nicht nur sudo)
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
```

Unter Debian und Ubuntu schreibt `aideinit` `/var/lib/aide/aide.db.new` und kopiert sie anschließend selbst nach `/var/lib/aide/aide.db` — ein manuelles `mv` ist nicht nötig.

Eine Prüfung ausführen um zu bestätigen dass es keine unerwarteten Unterschiede gibt:

```bash
sudo aide --check
# Bei frischer Einrichtung: "Looks okay, no differences found."
```

### Tägliche Prüfungen automatisieren

In cron ist nichts einzutragen: Ubuntus Paket `aide-common` bringt bereits einen systemd-Timer mit, `dailyaidecheck.timer`, der die Prüfung einmal täglich zwischen 02:00 und 04:00 ausführt. Sicherstellen, dass er aktiv ist:

```bash
sudo systemctl enable --now dailyaidecheck.timer
systemctl list-timers dailyaidecheck.timer
```

Der Bericht geht per Mail an die Adresse in `MAILTO` in `/etc/default/aide` (Standard: `root`). Mails verlassen die Maschine nur, wenn ein Mail Transfer Agent installiert und konfiguriert ist — etwa `postfix` als Satellitensystem, das über den eigenen Mailprovider zustellt. Ohne MTA das Ergebnis mit `sudo journalctl -u dailyaidecheck.service` lesen.

Nach System-Updates die Datenbank neu initialisieren, um den neuen Zustand als Baseline zu akzeptieren. `-y` und `-f` beantworten die Überschreib-Rückfragen für eine bestehende Datenbank:

```bash
sudo aideinit -y -f
```

---

## Das vollständige Bild

Über die drei Teile hinweg haben wir eine Verteidigung in Schichten aufgebaut, bei der jede Schicht unabhängig arbeitet:

| Schicht              | Teil                                       | Schützt gegen                                   |
| -------------------- | ------------------------------------------ | ----------------------------------------------- |
| SSH-Hardening        | [SSH-Beitrag](/de/blog/secure-ssh-server/) | Unbefugten Fernzugriff                          |
| UFW                  | Teil 1                                     | Versehentlich exponierte Dienste                |
| Fail2ban             | Teil 1                                     | Brute-Force-Angriffe                            |
| Unattended Upgrades  | Teil 1                                     | Bekannte CVEs in ungepatchten Paketen           |
| sysctl               | Teil 2                                     | Netzwerk- und Kernel-Exploits                   |
| Deaktivierte Dienste | Teil 2                                     | Angriffsfläche ungenutzter Dienste              |
| Sudo-Einschränkung   | Teil 2                                     | Privilege-Escalation-Schaden                    |
| Login-Richtlinie     | Teil 2                                     | Schwache lokale Anmeldedaten                    |
| AppArmor             | Teil 3                                     | Laterale Bewegung nach Prozess-Kompromittierung |
| auditd               | Teil 3                                     | Unerkannte Post-Compromise-Aktivität            |
| AIDE                 | Teil 3                                     | Binary- und Konfigurations-Manipulation         |

Keine einzelne Schicht bietet vollständige Sicherheit. Zusammen zwingen sie einen Angreifer dazu, jede unabhängig zu überwinden — und machen dauerhaften Zugang ohne Entdeckung extrem schwierig.

---

## Weiter vertiefen

- **[Lynis](https://cisofy.com/lynis/)** — führt ein bewertetes Audit der Hardening-Posture des Servers durch und generiert eine priorisierte To-do-Liste. `sudo lynis audit system` ist eine nützliche Baseline-Prüfung.
- **[Wazuh](https://wazuh.com/)** — ein SIEM-Agent der auditd, Fail2ban, AppArmor und Anwendungslogs in ein durchsuchbares Dashboard mit Alerting-Regeln zusammenführt.
- **[CIS Ubuntu Benchmarks](https://www.cisecurity.org/cis-benchmarks)** — bewertete Compliance-Benchmarks mit Hunderten von Hardening-Prüfungen. Die kostenlose PDF ist eine Referenz für das, was "vollständig gehärtet" in regulierten Umgebungen bedeutet.

---

## Weiterführende Links

- [Ubuntu Security Guide](https://documentation.ubuntu.com/security/docs/compliance/usg/)
- [AppArmor GitLab Wiki](https://gitlab.com/apparmor/apparmor/-/wikis/home)
- [auditd(8) Man-Page](https://man7.org/linux/man-pages/man8/auditd.8.html)
- [AIDE-Handbuch](https://aide.github.io/)
