# Analogy catalogue

Use them as starting points; adapt them to the learner. Always follow an analogy with the real thing.

| Concept | Analogy |
|---|---|
| Boot ROM | The phone's reflexes: hard-wired in the chip, it can't forget them, it can't be changed |
| Bootloader chain | A relay race: each runner checks the next one's badge before handing over the baton |
| Secure boot / signatures | Bouncers checking wristbands; unlocking the bootloader tells the bouncer "let my friends in too" |
| Second-stage bootloader (lk2nd) | A translator who stands between a strict old doorman (stock bootloader) and our modern guests (mainline kernels) |
| Kernel | The building manager: it owns the keys to every room (hardware) and tenants (programs) must ask it for everything |
| Device tree | The map of the house given to the building manager: "the kitchen light is switch 3 on panel B" |
| Drivers | The manager's phone book of technicians, one per appliance |
| Firmware blob | The tiny program a smart appliance needs before it works, like a printer that needs its own software |
| Coprocessor (modem, DSP) | A separate little computer living inside the phone, with its own OS, that we talk to through a mailbox |
| Rootfs | The furniture and tools in the house: everything that isn't the building itself |
| Initramfs | A camping kit: a tiny house carried in RAM that's enough to live in until the real house (storage) is ready |
| PID 1 | The first tenant, who must never leave: if it does, the building manager panics |
| Partitions | Labeled drawers in one big cabinet (the eMMC); some drawers hold the house keys and must never be emptied |
| Backup of EFS/persist | The phone's birth certificate and fingerprints: lose them and nobody can make new ones |
| fastboot boot | Trying on clothes in the shop (RAM) before buying (flashing) |
| Flashing | Writing with a pen instead of a pencil |
| Soft vs hard brick | A car that won't start vs a car with no engine |
| USB gadget networking | The phone pretends to be a USB network card, so the computer and the phone get a private two-person network |
| unudhcpd | A receptionist who only ever has one visitor and always gives them the same badge |
| Buildroot | A kitchen that cooks a whole OS from raw ingredients (source code) following a recipe (defconfig) |
| Cross-compiler | A translator who writes ARM books while living in an x86 house |
| Mainline vs downstream kernel | The official encyclopedia vs a photocopy someone annotated in 2014 |
| postmarketOS | A huge shared notebook where hundreds of people wrote down how they got Linux onto their phones |
| squashfs rootfs | A sealed, compressed suitcase: you can open and read, but not modify |
| A/B partitions | Two parachutes: you repack one while wearing the other; if the new one fails, the old one is still there |
| fwup | The parachute packer who knows exactly which straps go where |
| erlinit + BEAM | Instead of a crowd of shell scripts, one very reliable conductor (the BEAM) runs the whole orchestra |
| VintageNet | A network concierge written in Elixir that replaces NetworkManager & friends |
| Kernel command line | The sticky note the bootloader leaves for the kernel: "your root is in drawer 7, talk on screen 0" |
| ramoops / pstore | A flight recorder: the crashed kernel's last words, readable after a warm reboot |
