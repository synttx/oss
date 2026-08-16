# Quick Playtest ⚡❗

[![Version](https://img.shields.io/badge/version-1.0-E11D48?style=for-the-badge&logo=github&logoColor=white)](https://github.com/synttx/oss/releases)
[![Creator Store](https://img.shields.io/badge/Roblox-Creator_Store-00A2FF?style=for-the-badge&logo=roblox&logoColor=white)](https://create.roblox.com/store/asset/110463580214683/Quick-Playtest)
[![License](https://img.shields.io/badge/license-MPL--2.0-3B82F6?style=for-the-badge&logo=mozilla&logoColor=white)](LICENSE.md)
[![Luau](https://img.shields.io/badge/language-Luau-8B5CF6?style=for-the-badge&logo=luau&logoColor=white)](https://luau-lang.org)

A silly Roblox Studio plugin that lets you spawn your character right into the viewport during Edit Mode - **with live multiplayer replication**.

No playtest required. Jump straight into the viewport, mess around while your Team Create partners are busy working, fly around, and emote on them.

---

## Features

- ⚡ **Instant Viewport Spawning**: Spawn directly in Edit Mode without waiting for Studio playtesting to spin up.
- 👥 **Team Create Replication**: Movement, animations, and emotes replicate across the network in real time.
- 👀 **Zero Client Setup**: Other team members do not need the plugin installed to see your character.
- 🕺 **Emotes**: Wave, dance, and emote directly inside the editor.
- 🕹️ **Fly hax!!!**: Walk around or take flight across the workspace.

---

## Known Quirks & Notes

> [!NOTE]
> **Experimental Controller**: The movement controller is built from scratch and quite raw. You may run into rough edges with climbing, terrain, swimming, or occasional clipping.

> [!WARNING]
> **Network Overhead**: We're transmitting a lot of things here. In heavy places with many active characters, FPS drops may occur.

> [!NOTE]
> **Maintenance & Contributions**: Because this was a silly side project made while sick, it is not being actively maintained in favor of core libraries like [Scythe](../../packages/scythe) or [Vow](../../packages/vow). However, like with any other library in this repo, forks and PRs are completely welcome and reviewed!

---

## Credits

- [**Chickynoid**](https://github.com/MrChickenz/Chickynoid) - Took some code related to kinematic swept collision and stair stepping logic.
- [**Vide**](https://github.com/centau/vide) - UI library used.
- [**Play in Studio**](https://devforum.roblox.com/t/play-in-studio-plugin/2747428) (Chrythm) - Overall inspiration, the original plugin.

---

## Metadata

- **Version**: `1.0`
- **Author**: `checcerr` | `fridayqx`
- **License**: [Mozilla Public License 2.0 (MPL-2.0)](LICENSE.md)
