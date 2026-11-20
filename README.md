# Karlach's Rage

> *Karlach's engine burns with the flames of Avernus. They made her powerful enough to be a champion of the Blood War and Zariel's prized pet, and the destruction she now deals out shows it.*

A Baldur's Gate 3 mod that turns Karlach's Rage into a growing infernal fury. The longer she rages, the more damage types she becomes immune to, until her engine burns so hot it destroys the gear she is wearing.

## Requirements

| Requirement | Notes |
|---|---|
| [BG3 Script Extender](https://github.com/Norbyte/bg3se) | Required. All of the progression logic runs in Lua. |
| True Rage Unlimited
| [Mod Configuration Menu (MCM)](https://www.nexusmods.com/baldursgate3/mods/9162) | Optional. Adds the **Immune Items** and **Debug** tabs. |

## Features

### Always on: Infernal Engine Immunity
Karlach has a new passive that makes her immune to the **Burning** condition.

### Rage progression
The progression starts as soon as Karlach rages. Each tier keeps all the immunities of the tiers before it.

| Tier | Starts | Lasts | Effects |
|---|---|---|---|
| Fire | When she rages | 2 turns | Immune to Fire damage. **Vulnerable to Cold damage** for the whole rage. |
| Bludgeoning | Turn 2 | 2 turns | Immune to Bludgeoning damage. |
| Slashing | Turn 4 | 2 turns | Immune to Slashing damage. |
| Piercing | Turn 6 | 3 turns | Immune to Piercing damage. |
| Thunder | Turn 9 | 3 turns | Immune to Thunder damage. Gains **Scorching Aura** and a **burning aura**. **One random equipped item is destroyed.** |
| Force | Turn 12 | Until rage ends | Immune to Force damage. **+4 Strength, +2 Dexterity, +1 Constitution.** Gains an infernal **Fireball**. **Every equipped item is destroyed**, and anything she equips afterwards is destroyed every 2 turns. |

- **Scorching Aura:** her attacks deal an extra 1d6 Fire damage. It doesn't work while she is Wet.
- **Burning aura:** everyone within 2 m of Karlach is set Burning, **including your own party**.
- **Infernal Fireball:** 10d6 Fire damage in a 6 m radius, for 1 action. **Casting it ends her rage immediately.**
- **Outside combat:** the progression runs in real time, at about 6 seconds per turn.
- **Downed:** the progression pauses while she is downed and picks up again when she gets back up.
- **Rage ends:** however it ends (End Rage, True Rage Unlimited's inactivity rule, or the Fireball), every tier, aura and bonus is removed.

There are **no overhead indicators** for the tiers. Count her turns, or check her passives.

### Soul Coins
- A Soul Coin is now worth **5000 gold**.
- When Karlach consumes a Soul Coin, she gains the base game's **Infernal Fury** until her next long rest. While she has it:
  - **None of her equipment is destroyed** by the Thunder or Force tiers.
  - **Casting the Fireball doesn't end her rage.**
  - **Her rage can't end from inactivity** (not attacking or taking damage), in or out of combat. It ends only through End Rage, a long rest, or the Debug button.

### MCM settings
- **Immune Items:** search every item in the game or one mod's items, and tick any you want protected from destruction. The list is saved globally, so it applies to all your saves.
- **Debug:** an **End Karlach's Rage** button for when the progression keeps running after a fight. It only works **outside combat**.

## Installation
1. Install the BG3 Script Extender.
2. Install True Rage Unlimited.
3. Install Karlach's Rage and place it **after** True Rage Unlimited in your load order.
4. Optional: install MCM.

## Compatibility
- Works whether Karlach is a companion or your origin character.
- Overrides `ORIGIN_Karlach` (her passive list), `ORI_KARLACH_INFERNAL_FURY` and the Soul Coin's value (`GLO_SoulCoin`). Mods that change the same entries may conflict, and whichever loads last wins.
- Other Barbarians are not affected.

## Troubleshooting
The Script Extender console prints every step with a `[KarlachsRage]` prefix, for example `Rage shout detected`, `APPLY_STAGE_TB`, `TB turn decrement` and `Ending rage progression`. Include those lines when you report a bug.

## Comments and Reports
You can comment about the Mod here: https://rpghq.org/forums/viewtopic.php?p=433809-karlach-s-rage-5-baldur-s-gate-3 . (Be aware of the kind of Website this is if you venture out of my Thread though, people on the site are pretty unhinged.)

