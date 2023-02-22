---
draft: false
title: "How to check if a binary is statically or dynamically linked"
date: 2023-01-02T23:46:14+01:00
tags: ["tutorial", "golang", "linking"]
featured_image: "statically_linked.png"
toc: true
---

## What is the difference between statically and dynamically linked binaries?

Statically linked binaries and dynamically linked binaries refer to two different ways of linking software libraries to an executable program.

A statically linked binary **includes all necessary libraries** within the binary executable file itself. This means that when the program is executed, it does not rely on any external libraries, as all required libraries are already included in the binary. Static linking produces larger binary files, but they can be more portable and self-contained.

A dynamically linked binary, on the other hand, links to external libraries at runtime, rather than including them within the binary itself. When a dynamically linked binary is executed, it relies on shared libraries installed on the system to provide necessary functionality. This can result in smaller binary files, but requires the system to have the necessary shared libraries installed to run the program.

In summary, statically linked binaries are larger and self-contained, while dynamically linked binaries are smaller but rely on external libraries to provide functionality. The choice between static and dynamic linking depends on the specific requirements of the program and the target environment.

## When to use statically linked libraries?

1. Command-line tools: Many command-line tools, such as file compression utilities or network monitoring tools, can be distributed as statically linked binaries. This allows users to quickly and easily download and run the tool without having to install additional dependencies.
2. Embedded systems: When developing software for embedded systems, statically linking the necessary libraries can be important to ensure that the program will run correctly on the device, as the target environment may have limited resources or lack the required libraries.
3. Cross-platform software: Programs that need to run on multiple platforms, such as games or productivity software, may be distributed as statically linked binaries to ensure compatibility across different operating systems and architectures.
4. Security-focused software: Security-focused software, such as encryption tools or password managers, may be distributed as statically linked binaries to reduce the attack surface and minimize the risk of vulnerabilities.

## Check if a binary has been statically or dynamically linked

We have a golang cli tool called swag. And we want to integrate it into our CI pipeline. So it would be helpful to statically link the binary.

Lets see, what the go compiler produces with default parameters.

The -o flag just tells the compiler how to name the output file.

And the path is the path to the main.go file.

> go build -o swag cmd/swag/main.go 

We can now use the **file** command to check the binary.

> file swag

The command outputs:

> swag: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, Go BuildID=gfj1RxRs_HuaewolHit9/HmUS_HdD_89W_XqAu3ee/wf7S14q1IwrJ5uuIdWJA/pmDUv61yXYXhrSKw7FtO, with debug_info, not stripped

And we can see, that the binary has been dynamically linked.

Now we build the same go programm without cgo, which should result in statically linked binaries.

> CGO_ENABLED=0 go build -o swag-static cmd/swag/main.go

Let us now check if we have a statically linked binary.

> file swag-static

That command produces this output:

> swag-static: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, Go BuildID=7mPpucO9Ncafg5_JKWjE/DZbvRKfuHP9vWS79aEaM/3KcHlAJg9L4fvQnb8AL9/FxPS7iMjUAmw_Pc4KTaM, with debug_info, not stripped

And we can see, that we do now have a statically linked binary.

## Conclusion

The **file** command can be used to find out if a binary has been statically or dynamically linked.