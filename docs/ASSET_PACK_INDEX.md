# Asset Pack Index

The authoritative reference for the nine `.rbxm` packs in `assets/models/`.
Read this BEFORE spawning, cloning, or naming any pack model. Every name
below was extracted from the binary rbxm files themselves (parser dump:
`docs/asset-pack-index.json`, full instance tree per pack) and cross-checked
against the code that consumes them (`src/server/HubService.lua`,
`src/server/SceneryService.lua`, `src/shared/PetModels.lua`,
`tidetown/shared/CreatureModels.lua`, `tidetown/server/MountService.lua`,
`tidetown/server/MapBuilder.lua`). When this doc and the JSON disagree, the
JSON wins; regenerate it from the rbxm files, never edit it by hand.

Games referenced below: **SE** = +1 Size Escape (`src/`), **TT** = Tidetown
(`tidetown/`).

## Usage rules

**Mounting.** Both `default.project.json` and `tidetown.project.json` map
`assets/models/` to `ReplicatedStorage.Assets.Models`. Rojo turns each
`.rbxm` file into ONE child of that folder named after the file — e.g.
`ReplicatedStorage.Assets.Models.Sea_Animals_Pack`. The pack's own root
folder is unwrapped; its children (usually a `Models` folder) sit directly
under the file-named instance.

**Path helpers — never hand-roll FindFirstChild chains.**

- SE decoration: `HubService.lua` and `SceneryService.lua` each define
  `PropPath` helpers that encode the pack-internal prefix once —
  `naturePath(name)`, `beachPath(name)`, `seaPath(name)`, `eggPath(name)`,
  `cityPath(category, name)`, `foodPath(name)`, `cavePath(index)`,
  `bundlePath(folder, index)` — resolved by `findProp` (string segments via
  `FindFirstChild`, number segments via `GetChildren()[n]`) and placed by
  `placeProp` (clone, inert, scale to height, stand bottom-down). Add new
  props through these helpers only.
- SE pets: `src/shared/PetModels.lua` `findAnimalTemplate` — Sea pack
  `Models` folder, direct name then `MODEL_ALIASES`.
- TT creatures and eggs: `tidetown/shared/CreatureModels.lua`
  `findPackTemplate(packName, modelName)` — resolves inside the pack's
  `Models` folder (Models only, never `Decoration`): direct name, then
  `MODEL_ALIASES`, then space-stripped fallback
  (`string.gsub(modelName, " ", "")`).
- TT mounts: `MountService.lua` reads the Sea pack `Models` folder directly.
- TDS scene: `HubService.lua` (`buildTdsIsland` path) and TT
  `MapBuilder.lua` both clone `Tds_Town_Pack.Scenery` wholesale.

**Always-fallback discipline — non-negotiable.** The packs are optional at
runtime (Assets may not be synced). Every consumer must render something
sensible with zero pack instances present: `placeProp` takes an optional
part-work fallback and warns on missing props; `CreatureModels.build`
always returns a model (tinted ball with eyes); `PetModels` has a primitive
fallback pet; `CreatureModels.buildEgg` falls back to a studded primitive
egg. New code follows the same rule: prefer the pack model, compose
identically without it, never error on a missing template.

**Name traps — check before you type a model name.**

- `FindFirstChild` is exact-match. Several display names are stored
  space-less or oddly spelled; exact spellings are flagged per pack below.
- Duplicated siblings are common (Sea pack especially). `FindFirstChild`
  returns the FIRST; fine for cloning, but never assume a name is unique.
- Two Nature pack names carry a LEADING SPACE: `" Small Squared Tree"` and
  `" Small Tree"`.
- Numbered variants follow TWO patterns and the pack mixes them: some
  families have an explicit `1` (`Rock 1`/`Rock 2`, `Log 1`, `Fence 1`,
  `Street Lamp 1`), others use bare-name-plus-`2` (`Tree`/`Tree 2`,
  `Pine Tree`/`Pine Tree 2`, `Tree Stump`/`Tree Stump 2`, `Bush`/`Bush 2`,
  `Warning Fence`/`Warning Fence 2`, `Surf Board Scene`/`Surf Board
  Scene 2`). The lists below are exact — copy from them.
- Cave and Food packs have NO useful names: address caves by child index
  (`cavePath(n)`), food by `food_1`..`food_39`.

## Parser corrections (verbatim from the rbxm parse)

