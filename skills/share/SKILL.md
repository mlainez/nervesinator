---
name: share
description: Stage S6 of a port - make the Nerves system usable by someone else and add it to the family - the README with its Dependencies section, a one-command installer from a stock phone and its safety review, the release recipe (images, SHA256SUMS, GPL source references), gate G3 before anything becomes public, then the row for the awesome-nerves-systems list. Use when tools/kit-next.sh shows stage S6, or when the user wants to publish a port.
---

# S6 Share

A port is finished when someone else can install it and the next similar device can start from
it. Details of the README, installer and release recipe: `nerves-system` porting.md section 8.

## 1. Prepare (host only, nothing public yet)

- **README**: what works and what does not, the Dependencies section, the flash steps.
- **`install.sh`**, from a stock phone to Nerves: dry run by default, identity checks, class B
  backups before any write, checksum-verified downloads, the port's proven key-free path.
- **LICENSE**, and no proprietary blob in the repository.

Review the installer like a flash plan, since the kit's guard does not run on other people's
computers: every write targets an allowlisted partition through the proven path, the forbidden
list is enforced in the script, irreversible costs are named before the typed confirmation, and
each failure point says how to recover. Report each finding with its line.

## 2. Gate G3: publish

Show the user exactly what becomes public: the repository and its name, the release assets, the
row for the list. Pushing, creating a release and opening a pull request happen only after their
go, recorded as `G3` in `gates_passed`.

## 3. Release

A tagged release carrying the system artifact, the raw image and `.fw` of the test app, the
second-stage image, `SHA256SUMS`, and the source references of the GPL parts (kernel commit,
Buildroot and package versions) → `checks.release: "<release URL>"`.

## 4. The family list

Add the device to [awesome-nerves-systems](https://github.com/mlainez/awesome-nerves-systems), in
the table of its category (phones and tablets go under "Smartphones and Tablets"), as a pull
request the user opens or approves:

```
| <Device name> | [<owner>/<repo>](<repo URL>) | <nerves_system_br version from mix.exs> |
```

Then add its line to `tools/lib/family.tsv` in the kit, so the next similar device finds it
(`nerves-system` family.md) → `checks.awesome_row: "<pull request URL>"`.

## 5. Optional

- A buildroot-android board and its pull request (`buildroot-port`), when the user took that branch.
- The port's story (`explain`, journal), when teaching was on.
