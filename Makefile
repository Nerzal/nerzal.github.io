HUGO_VERSION := 0.160.1

.PHONY: serve build lint lint-css lint-md \
        install update \
        hugo-install hugo-update \
        new-post new-page \
        ci help

.DEFAULT_GOAL := help

# ── Development ──────────────────────────────────────────────────────────────

serve: ## Start local dev server with draft posts
	hugo server -D

build: ## Build production site (output → ./public)
	hugo --minify

# ── Linting ──────────────────────────────────────────────────────────────────

lint: lint-css lint-md ## Run all linters (CSS + Markdown)

lint-css: ## Lint CSS files with stylelint
	npm run lint:css

lint-md: ## Lint Markdown files with markdownlint
	npm run lint:md

# ── Node dependencies ─────────────────────────────────────────────────────────

install: ## Install Node.js dependencies from lockfile (npm ci)
	npm ci

update: ## Update Node.js dependencies to latest compatible versions
	npm update

# ── Hugo ─────────────────────────────────────────────────────────────────────
# Requires winget (Windows Package Manager, ships with Windows 11 / modern Win 10)

hugo-install: ## Install Hugo Extended via winget
	winget install Hugo.Hugo.Extended

hugo-update: ## Update Hugo Extended to latest via winget
	winget upgrade Hugo.Hugo.Extended

# ── Content creation ──────────────────────────────────────────────────────────

new-post: ## Create a new EN+DE blog post   →  make new-post NAME=my-post-title
	hugo new blog/$(NAME).md
	@cp -n content/en/blog/$(NAME).md content/de/blog/$(NAME).md 2>/dev/null || \
	  cp content/en/blog/$(NAME).md content/de/blog/$(NAME).md

new-page: ## Create a new EN+DE page        →  make new-page NAME=my-page
	hugo new page/$(NAME).md
	@cp -n content/en/page/$(NAME).md content/de/page/$(NAME).md 2>/dev/null || \
	  cp content/en/page/$(NAME).md content/de/page/$(NAME).md

# ── CI simulation ────────────────────────────────────────────────────────────

ci: install lint build ## Simulate full CI pipeline locally (install → lint → build)

# ── Help ─────────────────────────────────────────────────────────────────────

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} \
	/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-14s\033[0m  %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf "\nHugo version (local): %s\n" "$(HUGO_VERSION)"
