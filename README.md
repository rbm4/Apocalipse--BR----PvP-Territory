# Apocalipse [BR] - PvP Territory

Project Zomboid Build 42 multiplayer mod that turns marked regions into faction-controlled PvP objectives. Factions can capture territory, defend holdings with allies, earn rewards from owned zones, and give admins in-game tools to build the battlefield around their server economy.

## Features

- Faction-based territory capture with live owner, attacker, contested, protected, and progress states.
- Capture logic based on online faction presence inside a zone.
- Defenders and allied factions can contest attacks and stop capture progress.
- Multiple attacker factions in the same zone force a contested state.
- Offline raid protection for territory owners, with optional expiry after inactivity.
- Abandonment cleanup that can return territories to Neutral after a faction has been inactive too long.
- Global radio-style alerts and local player alerts for attacks, captures, abandoned zones, and payday events.
- ModData-backed synchronization for multiplayer zone definitions and zone status.

## Territory Tools

- Player-facing capture progress overlay while standing inside a territory.
- Faction control panel with territory status, ownership lists, map display, and diplomacy actions.
- World map rendering for territory areas, using faction colors when available.
- Context-menu access to the faction territory panel.
- Admin-only territory editor for creating, renaming, deleting, teleporting to, and changing zone types.
- Drag-to-draw style map workflow for creating custom conquest areas.
- Reward containers can be linked to territories through the world object context menu.

## Rewards and Buffs

- Daily faction salary payout at 9:00 AM for online faction members.
- Salary scales with the number of zones owned by the player's faction.
- Linked reward crates restock every 24 in-game hours for the owning faction.
- Configurable salary item, salary amount, crate reward item, crate amount, and bonus loot.
- Custom reward item lists support comma- or semicolon-separated item IDs.
- Server-authoritative passive XP and survival buffs for players inside zones owned by their faction or an allied faction.
- Territory perk tree with themed zone perks.

## Zone Types

Zones can be assigned gameplay themes that affect passive training and reward flavor:

- Standard
- Armory
- Hospital
- Workshop
- Bunker
- Industrial
- Estacao
- Umbrella
- Posto

## Diplomacy

- Faction leaders can send alliance invites from the territory panel.
- Alliances are mutual once accepted.
- Allied factions count as defenders for contested-zone logic.
- Invites can be accepted, declined, or cleared through the UI.
- Alliance creation is limited so each faction can keep one active ally.

## Server Configuration

Sandbox options let server owners tune the system without editing Lua:

- Capture time
- Capture speed multiplier
- Decay speed multiplier
- Capture announcements
- Daily salary item and amount
- Passive XP amount
- Offline protection and expiry time
- Faction abandonment timeout
- Custom salary reward items
- Custom crate reward items
- Crate loot amount
- Bonus crate loot toggle

## Requirements

- Project Zomboid Build 42.19 or newer.
- `ApocalipseBR_Regioes` is required and loaded before this mod.

## Repository Layout

- `Apocalipse [BR] - PvP Territory/common/mod.info` - mod metadata.
- `Apocalipse [BR] - PvP Territory/common/media/lua/shared/FactionZones.lua` - shared zone lookup and client cache bridge.
- `Apocalipse [BR] - PvP Territory/common/media/lua/server/FactionWarLogic.lua` - server capture, rewards, diplomacy, and zone commands.
- `Apocalipse [BR] - PvP Territory/common/media/lua/server/FactionBuffsAuthority.lua` - server-authoritative zone buffs and XP.
- `Apocalipse [BR] - PvP Territory/common/media/lua/client/` - UI, HUD, map editor, moodle, and admin helpers.
- `Apocalipse [BR] - PvP Territory/common/media/sandbox-options.txt` - server tuning options.
- `workshop/description.txt` - Steam Workshop description.

## Build

This repository is configured for Project Zomboid Studio:

```sh
npm run build
```

Other available scripts are `npm run clean`, `npm run watch`, and `npm run update`.
