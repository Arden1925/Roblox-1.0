# +1 Size Escape — Design

The approved design. Update this document when the design changes so the
code and the plan never drift apart.

## Concept

You spawn tiny. Standing on **Grow Pads** raises your Size, which physically
scales your character. The map is a chain of **square worlds** separated by
**boundary walls that get taller every world**: bigger characters jump
higher, so growing is what earns you the climb — helped by floating steps
that add a light skill element. Tall borders ring the whole map; nobody
falls out.

Inside each world, barriers gate progress in both directions:

- **Size Gates** open only for characters that are big enough.
- **Squeeze Cracks** are passable only for characters that are small enough.
- **Shrink Pads** temporarily shrink you; you regrow automatically.

## The fairness rule

Two separate numbers per player:

| Number | Meaning |
| --- | --- |
| **Max Size** | Permanent progress. Only ever goes up. Saved, shown on the leaderboard. |
| **Current Size** | The body right now. Shrink Pads and Hazards lower it; it regrows to Max Size over time. |

Shrinking never costs progress. Nothing in the game — pads, hazards,
rebirth aside — ever lowers Max Size.

## The worlds

| # | World | Challenge theme | Exit wall |
| --- | --- | --- | --- |
| 1 | Sprout Meadows | Learn to grow | 14 studs, 3 steps |
| 2 | Vent City | Squeeze cracks, low vents | 22 studs, 3 steps |
| 3 | Ember Foundry | Hazards that shrink you, fading-platform bonus bridge | 32 studs, 2 steps |
| 4 | Cloud Capital | Bounce pads, fading staircase, sky garden | — |

Reaching a world for the first time (crossing its wall on foot) records it
permanently. **Portals** in every world open a destination picker: reached
worlds show a teleport button, unreached ones an animated lock and a
"reach it on foot first" message. The server validates every teleport.

## Skill obstacles

| Tag | Behavior |
| --- | --- |
| `Hazard` | Touch drops Current Size to the shrunk minimum (never Max Size) |
| `FadingPlatform` | Flickers ~0.8s after first touch, vanishes, returns after 3s |
| `BouncePad` | Launches you upward |

Worlds are 200 studs long and split into three sections -- grow (a size
gate), shrink (a squeeze crack), and skill (world flavor plus coin
routes) -- with **checkpoints** between them. Checkpoints save your
respawn point across sessions and pay coins the first time only.

## Coins

Every award scales with world index: pickups (`Coin` tag), first-touch
checkpoints, and first-time world reaches. Coins buy, at every world's
**Station**: potions (consumables; price scales with the world) and
**forever upgrades** whose price rises each level (Growth Training, Coin
Magnet, Spring Legs). Worlds divisible by 3 also have a **Mystery
Machine**: pay coins, get a random strong boost. Balance lives entirely
in `GameConfig.economy/potions/upgrades`.

## Pets

Each world has an egg capsule (`EggStand` tag). Coin eggs hold 5 pets on
3 rarity tiers; tiers slide up one per world, so later eggs are strictly
better. Rarity sets the pet's permanent growth bonus. One pet equips at
a time and follows you around. Each world also sells a Robux **royal
egg** (3 exclusive stronger pets), and a **limited Ultra Dragon** sits
on a pedestal at spawn. Inventory lives in the **Backpack** (bottom-left
button): Pets, Boosts, and a placeholder tab.

## Engagement systems

- **Offline growth**: size per minute away (config `offline`), capped,
  with a welcome-back popup. **AFK pods** at spawn grow you hands-free.
- **Events**: Golden Pads (random pad per world, x5, gold while lit) and
  Falling Stars (beacon beam; first touch wins size + coins).
- **Shiny hatches**: any hatch has a 5% shiny chance (x1.5 bonus).
  Server Luck (Robux) and rebirth luck skew the top-tier odds.
- **Daily quests + streak**: three rolled per day (`questTemplates`),
  seven-day streak calendar, all claims server-validated. The **group
  chest** at spawn pays members once `group.groupId` is set.
- **Mechanisms** (tags): `WeightPlate`/`MechBridge` (combined Current
  Size holds a bridge extended), `CrushBoulder` (CrushSize shatters it),
  `Updraft` (MaxLiftSize lifts small bodies), `Crusher` (sine-cycle bar,
  gentler cycles in early worlds), `AfkPod`, `GroupChest`.
- **Rebirth**: a page with the requirement bar and a NOW/AFTER perk
  table (+growth, +coins, +egg luck per rebirth), then a machine
  cinematic that drains the player before the reset applies.
- **Value packs**: escalating Starter/Pro/Mega products (Mega grants a
  permanent growth bonus) plus the server-wide luck boost.

## Sliders

A right-edge panel: **speed** (free, deliberately narrow 12-20 range --
speed is comfort, never progression) and **body size** (Size Master
pass, 999 R$), clamped between the shrunk minimum and earned Max Size.

## Tutorial

`GameConfig.tutorialSteps`, shown once to new players as a step-by-step
card with Next/Skip; the done flag persists.

## Rebirth

At the required Max Size (rises with each rebirth), a player can rebirth:
Max Size resets to 0 in exchange for a permanent growth multiplier.

## Monetization

Everything is speed or convenience; the whole game is completable free.

**Game passes** (`GameConfig.passes`, IDs pasted after creation on the
Creator Hub): 2x Growth, Instant Shrink (adds a Shrink button), Auto-Grow
(quarter-rate growth off pads), Super Squeeze (fit tighter cracks), VIP
(+25% growth and a golden trail), 2x Rebirth Bonus.

**City items** (developer products, one per world, buyable only while
standing in that world): Meadow Surge (+300 Max Size), Slick Coating (fit
any crack, 5 min), Ember Shield (hazard immunity, 5 min), Cloud Boots
(+50% jump, 5 min).

Ownership and timed effects are published as player attributes
(`Owns<PassKey>`, `<EffectKey>Until`) so any system can read them.

## Architecture rules

1. The server is the only authority on Size, world progress, and purchase
   effects. Clients display; they never decide.
2. Every tunable number lives in `src/shared/GameConfig.lua`; all world
   geometry math lives in `src/shared/WorldLayout.lua`.
3. DataStore calls are wrapped in `pcall` with retries. If a load fails,
   the session never saves, so real data is never overwritten.
4. Nothing yields on the main task; anything that waits runs in `task.spawn`.
5. Map elements are driven by CollectionService tags and attributes, so the
   map can be built and decorated freely in Studio:

| Tag | Attribute | Meaning |
| --- | --- | --- |
| `GrowPad` | — | Standing on it raises Size |
| `ShrinkPad` | — | Standing on it lowers Current Size |
| `SizeGate` | `RequiredSize` | Opens for players at or above the size |
| `SqueezeCrack` | `MaxAllowedSize` | Passable at or below the size |
| `Hazard` | — | Shrinks Current Size on touch |
| `FadingPlatform` | — | Vanishes after being stood on |
| `BouncePad` | — | Launches upward |
| `Portal` | — | ProximityPrompt opens the destination picker |

`MapGenerator` builds the starter map only when the workspace contains no
tagged parts, so a hand-built map always wins. The map floats slightly
above Y=0 so it never z-fights a leftover Baseplate, and leftover template
SpawnLocations are disabled (not deleted) so players always spawn inside
the borders.
