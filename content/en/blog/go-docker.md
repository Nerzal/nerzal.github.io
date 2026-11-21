---
title: "Containerization and Go: A Powerful Combination"
seo_title: "Go and Docker: Multi-Stage Builds"
date: 2023-03-16
lastmod: 2026-11-13T17:36:59+01:00
draft: false
description: "Learn why Go is ideal for containerization and how to use multi-stage Docker builds to create minimal, secure production images."
images: ["img/go-docker.png"]
tags: ["go", "docker"]
featured_image: "img/go-docker.png"
toc: true
---

{{< tldr >}}
- Go suits containers because it compiles to small, statically linked binaries, cross-compiles easily for other platforms and architectures, and has goroutines and channels built in.
- The example multi-stage Dockerfile builds with `golang:1.27-alpine` and `CGO_ENABLED=0`, then copies only the binary into `gcr.io/distroless/static-debian13:nonroot`.
- The distroless runtime image contains only CA certificates, timezone data and a few files like `/etc/passwd`, with no shell and no package manager.
- `USER nonroot:nonroot` runs the Go app as UID 65532 instead of root, so it listens on port 8080 because that user cannot bind ports below 1024.
- Containers share the host kernel and isolate more weakly than virtual machines, but they have a smaller attack surface and are patched by rebuilding the image.
{{< /tldr >}}

## Introduction

