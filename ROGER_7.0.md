# Roger 7.0

**A clean slate.** This file is the home for the new information — the
Roger 7.0 information. It starts empty on purpose and fills up as you tell
me things.

## What this file is

- **Separate from everything else.** Nothing in [GAME_DESIGN.md](GAME_DESIGN.md)
  applies here. That document describes *+1 Size Escape* and stays exactly
  as it is; Roger 7.0 does not inherit its concept, its worlds, its economy,
  or its rules. If a Roger 7.0 idea happens to look like an old one, it is
  still decided fresh, here.
- **Live and editable.** Claude maintains this file: when you give new
  information for Roger 7.0, it gets written into the sections below,
  committed, and pushed. You can edit it by hand too — the next update
  builds on whatever the file says at that moment.
- **Allowed to reuse what already exists.** Roger 7.0 is a fresh design, not
  a fresh toolbox. It can pull from the models, asset packs, and modules
  already in this repository (inventory below) without copying the old
  design along with them.

## The Roger 7.0 information

Roger 7.0 is **TIDETOWN** — designed in-session from the proven elements of
the popular Roblox genres, then implemented under `tidetown/`.

### Concept

**TIDETOWN** — every few minutes the sea swallows a seaside town and you
ride the flood: catch creatures in the exposed tide pools at low tide,
then surf the flooded streets when the water comes roaring back.

You are a Tidekeeper. The whole server shares one visible tide clock
(~4 min low, ~2.5 min high, short foam-wall transitions). Low tide exposes
tide pools, a glowing cave, and the seabed; high tide floods the town to
the waist, opens mount surfing and the Deep Reef, and sends feral waves
against every keeper's boardwalk reef plot. One fantasy holds every
system: *you keep the shore, and the shore keeps changing.*

### Features

- **Timed-cast catching** — tap to cast, tap the flashing ring; a perfect
  tap rolls a strictly better rarity table. The server judges every tap
  on its own clock; the ring's speed and flash point are randomized per
  cast so no rhythm farms it.
- **Egg incubation by catches, not clocks** — eggs charge from successful
  catches; playing *is* the incubation. Caught species feed the Tidepedia
  and pay Shells; creatures you *keep* hatch from eggs.
- **Surge defense** — at high tide, feral waves attack your plot's
  barrier on a fixed lane. Your 3-creature team fights by role — Anchor,
  Sprayer, Herder, Sparker — with an explicit mixed-role link bonus, and
  your deflect tap (plus Sparker triggers) marks engagement. Uncleared
  enemies become salvage piles: failure pays differently, never punishes.
- **Mount surfing** — a free pier inner tube means every player surfs
  their very first flood; owned mounts add speed and Deep Reef access.
- **Reef building** — a persistent, publicly visible boardwalk aquarium
  paying capped passive Shells (offline under a third of active rate).
- **Tidepedia** — every first catch is permanent: capped luck buffs,
  Keeper Rank, and the zone gates (Town → Cave → Deep Reef).
- **Daily bounties + a streak that pauses, never resets.**
- **Full UI suite** — HUD with tide clock and currencies, Shop with
  published odds, Team, Reef, Tidepedia, Bounties, Settings (music, SFX,
  reduced motion), egg strip with hatch cinematic, surge banner and
  deflect button, tutorial, loading screen, toasts.

### Systems and rules

1. **Disjoint currencies.** Shells are time-earned (catching, reef,
   salvage) and buy eggs, reef, cosmetics. Stormglass is skill-earned
   (cleared surge waves, engagement-gated) and buys mounts and surge
   gear — things Shells can never touch.
2. **RNG picks which creature, never how strong.** All species sit in a
   narrow power band (rarity multipliers 1.0–1.4) as role side-grades.
3. **The server is the only authority** — casts, currencies, hatches,
   purchases, surge outcomes, mounts. Clients display and request.
4. **Every tunable number lives in `tidetown/shared/TidetownConfig.lua`.**
5. **Surges scale per player** (own lane, own Keeper Rank), escalation
   resets every cycle, odds are published in the shop, soft pity on every
   roll, offline gains capped, streaks pause. No monetization systems;
   nothing purchasable grants power.
6. Tidetown is a **separate Rojo project** (`tidetown.project.json`,
   its own place) — it never touches the +1 Size Escape game.

### Assets and models it uses

