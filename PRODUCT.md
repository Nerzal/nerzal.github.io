# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Two primary audiences with equal weight (confirmed):

- **Developers arriving from search** who read in-depth tutorials (Go, Docker, Ubuntu hardening, Hugo, PowerShell, AI token cost, architecture topics such as Event Storming and Bounded Contexts).
- **Recruiters, clients and conference organisers** who judge Tobias Theel as a hire, consultant or speaker (résumé, talks, book, open source, contact).

Secondary audience (confirmed): users of Tobias's own products, Neuroclip (Twitch streamers) and Level Time (World of Warcraft players), reaching the product pages and their blog series.

## Product Purpose

The personal website and technical blog of Tobias Theel, a remote-first Senior Software Engineer (Go, cloud-native, game development, author, speaker) based in Fritzlar, Germany. It publishes detailed bilingual (EN/DE) tutorials, shows his professional record, and presents his own products as developer content.

Success counts all three (confirmed): readership and SEO reach, speaking and consulting inquiries, and product sign-ups or downloads. Open: the relative ranking between them has not been decided.

## Positioning

Inferred, not contradicted: tutorials written by an engineer who ships real products (Neuroclip, Level Time, a book, conference talks, open-source libraries). Posts teach in depth, link sources such as RFCs, give Linux and Windows (PowerShell) variants side by side, and exist in English and German. Product posts are framed as engineering write-ups; the blog stays developer-only.

## Operating Context

- Static Hugo site (0.170.0) deployed to GitHub Pages at blog.noobygames.de; English at the root, German under `/de/`.
- Long-form reading with code blocks, platform tabs (`os-tabs`, choice synced and remembered), tables of contents, series boxes, image lightbox.
- Scheduled posts go live through a daily rebuild; links to unpublished posts render as plain text.
- Contact is a mailto call to action (info@noobygames.de). No analytics, no comments.
- Publications overview and submenu are driven by `[[params.publications]]` in config.toml.

## Capabilities and Constraints

- Static output only; CSS and JS through Hugo Pipes; Tachyons utilities from the Ananke submodule are a required dependency.
- All colours via CSS variables; dark and light themes. First visit follows the OS `prefers-color-scheme`; the toggle stores an explicit choice that wins afterwards (confirmed).
- Media queries in `em`; raw HTML in Markdown is intentional (`goldmark unsafe`).
- English and German are always edited together, content and UI strings.
- Neuroclip: early-access status stays visible; posts stay at concept level (no repo code, thresholds, internal names, paths, keys). Level Time is public open source and may be detailed.
- Scheduled posts stay hidden until their date.

## Brand Commitments

- Name "Tobias Theel", role "Senior Software Engineer", hero line "Go · Cloud-Native · Open Source · Game Dev · Author · Speaker".
- Location: Fritzlar, Germany (confirmed), UTC+1/UTC+2, 100% remote.
- Personality is part of the site (inferred, not contradicted): the dogs page (Solo and Luca) and the Konami-code Easter egg stay, kept out of the main reading path.
- Products are named "Neuroclip", "Level Time" and "Level Time Goals".

## Evidence on Hand

- Published blog series: Neuroclip 1–5, Level Time 1–4, Token Cost 1–3, Ubuntu Server Hardening 1–3, plus standalone posts (`content/en/blog/`, `content/de/blog/`).
- Profile photo `assets/img/profile2.jpg`; Neuroclip screenshots `static/img/neuroclip/`; Level Time logo `static/img/level-time/`.
- Book, talks, open-source and games pages under `content/*/page/`; CurseForge and GitHub links for Level Time; Neuroclip waitlist.
- Absent, never to be fabricated: testimonials, client logos, usage numbers, download counts, pricing.

## Product Principles

1. Teach in depth: sources, examples, and both Linux and Windows paths.
2. Bilingual parity: nothing ships in only one language.
3. Honest status: unfinished products say so plainly.
4. Developers first: products appear as engineering stories, not ads.
5. Personality is welcome, but never in the way of reading.

## Accessibility & Inclusion

Target WCAG 2.2 AA (inferred, not contradicted). Existing commitments: skip link, `prefers-reduced-motion` support, em-based breakpoints that respect browser font size, keyboard-operable platform tabs and navigation, theme that respects the OS preference.
