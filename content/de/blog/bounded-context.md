---
draft: false
title: "Bounded Context"
date: 2023-02-26T17:46:14+01:00
tags: ["ddd", "requirements engineering", "bounded context"]
description: "Ein tiefer Einblick in Bounded Contexts im Domain-Driven Design: Wie Grenzen definiert und Domänenlogik effektiv verwaltet werden."
images: ["img/event-storming.png"]
featured_image: "img/event-storming.png"
toc: true
---

{{< tldr >}}
* Ein Bounded Context im Domain-Driven Design (DDD) ist eine explizite Grenze innerhalb eines größeren Domänenmodells, in der ein Modell und seine Ubiquitous Language konsistent bleiben.
* Derselbe Begriff kann in verschiedenen Bounded Contexts Verschiedenes bedeuten: Ein „Kunde“ ist für den Vertrieb ein Lead, für den Support jemand mit offenem Ticket und für die Buchhaltung eine Einheit mit offener Rechnung.
* Bounded Contexts interagieren über klar definierte Schnittstellen wie Events oder APIs, statt eine einzige, monolithische Datenbank oder ein Domänenmodell zu teilen.
* Event Storming findet Bounded Contexts, indem es Events, Commands und Aggregates mit gemeinsamer Sprache und gemeinsamem Zweck zu Clustern gruppiert und Swimlanes um jeden Cluster zieht.
* Gängige Context-Map-Beziehungen zwischen Bounded Contexts sind Customer-Supplier, Shared Kernel, Anti-Corruption Layer und Published Language.
{{< /tldr >}}

## Was ist ein Bounded Context?

Bounded Contexts sind ein Kernkonzept im Domain-Driven Design (DDD). Ein Bounded Context ist eine explizite Grenze innerhalb eines größeren Domänenmodells: der Bereich, in dem ein bestimmtes Modell (und seine zugehörige Ubiquitous Language) konsistent und anwendbar ist. Außerhalb dieser Grenze können Begriffe und Konzepte unterschiedliche Bedeutungen haben oder sogar irrelevant sein.

Stell dir ein großes Unternehmen vor. Der Begriff „Kunde“ kann für die Vertriebsabteilung etwas anderes bedeuten (ein Lead, ein Interessent), für die Support-Abteilung etwas anderes (jemand mit einem offenen Ticket) und für die Buchhaltung wieder etwas anderes (eine Einheit mit einer offenen Rechnung). Jede dieser Interpretationen existiert innerhalb ihres eigenen Bounded Context, in dem der Begriff „Kunde“ eine präzise, eindeutige Bedeutung hat.

[Event Storming](/de/blog/event-storming/), das ich im vorherigen Beitrag beschrieben habe, ist eine sehr nützliche Technik, um diese Bounded Contexts kollaborativ zu identifizieren und zu definieren.

### Beispiel: Eine E-Commerce-Website

Betrachten wir eine fiktive E-Commerce-Website, die Kleidung verkauft. Der übergeordnete Geschäftsbereich ist „E-Commerce“, aber darin können wir mehrere unterschiedliche Bounded Contexts identifizieren:

*   **Order Management Context**:
    *   Verantwortung: Verwaltung des Prozesses der Erstellung, Verarbeitung und Abwicklung von Kundenbestellungen.
    *   Ubiquitous Language: Begriffe wie „Bestellung aufgegeben“, „Zahlung erhalten“, „Bestellung versandt“, „Rückgabe eingeleitet“, „Erstattung verarbeitet“. Entities umfassen „Bestellung“, „Bestellposition“, „Lieferung“.
    *   Regeln: Versandkosten berechnen, Zahlung validieren, Rückgaben bearbeiten, Bestellstatusübergänge verwalten.

*   **Product Catalog Context**:
    *   Verantwortung: Verwaltung der Anzeige, Suche und Details verfügbarer Produkte.
    *   Ubiquitous Language: „Produkt“, „SKU“, „Kategorie“, „Attribut“, „Preis“, „Beschreibung“, „Bild“.
    *   Regeln: Produktverfügbarkeit, Preisregeln (z. B. Rabatte), Suchindizierung.

*   **Customer Management Context**:
    *   Verantwortung: Verwaltung von Kundenkonten, Profilen und persönlichen Informationen.
    *   Ubiquitous Language: „Kunde“, „Benutzerkonto“, „Adresse“, „Kontaktdaten“, „Treuepunkte“.
    *   Regeln: Benutzerauthentifizierung, Profilaktualisierungen, Datenschutzeinstellungen.

*   **Inventory Management Context**:
    *   Verantwortung: Bestandsverfolgung, Lagerverwaltung und Sicherstellung der Produktverfügbarkeit.
    *   Ubiquitous Language: „Lagerartikel“, „Lager“, „Verfügbare Menge“, „Nachbestellungsalarm“, „Bestandsanpassung“.
    *   Regeln: Bestandsreservierung, Nachbestellungspunkte, Bestandsabgleich.

