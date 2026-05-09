---
draft: false
title: "Bounded Context"
date: 2023-02-26T17:46:14+01:00
tags: ["ddd", "requirements engineering", "bounded context"]
description: "A deep dive into Bounded Contexts in Domain-Driven Design, exploring how to define boundaries and manage domain logic effectively."
images: ["img/event-storming.png"]
featured_image: "img/event-storming.png"
toc: true
---

### What is a bounded context?
Bounded Contexts are a core concept in Domain-Driven Design (DDD), serving as explicit boundaries within a larger domain model. They define a specific area where a particular model (and its associated ubiquitous language) is consistent and applicable. Outside this boundary, terms and concepts might have different meanings, or even be irrelevant.

Think of a large enterprise. The term "Customer" might mean one thing to the Sales department (a lead, a prospect), another to the Support department (someone with an open ticket), and yet another to the Billing department (an entity with an outstanding invoice). Each of these interpretations exists within its own Bounded Context, where the term "Customer" has a precise, unambiguous meaning.

Event Storming, as discussed in your previous post, is an incredibly useful technique for collaboratively identifying and defining these Bounded Contexts.

#### Example: An E-commerce Website

Let's consider a fictional e-commerce website that sells clothing. The overall business domain is "E-commerce," but within it, we can identify several distinct Bounded Contexts:

*   **Order Management Context**:
    *   **Responsibility**: Managing the process of creating, processing, and fulfilling customer orders.
    *   **Ubiquitous Language**: Terms like "Order Placed," "Payment Received," "Order Shipped," "Return Initiated," "Refund Processed." Entities include "Order," "OrderItem," "Shipment."
    *   **Rules**: Calculating shipping costs, validating payment, handling returns, managing order status transitions.

*   **Product Catalog Context**:
    *   **Responsibility**: Managing the display, search, and details of available products.
    *   **Ubiquitous Language**: "Product," "SKU," "Category," "Attribute," "Price," "Description," "Image."
    *   **Rules**: Product availability, pricing rules (e.g., discounts), search indexing.

*   **Customer Management Context**:
    *   **Responsibility**: Managing customer accounts, profiles, and personal information.
    *   **Ubiquitous Language**: "Customer," "User Account," "Address," "Contact Information," "Loyalty Points."
    *   **Rules**: User authentication, profile updates, privacy settings.

*   **Inventory Management Context**:
    *   **Responsibility**: Tracking stock levels, managing warehouses, and ensuring product availability.
    *   **Ubiquitous Language**: "Stock Item," "Warehouse," "Quantity On Hand," "Restock Alert," "Inventory Adjustment."
    *   **Rules**: Stock reservation, reorder points, inventory reconciliation.

Each of these Bounded Contexts has its own distinct model, rules, and, crucially, its own **ubiquitous language**. They interact with each other through well-defined interfaces, often using events or APIs, rather than sharing a single, monolithic database or domain model.

### Why Bounded Contexts Matter

Defining Bounded Contexts offers significant advantages in software development:

1.  **Clarity and Reduced Ambiguity**: By giving terms precise meanings within a specific context, it eliminates confusion among stakeholders (developers, domain experts, business analysts).
2.  **Improved Maintainability**: Changes within one Bounded Context are less likely to break functionality in another, as their internal models are isolated.
3.  **Scalability and Autonomy**: Bounded Contexts often align well with microservices architectures, allowing teams to work independently on different parts of the system and deploy them separately.
4.  **Better Communication**: The ubiquitous language fosters a shared understanding, making communication more efficient and reducing misunderstandings.
5.  **Strategic Design**: It forces a deliberate design process, helping to identify the core domains and their relationships.

### Identifying Bounded Contexts with Event Storming

Event Storming is a highly effective, collaborative workshop format for discovering Bounded Contexts. Here's a refined approach to finding them during an Event Storming session:

1.  **Identify Domain Events (Orange Stickies)**: Start by identifying all significant events that occur within the system. These should be past-tense verbs (e.g., "Order Placed," "Item Added to Cart"). Place them chronologically on a large modeling surface.

2.  **Find Commands (Blue Stickies)**: For each event, identify the command that caused it (e.g., "Place Order" command leads to "Order Placed" event).

3.  **Identify Aggregates (Yellow Stickies)**: Group related events and commands around the entities that execute the commands and emit the events. These are your aggregates (e.g., an "Order" aggregate handles "Place Order" and emits "Order Placed").

4.  **Discover Read Models/Views (Green Stickies)**: Identify where data is needed for user interfaces or reports (e.g., "Order History View" needs data from "Order Placed" events).

5.  **Draw Swimlanes for Bounded Contexts**: As patterns emerge, you'll notice clusters of events, commands, and aggregates that share a common language and purpose. Draw large lines or use different colored areas to delineate these clusters. Each cluster represents a potential Bounded Context.

6.  **Define the Ubiquitous Language for Each Context**: For each identified Bounded Context, explicitly define the meaning of key terms within that boundary. Discuss how these terms might differ in other contexts.

7.  **Identify Context Map Relationships**: Once Bounded Contexts are identified, discuss how they interact. Common patterns include:
    *   **Customer-Supplier**: One context provides data/services to another.
    *   **Shared Kernel**: Two contexts share a small, well-defined portion of code/model.
    *   **Anti-Corruption Layer (ACL)**: A translation layer between two contexts to prevent the model of one from being "corrupted" by the other's different model.
    *   **Published Language**: One context publishes a well-defined API or event stream for others to consume.

8.  **Refine and Iterate**: Bounded Context discovery is an iterative process. Based on feedback from domain experts and further analysis, you may split, merge, or rename contexts to achieve a clearer, more cohesive design.

By following these steps, you can effectively leverage Event Storming to uncover the natural boundaries within your domain, leading to more robust, maintainable, and scalable software systems.