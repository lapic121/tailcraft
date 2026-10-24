<div align="center">

# 🧊 TailCraft

**A free Windows launcher that opens a Minecraft server in one click — no port forwarding.**

[Download](https://lapic121.github.io/tailcraft/) · [Ko-fi](https://ko-fi.com/sangdeok) · [Discord](https://discord.gg/rv5sH6RbS)

Windows 10 / 11 · Free

**🇬🇧 English · [🇰🇷 한국어](README.ko.md)**

</div>

---

## About

TailCraft is a GUI launcher that handles everything you normally repeat when hosting a Minecraft server for friends — router port forwarding, installing Java, downloading server files, firewall rules. Run the EXE, pick your language (Korean/English), and an 8-step tutorial walks you through to a running server.

## Features

- **Server types** — Paper · Purpur · Folia · Fabric · NeoForge · Forge · Arclight (run Bukkit plugins on a modded server). Versions/builds load automatically; the right Java (8/17/21/25) installs itself.
- **3 ways to connect** — Tailscale (no port forwarding) · port forwarding (automatic UPnP) · LAN. Allow it through the firewall with one click.
- **Live dashboard** — CPU · RAM · disk · players, with a RAM allocation slider.
- **Mods & plugins** — Modrinth search & install (dependencies resolved automatically), enable/disable toggle, export a mod zip for friends.
- **Player tools** — nickname & IP history, one-click whitelist / OP / kick / ban.
- **Console, event log, diagnostics** — quick-command buttons, a separate view for join/leave/error events, one-click diagnostics copy.
- **Korean / English UI** — switch instantly from the top bar.
- Korean & English network-setup guide PDFs included.

## Download

👉 **https://lapic121.github.io/tailcraft/**

Or grab `TailCraft.zip` from [Releases](https://github.com/lapic121/tailcraft/releases/latest).

1. Unzip and run `TailCraft.exe`
2. Unsigned personal build, so if SmartScreen warns: **More info → Run anyway**
3. Server files and Java are not bundled — they download from official sources at runtime. The Minecraft EULA must be accepted.

## Safety & integrity

This repository is **source-available** — anyone can read and audit the code (see the license below).

- **No bundled third-party files.** No server jar, Java or plugin is included. At your choice, they download at runtime only from their official sources (PaperMC, FabricMC, NeoForged, Forge, Modrinth, Adoptium, Tailscale). No information is sent to the author.
- **Integrity check.** At launch the launcher compares the SHA-256 of the bundled `lib\core.ps1` against a value embedded in the EXE and refuses to run if tampered with.
- **Verify your download.** Check that the EXE you downloaded matches the official build.

  ```
  TailCraft.exe  SHA-256:
  B0215D85E829FC1B8FA90EBCFEDBB175588965F4EFF97814281DD3B0F639DC27
  ```

  Windows (PowerShell or cmd):
  ```
  certutil -hashfile TailCraft.exe SHA256
  ```
  If it matches, it's authentic. If not, re-download from the official link.

## Build from source

- Launcher: `launcher.ps1` + `lib/core.ps1` (PowerShell 5.1 / WPF)
- Single-EXE wrapper: `build/exe/main.go` (Go) — embeds and extracts the scripts, then runs them with a hidden console. `go build` injects the script-hash check.
- Manual PDFs: `build/make_pdf.py`, `build/make_pdf_en.py` (reportlab)

## License

**Copyright © 2026 Sangdeok. All rights reserved. — Source-available (NOT open source).**

The source is published for reading, auditing and learning, but **modification, redistribution, commercial use, code reuse and bypassing the integrity check are not permitted**. See [`LICENSE.txt`](LICENSE.txt). Contact for exceptions.

## Unofficial

TailCraft is not affiliated with, sponsored or endorsed by Mojang Studios, Microsoft, Tailscale Inc., PaperMC, FabricMC, NeoForged, Minecraft Forge, Arclight or Modrinth. "Minecraft" and "Tailscale" are trademarks of their respective owners; references are for compatibility only.

## Contact

- Email: dwxw777@gmail.com
- Discord: [discord.gg/rv5sH6RbS](https://discord.gg/rv5sH6RbS) (sangdeok)
- Support (optional): [ko-fi.com/sangdeok](https://ko-fi.com/sangdeok)
