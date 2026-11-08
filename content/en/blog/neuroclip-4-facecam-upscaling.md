---
draft: false
title: "Building Neuroclip — Part 4: AI Facecam Upscaling with Real-ESRGAN (and Why Not CodeFormer)"
seo_title: "Facecam Upscaling with Real-ESRGAN in Go"
date: 2026-11-08T06:30:00+01:00
tags:
  [
    "go",
    "real-esrgan",
    "ffmpeg",
    "upscaling",
    "open-source-licenses",
    "neuroclip",
    "video-processing",
  ]
categories: ["Software Engineering"]
series: ["Building Neuroclip"]
description: "Sharpening a tiny facecam crop in vertical shorts: an external upscaler behind a Go interface, a cache, a safe fallback and why not CodeFormer."
images: ["img/neuroclip/og.png"]
featured_image: "img/neuroclip/facecam-nachher-460.jpg"
toc: true
---

> **Building Neuroclip, Part 4 of 5.** Previous: [Part 3 — the OBS Regie](/blog/neuroclip-3-obs-regie/). Others: [Part 1 — architecture](/blog/neuroclip-1-architecture/), [Part 2 — the VOD-to-short pipeline](/blog/neuroclip-2-vod-to-short-pipeline/), [Part 5 — shipping on Kubernetes](/blog/neuroclip-5-shipping-kubernetes/). The product page is [Neuroclip](/page/neuroclip/) (early access, single-user beta).

A Twitch stream is 1920x1080 and the facecam in the corner is small, a few hundred pixels wide. A vertical short is 1080 pixels wide, and the layout shows the cam as a strip across the full width. That is a magnification of more than 2x, and it looks exactly like you think: soft, blocky, a bit sad.

This post is about the feature I built to fix that, and about three engineering decisions that I find more interesting than the AI model itself:

1. **Scope**: upscale only the cam crop, never the game.
2. **Boundaries**: run the model as an external tool behind a small interface, with a cache and a fallback that can never break a render.
3. **Licensing**: why I picked Real-ESRGAN over CodeFormer, even though face restoration sounds like the better fit.

Neuroclip is my own tool for streamers (see [Part 1](/blog/neuroclip-1-architecture/)). It is in early access and I am the only user so far, so treat everything below as "works for me, on one face".

## The problem: a small crop on a wide strip

Scaling is simple arithmetic: a few hundred pixels of source have to cover 1080 pixels of output. ffmpeg's [`scale` filter](https://ffmpeg.org/ffmpeg-filters.html#scale-1) with Lanczos does a decent job, but it cannot invent detail that the stream encoder already threw away. The result is a smooth but blurry face.

The options I considered:

| Option | Why not (or why yes) |
| --- | --- |
| Raise the stream bitrate or cam size | Changes the live stream, only helps future streams |
| Upscale the whole clip | Full frames through a neural network are far too slow, and the game does not need it |
| Face restoration model (CodeFormer) | Made for faces, but a license problem (more on that below) |
| **General super-resolution on the cam crop only** | Small input, fixed scope, permissive license |

The last row won.

## The approach in one picture

{{< diagram src="neuroclip-4-upscale-flow.svg" caption="Data flow of the AI facecam: crop, upscale in an external process, encode to a cache file, feed it to the short render as a second input." >}}

On a box-and-arrow level:

1. **Crop frames.** ffmpeg cuts the camera box out of the source and writes image frames. Only the parts that are actually visible in the short are extracted, and the frame rate is capped, because the cam does not need more.
2. **Upscale.** An external super-resolution program runs over the folder of frames on the GPU.
3. **Encode.** ffmpeg puts the frames back on the time axis of the source and encodes them into a small intermediate video. Optionally the plain upscale is blended in, so the effect can be dialled back.
4. **Cache.** The result is stored under a key made of everything that influences it: the source, the crop, the visible parts and the settings. Rendering the same clip again reuses the file.
5. **Render.** The short render gets that file as an additional input and uses it in place of the plain upscaled crop.

One design choice keeps cuts, slow motion and intros working: the upscaled cam is not a separate overlay with its own timeline logic. It is attached to the source frame, so everything downstream treats both the same way. ffmpeg's [`pad`](https://ffmpeg.org/ffmpeg-filters.html#pad-1) and [`overlay`](https://ffmpeg.org/ffmpeg-filters.html#overlay-1) filters are the building blocks for this kind of trick.

## Why an external tool behind an interface

Real-ESRGAN started as a Python/PyTorch project. I wanted none of that on a streamer's machine: no Python environment and no CUDA toolchain. The [Real-ESRGAN repository](https://github.com/xinntao/Real-ESRGAN) also ships a portable executable built on [ncnn](https://github.com/Tencent/ncnn) that runs on Vulkan-capable GPUs. Installation is described in its README.