> **No corrections needed — MODEL_ALIASES is fully correct.** All four
> aliased names exist in the pack exactly as the alias targets say
> (space-less): `ElectricEel`, `SteampunkTurtle`, `FruitTurtle`,
> `FlowerWhale`; the spaced forms do not exist in the pack. All 27
> `modelName`s in CreatureCatalog.lua resolve: 24 direct hits, 3 via alias
> (`Electric Eel`, `Steampunk Turtle`, `Flower Whale`). The `Fruit Turtle`
> alias is currently unused by the catalog but correct. Note the aliases
> are technically redundant — `findPackTemplate`'s space-strip fallback
> (`string.gsub(modelName, " ", "")`) would also resolve all three.
> Caveats for future code: several sea models are DUPLICATED siblings
> (`FindFirstChild` gets the first): Alligator, Beluga Whale, Crystal
> Shark, Dolphin, Jellyfish, Lobster, Manta, Narwhal x3, Nebula Whale,
> Orca, Penguin, Pufferfish, Seahorse, Seal x3, Shark, Swordfish, Tuna,
> Turtle, Walrus, Whale x3. Near-duplicate spelling traps: `Angler Fish`
> vs `Anglerfish`, `Hammerhead Shark` vs `HammerheadShark`, `JellyFish`
> vs `Jellyfish`, `Collosal Squid` (sic), `Seaturtle` + `Seaturtle_E1`,
> and 5 `PetLOD/Xxx` variants (slash in the Name).

(SE's `src/shared/PetModels.lua` carries the identical `MODEL_ALIASES`
table and the same conclusion applies.)

## Sea_Animals_Pack — 9,348 instances

Structure: `Sea Animals Pack - Uqel` [Folder] → **`Models`** [Folder]
(132 rigged Model children — Motor6D/Bones/AnimationController inside) +
`Baseplate` [Folder] (a base Part and 3D-text `Title` — decor, not usable).
Path prefix: `seaPath(name)` = `{ "Sea_Animals_Pack", "Models", name }`.

Exact-spelling flags (no space / odd spelling — use these strings):
`ElectricEel`, `SteampunkTurtle`, `FruitTurtle`, `FlowerWhale`,
`HamburgerTurtle`, `HammerheadShark` (also spaced `Hammerhead Shark` — a
DIFFERENT sibling), `Anglerfish` (also `Angler Fish`), `JellyFish` (also
`Jellyfish` x2), `Collosal Squid` (sic), `Killerwhale`, `OceanSunfish`,
`Pacificnewt`, `PirateCrab`, `SeaHare`, `SeaSlug`, `SeaUrchin`,
`Seaturtle`, `Seaturtle_E1`, and five names containing a literal slash:
`PetLOD/Lionfish`, `PetLOD/Octopus`, `PetLOD/Sawfish`, `PetLOD/Tigerfish`,
`PetLOD/Tuna`.

**Used by BOTH games (29)** — SE egg pets + TT creature catalog:
Alien Jellyfish, Ancient Whale, Axolotl, Beluga Whale (also TT mount),
Candy Turtle, Catfish, Clownfish, Crab, Crystal Shark, Cyber Shark,
ElectricEel (via alias "Electric Eel"), Flounder, FlowerWhale (via alias),
Galaxy Axolotl, Goldfish, Infernal Axolotl, Lobster, Lunar Penguin,
Meteor Crab, Meteor Lobster, Narwhal, Nebula Whale, Pufferfish, Seahorse,
Skeletal Shark, SteampunkTurtle (via alias), Steve The Stingray,
Tigerfish, Void Turtle.

**Used by SE only (8)**: Ancient Kraken (limited pet), Celestial Axolotl
(Cloud Royal Egg), FruitTurtle (via alias, Meadow Royal Egg),
Mutated Shark (Ember Royal Egg), plus decor placements — Whale (sky
whale), Turtle (beach), Jellyfish (grotto), Shark (SceneryService).

