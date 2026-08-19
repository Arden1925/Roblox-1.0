# Roblox-1.0

**+1 Size Escape** — grow huge to open gates, shrink small to squeeze
through cracks. See [GAME_DESIGN.md](GAME_DESIGN.md) for the design and the
map-building tags.

**Roger 7.0** is **TIDETOWN** — a second, separate game in this repo: a
seaside town on a supernatural tide clock (catch at low tide, surf and
defend at high tide). Design and implementation map live in
[ROGER_7.0.md](ROGER_7.0.md); the code lives under `tidetown/` and syncs
with `rojo serve tidetown.project.json` as its own place.

A Roblox game project, developed file-first: the code lives in this
repository and syncs into Roblox Studio with [Rojo](https://rojo.space/).

## Coding style

Every line of Lua/Luau in this repo follows the official
[Roblox Lua Style Guide](https://roblox.github.io/lua-style-guide/), captured
in full in [STYLE_GUIDE.md](STYLE_GUIDE.md). It is enforced three ways:

- **StyLua** (`stylua.toml`) handles formatting: tabs, 100-column lines,
  double quotes, trailing commas, sorted requires.
- **CI** (`.github/workflows/ci.yml`) runs `stylua --check src` on every push
  and pull request, so unformatted code cannot merge quietly.
- **[CLAUDE.md](CLAUDE.md)** instructs Claude Code to apply the full guide —
  including the rules formatters can't check, like naming, file structure,
  metatable limits, and error handling — to all code it writes here.

Reference implementations of the guide's core patterns live in `src/shared`:

- `Stack.lua` — the typed prototype-based class pattern
- `GamePhase.lua` — an enum-like table with a throwing typo guard

## Project layout

| Path | Syncs to | Purpose |
| --- | --- | --- |
| `src/shared/` | `ReplicatedStorage.Shared` | Modules used by both sides |
| `src/server/` | `ServerScriptService.Server` | Server-only code |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` | Client-only code |

The mapping is defined in `default.project.json`.

## Getting started

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run
   `rokit install` in the repo root to get pinned versions of Rojo, StyLua,
   and selene.
2. Install the [Rojo plugin](https://create.roblox.com/store/asset/13916111004)
   in Roblox Studio.
3. Run `rojo serve` in the repo root, open your place in Studio, and connect
   via the Rojo plugin. Edits to files here now appear in Studio live.

Before committing:

```sh
stylua src
selene src
```
