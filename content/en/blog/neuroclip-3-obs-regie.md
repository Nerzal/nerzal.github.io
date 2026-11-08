---
draft: false
title: "Building Neuroclip — Part 3: OBS Regie — WebSocket, audio meters and the mute alarm"
seo_title: "OBS WebSocket v5 in Go: Audio Meters and a Mute Alarm"
date: 2026-11-08T06:20:00+01:00
tags:
  [
    "go",
    "obs",
    "obs-websocket",
    "websocket",
    "streaming",
    "audio",
    "sha256",
    "neuroclip",
    "software-engineering",
  ]
categories: ["Software Engineering"]
series: ["Building Neuroclip"]
description: "How a Go service talks to OBS over obs-websocket v5: the SHA-256 handshake, audio meters in dB, and the idea behind a mute alarm that hears speech."
images: ["img/neuroclip/og.png"]
featured_image: "img/neuroclip/regie-1440.jpg"
toc: true
---

> **Building Neuroclip, part 3 of 5.** The series: [Part 1 — Architecture](/blog/neuroclip-1-architecture/) · [Part 2 — VOD to short pipeline](/blog/neuroclip-2-vod-to-short-pipeline/) · **Part 3 — OBS Regie** · [Part 4 — Facecam upscaling](/blog/neuroclip-4-facecam-upscaling/) · [Part 5 — Shipping to Kubernetes](/blog/neuroclip-5-shipping-kubernetes/). More on the [Neuroclip product page](/page/neuroclip/). Neuroclip is in **early access** and a **single-user beta** — everything below describes what runs on my machine today.

The first two parts were about things that happen *after* a stream: cutting, subtitling, exporting. This part is about the live side, which I call the **Regie** (German for "direction" or "control room"). It is the part of the product that talks to OBS while the stream is running: it switches scenes, saves replays, sets markers, keeps an eye on encoder health, and — my favourite — warns me when I talk into a muted microphone.