**Unused — design headroom (72)**: Alligator, Angler Fish, Anglerfish,
Arowana, Astronaut Crocodile, Barreleye Fish, Bighead, Blobfish, Bloop,
Blue Octo, Blue Tang, Bonnethead Shark, Butterflyfish, Candy Orca,
Cherry Orca, Collosal Squid, Corrupt Crocodile, Dolphin, Eel, El Maja,
Festive Penguin, Festive Seal, Fish, Great White Shark, Greg The Shark,
Hairtail, HamburgerTurtle, Hammerhead Shark, HammerheadShark, JellyFish,
Killerwhale, King Crab, King Seal, Kraken, Leopard Seal, Lionfish, Manta,
Mutated Axolotl, Nautilus, Needlefish, Newt, Noble Crocodile,
OceanSunfish, Octopus, Orca, Pacificnewt, Penguin, PetLOD/Lionfish,
PetLOD/Octopus, PetLOD/Sawfish, PetLOD/Tigerfish, PetLOD/Tuna, Pink Octo,
PirateCrab, Red Squid, Salamander, Sawfish, SeaHare, SeaSlug, SeaUrchin,
Seal, Seal Plushie, Seaturtle, Seaturtle_E1, Skeleton Crab, Spider Crab,
Starfish, Swordfish, Tuna, Vampire Squid, Walrus, Whale Shark.

Duplicated siblings (x2 unless noted): Alligator, Beluga Whale, Crystal
Shark, Dolphin, Jellyfish, Lobster, Manta, Narwhal x3, Nebula Whale, Orca,
Penguin, Pufferfish, Seahorse, Seal x3, Shark, Swordfish, Tuna, Turtle,
Walrus, Whale x3.

## Classic_Studs_Eggs_Pack — 2,890 instances

Structure: `Classic_Studs_Eggs_Pack` [Folder] → **`Models`** [Folder]
(70 egg Models + 1 loose `Egg` MeshPart) + **`Decoration`** [Folder]
(28 egg Models — FX-heavy visual variants; names overlap Models). Egg
anatomy: `Root` Part + `Egg`/`EggEffects` MeshParts + Attachments/Beams/
ParticleEmitters/ManualWelds. Path: `eggPath(name)` hits `Models`; SE's
`findEggTemplate` (HubService) searches `Models` THEN `Decoration`; TT's
`CreatureModels.buildEgg` searches `Models` only.

Exact-spelling flags: `GalaxyAxolotl Egg`, `SnowLeopard Egg`,
`SnowWolf Egg`, `FennecFox Egg` (all space-less first word), `XMas
Exclusive Egg`. Duplicates in Models: Epic Egg x2, Panda Egg x2,
SnowLeopard Egg x3, SnowWolf Egg x2, Unicorn Egg x2; in Decoration:
GalaxyAxolotl Egg x2.

Models (70): Admin Alien Egg, Admin Easter Egg, Admin Mystery Egg,
Admin Safari Egg, Beehive Egg, Beetle Golem Egg, Black Cat Egg,
Blue Octo Egg, Buffalo Egg, Cake Egg, Candy Egg, Celestial Axolotl Egg,
Celestial Griffin Egg, Celestial Hydra Egg, Cloud Egg, Common Egg,
Cyber Egg, Cyclops Fox Egg, Dingrat Egg, Edthaniel Egg, Epic Egg x2,
Everything Egg, Exclusive Alien Egg, Exclusive Easter Egg, Exclusive Egg,
Fat Panda Egg, Feep Egg, FennecFox Egg, Galaxy Admin Egg,
Galaxy Gecko Egg, Galaxy Kitsune Egg, GalaxyAxolotl Egg, Giraffe Egg,
Glacial Egg, Gorilla Egg, Grey Lynx Egg, Hydra Egg, Kreek Egg,
Legendary Egg, Lemur Egg, Lunar Penguin Egg, Lynx Egg, Mythical Egg,
Panda Egg x2, Prehistoric Exclusive Egg, Rainbow Egg, Rare Egg,
Sabertooth Egg, Safari Egg, Seahorse Egg, Skeleton Egg,
SnowLeopard Egg x3, SnowWolf Egg x2, Stitched Egg, Tortoise Egg,
Toucan Egg, Underwater Egg, Unicorn Egg x2, Unknown Egg, Valentines Egg,
Walrus Egg, White Lion Egg, Woolly Rhino Egg, XMas Exclusive Egg. Plus a
loose `Egg` MeshPart.

Decoration (28): Admin Easter Egg, Beehive Egg, Cake Egg, Candy Egg,
Celestial Axolotl Egg, Celestial Hydra Egg, Cloud Egg, Cyber Egg,
Exclusive Alien Egg, Exclusive Easter Egg, Feep Egg, Galaxy Admin Egg,
Galaxy Kitsune Egg, GalaxyAxolotl Egg x2, Giraffe Egg, Glacial Egg,
Gorilla Egg, Hydra Egg, Kreek Egg, Mythical Egg, Rainbow Egg, Rare Egg,
Sabertooth Egg, Safari Egg, Underwater Egg, Unknown Egg, Valentines Egg.

