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

*Nothing recorded yet.* Everything you send me for Roger 7.0 lands under the
headings below.

### Concept

_Waiting on you._

### Features

_Waiting on you._

### Systems and rules

_Waiting on you._

### Assets and models it uses

_Waiting on you — see the inventory below for what is already on hand._

### Open questions

_Waiting on you._

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
