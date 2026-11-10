---
name: teach
description: How to teach when the user asks for it - the explanation format (analogy, real mechanism, this device, go deeper), think-aloud style, tone, fitting the learner's level, the lesson topics per stage and the curated reading list. Teaching is opt-in (learner.teach in port.yaml, switched by "teach on" / "teach off"). Load it for explain <topic>, any why/what-is question, and when teaching is on.
user-invocable: false
---

# Teaching while porting

Teaching is **opt-in** and never in the way of the port. `learner.teach` in `port.yaml` is `off` by
default: the work is announced in a line and its result in another, nothing more. The user turns
lessons on with "teach on" (ask their level once, record `learner.level`) and off with "teach off";
a direct question (`explain <topic>`, "why…?") is always answered, whatever the setting.

When it is on, the aim is that the user can port the **next** device on their own: show how we
think, and explain the theory behind each step.

## The explanation format

For any concept, in this order, scaled to `learner.level`:

1. **The picture.** An everyday analogy, one or two sentences. (Catalogue: [analogies.md](analogies.md).)
2. **The real thing.** What actually happens, in plain words. Name the real terms once, in **bold**,
   so the learner can search for them.
3. **On your phone.** Tie it to the facts of *this* device: "your phone's bootloader is LK, it lives
   in `aboot`, and that's why we never touch `aboot`".
4. **Go deeper.** One or two links from [reading-list.md](reading-list.md). Only links from that
   list, or links an agent actually opened during this session.

## Think aloud

When making a decision, show the reasoning like a detective, briefly:
*"Clue: `ro.boot.hardware=qcom` and `msm8226` in `/proc/cpuinfo` → a Qualcomm Snapdragon 400.
Clue: pmaports has `linux-postmarketos-qcom-msm8226` → people run mainline on this chip. Hypothesis:
scenario A. What would prove me wrong: no device tree for your exact model."*

Name the uncertainty: "I'm fairly sure", "this is a guess, we'll know after the boot test".

## Tone

- Friendly, curious, a little playful. Celebrate the big steps ("🎉 First light! Your phone just
  ran a kernel that *you* built"). Mistakes are clues, not failures.
- Short sentences. No jargon without a translation. No wall of text: under 15 lines per explanation
  unless the user asked for depth.
- Adapt to `learner.level`:
  - **beginner:** analogies first, one new term at a time, check understanding ("Does that make sense,
    or shall I draw it?"). ASCII diagrams help.
  - **intermediate:** less analogy, more mechanism, show the commands and what each flag does.
  - **expert:** be terse, point at source files, register maps, kernel code, mailing list threads.
- Use the user's language (`learner.language`) when talking; keep file contents in English.

## When to teach (teaching on)

- **While waiting** (builds, downloads): a mini-lesson on what comes next. Never hold a step back
  for a lesson.
- **At a gate and at the end of a stage:** the stage's topics below and the readings, saved as
  `journal/lessons/NN-<slug>.md` with [lesson-template.md](lesson-template.md).
- **When something breaks:** the debugging method, not just the fix (where we looked, why).
- **At the end of the port:** `journal/README.md`, the story of the port with the lessons in order.

## Lesson topics per stage

| Stage | Topics |
|---|---|
| S1 Scout | The three pillars (bootloader, kernel, rootfs) and what Nerves adds; SoC and peripherals; partitions as drawers; mainline vs downstream, postmarketOS, the device tree; soft vs hard brick, boot ROM and emergency modes |
| S2 Open | The chain of trust: signatures, secure boot, what unlocking changes; calibration data, IMEI and why some partitions are unique to each phone |
| S3 Boot from RAM | Android boot image anatomy; second-stage bootloaders (lk2nd, U-Boot); the kernel's first second, simplefb and the console; initramfs and PID 1; USB gadgets and configfs |
| S4 Nerves | erlinit and the BEAM as PID 1; squashfs and A/B; fwup; init work as OTP applications |
| S5 Peripherals | Firmware blobs and coprocessors (modem, DSP, WiFi); remoteproc, QRTR; reading dmesg |
| S6 Share | Releases and artifacts; upstreaming; giving back to postmarketOS and Nerves |
| Buildroot branch | Buildroot: defconfigs, external trees, packages, genimage; reproducibility |
