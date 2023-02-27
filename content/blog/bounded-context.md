---
draft: false
title: "Bounded Context"
date: 2023-02-26T17:46:14+01:00
tags: ["ddd", "requirements engineering", "bounded context"]
featured_image: "img/event-storming.png"
toc: true
---

### What is a bounded context?

Bounded contexts are one of the key concepts in Domain-Driven Design, and event storming is a useful technique for identifying and defining bounded contexts.

Consider a fictional e-commerce website that sells clothing. One possible bounded context within this domain might be "Order Management." This bounded context would be responsible for managing the process of creating and fulfilling customer orders.

Within the Order Management bounded context, there might be a **set of domain events**, such as "Order Placed," "Payment Received," and "Order Shipped." There might also be a set of domain entities, such as "Order," "Product," and "Customer."

The Order Management bounded context might have its **own set of rules and language** that are specific to order management, such as rules for calculating shipping costs, validating payment information, and handling returns.

Other bounded contexts within the e-commerce domain might include:

- Product Catalog (responsible for managing the catalog of available products)
- Customer Management (responsible for managing customer accounts and profiles)
- Inventory Management (responsible for tracking inventory levels and managing stock).

Each of these bounded contexts would have its own set of domain events, entities, rules, and language that are specific to its area of responsibility, and they would **interact** with each other **through** well-defined **interfaces**. By defining these bounded contexts, we can create a better understanding of the domain and design more effective software solutions.

### Identifying bounded contexts

Here are the steps to follow in an event storming meeting to find bounded contexts:

1. Identify the domain events: Start by identifying the events that occur within the domain. These events should be identified in collaboration with domain experts.
2. Group the events: Once you have a list of events, group them based on their relationships. Events that have a cause-and-effect relationship can be grouped together.
3. Define the contexts: Next, examine each group of events and identify the context in which they occur. A bounded context is a well-defined area of the domain that has its own language, rules, and concepts. Each group of events may correspond to one or more bounded contexts.
4. Identify the boundaries: Once you have identified the bounded contexts, you need to define their boundaries. This involves identifying the interactions between the contexts and any overlaps or shared concepts.
5. Refine the boundaries: Finally, refine the boundaries of the bounded contexts based on feedback from domain experts. This may involve splitting or merging contexts as needed.