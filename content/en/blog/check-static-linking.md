---
draft: false
title: "How to check if a binary is statically or dynamically linked"
seo_title: "Check if a Go Binary is Statically Linked"
date: 2023-01-02T23:46:14+01:00
lastmod: 2026-11-13T17:36:59+01:00
tags: ["tutorial", "golang", "linking"]
description: "Learn how to differentiate between static and dynamic linking in Go and use terminal tools to verify your application's portability."
images: ["img/statically_linked.png"]
featured_image: "img/statically_linked.png"
toc: true
---

{{< tldr >}}
- Run `file <binary>` to see whether a Linux binary is "statically linked" or "dynamically linked"; `ldd` reports "not a dynamic executable" for a static one.
- A default `go build` on Linux is dynamically linked when cgo is enabled, because packages like `net` and `os/user` then use the system C library.
- Building with `CGO_ENABLED=0` produces a statically linked Go binary, and `go version -m <binary>` shows the `CGO_ENABLED` setting embedded in any Go binary.
- Never run `ldd` on untrusted binaries, because depending on the implementation it may execute them; `file` only reads the binary.
- A statically linked binary does not receive the security patches your Linux distribution ships, so it has to be rebuilt and redeployed when an embedded library is fixed.
{{< /tldr >}}

## What is the difference between statically and dynamically linked binaries?

Static and dynamic linking are two ways of attaching software libraries to an executable program.

A statically linked binary **includes all necessary libraries** within the binary executable file itself. This means that when the program is executed, it does not rely on any external libraries, as all required libraries are already included in the binary. Static linking produces larger binary files, but they can be more portable and self-contained.

A dynamically linked binary, on the other hand, links to external libraries at runtime, rather than including them within the binary itself. When a dynamically linked binary is executed, it relies on shared libraries installed on the system to provide necessary functionality. This can result in smaller binary files, but requires the system to have the necessary shared libraries installed to run the program.

Which one you pick depends on what the program needs and where it will run.

## When to use statically linked libraries?

1. Command-line tools: Many command-line tools, such as file compression utilities or network monitoring tools, can be distributed as statically linked binaries. Users download the tool and run it without installing additional dependencies.
2. Embedded systems: When developing software for embedded systems, statically linking the necessary libraries helps the program run correctly on the device, because the target environment may have limited resources or lack the required libraries.
3. Cross-platform software: Programs that need to run on multiple platforms, such as games or productivity software, may be distributed as statically linked binaries so they work the same across different operating systems and architectures.
4. Security-focused software: Security-focused software, such as encryption tools or password managers, is sometimes distributed as statically linked binaries, because it cannot be tricked into loading a manipulated shared library at runtime (for example via `LD_PRELOAD`). This comes with a trade-off though: a statically linked library does **not** receive the security patches your Linux distribution ships. If a vulnerability is found in an embedded library, the binary has to be rebuilt and redeployed. Security scanners also have a harder time finding vulnerable library versions inside a static binary. Static linking moves the responsibility for patching from the operating system to you.

## Check if a binary has been statically or dynamically linked

We have a golang cli tool called swag and want to integrate it into our CI pipeline, so it would be helpful to statically link the binary.

Lets see, what the go compiler produces with default parameters.

The -o flag just tells the compiler how to name the output file, and the path points to the main.go file.

```bash
go build -o swag cmd/swag/main.go
```

We can now use the [**file**](https://man7.org/linux/man-pages/man1/file.1.html) command to check the binary.

```bash
file swag
```

The command outputs:

```text
swag: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, Go BuildID=gfj1RxRs_HuaewolHit9/HmUS_HdD_89W_XqAu3ee/wf7S14q1IwrJ5uuIdWJA/pmDUv61yXYXhrSKw7FtO, with debug_info, not stripped
```

The binary has been dynamically linked. The reason is [cgo](https://pkg.go.dev/cmd/cgo): packages like `net` or `os/user` use the C library of the system when cgo is enabled, which is the default on Linux if a C compiler is installed.

Now we build the same Go program without cgo, which should result in a statically linked binary.

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
CGO_ENABLED=0 go build -o swag-static cmd/swag/main.go
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
# Cross-compile a Linux binary; file and ldd only work on Linux ELF binaries
$env:CGO_ENABLED = "0"
$env:GOOS = "linux"
go build -o swag-static cmd/swag/main.go
```

{{< /os-tab >}}
{{< /os-tabs >}}

Let us now check if we have a statically linked binary.

```bash
file swag-static
```

That command produces this output:

```text
swag-static: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, Go BuildID=7mPpucO9Ncafg5_JKWjE/DZbvRKfuHP9vWS79aEaM/3KcHlAJg9L4fvQnb8AL9/FxPS7iMjUAmw_Pc4KTaM, with debug_info, not stripped
```

Now the binary is statically linked.

## Alternatives to the file command

### ldd

[`ldd`](https://man7.org/linux/man-pages/man1/ldd.1.html) prints the shared libraries a binary needs at runtime:

```bash
ldd swag
```

For the dynamically linked binary, it lists the libraries, e.g. `libc.so.6` and the dynamic loader `/lib64/ld-linux-x86-64.so.2`. For the statically linked binary, it reports that there is nothing to load:

```bash
ldd swag-static
```

```text
        not a dynamic executable
```

Never run `ldd` on binaries you do not trust: depending on the implementation, it may execute the binary. `file` only reads it.

### go version -m

If you only have the binary, but want to know how it has been built, Go itself can tell you. [`go version -m`](https://pkg.go.dev/cmd/go#hdr-Print_Go_version) prints the build information embedded in every Go binary, including the `CGO_ENABLED` setting. This works on every operating system, also for binaries built for another platform:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
go version -m swag-static | grep CGO_ENABLED
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
go version -m swag-static | Select-String CGO_ENABLED
```

{{< /os-tab >}}
{{< /os-tabs >}}

```text
        build   CGO_ENABLED=0
```

`CGO_ENABLED=0` means the binary does not link against the C library and is statically linked (unless special linker flags were used).

### A note on Windows

On Windows, the question is less relevant: Go binaries never depend on a C runtime there, they only load system DLLs like `kernel32.dll`, which are part of every Windows installation. If you want to inspect the DLLs a Windows executable imports, use `dumpbin /dependents myapp.exe` from the [Visual Studio developer tools](https://learn.microsoft.com/en-us/cpp/build/reference/dependents).

## Conclusion

The **file** command can be used to find out if a binary has been statically or dynamically linked. `ldd` and `go version -m` are useful alternatives.

Static linking matters most when you ship inside a container. A statically linked Go binary can run in a `FROM scratch` or distroless Docker image with zero OS dependencies, which gives you a very small image with almost nothing an attacker could use. Just remember to rebuild it regularly, so it picks up fixes in Go and your dependencies. If you are interested in containerising your Go applications, check out [Containerization and Go: A Powerful Combination](/blog/go-docker/).
