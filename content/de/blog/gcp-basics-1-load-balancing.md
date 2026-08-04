---
draft: false
title: "GCP Grundlagen — Teil 1: Load Balancing in der Google Cloud verstehen"
seo_title: "GCP Load Balancing erklärt: Network LB vs. Application LB"
date: 2026-08-04T19:30:00+02:00
tags:
  [
    "gcp",
    "google-cloud",
    "load-balancer",
    "gcloud",
    "tutorial",
    "cloud",
    "devops",
    "learning-in-public",
  ]
categories: ["Cloud Computing"]
description: "Target Pools, URL Maps, Forwarding Rules — Google Cloud Load Balancing von Grund auf erklärt. Regionaler Network Load Balancer und globaler Application Load Balancer mit gcloud, Schritt für Schritt."
toc: true
---

Dies ist der erste Teil einer Serie, in der ich mich in die Google Cloud Platform einarbeite und das Gelernte dokumentiere — Learning in Public. Falls hier etwas falsch oder veraltet ist: sag Bescheid, ich korrigiere es.

Wir starten mit **Load Balancing**, weil genau dort die meisten GCP-Einsteiger gegen die erste Vokabelwand laufen: Target Pools, URL Maps, Forwarding Rules, Backend Services, Target Proxies. Fünf Begriffe, von denen sich keiner selbst erklärt.

Am Ende dieses Artikels hast du zwei verschiedene Load Balancer mit der `gcloud`-CLI gebaut und — wichtiger — du weißt, welche Kiste wofür zuständig ist.