**Used by BOTH games (4)** — world/tier eggs in SE (`GameConfig.worlds[].
eggModelName`) and TT (`TidetownConfig` egg tiers): Rare Egg, Epic Egg,
Exclusive Egg, Celestial Axolotl Egg.

**Used by SE only (5)** — hatchery showcase pedestals (HubService):
Legendary Egg, Mythical Egg, Rainbow Egg, Galaxy Admin Egg,
Celestial Griffin Egg.

**Unused — headroom**: the other 61 Models-folder eggs and all
Decoration-only variants.

## Beach_Summer_Asset_Pack_2025 — 452 instances

Structure: `Beach/Summer Asset Pack 2025 - Moijjj56` [Folder] →
**`Models`** [Folder] (82 children: 64 Models + 18 decorative MeshParts) +
`Lighting` [Configuration] (Sky/Atmosphere presets — not models). Path:
`beachPath(name)`.

Numbering trap: `Surf Board Scene` has NO "1" — the set is `Surf Board
Scene`, `Surf Board Scene 2`..`4` (parser summary shorthand "1-4" is
wrong). Same for `Surf Board`/`Surf Board 2`, `Curved Surf Board`/`Curved
Surf Board 2`. Bare `Rock` is a MeshPart; `Rock 2` and `Rock 3` are
Models (no "Rock 1"). Duplicates: Beach Chair x3, Bucket x2, Empty Bucket
x2, Sand Shovel x5, Shovel Bucket x2, Starfish x2, Sunshade x2, Shell
(MeshPart) x5, Plank Stick (MeshPart) x2.

Models (64): Beach Ball 1, Beach Ball 2, Beach Ball 3, Beach Chair x3,
Big Flat Rock, Big Plant 1, Big Plant 2, Border 1-4, Broken Sand Castle,
Bucket x2, Buoy, Chest, Chest Scene, Colored Towel, Curved Colored Towel,
Curved Palm Tree, Curved Surf Board, Curved Surf Board 2, Decorated Sand
Hill 1, Decorated Sand Hill 2, Double Trees Decoration, Empty Bucket x2,
Flat Border 1-4, Open Chest, Palm Tree, Plant 1, Plant 2, Rock 2, Rock 3,
Sand Castle, Sand Shovel x5, Shovel Bucket x2, Small Buoy, Small Plant 1,
Small Plant 2, Small Spinning Buoy, Spinning Buoy, Starfish x2, Sunshade
x2, Surf Board, Surf Board 2, Surf Board Scene, Surf Board Scene 2,
Surf Board Scene 3, Surf Board Scene 4, Trees Decoration, Unicorn Buoy.

Loose MeshParts (18): Bigger Sand Hill 1, Bigger Sand Hill 2, Curved
Towel, Flat Rock, Grass 1, Grass 2, Plank Stick x2, Rock, Sand, Sand Hill
1, Sand Hill 2, Shell x5, Towel.

**Used by SE only (12)** — hub cove + world scenery: Beach Ball 1,
Beach Chair, Buoy, Chest Scene, Curved Palm Tree, Palm Tree, Rock 2,
Sand Castle, Starfish, Sunshade, Surf Board, Unicorn Buoy. TT uses none.

**Unused — headroom**: the other 52 Models + all 18 MeshParts.

## City_Asset_Pack_2026 — 2,201 instances

Structure: `City Asset Pack 2026 - Moijjj56` [Folder] → `Lighting`
[Configuration] + **`Models`** [Folder] with 14 CATEGORY subfolders — the
only pack with deep nesting. Path: `cityPath(category, name)` =
`{ "City_Asset_Pack_2026", "Models", category, name }`; two-level
categories (MailBoxes, Red Lights, Signs, Roadworks Stuff subfolders) need
a manual `findProp` path with the extra segment.

Category → exact contents:

- **Benches & Picnic** (7): Bench 1-3, Picnic Table, Wooden Bench 1-3
- **City Lamps** (12): City Street Lamp 1-4, Double Street Lamp 1-2,
  Round Street Lamp 1-2, Street Lamp 1-2, Triple Street Lamp 1-2
