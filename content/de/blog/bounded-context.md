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

## Was ist ein Bounded Context?

Bounded Contexts sind ein Kernkonzept im Domain-Driven Design (DDD) und dienen als explizite Grenzen innerhalb eines größeren Domänenmodells. Sie definieren einen spezifischen Bereich, in dem ein bestimmtes Modell (und seine zugehörige Ubiquitous Language) konsistent und anwendbar ist. Außerhalb dieser Grenze können Begriffe und Konzepte unterschiedliche Bedeutungen haben oder sogar irrelevant sein.

Stell dir ein großes Unternehmen vor. Der Begriff „Kunde" kann für die Vertriebsabteilung etwas anderes bedeuten (ein Lead, ein Interessent), für die Support-Abteilung etwas anderes (jemand mit einem offenen Ticket) und für die Buchhaltung wieder etwas anderes (eine Einheit mit einer offenen Rechnung). Jede dieser Interpretationen existiert innerhalb ihres eigenen Bounded Context, in dem der Begriff „Kunde" eine präzise, eindeutige Bedeutung hat.

[Event Storming](/de/blog/event-storming/) – wie im vorherigen Beitrag besprochen – ist eine unglaublich nützliche Technik, um diese Bounded Contexts kollaborativ zu identifizieren und zu definieren.

### Beispiel: Eine E-Commerce-Website

Betrachten wir eine fiktive E-Commerce-Website, die Kleidung verkauft. Der übergeordnete Geschäftsbereich ist „E-Commerce", aber darin können wir mehrere unterschiedliche Bounded Contexts identifizieren:

*   **Order Management Context**:
    *   **Verantwortung**: Verwaltung des Prozesses der Erstellung, Verarbeitung und Erfüllung von Kundenbestellungen.
    *   **Ubiquitous Language**: Begriffe wie „Bestellung aufgegeben", „Zahlung erhalten", „Bestellung versandt", „Rückgabe eingeleitet", „Erstattung verarbeitet". Entities umfassen „Bestellung", „Bestellposition", „Lieferung".
    *   **Regeln**: Versandkosten berechnen, Zahlung validieren, Rückgaben bearbeiten, Bestellstatusübergänge verwalten.

*   **Product Catalog Context**:
    *   **Verantwortung**: Verwaltung der Anzeige, Suche und Details verfügbarer Produkte.
    *   **Ubiquitous Language**: „Produkt", „SKU", „Kategorie", „Attribut", „Preis", „Beschreibung", „Bild".
    *   **Regeln**: Produktverfügbarkeit, Preisregeln (z.B. Rabatte), Suchindizierung.

*   **Customer Management Context**:
    *   **Verantwortung**: Verwaltung von Kundenkonten, Profilen und persönlichen Informationen.
    *   **Ubiquitous Language**: „Kunde", „Benutzerkonto", „Adresse", „Kontaktdaten", „Treuepunkte".
    *   **Regeln**: Benutzerauthentifizierung, Profilaktualisierungen, Datenschutzeinstellungen.

*   **Inventory Management Context**:
    *   **Verantwortung**: Bestandsverfolgung, Lagerverwaltung und Sicherstellung der Produktverfügbarkeit.
    *   **Ubiquitous Language**: „Lagerelement", „Lager", „Verfügbare Menge", „Nachbestellungsalarm", „Bestandsanpassung".
    *   **Regeln**: Bestandsreservierung, Nachbestellungspunkte, Bestandsabgleich.

Jeder dieser Bounded Contexts hat sein eigenes, unterschiedliches Modell, eigene Regeln und vor allem seine eigene **Ubiquitous Language**. Sie interagieren miteinander über klar definierte Schnittstellen – oft über Events oder APIs – anstatt eine einzige, monolithische Datenbank oder ein Domänenmodell zu teilen.

### Warum Bounded Contexts wichtig sind

Das Definieren von Bounded Contexts bietet erhebliche Vorteile in der Software-Entwicklung:

1.  **Klarheit und weniger Mehrdeutigkeit**: Indem Begriffen innerhalb eines bestimmten Contexts präzise Bedeutungen gegeben werden, werden Missverständnisse unter Stakeholdern (Entwicklern, Domänenexperten, Business-Analysten) beseitigt.
2.  **Verbesserte Wartbarkeit**: Änderungen innerhalb eines Bounded Context schlagen mit geringerer Wahrscheinlichkeit auf die Funktionalität eines anderen durch, da ihre internen Modelle isoliert sind.
3.  **Skalierbarkeit und Autonomie**: Bounded Contexts passen oft gut zu Microservices-Architekturen und ermöglichen es Teams, unabhängig an verschiedenen Teilen des Systems zu arbeiten und diese separat zu deployen.
4.  **Bessere Kommunikation**: Die Ubiquitous Language fördert ein gemeinsames Verständnis, macht die Kommunikation effizienter und reduziert Missverständnisse.
5.  **Strategisches Design**: Es erzwingt einen bewussten Design-Prozess, der hilft, die Kerndomänen und ihre Beziehungen zu identifizieren.

### Bounded Contexts mit Event Storming identifizieren

Event Storming ist ein hocheffektives, kollaboratives Workshop-Format zur Entdeckung von Bounded Contexts. Hier ist ein verfeinerter Ansatz, um sie in einer Event-Storming-Session zu finden:

1.  **Domänen-Events identifizieren (Orange Haftnotizen)**: Beginne damit, alle bedeutsamen Ereignisse zu identifizieren, die innerhalb des Systems auftreten. Diese sollten Verben in der Vergangenheitsform sein (z.B. „Bestellung aufgegeben", „Artikel in den Warenkorb gelegt"). Platziere sie chronologisch auf einer großen Modellierungsfläche.

2.  **Commands finden (Blaue Haftnotizen)**: Identifiziere für jedes Event den Command, der es ausgelöst hat (z.B. der Command „Bestellung aufgeben" führt zum Event „Bestellung aufgegeben").

3.  **Aggregates identifizieren (Gelbe Haftnotizen)**: Gruppiere verwandte Events und Commands um die Entities, die die Commands ausführen und die Events erzeugen. Das sind deine Aggregates (z.B. ein „Bestellungs"-Aggregate führt „Bestellung aufgeben" aus und erzeugt „Bestellung aufgegeben").

4.  **Read Models/Views entdecken (Grüne Haftnotizen)**: Identifiziere, wo Daten für Benutzeroberflächen oder Berichte benötigt werden (z.B. „Bestellhistorie-Ansicht" benötigt Daten aus „Bestellung aufgegeben"-Events).

5.  **Swimlanes für Bounded Contexts zeichnen**: Wenn Muster entstehen, wirst du Cluster von Events, Commands und Aggregates bemerken, die eine gemeinsame Sprache und einen gemeinsamen Zweck teilen. Zeichne große Linien oder verwende verschiedenfarbige Bereiche, um diese Cluster abzugrenzen. Jeder Cluster repräsentiert einen potenziellen Bounded Context.

6.  **Die Ubiquitous Language für jeden Context definieren**: Definiere für jeden identifizierten Bounded Context explizit die Bedeutung von Schlüsselbegriffen innerhalb dieser Grenze. Diskutiere, wie sich diese Begriffe in anderen Contexts unterscheiden könnten.

7.  **Context Map-Beziehungen identifizieren**: Sobald Bounded Contexts identifiziert sind, diskutiere, wie sie interagieren. Gängige Muster sind:
    *   **Customer-Supplier**: Ein Context liefert Daten/Dienste für einen anderen.
    *   **Shared Kernel**: Zwei Contexts teilen einen kleinen, klar definierten Teil von Code/Modell.
    *   **Anti-Corruption Layer (ACL)**: Eine Übersetzungsschicht zwischen zwei Contexts, um zu verhindern, dass das Modell eines Contexts vom anderen „korrumpiert" wird.
    *   **Published Language**: Ein Context veröffentlicht eine klar definierte API oder einen Event-Stream für andere.

8.  **Verfeinern und iterieren**: Die Entdeckung von Bounded Contexts ist ein iterativer Prozess. Basierend auf Feedback von Domänenexperten und weiterer Analyse könntest du Contexts aufteilen, zusammenführen oder umbenennen, um ein klareres, kohärenteres Design zu erreichen.

Indem du diese Schritte befolgst, kannst du Event Storming effektiv nutzen, um die natürlichen Grenzen in deiner Domäne aufzudecken, was zu robusteren, wartbareren und skalierbaren Softwaresystemen führt.