> **Kostenwarnung:** Die Ressourcen aus diesem Artikel sind **nicht** vom [Google Cloud Free Tier](https://cloud.google.com/free) abgedeckt. Zwei `e2-medium`-VMs, drei `e2-small`-VMs, eine globale IP-Adresse und zwei Forwarding Rules kosten echtes Geld pro Stunde. Der [Aufräum-Abschnitt](#aufräumen--nicht-überspringen) am Ende löscht alles wieder. Nicht überspringen.

---

## Voraussetzungen

Du brauchst die **gcloud CLI** und ein GCP-Projekt mit aktivierter Abrechnung.

### gcloud CLI installieren

**Linux:**

```bash
# Debian / Ubuntu — Googles Paketquelle hinzufügen
sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates gnupg curl

curl https://packages.cloud.google.com/apt/doc/apt-key.gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg

echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
  | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list

sudo apt-get update && sudo apt-get install -y google-cloud-cli
```

**Windows (PowerShell):**

```powershell
# Benötigt PowerShell 5.1+; PowerShell 7 empfohlen
winget install --id Google.CloudSDK -e
```

Falls `winget` nicht verfügbar ist: Installer aus der [gcloud-CLI-Installationsdoku](https://cloud.google.com/sdk/docs/install) laden. PowerShell 7 einrichten steht in [Upgrade auf PowerShell 7](/de/blog/upgrade-powershell-7/).

### Authentifizieren und Projekt wählen

```bash
gcloud init
gcloud auth login
gcloud config set project DEINE_PROJEKT_ID
```

```powershell
gcloud init
gcloud auth login
gcloud config set project DEINE_PROJEKT_ID
```

Die `gcloud`-Syntax ist auf jeder Plattform identisch. Nur shell-spezifische Dinge — Zeilenumbrüche, Schleifen, Variablen — unterscheiden sich, und dafür zeige ich jeweils beide Varianten.

**Keine lokale Installation gewünscht?** Die [Cloud Shell](https://cloud.google.com/shell/docs) gibt dir ein Browser-Terminal mit vorinstalliertem und bereits authentifiziertem `gcloud`. Jeder Befehl aus diesem Artikel läuft dort unverändert.

---

## Zuerst: von welchem Load Balancer reden wir überhaupt?

Google Cloud hat nicht "einen" Load Balancer. Es gibt eine ganze Familie, und die unterscheidet sich in zwei Dimensionen: **auf welcher OSI-Schicht** sie arbeitet und **ob sie regional oder global** ist.

| | Network Load Balancer | Application Load Balancer |
| --- | --- | --- |
| OSI-Schicht | Layer 4 (TCP/UDP) | Layer 7 (HTTP/HTTPS) |
| Sieht | IP-Adressen, Ports | URLs, Header, Cookies |
| Scope in diesem Artikel | Regional | Global |
| Routing-Entscheidung | Pro Verbindung | Pro Request-Inhalt |
| Terminiert die Verbindung? | Nein (Passthrough) | Ja (Proxy) |

Layer 4 und Layer 7 beziehen sich auf das [OSI-Referenzmodell](https://www.iso.org/standard/20269.html) (ISO/IEC 7498-1). Der praktische Unterschied:

- Ein **Layer-4**-Balancer leitet Pakete weiter. Er weiß "TCP-Verbindung auf Port 80" und wählt ein Backend. Den HTTP-Request liest er nie. TCP selbst ist in [RFC 9293](https://www.rfc-editor.org/rfc/rfc9293) spezifiziert.
- Ein **Layer-7**-Balancer terminiert die Client-Verbindung, parst den HTTP-Request gemäß [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) und kann `/api/*` an ein Backend und `/images/*` an ein anderes schicken.

Wir bauen von jedem einen. Googles vollständige [Load-Balancing-Übersicht](https://cloud.google.com/load-balancing/docs/load-balancing-overview) listet die restlichen Varianten auf.

---

## Standardwerte setzen

Bevor wir irgendetwas erstellen, sagen wir `gcloud`, wo gearbeitet wird. Das spart `--region` und `--zone` an jedem Befehl.

```bash
gcloud config set compute/region us-east1
gcloud config set compute/zone us-east1-d
```

```powershell
gcloud config set compute/region us-east1
gcloud config set compute/zone us-east1-d
```

- **Region (`us-east1`)** — ein geografisches Gebiet, grob "US-Ostküste".
- **Zone (`us-east1-d`)** — ein isoliertes Rechenzentrum innerhalb dieser Region.

Eine Zone ist eine Fehlerdomäne: Fällt sie aus, fällt alles darin mit aus. Instanzen über mehrere Zonen zu verteilen ist die Antwort darauf. Siehe [Regionen und Zonen](https://cloud.google.com/compute/docs/regions-zones).

In den Befehlen unten stehen die `--zone`- und `--region`-Flags trotzdem explizit drin, damit jeder einzeln kopierbar bleibt.

---

## Teil 1: Ein regionaler Network Load Balancer

Der [externe Passthrough Network Load Balancer](https://cloud.google.com/load-balancing/docs/network) nimmt Traffic auf einer öffentlichen IP an und leitet ihn an Backends weiter, **ohne ihn zu verändern**. Dein Webserver sieht die Original-IP des Clients, nicht die des Balancers — genau das bedeutet "Passthrough".

### Schritt 1 — Drei Webserver erstellen

```bash
gcloud compute instances create web1 \
    --zone=us-east1-d \
    --tags=network-lb-tag \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --metadata=startup-script='#!/bin/bash
      apt-get update
      apt-get install apache2 -y
      service apache2 restart
      echo "<h3>Web Server: web1</h3>" | tee /var/www/html/index.html'
```

Für `web2` und `web3` wiederholen — Instanzname im Befehl **und** in der `echo`-Zeile anpassen.

**Was die Flags bedeuten:**

- `--machine-type=e2-small` — ein kleiner, günstiger [Maschinentyp](https://cloud.google.com/compute/docs/machine-resource). Zwei (geteilte) vCPUs, 2 GB RAM. Reichlich für einen Apache mit einer HTML-Datei.
- `--image-family=debian-12` — das Betriebssystem. Eine *Family* statt eines konkreten Image-Namens liefert immer den aktuellsten gepatchten Debian-12-Build. Siehe [Public Images](https://cloud.google.com/compute/docs/images/os-details).
- `--tags=network-lb-tag` — ein [Netzwerk-Tag](https://cloud.google.com/vpc/docs/add-remove-network-tags). Stell es dir als Post-it auf der VM vor. Firewall-Regeln zielen auf Tags statt auf einzelne Maschinen — "Port 80 für alles mit diesem Post-it erlauben" funktioniert damit auch noch, wenn Instanzen dazukommen oder verschwinden.
- `--metadata=startup-script=...` — das Skript, das Compute Engine beim ersten Boot als Root ausführt. So musst du dich nie per SSH auf die Maschine verbinden, um sie zu konfigurieren. Siehe [Startup-Skripte](https://cloud.google.com/compute/docs/instances/startup-scripts/linux).

**Unter Windows:** Mehrzeilige einfach-gequotete Strings überleben PowerShell nicht. Skript stattdessen in eine Datei legen und mit `--metadata-from-file` übergeben — was auf Linux ebenfalls der sauberere Weg ist, sobald das Skript länger als drei Zeilen wird.

```powershell
# startup.sh (LF-Zeilenenden! CRLF zerstört die Shebang-Zeile)
@'
#!/bin/bash
apt-get update
apt-get install apache2 -y
service apache2 restart
echo "<h3>Web Server: $(hostname)</h3>" | tee /var/www/html/index.html
'@ -replace "`r`n", "`n" | Set-Content -Path startup.sh -NoNewline

gcloud compute instances create web1 `
    --zone=us-east1-d `
    --tags=network-lb-tag `
    --machine-type=e2-small `
    --image-family=debian-12 `
    --image-project=debian-cloud `
    --metadata-from-file=startup-script=startup.sh
```

Das Backtick `` ` `` ist PowerShells Zeilenfortsetzungszeichen, das Äquivalent zu `\` in Bash.

### Schritt 2 — HTTP-Traffic erlauben

Die VMs existieren, aber niemand kommt an sie ran. Die Standard-VPC-Firewall von GCP blockiert eingehenden Traffic komplett. Port 80 für die getaggten Instanzen öffnen:

```bash
gcloud compute firewall-rules create www-firewall-network-lb \
    --target-tags network-lb-tag \
    --allow tcp:80
```

Das ist dasselbe Default-Deny-Prinzip wie in [Ubuntu Server Hardening — Teil 1](/de/blog/ubuntu-server-hardening-1-essentials/), nur eine Schicht höher durchgesetzt: in der [VPC-Firewall](https://cloud.google.com/firewall/docs/firewalls) statt auf dem Host.

Prüfen, ob die Instanzen laufen, und externe IPs notieren:

```bash
gcloud compute instances list
curl http://EXTERNE_IP_VON_WEB1
```

```powershell
gcloud compute instances list
Invoke-RestMethod -Uri "http://EXTERNE_IP_VON_WEB1"
```

### Schritt 3 — Den Load Balancer bauen

Vier Ressourcen, in Abhängigkeitsreihenfolge erstellt:

```bash
# 1. Statische regionale IP-Adresse reservieren
gcloud compute addresses create network-lb-ip-1 \
    --region=us-east1

# 2. Health Check erstellen
gcloud compute http-health-checks create basic-check

# 3. Target Pool erstellen — die Gruppe der Backends
gcloud compute target-pools create www-pool \
    --region=us-east1 \
    --http-health-check=basic-check

# 4. Die drei Instanzen in den Pool legen
gcloud compute target-pools add-instances www-pool \
    --instances=web1,web2,web3 \
    --instances-zone=us-east1-d

# 5. Forwarding Rule — verbindet IP und Port mit dem Pool
gcloud compute forwarding-rules create www-rule \
    --region=us-east1 \
    --ports=80 \
    --address=network-lb-ip-1 \
    --target-pool=www-pool
```

Der **Health Check** ist der Teil, den man weglässt und danach bereut. Der Balancer prüft jedes Backend in festem Intervall. Ein Backend, das den Check nicht besteht, bekommt keinen Traffic mehr, bis es sich erholt — automatisch, ohne dass nachts um drei ein Alarm losgeht. Details: [Health-Check-Konzepte](https://cloud.google.com/load-balancing/docs/health-check-concepts).

Ein **Target Pool** ist der Legacy-Backend-Typ für diesen Balancer. Er funktioniert weiterhin und steht in fast jedem Tutorial, aber Google empfiehlt für neue Deployments inzwischen [Backend-Service-basierte Network Load Balancer](https://cloud.google.com/load-balancing/docs/network/networklb-backend-service) — die unterstützen mehr Protokolle und teilen sich das Konfigurationsmodell mit dem Application Load Balancer, den wir gleich bauen. Gut zu wissen, bevor ein Target Pool in Produktion landet.

### Schritt 4 — Verteilung beobachten

```bash
IP=$(gcloud compute forwarding-rules describe www-rule \
    --region=us-east1 --format="value(IPAddress)")

while true; do curl -s -m 2 "http://$IP"; sleep 1; done
```

```powershell
$ip = gcloud compute forwarding-rules describe www-rule `
    --region=us-east1 --format="value(IPAddress)"

while ($true) {
    (Invoke-WebRequest -Uri "http://$ip" -TimeoutSec 2).Content
    Start-Sleep -Seconds 1
}
```

Die Ausgabe wechselt zwischen `web1`, `web2` und `web3`. Abbrechen mit `Strg+C`.

Übrigens kein striktes Round Robin: Dieser Balancer bildet einen Hash über ein 5-Tupel aus Quell-IP, Quell-Port, Ziel-IP, Ziel-Port und Protokoll, um ein Backend zu wählen. Gleiche Verbindung, gleiches Backend. Deshalb bleibt ein Browser-Reload oft auf einem Server hängen, während `curl` — jedes Mal neuer Quell-Port — durchrotiert.

---

## Teil 2: Ein globaler Application Load Balancer

Jetzt die Layer-7-Variante. Der [globale externe Application Load Balancer](https://cloud.google.com/load-balancing/docs/https) läuft auf Googles Edge-Netzwerk: eine IP-Adresse, weltweit per Anycast angekündigt, und Nutzer werden vom nächstgelegenen Point of Presence bedient.

### Schritt 1 — Ein Instance Template

Statt VMs einzeln zu bauen, definieren wir eine Blaupause.

```bash
gcloud compute instance-templates create lb-backend-template \
    --machine-type=e2-medium \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=allow-health-check \
    --metadata=startup-script='#!/bin/bash
      apt-get update
      apt-get install apache2 -y
      a2ensite default-ssl
      a2enmod ssl
      vm_hostname="$(curl -H "Metadata-Flavor:Google" \
        http://169.254.169.254/computeMetadata/v1/instance/name)"
      echo "Page served from: $vm_hostname" | tee /var/www/html/index.html
      systemctl restart apache2'
```

Beachte, wie der Hostname geholt wird: `169.254.169.254` ist der [Metadata-Server](https://cloud.google.com/compute/docs/metadata/overview), eine Link-Local-Adresse ([RFC 3927](https://www.rfc-editor.org/rfc/rfc3927)), erreichbar aus jeder GCE-Instanz heraus. Er beantwortet Fragen über die VM, auf der er läuft — Name, Zone, Projekt, Service-Account-Tokens. Der Header `Metadata-Flavor: Google` ist Pflicht; er existiert, um den Endpunkt gegen naive Cross-Site-Request-Forgery zu immunisieren.

Ein [Instance Template](https://cloud.google.com/compute/docs/instance-templates) ist unveränderlich. Zum Ändern erstellst du ein neues — was für reproduzierbare Infrastruktur genau das gewünschte Verhalten ist.

Jetzt eine **Managed Instance Group** (MIG) daraus erstellen:

```bash
gcloud compute instance-groups managed create lb-backend-group \
    --template=lb-backend-template \
    --size=2 \
    --zone=us-east1-d
```

Eine [MIG](https://cloud.google.com/compute/docs/instance-groups) hält die gewünschte Instanzanzahl aufrecht. Löschst du eine VM von Hand, erstellt die Gruppe sie neu. Setzt du `--size=50`, baut sie 48 weitere. Mit angehängtem Autoscaler passt sie die Anzahl selbstständig an die Last an.

### Schritt 2 — Firewall für Googles Health Checker

```bash
gcloud compute firewall-rules create fw-allow-health-check \
    --network=default \
    --action=allow \
    --direction=ingress \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=allow-health-check \
    --rules=tcp:80
```

Diese beiden CIDR-Bereiche gehören Googles Health-Check-Probern. Sie sind dokumentiert, fest und in jedem Projekt identisch — siehe [Probe-IP-Bereiche und Firewall-Regeln](https://cloud.google.com/load-balancing/docs/health-check-concepts#ip-ranges). Auch der Traffic vom globalen Application Load Balancer zu deinen Backends kommt aus diesen Bereichen, diese eine Regel deckt also beides ab.

Diese Regel zu vergessen ist der mit Abstand häufigste Grund, warum ein frisch gebauter Application Load Balancer `502 Server Error` liefert: Die Backends sind gesund, aber jede Health-Probe wird verworfen — also hält der Balancer alle für tot.

### Schritt 3 — Den Balancer zusammensetzen

Sechs Ressourcen, jede zeigt auf die vorherige:

```bash
# 1. Globale IP-Adresse reservieren
gcloud compute addresses create lb-ipv4-1 \
    --ip-version=IPV4 \
    --global

# 2. Health Check
gcloud compute health-checks create http http-basic-check \
    --port=80

# 3. Backend Service — das Routing-Ziel
gcloud compute backend-services create web-backend-service \
    --protocol=HTTP \
    --port-name=http \
    --health-checks=http-basic-check \
    --global

# 4. Instance Group als Backend anhängen
gcloud compute backend-services add-backend web-backend-service \
    --instance-group=lb-backend-group \
    --instance-group-zone=us-east1-d \
    --global

# 5. URL Map — die Routing-Tabelle
gcloud compute url-maps create web-map-http \
    --default-service=web-backend-service

# 6. Target HTTP Proxy — terminiert Client-Verbindungen
gcloud compute target-http-proxies create http-lb-proxy \
    --url-map=web-map-http

# 7. Forwarding Rule — bindet die globale IP an den Proxy
gcloud compute forwarding-rules create http-content-rule \
    --address=lb-ipv4-1 \
    --global \
    --target-http-proxy=http-lb-proxy \
    --ports=80
```

### Der Weg einer Anfrage

```text
Client
  │
  ▼
Forwarding Rule      "IP 34.x.x.x, Port 80 — gehört mir"
  │
  ▼
Target HTTP Proxy    terminiert TCP + TLS, parst den HTTP-Request
  │
  ▼
URL Map              "welcher Backend Service bedient diesen Pfad?"
  │
  ▼
Backend Service      Balancing-Policy, Session-Affinity, Health-Status
  │
  ▼
Instance Group       eine gesunde VM antwortet
```

Jede Kiste hat genau eine Aufgabe, und jede ist unabhängig austauschbar. Das ist das ganze Design:

1. Die **Forwarding Rule** besitzt IP und Port.
2. Der **Target Proxy** terminiert die Client-Verbindung und parst HTTP.
3. Die **URL Map** entscheidet, welcher Backend Service diesen Pfad bedient. Aktuell geht jeder Pfad an `--default-service`, aber hier würde sich `/api/*` von `/static/*` trennen. Siehe [URL-Map-Konzepte](https://cloud.google.com/load-balancing/docs/url-map-concepts).
4. Der **Backend Service** hält die Policy: Balancing-Modus, Session-Affinity, Timeouts, Health Checks.
5. Die **Instance Group** liefert die tatsächlichen VMs.

HTTPS statt HTTP gewünscht? Schritt 6 gegen einen `target-https-proxies` mit angehängtem [SSL-Zertifikat](https://cloud.google.com/load-balancing/docs/ssl-certificates) tauschen. Der Rest der Kette bleibt unverändert.

### Testen

Die IP zu bekommen geht sofort. Dass der Balancer funktioniert, nicht: Eine globale Forwarding Rule über Googles Edge zu propagieren dauert **mehrere Minuten**, und `404`- oder `502`-Antworten in diesem Zeitfenster sind normal.

```bash
gcloud compute forwarding-rules describe http-content-rule \
    --global --format="value(IPAddress)"
```

```powershell
gcloud compute forwarding-rules describe http-content-rule `
    --global --format="value(IPAddress)"
```

`http://IP_ADRESSE` im Browser öffnen. Du solltest `Page served from: lb-backend-group-xxxx` sehen. Ein paar Mal neu laden, dann wechselt der Hostname.

---

## Aufräumen — nicht überspringen

Load Balancer, statische IPs und VMs werden stündlich abgerechnet, egal ob du sie nutzt. In umgekehrter Abhängigkeitsreihenfolge löschen — GCP weigert sich, eine Ressource zu löschen, auf die noch etwas zeigt.

```bash
# Globaler Application Load Balancer
gcloud compute forwarding-rules delete http-content-rule --global --quiet
gcloud compute target-http-proxies delete http-lb-proxy --quiet
gcloud compute url-maps delete web-map-http --quiet
gcloud compute backend-services delete web-backend-service --global --quiet
gcloud compute health-checks delete http-basic-check --quiet
gcloud compute instance-groups managed delete lb-backend-group --zone=us-east1-d --quiet
gcloud compute instance-templates delete lb-backend-template --quiet
gcloud compute addresses delete lb-ipv4-1 --global --quiet
gcloud compute firewall-rules delete fw-allow-health-check --quiet

# Regionaler Network Load Balancer
gcloud compute forwarding-rules delete www-rule --region=us-east1 --quiet
gcloud compute target-pools delete www-pool --region=us-east1 --quiet
gcloud compute http-health-checks delete basic-check --quiet
gcloud compute addresses delete network-lb-ip-1 --region=us-east1 --quiet
gcloud compute firewall-rules delete www-firewall-network-lb --quiet
gcloud compute instances delete web1 web2 web3 --zone=us-east1-d --quiet
```

Danach prüfen, dass nichts übrig ist:

```bash
gcloud compute instances list
gcloud compute forwarding-rules list
gcloud compute addresses list
```

```powershell
gcloud compute instances list
gcloud compute forwarding-rules list
gcloud compute addresses list
```

Eine reservierte statische IP, die an nichts hängt, kostet *mehr* als eine angehängte — Google berechnet das Horten knapper Adressen. Nach jedem Experiment `gcloud compute addresses list` prüfen.

---

## Fazit

- **Layer 4 leitet weiter, Layer 7 versteht.** Network Load Balancer für rohen TCP/UDP-Durchsatz und Erhalt der Client-IP; Application Load Balancer, wenn das Routing vom Request selbst abhängt.
- **Die Kette ist immer dieselbe:** IP → Forwarding Rule → (Proxy → URL Map) → Backend → Instanzen. Wer diese Kette einmal sieht, ordnet jeden `gcloud compute`-Befehl sofort ein.
- **Health Checks sind nicht optional.** Ohne die passende Firewall-Regel für `130.211.0.0/22` und `35.191.0.0/16` sieht jedes Backend tot aus und du bekommst `502`.
- **Löschen, was du baust.** Vergessene Load Balancer sind einer der zuverlässigsten Wege zu einer überraschenden Cloud-Rechnung.

Das alles von Hand zu machen ist der richtige Weg, es zu lernen. Es ist der falsche Weg, es zu betreiben — die nächsten Schritte heißen Terraform oder [Config Connector](https://cloud.google.com/config-connector/docs/overview), damit Infrastruktur in der Versionskontrolle liegt statt in der Shell-History.

Als Nächstes in dieser Serie: was passiert, wenn zwei VMs nicht mehr reichen — Autoscaling und health-basierter Instanzaustausch in Managed Instance Groups.

## Quellen

- [Cloud Load Balancing Übersicht](https://cloud.google.com/load-balancing/docs/load-balancing-overview) — Google Cloud Docs
- [Externer Passthrough Network Load Balancer](https://cloud.google.com/load-balancing/docs/network) — Google Cloud Docs
- [Globaler externer Application Load Balancer](https://cloud.google.com/load-balancing/docs/https) — Google Cloud Docs
- [Health-Check-Konzepte](https://cloud.google.com/load-balancing/docs/health-check-concepts) — Google Cloud Docs
- [Instance Groups](https://cloud.google.com/compute/docs/instance-groups) — Google Cloud Docs
- [gcloud compute Referenz](https://cloud.google.com/sdk/gcloud/reference/compute) — Google Cloud Docs
- [RFC 9110 — HTTP Semantics](https://www.rfc-editor.org/rfc/rfc9110)
- [RFC 9293 — Transmission Control Protocol](https://www.rfc-editor.org/rfc/rfc9293)
- [RFC 3927 — Dynamic Configuration of IPv4 Link-Local Addresses](https://www.rfc-editor.org/rfc/rfc3927)
