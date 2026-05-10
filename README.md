# blog.noobygames.de

Personal blog and portfolio of **Tobias Theel** — Senior Software Engineer, Author, Speaker.

**Live:** [blog.noobygames.de](https://blog.noobygames.de)

---

## Stack

| Layer | Technology |
|-------|-----------|
| Static site generator | [Hugo Extended](https://gohugo.io/) v0.160.1 |
| Theme origin | [gohugo-theme-ananke](https://github.com/theNewDynamic/gohugo-theme-ananke) v1 (fully forked, no upstream dependency) |
| Hosting | GitHub Pages |
| CI/CD | GitHub Actions — lint → build → deploy |
| CSS linter | [Stylelint](https://stylelint.io/) + stylelint-config-standard |
| Markdown linter | [markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2) |

---

## Prerequisites

- [Hugo Extended](https://github.com/gohugoio/hugo/releases) v0.124.1 or later
- [Node.js](https://nodejs.org/) v18 or later (for linters)
- [Git](https://git-scm.com/)
- `make` (GnuWin32 on Windows, built-in on macOS/Linux)

---

## Getting started

```bash
git clone https://github.com/Nerzal/nerzal.github.io.git
cd nerzal.github.io
make install   # install Node.js linter dependencies
make serve     # start local dev server at http://localhost:1313
```

---

## Make targets

Run `make` or `make help` to see all available targets.

```
make serve          Start local dev server (includes draft posts)
make build          Build production site → ./public

make lint           Run all linters (CSS + Markdown)
make lint-css       Run stylelint on assets/css/**/*.css
make lint-md        Run markdownlint on content/**/*.md

make install        Install Node.js dependencies from lockfile (npm ci)
make update         Update Node.js dependencies to latest compatible versions

make hugo-install   Install Hugo Extended via winget (Windows)
make hugo-update    Update Hugo Extended via winget (Windows)

make new-post NAME=my-post-title    Create EN + DE blog post drafts
make new-page NAME=my-page          Create EN + DE page drafts

make ci             Simulate full CI pipeline locally: install → lint → build
```

---

## Project structure

```
.
├── assets/
│   ├── css/
│   │   ├── styles.css          # main stylesheet (all custom styles)
│   │   ├── timeline.css        # resume timeline component
│   │   ├── _code.css           # syntax highlighting (Chroma)
│   │   ├── _tachyons.css       # Tachyons utility framework (third-party)
│   │   └── _social-icons.css   # social icon styles (from Ananke theme)
│   └── img/                    # processed images (Hugo Pipes)
├── content/
│   ├── en/                     # English content (default language)
│   │   ├── blog/               # blog posts
│   │   └── page/               # standalone pages (resume, contact, …)
│   └── de/                     # German content
│       ├── blog/
│       └── page/
├── i18n/
│   ├── en.toml                 # English translation strings
│   └── de.toml                 # German translation strings
├── layouts/
│   ├── _default/baseof.html    # root HTML shell (all pages inherit from this)
│   ├── partials/               # reusable template fragments
│   │   ├── site-scripts.html   # all JavaScript
│   │   └── site-style.html     # CSS loading
│   ├── page/                   # page-type templates
│   └── shortcodes/             # custom Hugo shortcodes
├── static/                     # files copied as-is (favicons, humans.txt)
├── .github/workflows/hugo.yml  # CI/CD pipeline
├── .stylelintrc.json           # stylelint configuration
├── .markdownlint.jsonc         # markdownlint configuration
├── .stylelintignore            # stylelint ignore list (third-party CSS)
├── config.toml                 # Hugo site configuration
├── Makefile                    # developer workflow commands
└── package.json                # Node.js linter dependencies
```

---

## Content

### Writing a new blog post

```bash
make new-post NAME=my-post-title
```

This creates `content/en/blog/my-post-title.md` and a copy at `content/de/blog/my-post-title.md`. Edit both files — the English post first, then translate the DE version.

**Code block rule:** every fenced code block must have a language specifier (enforced by markdownlint MD040). Use `bash` as the default, `powershell` for Windows commands, and specific languages (`go`, `yaml`, `json`, …) where appropriate.

### Languages

The site is fully bilingual. English is the default (served from `/`), German from `/de/`. Every blog post and page must exist in both languages. Translation strings live in `i18n/en.toml` and `i18n/de.toml`.

---

## Linting

```bash
make lint        # CSS + Markdown
make lint-css    # CSS only
make lint-md     # Markdown only
```

**CSS (Stylelint):** enforces `stylelint-config-standard` with project-specific overrides for legacy color notation, `em`-based breakpoints, BEM class naming, and Tachyons utility classes. Third-party files (`_tachyons.css`, `_hugo-internal-templates.css`, `_social-icons.css`) are excluded.

**Markdown (markdownlint):** enforces structural rules — heading increments (MD001), blanks around fenced blocks (MD031), emphasis used as headings (MD036), and mandatory code fence language specifiers (MD040). Cosmetic rules (line length, list indentation) are disabled.

---

## CI/CD

Every push to `main` runs the GitHub Actions pipeline:

1. **Lint** — stylelint + markdownlint (build is blocked if lint fails)
2. **Build** — `hugo --minify`
3. **Deploy** — upload artifact to GitHub Pages

---

## CSS architecture

The CSS pipeline is managed entirely in `layouts/partials/site-style.html` using Hugo Pipes. All files are concatenated into a single bundle, minified and fingerprinted in production.

Load order (matters for cascade):
1. `_tachyons.css` — Tachyons utility framework (third-party, do not edit)
2. `_hugo-internal-templates.css` — Hugo pagination styles
3. `_social-icons.css` — social icon styles (from original Ananke theme)
4. `_code.css` — syntax highlighting (Chroma)
5. `styles.css` — all custom site styles
6. `timeline.css` — resume timeline component

Rules:
- Use `var(--text-color)`, `var(--highlight-color)`, `var(--background-color)` for all theming.
- For semi-transparent text use `rgba(var(--text-rgb), <opacity>)` — **never** hardcode `rgba(228, 241, 254, …)` as that breaks light mode.
- Media queries use `em` units (not `px`) to respect browser font-size settings.
- Tachyons utility classes (`ph3`, `pv5`, `mw8`, `tc`, …) are loaded from `_tachyons.css` — removing it breaks most page layouts.

## Theme architecture

This is a **standalone Hugo site** — there is no active theme dependency. The site was originally forked from [gohugo-theme-ananke](https://github.com/theNewDynamic/gohugo-theme-ananke) v1 and has since diverged completely:

- All layouts live in the project root `layouts/` — this is the correct Hugo pattern for a fully forked theme.
- The social rendering system (`layouts/partials/func/socials/`) is the only remaining Ananke-origin code, kept because it integrates tightly with `config.toml` social params.
- There is no `themes/` directory and no `theme =` in `config.toml` — this is intentional. Adding a modern Ananke version would not help because Ananke has since moved its partials to `layouts/_partials/` (different path), making the two incompatible.

---

## Credits

- Original theme fork: [gohugo-theme-ananke](https://github.com/theNewDynamic/gohugo-theme-ananke) by The New Dynamic (MIT)
- Static site generator: [Hugo](https://gohugo.io/) (Apache 2.0)