- **Decoration** (9): Barrel, Bike Stop Thingy, Broken Fire Hydrant,
  Bus Stop, Fire Hydrant, Open Barrel, Pallet, Post Box, Wall
- **Direction Signs**: Direction Sign x2, Tall Direction Sign x2, plus
  subfolder `Customizable` → `Customizable - Direction Sign`
- **Ground Decoration**: `Ground` MeshPart x2 (decor, not Models)
- **MailBoxes** → `Normal` / `Wooden` (each: Mailbox, Small Mailbox)
- **Red Lights** → `Normal` / `Wooden` (each: Long Traffic Light x4,
  Traffic Light x3, Traffic Light Customization)
- **Restaurant Related** (6): Outside Parasol Table, Parasol, Restaurant
  Chair, Restaurant Chair 2, Table, Restaurant Menu
- **Roadworks Stuff**: Warning Arrow Sign + subfolder `Fences` (Bicolor
  Fence, Double Fence, Fence, Short Fence, Short Water Fence, Small
  Double Fence, Warning Fence, Warning Fence 2, Warning Fence 3 — NO
  "Warning Fence 1", Water Fence, Wheel Fence) + subfolder `Cones`
  (`Cone1`, `Cone2`, `Cone3` — NO space, plus Tall Cone)
- **Signs** → `Normal` / `Wooden` (each 9: Circle Sign, Circle Sign 2,
  Cross Sign, Exclamation Mark Sign x2, No Stop Sign, Parking Sign,
  Speed Limit Sign, Stop Sign)
- **Street Wires** (2): Street Wire Thingy, Street Wires
- **Trash** (7): City Big Trash Can, City Trash Can, Side Trash Bag,
  Trash Bag, Trash Can 1-3
- **Vehicles** (6): Bike, Car, Police Car, Racing Car, Taxi Car,
  Truck Car
- **WC** (2): Empty Portable Toilet, Portable Toilet

**Used by SE only (14)**: Bench 1, Bench 2, Wooden Bench 1, Wooden Bench
2 (Benches & Picnic); Street Lamp 1, Street Lamp 2, Round Street Lamp 1,
Round Street Lamp 2 (City Lamps); Tall Direction Sign (Direction Signs);
Outside Parasol Table, Parasol (Restaurant Related); Warning Arrow Sign
(Roadworks Stuff); Trash Can 1 (Trash); Taxi Car (Vehicles). TT uses
none.

**Unused — headroom**: everything else, including ALL of Decoration,
MailBoxes, Red Lights, Signs, Street Wires, WC, all fences and cones, and
five of the six vehicles.

## Low_Poly_Nature_Asset_Pack — 560 instances

Structure: root Folder → single wrapper Model `Low Poly Nature Asset Pack
| Destiny Tech` with 128 children: 120 named Models (119 distinct names —
`Tree` appears twice) + 8 loose grass/plank MeshParts (Grass, Small Grass,
Small Thin Grass, Smaller Grass, Tall Grass, Tall Thin Grass, Plank 1,
Plank 2). Path: `naturePath(name)` =
`{ "Low_Poly_Nature_Asset_Pack", "Low Poly Nature Asset Pack | Destiny
Tech", name }` — note the wrapper Model's name contains a pipe.

LEADING-SPACE WARNING (verified in the JSON): `" Small Squared Tree"` and
`" Small Tree"` start with a space. `FindFirstChild("Small Tree")` misses
them. The space-less small trees are `Small Small Tree`, `Small Tree 2`,
`Tall Small Tree` (and the Squared equivalents).

Numbering is mixed — exact sets:

- With explicit 1: Basic Log 1/2, Bigger Log 1/2, Double Log 1/2, Fence
  1/2, Flat Rock 1/2, Flower 1-11, Hill 1/2, Inf. Fence 1/2 (dot in the
  name), Log 1/2, Plank 1/2, Rock 1/2.
- Bare + 2 (NO "1" variant): Bush/Bush 2, Tall Bush/Tall Bush 2,
  Tall Bush Flower/Tall Bush Flower 2, Double Tall Bush/Double Tall Bush
  2, Double Tall Bush Flower/Double Tall Bush Flower 2, Pine Tree/Pine
  Tree 2, Tall Pine Tree/2/3/4, Tree (x2!)/Tree 2, Tree Stump/Tree Stump
  2, Basic Tree Stump/Basic Tree Stump 2, Small Tree 2 (bare form has the
  leading space, above).