So the Go side treats the upscaler as a seam. A generic version of that idea looks like this:

```go
// Upscaler enlarges a folder of frames into another folder.
// It is the seam for other engines and for fakes in tests.
type Upscaler interface {
    Upscale(ctx context.Context, inputDir, outputDir string) error
}

type ExternalTool struct{ Executable string }

func (tool ExternalTool) Upscale(ctx context.Context, inputDir, outputDir string) error {
    command := exec.CommandContext(ctx, tool.Executable, "-i", inputDir, "-o", outputDir)
    return command.Run()
}
```

The flags differ per tool, so check the one you use. Three things are worth pointing out:

- **Folder in, folder out.** No pipes, no custom protocol, easy to debug by looking at the folders.
- **The context ends the process.** With [`exec.CommandContext`](https://pkg.go.dev/os/exec#CommandContext), cancelling a render also stops the GPU job. That is easy to forget when you shell out.
- **Tests use a fake.** Because callers only know the interface, cache and fallback logic can be tested without a GPU, and a future engine is just another implementation.

The call site follows the same discipline I use everywhere: it only integrates and decides, and the heavy lifting sits in functions that only operate. Its most important property is that **every failure path returns the original, unchanged options**. No error propagates up and aborts the render.

## Graceful fallback

{{< diagram src="neuroclip-4-fallback.svg" caption="Every no-branch ends in a plain render with a log line that explains why. The cache is checked before the tool is even looked for." >}}

Anything that goes wrong falls back to a normal render: the tool or its models are missing, the run fails, the disk is full, the job would be unreasonably long, or the layout simply has no use for a bigger cam. In all of them the short is rendered the usual way and the log says why. For a tool that can render unattended, I take "slightly softer cam, video exists" over "no video" every time.

The feature is also **off by default**. It is slow, so I turn it on deliberately for selected top shorts and never render during a stream. On my laptop GPU the good model takes minutes, not seconds, per short, which is why the cache matters: a re-render of the same clip is quick.

## The A/B test

The same frame, rendered both ways:

<div style="display:flex;gap:1rem;flex-wrap:wrap">
<figure style="margin:0;flex:1 1 220px">
<img src="/img/neuroclip/facecam-vorher-460.jpg" alt="Facecam crop enlarged with the plain scale filter, soft and blocky" loading="lazy" style="width:100%;height:auto">
<figcaption>Before: plain scale</figcaption>
</figure>
<figure style="margin:0;flex:1 1 220px">
<img src="/img/neuroclip/facecam-nachher-460.jpg" alt="The same facecam crop after Real-ESRGAN upscaling, sharper than the plain scale" loading="lazy" style="width:100%;height:auto">
<figcaption>After: Real-ESRGAN</figcaption>
</figure>
</div>

That is me in the pictures. I compared a general-purpose model with a lighter anime-oriented one. The general one clearly looked best, while the anime one looked waxy and painted on faces. Blending the AI picture with the plain upscale instead of using it at full strength looked the most natural to me. This is one person's eyes on one face, not a benchmark.

## Why not CodeFormer

[CodeFormer](https://github.com/sczhou/CodeFormer) is a face restoration model, and for a facecam it is the more obvious tool. I looked at it and decided against it, because as far as I understand its license, it is for non-commercial use only, which does not fit my goal of eventually selling Neuroclip. [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) is published under permissive licenses. **Check both licenses yourself** instead of trusting my one-line summary: licenses change, models and code can be licensed differently, and your use case may differ from mine. I did not run CodeFormer, so I make no claim about its quality compared to Real-ESRGAN.

### Enforcing license decisions in CI

License reasoning only helps if it is enforced. A small script in CI that lists what is really linked or bundled into your artifacts, and fails on copyleft licenses you cannot accept, is cheap insurance. Go links statically, so copyleft would end up inside your binary. An external program you start as a process is a different boundary, so it needs a manual decision. If you build something similar, make that boundary explicit. For more on what ends up inside a Go binary, see [check-static-linking](/blog/check-static-linking/).

## Lessons learned

- **Scope is the optimisation.** Shrinking the input from the full frame to the visible parts of a small crop turns an impossible job into a feasible one.
- **Put the slow, optional thing behind an interface and a cache.** Everything that can go wrong falls back to the cheap path.
- **Decide on licenses before you fall in love with a model.** The best-looking option is worthless if you cannot ship it.
- **Measure.** An A/B test settled the model choice in one afternoon.

## What's next

In [Part 5](/blog/neuroclip-5-shipping-kubernetes/) I cover shipping Neuroclip: container images, Kubernetes and how releases are verified. If you stream and want to try the early access, have a look at the [Neuroclip page](/page/neuroclip/).
