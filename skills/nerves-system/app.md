# The Nerves test app and the device's Elixir bits

The Nerves system makes the device bootable; the app makes it useful, in Elixir.

- Start from `mix nerves.new <app>` (`ports/<id>/hello_<name>/`). It brings `nerves_pack`:
  `nerves_runtime`, ssh, MOTD, VintageNet. Never hand-assemble an app: compare yours with a fresh
  generator output (mix.exs deps, config/target.exs, rel/vm.args.eex, iex.exs) and explain each
  difference.
- Networking stays `nerves_pack`'s: `usb0` through `VintageNetDirect`, `mdns_lite`, `nerves.local`.
  The kit's 10.0.42.1 convention belongs to its rescue images only: never carry it, a static
  address or a DHCP server into the app.
- Everything the device needs at boot (firmware loading, module order, a daemon such as rmtfs,
  marking an Android A/B slot successful) is a boot task or a supervised process, listed in
  `dossier/init-inventory.md` with its reason.
- Watchdog: decide between `nerves_heart` and feeding the hardware watchdog the bootloader armed,
  never neither.
- Iterate with `mix upload` over the USB network (or `scp -O` of single files); checkpoint with a
  full `mix firmware` and a clean install. Claim the device first (`tools/device-owner.sh`).

Report: the app path and generator version, the dependencies added and why, the compliance diff,
what ran on the device (IEx output), the firmware sha256 and the state the device was left in.