| Asset | Used as |
| --- | --- |
| `Sea_Animals_Pack` | Every catchable creature, companion, reef tank dweller, surge feral, and mount body |
| `Classic_Studs_Eggs_Pack` | The four zone eggs and the hatch cinematic |
| `Tds_Town_Pack` (Scenery) | The floodable town |
| Part-built | Beach, boardwalk, pier, plots, cave arches, water |

Reused code patterns: DataStore save discipline from `DataService`, the
model normalizer from `PetModels` (now `CreatureModels`), the remotes
registry pattern, and the full `UiBuilder` toolkit (now `TidetownUi`).

### Open questions

- Sound asset ids are `0` placeholders — paste real ids into the client
  `SoundController` / config when chosen.
- Kraken Tide, Daily Tide seed + leaderboard, Rival Tides, bait cooking,
  and tide variants are deliberately deferred to v1.1/v1.2 (see the
  concept's critique log in the pull request discussion).

## Implementation map

- `tidetown.project.json` — separate Rojo project (own place in Studio)
- `tidetown/shared/` — TidePhase, TidetownConfig, TidetownRemotes,
  CreatureCatalog, CreatureModels, CatchRules, TideLayout
- `tidetown/server/` — TidetownData, SettingsService, TideClockService,
  MapBuilder, CurrencyService, TidepediaService, CatchService,
  CreatureService, EggService, ReefService, BountyService, SurgeService,
  MountService, ShopService, init.server.lua
- `tidetown/client/` — TidetownUi, Toast, LoadingGui, HudGui,
  TideController, SwimController, CatchController, EggGui, TeamGui,
  ShopGui, SettingsGui, SoundController, TidepediaGui, BountyGui,
  ReefGui, SurgeGui, MountController, TutorialGui, init.client.lua

Sync it with `rojo serve tidetown.project.json`.

## What Roger 7.0 can reuse

Everything listed here already lives in this repository, so Roger 7.0 can
use it on day one. Listing something here does **not** mean Roger 7.0 uses
it — it means the option exists.

### Model and asset packs

Rojo mounts `assets/models/` at `ReplicatedStorage.Assets.Models`, so every
pack below is loadable at runtime from either side.

| Pack | Rough contents |
| --- | --- |
| `Low_Poly_Nature_Asset_Pack.rbxm` | Trees, rocks, terrain scatter |
| `Nature_Pack_Bundle.rbxm` | Additional nature scenery |
| `Low_Poly_Cave_Asset_Pack.rbxm` | Cave and underground pieces |
| `City_Asset_Pack_2026.rbxm` | Urban buildings and street props |
| `Tds_Town_Pack.rbxm` | Town buildings, tower-defense flavored |
| `Beach_Summer_Asset_Pack_2025.rbxm` | Beach, water, and summer props |
| `Classic_Studs_Eggs_Pack.rbxm` | Classic studded egg shells |
| `Sea_Animals_Pack.rbxm` | Fish, crabs, whales, krakens, axolotls |
| `Ultimate_Low_Poly_Food_and_Candy_Pack.rbxm` | Food and candy props |

### Code worth borrowing

| Module | What it gives you |
| --- | --- |
| `src/shared/PetModels.lua` | Loads a model from a pack, normalizes its size, centers it, and dresses it with auras, particles, and light |
| `src/shared/PetCatalog.lua` | Catalog/tier data shape for creature collections |
| `src/shared/Remotes.lua` | Remote event and function plumbing between server and client |
| `src/shared/GameConfig.lua` | The one place tunable numbers live |
| `src/shared/Stack.lua` | Reference typed prototype class |
| `src/shared/GamePhase.lua` | Reference enum table with a typo guard |
| `src/client/UiBuilder.lua` | UI construction helpers |
| `src/server/DataService.lua` | DataStore saving and loading with retries |

Roger 7.0 code, when there is any, follows the same house rules as the rest
of the repository: the style guide in [STYLE_GUIDE.md](STYLE_GUIDE.md) and
the project instructions in [CLAUDE.md](CLAUDE.md).

### Where new code would go

The Rojo map in `default.project.json` already routes `src/shared/`,
`src/server/`, and `src/client/` into the game. Roger 7.0 modules drop into
those same folders unless this file later says otherwise.

## How this file gets updated

1. You tell me the new Roger 7.0 information — in any order, in any amount.
2. I write it into the sections above, filling in or replacing the
   placeholders, and add new sections when the information needs them.
3. I run the repository's checks, commit, and push to the Roger 7.0 branch.

Old information never leaks in on its own. If you want something from
*+1 Size Escape* to apply to Roger 7.0, say so and I will copy it in here
explicitly.
