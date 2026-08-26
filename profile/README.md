<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/nivuus/.github/main/profile/assets/wordmark-dark.png">
    <img src="https://raw.githubusercontent.com/nivuus/.github/main/profile/assets/wordmark-light.png" alt="Nivuus" width="220">
  </picture>
</div>

<br>

## One machine instead of five

Nivuus replaces the NAS, the home automation hub, the media server, the central
router and the living-room console with a single self-hosted box. You set it up
from your phone, in about ten minutes. No subscription to play online, and no
data leaving your home by default.

Pronounced **/ni.vys/** — *nee-vuce*, two syllables.

## The range

|  | Nivuus Core | Nivuus Play |
| --- | --- | --- |
| Replaces | NAS, home automation hub, media server, router | the same, plus the living-room console |
| Graphics | integrated (Intel QuickSync) | discrete card |

One chassis, one power supply, one certification. The Core is a Play without the
card — **start without one, add it whenever you want.** The installer detects the
discrete GPU and configures passthrough on its own, so the machine reconfigures
itself instead of being replaced.

## What we publish

- **[installer](https://github.com/nivuus/installer)** — the bootable ISO and its
  setup wizard. It opens its own hotspot at boot, a setup page appears, you pick
  your disk and your features, and the server installs itself. Runs on any
  machine, not just ours. MIT.
- **[shell](https://github.com/nivuus/shell)** — the ZSH environment that ships on
  every Nivuus machine. MIT.

The printable chassis of the Nivuus Slim — STL files and full bill of materials —
is published as open hardware next, alongside the first hardware kit.

## What Nivuus does not replace

Worth saying ourselves, since anyone testing it will find out anyway.

- **Your ISP's fibre termination.** Nivuus sits behind it. We replace the router
  and the central access point, not the line.
- **Wi-Fi coverage across a whole house.** A box in a cabinet is physics, not
  software. Existing mesh satellites stay where they are and connect behind it.
- **A screen, a controller and a TV client.** The console goes away; the things
  you plug into it do not.

## Principles

**Sovereignty.** Free software, self-hosted, nothing routed through a third-party
cloud by default.

**Repairability.** Upgrading from Core to Play does not mean buying another
machine. Documented parts, nothing sealed shut.

**Commons.** The installer and the wizard are open source; the Slim chassis is
open hardware.

---

<div align="center">
  <a href="https://nivuus.com">nivuus.com</a> · <a href="mailto:support@nivuus.com">support@nivuus.com</a>
</div>
