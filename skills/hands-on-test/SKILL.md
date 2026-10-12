---
name: hands-on-test
description: Running a test that needs the user at the device (keys, cables, watching the screen, a battery pull) - one test at a time, exact instructions with timing and the expected screen, key windows designed for humans, photos read and confirmed from the host, and never acting before the user says they are watching. Load it before asking the user to do anything with the device.
---

# Tests with the user at the device

1. **One test at a time.** Say what it proves, then wait for "I'm watching" (or "ready") before any
   flash, boot or reboot. Never act on a timeout while waiting for the user.
2. **Exact instructions:** when (after which screen), which key, for how long, what the screen must
   show at each step, what success looks like, what failure looks like, and how to get out
   (the key combo, the battery).
3. **Key windows for humans:** a prompt on the screen and polling for about 3 s, accepting a key
   already held; never a single sample at one instant (users miss it every time). Never ask for a
   key from power-on when the stock bootloader reads that key too (it may mean factory mode).
4. **Photos:** ask for a photo at the steps that matter and say what to frame; read it and transcribe
   the relevant lines into the journal.
5. **Confirm from the host:** check the result with `fastboot getvar`, ssh, `lsusb`, `dmesg` rather
   than trusting the screen alone.
6. **While the user works on the device** (a write they run, a cable swap): they type "hands off"
   and every agent's device commands are denied until "hands on".
7. **Record** the test, the instructions given, the photos and the host evidence in the backlog task.
