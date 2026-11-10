---
name: explain
description: Explain a concept from the porting journey (bootloader, device tree, initramfs, fastboot, A/B, firmware blobs…) at the learner's level, short inline or as a full lesson saved to the journal. Use for /explain <topic> or any "why/what is" question from the user.
argument-hint: "<topic>"
---

# Explain

1. Read `learner:` from the active `port.yaml` (level, language). Load the `teach` skill. A question
   is always answered, whether teaching is on or off.
2. If the question can be answered in under ~15 lines, answer inline using the teach format
   (analogy → the real thing → how it shows up on *this* device → one reading link).
3. If it deserves more (or the user asks "go deeper"), write a lesson with the teach skill's
   lesson template, using the facts of this device, to `ports/<id>/journal/lessons/NN-<slug>.md`.
   Give the user a 5-line summary and the path.
4. Tie it back to the current task: "this is why we are doing X right now".