Full Model list (120 instances, 119 distinct): " Small Squared Tree", " Small Tree", Bad
Mushroom, Basic Log 1, Basic Log 2, Basic Tree Stump, Basic Tree Stump 2,
Big Flower Water Lily, Big Liana, Big Mushroom, Big Quad Broken Rock, Big
Quad Rock, Big Rock, Big Water Lily, Bigger Log 1, Bigger Log 2, Bigger
Messy Plant, Bigger Plant, Bigger Tree, Birch Tree, Bush, Bush 2, Cactus,
Damaged Plant, Dirt Thing, Double Log 1, Double Log 2, Double Reed,
Double Tall Bush, Double Tall Bush 2, Double Tall Bush Flower, Double
Tall Bush Flower 2, Double Tree, Double Wizard Mushroom, Falling Potted
Plant, Fence 1, Fence 2, Five Sugar Cane/Bamboo, Flat Rock 1, Flat Rock
2, Flat Straw Ball, Flower 1-11, Flower Water Lily, Hill 1, Hill 2,
Inf. Fence 1, Inf. Fence 2, Liana, Log 1, Log 2, Long Rock, Messy Plant,
Mushroom, Not Grown Wheat, Pine Tree, Pine Tree 2, Plant, Potted Plant,
Quad Broken Rock, Quad Rock, Reed, Rock 1, Rock 2, Rooted Tree, Round
Plant, Round Rock, Seed Plant, Shrek Restroom, Single Sugar Cane/Bamboo,
Small Small Squared Tree, Small Small Tree, Small Tree 2, Squared Tree,
Straw Ball, Tall Bad Mushroom, Tall Bush, Tall Bush 2, Tall Bush Flower,
Tall Bush Flower 2, Tall Light, Tall Pine Tree, Tall Pine Tree 2, Tall
Pine Tree 3, Tall Pine Tree 4, Tall Reed, Tall Round Plant, Tall Round
Rock, Tall Small Squared Tree, Tall Small Tree, Tall Tree, Tall Weird
Mushroom, Three Sugar Cane/Bamboo, Tomato Plant, Tree x2, Tree 2, Tree
Stump, Tree Stump 2, Triple Big Mushroom, Triple Mushroom, Triple Wheat,
U Shaped Tree, Water Lily, Water Lily Flower, Weird Mushroom, Weird Pine
Tree, Wheat, Wizard Mushroom, Wooden Boat, Wooden Bridge. Note three
names contain a literal slash (`Five Sugar Cane/Bamboo` etc.).

**Used by SE only (55)** — hub island + world scenery (HubService,
SceneryService): Big Liana, Big Mushroom, Big Rock, Bigger Tree, Birch
Tree, Bush, Bush 2, Double Tall Bush, Double Tree, Fence 1, Flower 1-10,
Flower Water Lily, Grass (MeshPart), Inf. Fence 1, Liana, Log 1, Log 2,
Mushroom, Pine Tree, Pine Tree 2, Plant, Potted Plant, Reed, Rock 1,
Rock 2, Rooted Tree, Round Plant, Round Rock, Squared Tree, Tall Bush,
Tall Bush Flower, Tall Bush Flower 2, Tall Grass (MeshPart), Tall Pine
Tree 1-4 set (bare + 2/3/4), Tall Reed, Tall Tree, Tree, Tree 2, Tree
Stump, U Shaped Tree, Water Lily, Weird Pine Tree, Wooden Boat. TT uses
none.

**Unused — headroom (~70)**: everything else, notably Cactus, Wooden
Bridge, all Sugar Cane/Bamboo, all wheat/crops, all logs except Log 1/2,
Hill 1/2, all wizard/weird mushrooms, Shrek Restroom, Tall Light, the
water lilies except the two used, and every " Small"/"Small Small"
tree.

## Nature_Pack_Bundle — 132 instances

Structure: `Nature Pack` [Folder] → 5 category folders; mostly UNNAMED
duplicate MeshParts, so consumers address by index:
`bundlePath(folderName, index)` → `GetChildren()[index]`.

- **Grass** (7 named Models): GrassWall x3, Plant1, Plant2, Plant3,
  Plant4 (no spaces in PlantN).
- **Plants Pack** → subfolders `Plants 1`-`Plants 5`, `Plants 7`,
  `Plants 9`, each holding identical-named MeshParts `plants_v1`(x4),
  `plants_v2`(x3), `plants_v3`(x4), `plants_v4`(x6), `plants_v5`(x5),
  `plants_v7`(x8), `plants_v9`(x7).