Jeder dieser Bounded Contexts hat sein eigenes Modell, eigene Regeln und vor allem seine eigene **Ubiquitous Language**. Sie interagieren miteinander über klar definierte Schnittstellen, oft über Events oder APIs, anstatt eine einzige, monolithische Datenbank oder ein Domänenmodell zu teilen.

### Warum Bounded Contexts wichtig sind

Bounded Contexts zu definieren hilft auf mehreren Ebenen:

1.  Klarheit und weniger Mehrdeutigkeit: Begriffe bekommen innerhalb eines Contexts eine präzise Bedeutung, dadurch reden Stakeholder (Entwickler, Domänenexperten, Business-Analysten) nicht mehr aneinander vorbei.
2.  Wartbarkeit: Änderungen innerhalb eines Bounded Context schlagen mit geringerer Wahrscheinlichkeit auf die Funktionalität eines anderen durch, da ihre internen Modelle isoliert sind.
3.  Skalierbarkeit und Autonomie: Bounded Contexts passen oft gut zu Microservices-Architekturen und ermöglichen es Teams, unabhängig an verschiedenen Teilen des Systems zu arbeiten und diese separat zu deployen.
4.  Kommunikation: Die Ubiquitous Language gibt allen dasselbe Vokabular. Dadurch werden Gespräche kürzer und Missverständnisse seltener.
5.  Strategisches Design: Du musst bewusst entwerfen, und dabei werden die Kerndomänen und ihre Beziehungen sichtbar.

### Bounded Contexts mit Event Storming identifizieren

Event Storming ist ein kollaboratives Workshop-Format, das sich gut eignet, um Bounded Contexts zu entdecken. In einer Session findest du sie mit diesen Schritten:

1.  **Domänen-Events identifizieren (Orange Haftnotizen)**: Beginne damit, alle relevanten Ereignisse zu identifizieren, die innerhalb des Systems auftreten. Diese sollten Verben in der Vergangenheitsform sein (z. B. „Bestellung aufgegeben“, „Artikel in den Warenkorb gelegt“). Platziere sie chronologisch auf einer großen Modellierungsfläche.

2.  **Commands finden (Blaue Haftnotizen)**: Identifiziere für jedes Event den Command, der es ausgelöst hat (z. B. der Command „Bestellung aufgeben“ führt zum Event „Bestellung aufgegeben“).

3.  **Aggregates identifizieren (Gelbe Haftnotizen)**: Gruppiere verwandte Events und Commands um die Entities, die die Commands ausführen und die Events erzeugen. Das sind deine Aggregates (z. B. ein „Bestellungs“-Aggregate führt „Bestellung aufgeben“ aus und erzeugt „Bestellung aufgegeben“).

4.  **Read Models/Views entdecken (Grüne Haftnotizen)**: Identifiziere, wo Daten für Benutzeroberflächen oder Berichte benötigt werden (z. B. „Bestellhistorie-Ansicht“ benötigt Daten aus „Bestellung aufgegeben“-Events).

5.  **Swimlanes für Bounded Contexts zeichnen**: Wenn Muster entstehen, wirst du Cluster von Events, Commands und Aggregates bemerken, die eine gemeinsame Sprache und einen gemeinsamen Zweck teilen. Zeichne große Linien oder verwende verschiedenfarbige Bereiche, um diese Cluster abzugrenzen. Jeder Cluster repräsentiert einen potenziellen Bounded Context.

6.  **Die Ubiquitous Language für jeden Context definieren**: Definiere für jeden identifizierten Bounded Context explizit die Bedeutung von Schlüsselbegriffen innerhalb dieser Grenze. Diskutiere, wie sich diese Begriffe in anderen Contexts unterscheiden könnten.

7.  **Context-Map-Beziehungen identifizieren**: Sobald Bounded Contexts identifiziert sind, diskutiere, wie sie interagieren. Gängige Muster sind:
    *   **Customer-Supplier**: Ein Context liefert Daten/Dienste für einen anderen.
    *   **Shared Kernel**: Zwei Contexts teilen einen kleinen, klar definierten Teil von Code/Modell.
    *   **Anti-Corruption Layer (ACL)**: Eine Übersetzungsschicht zwischen zwei Contexts, um zu verhindern, dass das Modell eines Contexts vom abweichenden Modell des anderen „korrumpiert“ wird.
    *   **Published Language**: Ein Context veröffentlicht eine klar definierte API oder einen Event-Stream für andere.

8.  **Verfeinern und iterieren**: Die Entdeckung von Bounded Contexts ist ein iterativer Prozess. Basierend auf Feedback von Domänenexperten und weiterer Analyse könntest du Contexts aufteilen, zusammenführen oder umbenennen, um ein klareres, kohärenteres Design zu erreichen.

Mit diesen Schritten deckst du per Event Storming die natürlichen Grenzen deiner Domäne auf. Software, die diesen Grenzen folgt, lässt sich leichter warten und skalieren.
