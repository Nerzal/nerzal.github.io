---
draft: false
title: "Event Storming"
date: 2023-02-26T14:46:14+01:00
tags: ["ddd", "requirements engineering", "bounded context"]
featured_image: "img/event-storming.png"
toc: true
---

## What is Event Storming?

Event storming is a collaborative modeling technique used in domain-driven design (DDD) to explore and understand complex business domains. It involves bringing together a diverse group of stakeholders, including developers, domain experts, and business analysts, to collaborate on the creation of a visual representation of a business process or system.

In event storming, the participants work together to **identify events** that occur within the system or process, and then organize these events into a **timeline** that represents the **flow of actions** and outcomes. These events can include user actions, system responses, and any other activities or processes that occur within the domain being modeled.

As the events are identified and organized, the participants can begin to identify and define the different components of the system, including aggregates, entities, and value objects. 

**Aggregates** are collections of entities that are treated as a single unit within the system, while **entities** are individual objects with a unique identity and state. **Value objects**, on the other hand, are objects that represent a value or concept within the domain, but do not have a unique identity.

The visual representation created through event storming can be used as a starting point for further discussion and refinement, helping to ensure that all stakeholders have a shared understanding of the business domain and the processes that occur within it. This shared understanding can then be used to guide the development of software systems that meet the needs of the business and its stakeholders.

## When to use?
A good list of examples when to use event storming is provided by [eventstorming.com](https://www.eventstorming.com/)

> It (eventstorming) comes in different flavours, that can be used in different scenarios:
>
> 1. to assess health of an existing line of business and to discover the most effective areas for improvements;
> 2. to explore the viability of a new startup business model;
> 3. to envision new services, that maximise positive outcomes to every party involved;
> 4. to design clean and maintainable Event-Driven software, to support rapidly evolving businesses.

## Where to start?

You might want to design a completely new software system, or just a new feature for an existing software system.
Now you have some Domain Experts, that perfectly understand the requirements and implications.
Gather domain experts, developers and business analysts together in a room to answer all questions.

### How many people do we need?

Apply the 2 Pizza rule.

The 2 pizza rule is a concept introduced by Jeff Bezos, the founder of Amazon, regarding the optimal number of attendees in a meeting. The rule states that the ideal number of people for a productive meeting is no more than the number of people who can be fed by two pizzas. In other words, if you can't feed everyone in the meeting with two pizzas, the group is too large.

The reason for this rule is that having too many people in a meeting can often lead to inefficiency and a lack of productivity. Large meetings tend to be less focused and more prone to distractions and tangential conversations. It can also be more difficult for individuals to contribute meaningfully to the discussion and to have their voices heard.

## Moderator (Facilitator)

The Moderator is called Facilitator in DDDs event storming context.

The Facilitator has 2 tasks:

1. Lead the meeting
    1. Start the meeting by asking questions
    2. Sticks first note to the wall to show the way
2. Guide the modeling effort
    1. Asks question to better understand the emerging model
    2. Ensure ideas are represented accurately 
    3. Keep focused and moves ahead

## Requirements

The requirements for this meeting depend on the kind of meeting. Onsite and Remote meetings do have different requirements.

### Onsite

You typically want to have a really large whiteboard, whiteboard marker and sticky notes.

### Remote

You'll need some drawing tool, that allows fast iteration of inputs.
You could use [excalidraw](https://excalidraw.com/) or [draw.io](https://draw.io) for example.

## Workflow

1. Identify all relevant domain events.
2. Find what causes the event.
    1. User action? (command) Add note.
    2. Asynchronous event? Add note.
    3. Another event? Add note.
3. Look at the modeling surface as a timeline
    1. Add notes
4. Identify bounded contexts and aggregates in each context

## Benefits

After the event storming session you should have achieved the following:

1. Comprehensive vision of the business domain
2. Identified the bounded contexts and aggregates in each context
    1. Aggregates handle commands and control persistence
3. Identified the types of users in the system
    1. Who runs commands and why?
4. Identified where UX is critical
    1. Sketches of the UI