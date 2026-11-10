# Kernel work: drivers and device trees

A diagnosis becomes a kernel change that works on the device and could be sent upstream.

## Rules

- Search the kernel for an existing mechanism (a subsystem, a generic driver, a DT binding) before
  writing driver code, and say which ones the fix uses.
- Never work in the kernel's main checkout. Each topic gets a branch from the stable base in its
  own worktree (`git worktree add ../linux-<topic> -b <topic> <base>`).
- One change per commit, with an upstream-style message; run `scripts/checkpatch.pl` and, for DT
  changes, `make dt_binding_check`/`dtbs_check` on the touched bindings.
- Define the acceptance test before the first try, with enough trials to beat the failure rate:
  N runs without a failure at a 1-in-k rate happen by chance with probability (1 - 1/k)^N (14 good
  boots at 1 in 4 is about 2%). Test the real path: clean reboots, unclean resets and the second
  stage's hand-off, not only blank/unblank.
- Claim the device (`tools/device-owner.sh`) before any device command, release it when you
  report, and say which state you left it in. Respect "hands off".

## The hardware loop

1. Build only what changed, from the same tree and config as the running kernel, so module
   vermagic matches: the module, or the zImage/DTB (`make dtbs` for DT-only changes).
2. Copy with `scp -O` next to the original, keeping a backup of what it replaces (`<file>.orig`),
   or to the second stage's test slot (`buildroot-port` section 7: a kernel boots once and falls
   back on its own).
3. Reload or reboot, run the acceptance test, log the try in `journal/peripherals/<topic>.md`.
4. When it passes: fold it into the system's patches and run the full-build checkpoint.

## Lessons that cost days

- **Bootloader-lit displays:** a driver taking over a link the bootloader left running (LVDS, DSI,
  eDP) must stop the transmitter before reprogramming its PLL or clock; rewriting registers that
  already hold the right values does not reset it, and a clock change under a running link can
  leave the panel receiver unlocked (seen on MT8127 LVDS: stop the transmitter, then the vendor's
  1 ms PLL settle).
- **"Identical" register dumps** must cover the whole path (TX, analog and PLL blocks too), or they
  prove nothing.
- **Unbinding display components** on a live system: unbind the DRM master before its bridges, or
  it can oops.
- Judge the display only after a clean reboot: a watchdog or forced reset can leave the display
  engine stalled.