Containerization is a standard part of modern software development, because it makes deploying and managing applications across multiple environments easier. [Go](https://go.dev/) has proven to be a great fit for containerized applications.

In this blog post we look at why Go is a good choice for containerized applications and how it works together with containerization technologies like Docker and Kubernetes.

## Go's Advantages for Containerization

1. Lightweight binaries: Go compiles to small, [statically linked binaries](/blog/check-static-linking/) that include all dependencies. Container images stay small, start faster and need fewer resources.

2. Cross-compilation: Go makes it easy to cross-compile binaries for different platforms and architectures, which simplifies building multi-platform container images.

3. Performance: Go is known for its high performance, which matters in containerized environments where resources are often limited.

4. Concurrency: Goroutines and channels are built into the language, so you can write efficient, responsive applications that make good use of the CPU and memory a container gets.

5. Simple and maintainable code: Go's plain syntax leads to readable, maintainable code, and that pays off once a containerized system grows large.

## Integrating Go with Docker

[Docker](https://www.docker.com/) is a popular containerization platform that makes it easy to package, distribute, and run applications in containers. Here's a simple example of a `Dockerfile` for a Go application:

```dockerfile
#Start with the official Golang base image
FROM golang:1.27-alpine AS build

#Set the working directory
WORKDIR /app

# Copy go.mod and go.sum files
COPY go.mod go.sum ./

#Download dependencies
RUN go mod download

# Copy source files
COPY . .

#Build a statically linked binary without cgo
RUN CGO_ENABLED=0 go build -o myapp

#Start a new stage from a minimal distroless image that runs as a non-root user
FROM gcr.io/distroless/static-debian13:nonroot

#Set the working directory
WORKDIR /app

# Copy the binary from the build stage
COPY --from=build /app/myapp /app/

#Never run the application as root
USER nonroot:nonroot

#Expose the application's port
EXPOSE 8080

# Run the application
CMD ["/app/myapp"]
```

This `Dockerfile` builds a Docker image for a Go application: it starts with the official Golang base image, downloads the dependencies and compiles the application.

## Multi-Stage Dockerfiles

Multi-stage Dockerfiles help optimize the build process and reduce the size of the final Docker image. The example `Dockerfile` above already uses a multi-stage build to get a smaller, more efficient image. These are the advantages:

1. Separation of build and runtime environments: You use separate base images for building and running your application. The build stage gets an image with all the necessary build tools and dependencies, and the runtime stage switches to a minimal image, which keeps the final image small.

2. Reduced image size: Only the compiled binary and required assets are copied from the build stage to the runtime stage, which shrinks the final image considerably. Smaller images download faster, need less storage and use less bandwidth.

3. Better security: A minimal runtime image with only the necessary components reduces the attack surface of your application, so there are fewer vulnerabilities an attacker could exploit in the runtime environment.

4. Faster builds: Multi-stage Dockerfiles allow better caching of intermediate build layers. With the build steps split into stages, Docker's build cache can be used more effectively, and builds get faster.

Step by step, the multi-stage `Dockerfile` from our example does the following:

- The first stage, `FROM golang:1.27-alpine AS build`, uses the [official Go Alpine image](https://hub.docker.com/_/golang) as the base for the build environment. This image includes the Go compiler and other necessary build tools. Pin the Go version you develop with and update it regularly: the Go team only supports the [two most recent major releases](https://go.dev/doc/devel/release#policy).
- `CGO_ENABLED=0` makes the Go compiler produce a [statically linked binary](/blog/check-static-linking/) that does not depend on the C library of the base image.
- The second stage, `FROM gcr.io/distroless/static-debian13:nonroot`, uses a [distroless](https://github.com/GoogleContainerTools/distroless) image for the runtime environment. It contains only CA certificates, timezone data and a few files like `/etc/passwd`. There is no shell and no package manager, which leaves an attacker very little to work with.
- `USER nonroot:nonroot` runs the application as an unprivileged user (UID 65532) instead of root. If an attacker manages to exploit your application, they do not get root privileges inside the container. Because the user cannot bind to ports below 1024, the application listens on port 8080.
- The `COPY --from=build` command copies the compiled binary from the build stage to the runtime stage, so only the necessary files end up in the final image.

## Security Aspects: Containers vs. Virtual Machines

Containers and virtual machines have different security strengths and weaknesses. These are the main differences:

### Isolation

**Virtual Machines**: VMs isolate instances strongly, because each VM runs its own operating system and is separated at the hypervisor level. A compromised VM is unlikely to affect others on the same host.

**Containers**: Containers share the host's operating system kernel and run in isolated user-space instances. That isolation is generally weaker than with VMs, because vulnerabilities in the host kernel or container runtime can affect all containers running on the host.

### Resource Consumption and Attack Surface

**Virtual Machines**: Each VM runs a full operating system, which costs more resources and creates a larger attack surface. More components means more places where a vulnerability could hide.

**Containers**: Containers are lightweight and run only the components the application needs. They consume fewer resources and have a smaller attack surface, which makes them less susceptible to certain types of attacks.

### Patching and Updates

**Virtual Machines**: Patching and updating VMs can take more time and resources, because each VM must be updated individually. As a result, outdated or vulnerable software sometimes stays in use simply because keeping every VM up to date is hard.

**Containers**: With containers you update the image and deploy new containers from it. Updates are faster and easier, so applications stay patched.

### Security Tools and Practices

**Virtual Machines**: Traditional security tools and practices, such as firewalls, intrusion detection systems, and antivirus software, protect VMs. These tools are often not optimized for containerized environments and may not protect containers as well.

**Containers**: Container-specific tools and practices, such as vulnerability scanning, image signing, and runtime security monitoring, were developed for the problems specific to containerized environments. With them you can run secure and resilient container deployments.

So both models come with their own security advantages and challenges. Understand the differences and pick the deployment model based on your application's security requirements. With best practices and appropriate security measures, you can deploy secure applications on containers as well as on VMs.


## Go and Kubernetes

[Kubernetes](https://kubernetes.io/) is an orchestration platform for managing containerized applications at scale. Go is often used for applications that run on Kubernetes and for tools and services that talk to the Kubernetes API.

The Kubernetes project itself is written primarily in Go, so developers who know Go can contribute to the project and write custom extensions and integrations.

## Conclusion

Go makes deploying, scaling and managing containerized applications simpler. Its small static binaries, easy cross-compilation and performance give you efficient, responsive applications that run well on platforms like Docker and Kubernetes.
