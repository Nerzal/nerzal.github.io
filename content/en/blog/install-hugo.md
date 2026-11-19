---
draft: false
title: "Introduction to Hugo #1"
date: 2023-01-02T23:46:14+01:00
tags: ["tutorial", "hugo"]
description: "Get started with Hugo, the world's fastest framework for building websites. Learn installation, theme creation, and deployment basics."
images: ["img/hugo-logo-wide.svg"]
featured_image: "img/hugo-logo-wide.svg"
toc: true
---

## What is Hugo?

Hugo is a static site generator for building fast and secure websites.

Builds are fast, so even large sites are generated quickly. The directory structure is straightforward and the interface is intuitive, which makes it easy to get started. Templates, shortcodes and custom output formats give you flexibility, and the result can be deployed to many hosting platforms.

Hugo handles large sites well, and because it generates static HTML files, the result is more secure than a dynamic site. It is a popular choice for developers and content creators who want efficient, secure websites.

## Why should u use Hugo?

1. Speed: Hugo builds sites with thousands of pages in milliseconds, so large sites are generated quickly. Static HTML files also tend to load blazingly fast, which leads to good [PageSpeedInsights](https://pagespeed.web.dev/) scores.

2. Ease of use: Hugo has a simple, intuitive interface, a straightforward directory structure and Markdown-based content files, so new users get started quickly.

3. Flexibility: You can customize your site with templates, shortcodes, and custom output formats, and build a site that fits your specific needs.

4. Portability: Hugo sites can be deployed to many hosting platforms, including GitHub Pages, Amazon S3, and Netlify, so you can host your site wherever you prefer.

5. Scalability: Hugo handles large sites without trouble, so your site can keep growing.

6. Security: Hugo generates static HTML files, so there are no dynamic elements or database queries. That leaves attackers much less to work with.

## Install Hugo

Since [v0.170.0](https://github.com/gohugoio/hugo/releases/tag/v0.170.0) there is only one Hugo edition. The former **extended** edition is gone: everything it offered (such as WebP encoding) is now in the standard binary, except the deprecated LibSass. If your theme uses Sass/SCSS, install [Dart Sass](https://gohugo.io/functions/css/sass/) next to Hugo.

### Install Hugo

{{< os-tabs >}}
{{< os-tab "Windows (PowerShell)" >}}

The easiest way to install Hugo on Windows is using **Winget** (Windows Package Manager), which is built into modern Windows 10/11.

1.  Open PowerShell or Command Prompt as an administrator.
2.  Run the following command:

    ```powershell
    winget install Hugo.Hugo
    ```

3.  Restart your terminal so the new PATH is loaded.

If you installed `Hugo.Hugo.Extended` earlier, switch packages with `winget uninstall Hugo.Hugo.Extended`, then run the install command above. Later updates: `winget upgrade Hugo.Hugo`.

{{< /os-tab >}}
{{< os-tab "macOS" >}}

The easiest way on macOS is [Homebrew](https://brew.sh/). The `hugo` formula installs the current release:

```bash
brew install hugo
```

{{< /os-tab >}}
{{< os-tab "Linux" >}}

For Debian-based systems (like Ubuntu):
1.  Download the latest Hugo `.deb` file from the [Hugo Releases page](https://github.com/gohugoio/hugo/releases). Look for `hugo_VERSION_linux-amd64.deb`.
2.  Install it using `dpkg`:

    ```bash
    sudo dpkg -i /path/to/hugo_VERSION_linux-amd64.deb
    ```

For other Linux distributions, you can download the tarball:
1.  Download the `hugo_VERSION_linux-amd64.tar.gz` from the [Hugo Releases page](https://github.com/gohugoio/hugo/releases).
2.  Extract it and move the executable to your PATH:

    ```bash
    tar -xf hugo_VERSION_linux-amd64.tar.gz
    sudo mv hugo /usr/local/bin/
    ```

{{< /os-tab >}}
{{< /os-tabs >}}

### Verify Installation
After installation, open your terminal and run:

```bash
hugo version
```

You should see the installed Hugo version, e.g. `hugo v0.170.0-... windows/amd64`. Since v0.170.0 the version string no longer ends in `+extended`. You can always find the latest release and its changelog on the [Hugo releases page](https://github.com/gohugoio/hugo/releases).

## Use Docker

Instead of installing Hugo locally on your machine, you can use the official Hugo container image [`ghcr.io/gohugoio/hugo`](https://github.com/gohugoio/hugo/pkgs/container/hugo). It already contains Hugo, Dart Sass, Git and Node.js. You need [Docker](https://docs.docker.com/get-started/get-docker/) installed for this.

### Development server in a container

For local development, mount your site directory into the container and run `hugo server`. The container listens on port `1313`, so you have to publish that port with `-p 1313:1313`, and `--bind 0.0.0.0` makes the server reachable from outside the container:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
docker run --rm -it \
  -v "$(pwd)":/project \
  -u "$(id -u):$(id -g)" \
  -p 1313:1313 \
  ghcr.io/gohugoio/hugo:v0.170.0 \
  server --bind 0.0.0.0
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
docker run --rm -it `
  -v "${PWD}:/project" `
  -p 1313:1313 `
  ghcr.io/gohugoio/hugo:v0.170.0 `
  server --bind 0.0.0.0
```

{{< /os-tab >}}
{{< /os-tabs >}}

`hugo server` is a development server with live reload. It is not meant to serve a production website.

### Production image

For production, Hugo should only **build** the site. The generated static files in `public/` are then served by a regular web server such as [nginx](https://hub.docker.com/_/nginx). A [multi-stage build](https://docs.docker.com/build/building/multi-stage/) keeps Hugo out of the final image:

```dockerfile
# Stage 1: build the static site with the official Hugo image
FROM ghcr.io/gohugoio/hugo:v0.170.0 AS build

# The image runs as the unprivileged user "hugo" by default. This stage is
# thrown away after the build, so we switch to root to be able to write to /src.
USER root
WORKDIR /src
COPY . .
RUN hugo build --minify

# Stage 2: serve the generated files with nginx
FROM nginx:stable-alpine

COPY --from=build /src/public /usr/share/nginx/html

EXPOSE 80
```

Place the `Dockerfile` in the root directory of your Hugo site and build the image:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
cd path/to/your/site
docker build -t my-hugo-site .
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
cd path\to\your\site
docker build -t my-hugo-site .
```

{{< /os-tab >}}
{{< /os-tabs >}}

When the image has been built successfully, start the container and map port `8080` on your machine to port `80` of nginx:

```bash
docker run --rm -p 8080:80 my-hugo-site
```

The command is identical in Bash and PowerShell. Your site is now available at [http://localhost:8080/](http://localhost:8080/).

## Create a new website

To create a new website, run the following command:

```bash
hugo new site example.com
```

The command is built as follows:

```bash
hugo(cli) new (command) site (parameter) siteName (parameter)
```

This is going to create a new folder structure for your site. Change into it, all following commands are run inside the site directory:

```bash
cd example.com
```

When examining the output of the create command, Hugo is going to tell you something like the following:

```text
Just a few more steps...

1. Change the current directory to example.com.
2. Create or install a theme:
   - Create a new theme with the command "hugo new theme <THEMENAME>"
   - Or, install a theme from https://themes.gohugo.io/
3. Edit hugo.toml, setting the "theme" property to the theme name.
4. Create new content with the command "hugo new content <SECTIONNAME>/<FILENAME>.<FORMAT>".
5. Start the embedded web server with the command "hugo server --buildDrafts".

See documentation at https://gohugo.io/.
```

### Create a new theme

You can now either download any Hugo theme from the [Hugo themes directory](https://themes.gohugo.io/), or create your very own theme. In this tutorial series, we are going to create our own theme.

So we use the following command while being inside the site directory:

```bash
hugo new theme my-theme
```

This is going to create the complete folder structure for your theme in `themes/my-theme`.

Hugo does not use a theme just because it exists in the `themes` folder. You have to activate it by adding the following line to the `hugo.toml` file in your site directory:

```toml
theme = 'my-theme'
```

### Hello World

Before we can finally render something, we have two more things to do.

Since [Hugo v0.146.0](https://github.com/gohugoio/hugo/releases/tag/v0.146.0) a theme uses the new template system (see [template lookup order](https://gohugo.io/templates/lookup-order/)). The skeleton consists of `layouts/baseof.html`, the HTML shell every page inherits from, and specialized templates like `layouts/home.html` for the home page. `baseof.html` defines a `main` block, which the other templates fill.

As a first step, we replace the content of the **home.html** file that is located in example.com (site directory) -> themes -> my-theme -> layouts -> home.html with the following:

```go-html-template
{{ define "main" }}
  {{ .Content }}
{{ end }}
```

`{{ .Content }}` is a template action that simply renders the Markdown content of a file into HTML. There is much more to explain about templates, shortcodes etc., but for now all that matters is that your Markdown content ends up in the HTML.

Now we need a content file to render. Use the following command:

```bash
hugo new content _index.md
```

That command creates a new file with the given path inside the `content` directory. `_index.md` is the content file of the home page.

Your file should now look like this. The default archetype uses [TOML front matter](https://gohugo.io/content-management/front-matter/), enclosed by `+++`:

```toml
+++
date = '2026-11-13T17:29:35+01:00'
draft = true
title = ''
+++
```

`title` is the title of the page.
`date` is the creation date of the page.
`draft` controls whether this page should be published or not.

Let's add a nice greeting to our first page. You can freely choose any greeting, I go with the classic.

```markdown
+++
date = '2026-11-13T17:29:35+01:00'
draft = true
title = 'My first page'
+++

## Hello World!

It's **very nice** to meet you!
```

In the last step we start a Hugo server to see the result. Use the following command:

```bash
hugo server -D
```

That command starts a server in development mode, which includes pages that are in draft status (`-D` is short for `--buildDrafts`). Now visit [http://localhost:1313/](http://localhost:1313/) in your browser.

{{< image image="/img/hugo-world.png" imageAlt="Image of hello world result" >}}