I am deliberately staying on the concept level here. Neuroclip is a commercial product, so this is not a build plan. What I can give you is the public protocol it builds on, the audio maths that trips people up, and the design reasoning behind the alarm. If you only care about the protocol, jump to [the handshake](#the-obs-websocket-v5-handshake). For the alarm idea, go to [the mute alarm](#the-mute-alarm-hearing-speech-through-a-muted-microphone).

## What the Regie does

The Regie page of the dashboard shows the current scene, stream and recording state, the audio inputs with live level meters, a few health numbers and a list of warnings. From there (or from a hotkey, a phone or a Stream Deck) I can:

- switch scenes, start and stop stream and recording, save the replay buffer,
- mute inputs and set fader volumes,
- set a **marker** (a Twitch stream marker while streaming, a chapter in the recording while recording),
- trigger **"Clip jetzt"** (a Twitch clip of the last seconds),
- toggle sources in the current scene.

![The Regie page of the Neuroclip dashboard with scene buttons, audio level meters, health numbers and a microphone warning](/img/neuroclip/regie-1440.jpg)

*The Regie page. The microphone alarm in this screenshot was staged for the picture — I did not actually talk into a muted mic on stream.*

The dashboard is React, the server is Go, and all OBS traffic goes through one component on the server that speaks the [obs-websocket v5 protocol](https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md). Since OBS 28 the WebSocket server is built into OBS itself, so there is nothing to install on the OBS side: *Tools › WebSocket Server Settings*, enable it, set a password.

## The obs-websocket v5 handshake

The protocol is JSON over WebSocket ([RFC 6455](https://www.rfc-editor.org/rfc/rfc6455)). Every message is an envelope `{"op": <int>, "d": {...}}`. The opcodes that matter for a simple client:

| op | Name | Direction | Purpose |
| --- | --- | --- | --- |
| 0 | Hello | OBS → client | server version, optional auth challenge |
| 1 | Identify | client → OBS | rpcVersion, auth answer, event subscriptions |
| 2 | Identified | OBS → client | login accepted |
| 5 | Event | OBS → client | something happened |
| 6 | Request | client → OBS | do something or read something |
| 7 | RequestResponse | OBS → client | result, matched by `requestId` |

{{< diagram src="neuroclip-3-obs-websocket-flow.svg" caption="Three phases on the wire: the handshake, request/response pairs, and a separate long-lived connection that only receives the high-volume meter events." >}}

### Challenge-response authentication

If a password is set, OBS puts an `authentication` object with a `challenge` and a `salt` into its Hello message. The client proves that it knows the password without sending it, as described in the [protocol document](https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md#creating-an-authentication-string):

1. `secret = base64( sha256( password + salt ) )`
2. `authentication = base64( sha256( secret + challenge ) )`

SHA-256 is specified in [FIPS 180-4](https://csrc.nist.gov/pubs/fips/180-4/upd1/final). In Go that is a handful of lines using only the standard library:

```go
package main

import (
    "crypto/sha256"
    "encoding/base64"
    "fmt"
)

func authenticationString(password, salt, challenge string) string {
    secretSum := sha256.Sum256([]byte(password + salt))
    secret := base64.StdEncoding.EncodeToString(secretSum[:])

    answerSum := sha256.Sum256([]byte(secret + challenge))
    return base64.StdEncoding.EncodeToString(answerSum[:])
}

func main() {
    fmt.Println(authenticationString("password", "salt-from-hello", "challenge-from-hello"))
}
```

The rest of the handshake is: read Hello, answer with Identify (including the authentication string only if Hello contained an `authentication` block), and expect op 2. Two details are worth knowing. First, **a missing authentication block means OBS has no password**, which is a legitimate setup on a loopback-only machine. Second, put a timeout on the login so a stuck OBS cannot hang a caller forever; a context-aware WebSocket library such as [`coder/websocket`](https://github.com/coder/websocket) makes that natural.

### Requests and events

A request is op 6 with a `requestType`, a `requestId` and optional `requestData`. The response (op 7) carries the same id plus a status with a result flag and a comment. Because events can arrive between your request and its answer, a client has to skip everything that is not the matching response. Everything useful — switching a scene, saving the replay buffer, muting an input, creating a recording chapter — is one such request. The full list is in the [protocol document](https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md#requests).

## Design lessons from the live side

A few decisions shaped how the Regie behaves. I describe the ideas, not the numbers.

**One short-lived session per action.** For "click a button", the simplest client dials, logs in, sends its requests and closes again. There is no connection state to get wrong: no reconnect logic, no half-dead sockets after an OBS restart. The price is that polling becomes expensive, because every poll is a fresh connection plus a login plus a batch of requests.

**Share status reads.** Once several parts of the product (the dashboard, a phone remote, a warning watcher) all wanted the current status, they multiplied the load on an OBS that was busy encoding a game. The fix is the classic pair: let concurrent callers wait for one in-flight fetch instead of each starting their own, and let results be reused for a short moment. Two things need care. Any action that changes OBS must invalidate what was cached, otherwise the next poll shows stale state. And callers must receive copies, so one consumer modifying its view cannot corrupt another's. I have not published before/after numbers; I treat this as a judgement call, not a benchmark result.

**A persistent connection only where it earns its keep.** The one place that needs a permanent connection is the audio meters. `InputVolumeMeters` is a *high-volume* event, which the protocol keeps off by default; you opt in with a bit in the Identify message. That connection exists only while somebody is actually looking at the dashboard, it reconnects after errors, and it tells the UI when the link to OBS is lost. Every subscriber only ever needs the *newest* frame, so a slow browser must never be able to block the producer or the other subscribers: drop the stale frame, keep the new one. The browser gets the frames over Server-Sent Events, a [WHATWG standard](https://html.spec.whatwg.org/multipage/server-sent-events.html) that fits a one-way stream much better than a second WebSocket.

I should be honest about the state of this design: a single permanent session with events would be the more elegant end state, and it is still on my roadmap. The current shape is simple and robust, and the shared status read exists precisely because of its cost. Do not pretend a stateless design is free.

## Audio meters: dB, linear, and the third number

OBS reports levels as **linear multipliers**, not decibels. Each input has one array per channel, and each array has three values: `[magnitude, peak, input-peak]`. Magnitude and peak are measured *after* the fader and mute; the third value is the peak of the signal *before* fader and mute. Keep that third value in mind, it is the whole trick of the mute alarm.

Conversion to dBFS is the textbook formula `20 · log10(x)`, with one pitfall: silence is a multiplier of `0`, and `log10(0)` is `-Inf`. OBS reports `-inf` for the fader of a silent input, which **JSON cannot carry**, so it arrives as `null`. The safe approach is to never trust dB values from the wire and always compute from the multiplier, clamping silence to a floor:

```go
package main

import (
    "fmt"
    "math"
)

const silentDecibels = -100.0

func multiplierToDecibels(multiplier float64) float64 {
    if multiplier <= 0 || math.IsNaN(multiplier) {
        return silentDecibels
    }
    return math.Max(silentDecibels, 20*math.Log10(multiplier))
}

func main() {
    fmt.Println(multiplierToDecibels(0.01)) // -40
    fmt.Println(multiplierToDecibels(0))    // -100
}
```

Between two published meter frames, keep the **maximum** per input rather than the average, so a short shout still shows up. And think in dB everywhere: a linear 0.01 is −40 dBFS, while −50 dBFS is about 0.003. Humans think in dB, hardware reports linear, and the classic bug is a threshold that is off by orders of magnitude. Keep every threshold in dBFS and convert exactly once, at the edge.

## The mute alarm: hearing speech through a muted microphone

The failure I wanted to catch is embarrassing and common: you are live, you start talking, and your microphone is muted in OBS. Chat is typing "can't hear you" — which you cannot read because you are in the game.

A simple "mic is muted" alarm is useless: muting is legitimate for coughing, for a phone call, for an AFK break. What is *not* legitimate is talking into a muted mic. The signal that separates the two is the **raw input peak**, the third value above. A muted input has zero output, but OBS still measures what the microphone hears *before* the mute. If that raw level is clearly above the room noise, somebody is talking.

{{< diagram src="neuroclip-3-mute-alarm.svg" caption="The mute alarm as a state machine. Speech is judged over a rolling window, not a single loud frame, and the alarm re-arms itself instead of latching." >}}

In words, the alarm fires when the microphone has been muted for a while *and* has recently heard a meaningful amount of sound clearly above the noise floor. The warning repeats at a calm interval while the situation lasts, and unmuting clears everything at once.

### About hysteresis, honestly

If you expect a textbook Schmitt trigger (two thresholds, one for entering and one for leaving the alarm state), I have to disappoint you: the alarm has no classic hysteresis band. It avoids flapping with three other mechanisms:

1. **Durations instead of instantaneous levels.** One loud frame does nothing; sound has to accumulate over a window. A cough or a keyboard clack does not.
2. **A margin above the noise floor.** A muted microphone still hears the room, and the margin keeps fan noise out.
3. **A repeat interval instead of re-triggering.** The warning has an identity, and the watcher stays quiet about it until the interval has passed.

A time-integrated rule like this tolerates a signal sitting right at the threshold. A rule that switches on and off based on a single instantaneous level would need real hysteresis. Know which of the two you are building. Two practical details: cap how much time one frame can be credited with (otherwise a stalled connection followed by one loud frame looks like a minute of speech), and sum durations instead of counting frames so the rule does not depend on the frame rate.

### Where the alarm must stay silent

An alarm that fires at the wrong moments gets switched off, and then it protects nobody. So it is gated: it only runs while streaming, it stays quiet in scenes where silence is expected (AFK, starting soon), it only looks at inputs that are actually microphones, and there is a kill switch. The thresholds are configurable and clamped on load, so the rest of the code never has to defend against nonsense values.

The same machinery also implements the plainer cousin, "microphone or game sound has been silent for too long", using the post-fader peak and ignoring muted inputs, because muted counts as quiet.

One structural choice made all of this easy to test: a stateful tracker collects facts, a stateless rule judges them. That split is the IOSP principle (integration vs. operation) in practice. You build a facts struct, call the rule, assert on the warnings, and no OBS is needed.

## Health, markers and remote control

The health numbers come from `GetStats`, which returns counters that grow since OBS started. A counter on its own is useless ("37,412 skipped frames" since when?), so the useful form is a **share over a recent window**: render lag, encoder lag and network drops as a percentage of frames. Two robustness rules apply to any such counter: do not compute shares from a window that is too short, and treat a counter that goes *backwards* as an OBS restart that resets your history.

Actions are a small closed set. Hotkeys, the phone and the dashboard all call the same runner, so behaviour cannot drift between them. The marker action has two sinks: a Twitch stream marker while streaming, a chapter via `CreateRecordChapter` while recording. Chapters need **OBS 30.2 or newer and Hybrid MP4 recordings**, so it pays to translate the cryptic "unknown request" error into exactly that hint. Markers are also logged, and the post-stream tooling reads them as highlights — the bridge to the VOD side covered in [part 2](/blog/neuroclip-2-vod-to-short-pipeline/).

For the phone and a Stream Deck, the main API stays on loopback and a separate, tiny HTTP surface offers just a handful of operations, protected by a long random token. When a token has to travel in a URL, put it in the **fragment**: browsers never send it to the server, so it does not end up in an access log. This is meant for a home LAN; if you expose something like it beyond that, put TLS in front of it.

Finally, everything above costs CPU on the same machine that renders the game and encodes the stream. So while OBS is streaming, the product steps back: its own child processes run at lower priority, meter frames are published less often, and scheduled heavy measurements wait until the stream is over.

## Pitfalls I would warn you about

1. **dB vs. linear.** Keep thresholds in dBFS, convert at the edge, and remember `-inf` becomes `null` in JSON.
2. **Raw vs. post-fader levels.** If you alarm on the post-fader peak of a muted mic, you will never hear anything. The pre-mute value carries the information.
3. **Counters since boot.** `GetStats` counters need a window and a reset-on-decrease rule.
4. **High-volume events are opt-in for a reason.** They are fine for one meter connection and terrible if every poller subscribes.
5. **Time-based rules need injectable clocks.** That is what makes "muted for a while" testable in microseconds.
6. **Do not pretend a stateless design is free.** It is simple and robust, and it is also the reason shared status reads exist.

## What's next

The Regie is the live half of the product. In [part 4](/blog/neuroclip-4-facecam-upscaling/) I go back to post-production and look at the most GPU-hungry stage: upscaling facecam footage, a job that, like everything heavy in the product, should not compete with a running stream. If you want to see the whole thing together, the [Neuroclip page](/page/neuroclip/) has the overview; early-access requests go to info@noobygames.de.

If you build your own OBS tooling in Go, the best starting point is still the [official protocol document](https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md) — it is precise and short. And for the Go side of things, my posts on [static linking checks](/blog/check-static-linking/) and [Go in Docker](/blog/go-docker/) cover background for the packaging in [part 5](/blog/neuroclip-5-shipping-kubernetes/).