- **Stones Pack**: `Stones` MeshPart x9 (identical names).
- **Bamboo Packs** (note plural): `Bamboo` MeshPart x12.
- **Water Plant Pack** → `Plants 6` → `plants_v6` MeshPart x3.

**Used by SE only**: `bundlePath("Grass", 1-3)` (town skirt),
`bundlePath("Stones Pack", 1/2/4/5/7)`, `bundlePath("Bamboo Packs", 1)`.
TT uses none. Headroom: remaining stones/bamboo indices, all Plants Pack
folders, water plants, Plant1-4 models.

## Low_Poly_Cave_Asset_Pack — 109 instances

Structure: root Folder → single wrapper Model `Low Poly Cave Asset Pack |
Destiny Tech`. NO usable names: 20 default-named children (`MeshPart`
x11, `Model` x9 — rock/crystal clusters; one Model contains a `B -
FLAMES` Part with PointLight/ParticleEmitters, i.e. a campfire). Address
by child index ONLY: `cavePath(index)`. Index order is load order — do
not reorder the rbxm.

**Used by SE only**: cavePath 6 (hub grotto); cavePath 1, 2, 3, 4, 5, 7,
9, 11, 13 (world scenery). TT uses none. Headroom: indices 8, 10, 12,
14-20.

## Tds_Town_Pack — 5,659 instances

Structure: `Tds_Town_Pack` [Folder] → single **`Scenery`** [Model]: a
baked town SCENE, not a kit — 2,755 default-named Parts + 2,897 Welds + 5
default-named single-Part Models. No individually named models; clone
`Scenery` whole as one drop-in set piece only. Do not try to pick pieces
out of it.

**Used by BOTH games**: SE hub places it as the mid-tier town
(HubService; the legacy separate TDS island is gated behind
`GameConfig.tdsIsland.enabled`); TT `MapBuilder.lua` clones it as the
town. Nothing unused — it is all-or-nothing.

## Ultimate_Low_Poly_Food_and_Candy_Pack — 41 instances

Structure: root Folder → single wrapper Model `Ultimate Low Poly Food and
Candy Pack` (no underscores in the wrapper's Name, unlike the file)
containing 39 MeshParts named `food_1`..`food_39`. No descriptive names —
identify visually in Studio or by mesh id. Path: `foodPath("food_N")`.

**Used by SE only**: food_1, food_12, food_24 (hub), food_7, food_21,
food_33 (world scenery). TT uses none. Headroom: the other 33.

## Totals

| Pack | Instances | Named usable models | Structure |
|---|---|---|---|
| Sea_Animals_Pack | 9,348 | 132 (`Models` folder) | Models + Baseplate |
| Tds_Town_Pack | 5,659 | 1 scene (`Scenery`) | single scene Model |
| Classic_Studs_Eggs_Pack | 2,890 | 70 + 28 decoration | Models + Decoration |
| City_Asset_Pack_2026 | 2,201 | ~135 in 14 categories | deep folder nesting |
| Low_Poly_Nature_Asset_Pack | 560 | 120 (+8 loose MeshParts) | wrapper Model |
| Beach_Summer_Asset_Pack_2025 | 452 | 64 (+18 loose MeshParts) | Models folder |
| Nature_Pack_Bundle | 132 | 7 (rest unnamed MeshParts) | 5 category folders |
| Low_Poly_Cave_Asset_Pack | 109 | 0 named (index-addressed) | wrapper Model |
| Ultimate_Low_Poly_Food_and_Candy_Pack | 41 | 39 generic (`food_N`) | wrapper Model |

Regenerating the JSON: the packs are LZ4-block-compressed binary rbxm
(none zstd). Parser format notes — header `<roblox!\x89\xff\x0d\x0a\x1a
\x0a` + u16 version + u32 classCount + u32 instanceCount + 8 reserved;
chunks = 4-byte tag + u32 compressedLen + u32 uncompressedLen + 4
reserved + payload (LZ4 block if compressedLen>0); referent arrays are
byte-interleaved big-endian i32, zigzag-decoded, cumulative-summed; PROP
`Name` (type 0x01) values are sequential u32-length-prefixed strings in
INST referent order; PRNT is u8 version + u32 count + child refs + parent
refs (parent -1 = root).
