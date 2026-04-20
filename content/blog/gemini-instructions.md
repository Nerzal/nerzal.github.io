---
title: "The Architecture of Instructions: Mastering GEMINI.md"
date: 2026-04-20
draft: false
description: "Deep dive into creating a GEMINI.md file to enforce SOLID, IOSP, and idiomatic Go patterns when using Gemini Code Assist's Agent Mode."
tags: ["ai", "gemini", "clean-code", "golang", "tutorial"]
toc: true
---

## Introduction

In my [previous post](/blog/gemini-agent-mode/), we explored how Gemini Code Assist's Agent Mode can handle multi-file refactors. However, an agent is only as good as the instructions it follows. Without guidance, AI might generate code that works but violates your team's architectural standards.

To solve this, Gemini supports a special file: `GEMINI.md`. Think of this as the "System Prompt" for your entire repository.

## What is GEMINI.md?

The `GEMINI.md` file is a Markdown document placed in your project's root. It serves as a persistent set of rules and context that the Agent reads before every task. It allows you to define:

1.  **Coding Standards:** (e.g., SOLID, DRY).
2.  **Architectural Patterns:** (e.g., IOSP, Hexagonal).
3.  **Language Preferences:** (e.g., Idiomatic Go, strict TypeScript).
4.  **Testing Requirements:** (e.g., Table-driven tests, specific libraries).

## Where to Start?

Simply create a file named `GEMINI.md` in your root directory. The Agent is pre-programmed to look for this specific filename.

### Recommended Structure

A well-structured `GEMINI.md` follows a hierarchy from general philosophy to technical specifics:

```markdown
# Gemini Code Assist Instructions

## 1. General Engineering Principles
## 2. Architectural Patterns (e.g., IOSP)
## 3. Language Specific Rules (e.g., Go)
## 4. Testing & Documentation
```

---

## Universal Examples

Here are some high-quality, universally applicable rules you can add to your project today.

### 1. Clean Code & SOLID
This ensures the Agent doesn't create "God Classes" and follows industry-standard object-oriented design.

```markdown
### General Principles
- **SOLID:** Strictly follow SOLID principles. Prioritize the Single Responsibility Principle; if a function does two things, it must be split.
- **KISS & YAGNI:** Do not build for the future. Only implement the requested logic without adding unnecessary abstractions or "just in case" interfaces.
- **Fail Fast:** Validate all inputs at the start of a function. Never swallow errors or exceptions.
```

### 2. IOSP (Integration/Operation Separation Principle)
IOSP is a game-changer for AI-generated code. It forces the AI to separate "Logic" from "Orchestration," making the code much easier to test and review.

```markdown
### Architecture (IOSP)
- **Strict Separation:** Every function must be either an **Integration** or an **Operation**.
- **Operations:** These contain pure logic and computations. They must not call other complex functions or side-effect heavy methods. They are 100% unit testable.
- **Integrations:** these coordinate the flow by calling Operations. They must not contain complex logic (like `if` statements with complex math) themselves.
```

### 3. Idiomatic Go (Golang)
Go is a "less is more" language. Use these instructions to prevent the Agent from bringing patterns from other languages (like Java) into your Go code.

```markdown
### Go Specific Rules
- **Error Handling:** Use idiomatic error wrapping: `return fmt.Errorf("user service: %w", err)`. This allows callers to use `errors.Is()`.
- **Package Naming:** Never use `util`, `common`, or `helpers`. Name packages after their capability (e.g., `auth`, `storage`, `handlers`).
- **Pointers:** Pass by value by default. Only use pointers for large structs or when mutation is explicitly required.
```

### 4. Meaningful Testing
Force the Agent to use modern testing tools properly.

```markdown
### Testing with Testify
- **Table-Driven Tests:** All unit tests must use the `[]struct{ name string... }` pattern.
- **Assert vs Require:** 
    - Use `require.NoError` for setup and critical checks to stop the test execution early.
    - Use `assert.Equal` for verifying multiple independent values.
```

---

## Why This Works

When you prompt the Agent to *"Add a new payment provider,"* the Agent doesn't just look at the request. It checks `GEMINI.md`, sees the **IOSP** requirement, and automatically creates a clean separation between the API client (Operation) and the payment workflow (Integration).

By maintaining this file, you are essentially training the AI on your specific engineering culture.

## Conclusion

The `GEMINI.md` file is the bridge between generic AI and a world-class coding partner. By defining your expectations for **SOLID**, **IOSP**, and **Language Idioms**, you ensure that the "Agent Mode" produces code that is not only functional but maintainable.

What rules are you putting in your `GEMINI.md`? Let's discuss in the comments!

---
*Want to see the Agent in action? Check out my Introduction to Agent Mode.*