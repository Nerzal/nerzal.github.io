---
draft: false
title: "Event Storming"
date: 2023-02-26T14:46:14+01:00
tags: ["ddd", "requirements engineering", "bounded context"]
description: "Eine Einführung in Event Storming: eine kollaborative Modellierungstechnik zum Verstehen komplexer Geschäftsbereiche und -prozesse."
images: ["img/event-storming.png"]
featured_image: "img/event-storming.png"
toc: true
---

## Was ist Event Storming?

Event Storming ist eine kollaborative Modellierungstechnik, die im Domain-Driven Design (DDD) verwendet wird, um komplexe Geschäftsbereiche zu erkunden und zu verstehen. Dabei bringt man eine diverse Gruppe von Stakeholdern zusammen – darunter Entwickler, Domänenexperten und Business-Analysten –, um gemeinsam eine visuelle Darstellung eines Geschäftsprozesses oder -systems zu erarbeiten.

Beim Event Storming arbeiten die Teilnehmer zusammen, um **Ereignisse** (Events) zu identifizieren, die innerhalb des Systems oder Prozesses auftreten, und ordnen diese dann in einer **Zeitleiste** an, die den **Ablauf von Aktionen** und Ergebnissen darstellt. Diese Ereignisse können Benutzeraktionen, Systemreaktionen und alle anderen Aktivitäten oder Prozesse umfassen, die im modellierten Bereich stattfinden.

Während die Ereignisse identifiziert und angeordnet werden, können die Teilnehmer beginnen, die verschiedenen Komponenten des Systems zu identifizieren und zu definieren, darunter Aggregates, Entities und Value Objects.

**Aggregates** sind Sammlungen von Entities, die innerhalb des Systems als eine einzige Einheit behandelt werden, während **Entities** einzelne Objekte mit einer eindeutigen Identität und einem Zustand sind. **Value Objects** hingegen sind Objekte, die einen Wert oder ein Konzept innerhalb der Domäne repräsentieren, aber keine eindeutige Identität besitzen.

Die durch Event Storming erstellte visuelle Darstellung kann als Ausgangspunkt für weitere Diskussionen und Verfeinerungen dienen. Sie hilft sicherzustellen, dass alle Stakeholder ein gemeinsames Verständnis des Geschäftsbereichs und der darin ablaufenden Prozesse haben. Dieses gemeinsame Verständnis kann dann genutzt werden, um Softwaresysteme zu entwickeln, die den Bedürfnissen des Unternehmens und seiner Stakeholder gerecht werden.

## Wann einsetzen?

Eine gute Liste von Beispielen, wann Event Storming eingesetzt werden sollte, liefert [eventstorming.com](https://www.eventstorming.com/):

> Es (Event Storming) gibt es in verschiedenen Ausprägungen, die in unterschiedlichen Szenarien verwendet werden können:
>
> 1. um den Zustand eines bestehenden Geschäftsbereichs zu beurteilen und die wirksamsten Verbesserungsbereiche zu entdecken;
> 2. um die Tragfähigkeit eines neuen Startup-Geschäftsmodells zu erkunden;
> 3. um neue Dienste zu entwerfen, die für alle Beteiligten positive Ergebnisse maximieren;
> 4. um saubere und wartbare Event-Driven-Software zu entwickeln, die schnell wachsende Unternehmen unterstützt.

## Wo anfangen?

Du möchtest vielleicht ein komplett neues Softwaresystem entwerfen oder nur ein neues Feature für ein bestehendes Softwaresystem. Du hast einige Domänenexperten, die die Anforderungen und Auswirkungen perfekt verstehen. Versammle Domänenexperten, Entwickler und Business-Analysten in einem Raum, um alle Fragen zu beantworten.

### Wie viele Personen brauchen wir?

Wende die 2-Pizza-Regel an.

Die 2-Pizza-Regel ist ein von Jeff Bezos, dem Gründer von Amazon, eingeführtes Konzept bezüglich der optimalen Teilnehmerzahl in einem Meeting. Die Regel besagt, dass die ideale Anzahl von Personen für ein produktives Meeting nicht größer sein sollte als die Anzahl von Personen, die mit zwei Pizzen gesättigt werden können. Mit anderen Worten: Wenn man nicht alle Meeting-Teilnehmer mit zwei Pizzen versorgen kann, ist die Gruppe zu groß.

Der Grund für diese Regel liegt darin, dass zu viele Personen in einem Meeting oft zu Ineffizienz und mangelnder Produktivität führen. Große Meetings neigen dazu, weniger fokussiert zu sein und sind anfälliger für Ablenkungen und Nebenthemen. Außerdem ist es für Einzelne schwieriger, sinnvoll zur Diskussion beizutragen und Gehör zu finden.

## Moderator (Facilitator)

Der Moderator wird im DDD-Event-Storming-Kontext Facilitator genannt.

Der Facilitator hat 2 Aufgaben:

1. Das Meeting leiten
    1. Das Meeting mit Fragen eröffnen
    2. Den ersten Zettel an die Wand kleben, um den Weg zu zeigen
2. Die Modellierungsarbeit begleiten
    1. Fragen stellen, um das entstehende Modell besser zu verstehen
    2. Sicherstellen, dass Ideen korrekt dargestellt werden
    3. Den Fokus bewahren und vorantreiben

## Anforderungen

Die Anforderungen für dieses Meeting hängen von der Art des Meetings ab. Vor-Ort- und Remote-Meetings haben unterschiedliche Anforderungen.

### Vor Ort

Typischerweise braucht man ein sehr großes Whiteboard, Whiteboard-Marker und Haftnotizen.

### Remote

Man benötigt ein Zeichen-Tool, das schnelle Eingabeiterationen ermöglicht. Zum Beispiel eignen sich [Excalidraw](https://excalidraw.com/) oder [draw.io](https://draw.io).

## Arbeitsablauf

1. Alle relevanten Domänen-Events identifizieren.
2. Herausfinden, was das Event ausgelöst hat.
    1. Benutzeraktion? (Command) Notiz hinzufügen.
    2. Asynchrones Event? Notiz hinzufügen.
    3. Ein anderes Event? Notiz hinzufügen.
3. Die Modellierungsfläche als Zeitleiste betrachten
    1. Notizen hinzufügen
4. Bounded Contexts und Aggregates in jedem Context identifizieren

### Domänen-Events identifizieren

Die Domänenexperten identifizieren die Domänen-Events. Die Events werden in der Vergangenheitsform formuliert.

Beispiele:

1. **Termin vereinbart**
2. **Zahlung erhalten**
3. **Auf einen Patienten wartend**

Fokussiere dich in diesem Stadium nicht auf alle Werte, aus denen ein Termin besteht, wie Datum, Patientenname usw., sondern konzentriere dich auf das Verhalten.

## Vorteile

Nach der Event-Storming-Sitzung solltest du Folgendes erreicht haben:

1. Umfassende Vision des Geschäftsbereichs
2. Identifizierte Bounded Contexts und Aggregates in jedem Context
    1. Aggregates verarbeiten Commands und kontrollieren die Persistenz
3. Identifizierte Benutzertypen im System
    1. Wer führt Commands aus und warum?
4. Identifiziert, wo UX kritisch ist
    1. Skizzen der Benutzeroberfläche
