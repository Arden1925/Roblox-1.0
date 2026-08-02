# Project Instructions

This is a Roblox game project. All Lua/Luau code in this repository MUST
follow the official Roblox Lua Style Guide, captured in full in
[STYLE_GUIDE.md](STYLE_GUIDE.md). Read that file before writing or modifying
any `.lua`/`.luau` code, and apply it to every line you produce — new code,
edits, and reviews alike.

## Non-negotiable style rules (summary)

Formatting (enforced by StyLua via `stylua.toml`):

- Indent with tabs. Lines under 100 columns (tabs counted as 4).
- Double quotes for strings (single quotes only when the string contains
  double quotes).
- No semicolons. No trailing whitespace. Newline at end of file.
- Trailing commas in multi-line tables.
- One statement per line; function bodies and `if` bodies on their own lines
  (never `if x then return end` on one line).
- No vertical alignment.

Structure and conventions (enforced by review — check these yourself):

- File order: purpose block comment → `game:GetService` calls → `require`
  calls → constants → variables/functions → module table → `return`.
- All requires at the top of the file, sorted alphabetically, grouped per the
  Requires section of STYLE_GUIDE.md.
- All services referenced via `game:GetService` at the top of the file.
- Module variable names match the module they import; file names match the
  object they export.
- Naming: `PascalCase` for classes/enums and Roblox APIs, `camelCase` for
  locals/members/functions, `LOUD_SNAKE_CASE` for local constants,
  `_underscore` prefix for private members. Spell words out fully.
- Classes use the typed prototype pattern from STYLE_GUIDE.md (see
  `src/shared/Stack.lua` for the reference implementation). Constructors are
  named `new`; methods are declared dot-style with `self: ClassType`.
- Enum-like tables guard against typos with a throwing `__index` metamethod
  (see `src/shared/GamePhase.lua`).
- Metatables ONLY for prototype classes and typo guards — nothing else.
- Use `if-then-else` expressions instead of `x and y or z`.
- No parentheses around conditions in `if`/`while`/`repeat`.
- Always use parentheses when calling functions (no `doSomething "home"` or
  `doSomethingElse{u = 1}`).
- Iterate lists with `ipairs`, dictionaries with `pairs`; avoid mixed tables.
- Comments explain WHY, not what. Wrap comments at 80 columns. Block comments
  document files and functions. No section comments (`--- VARIABLES ---`).
- Errors: return `success, result` (or a Result/Promise); only throw when
  validating correct usage (`assert` on arguments). Wrap throwing calls in
  `pcall` with a comment saying which errors are expected.
- Never call yielding functions on the main task; wrap them in `task.spawn`/
  `coroutine.wrap` or expose a Promise-like interface.

## Project layout

- `src/shared/` → `ReplicatedStorage.Shared` (shared modules)
- `src/server/` → `ServerScriptService.Server` (server code)
- `src/client/` → `StarterPlayer.StarterPlayerScripts.Client` (client code)
- `default.project.json` — Rojo project map (syncs this repo with Roblox
  Studio)

## Workflow

- Format check: `stylua --check src` (config in `stylua.toml`). Run it after
  editing Lua files if StyLua is available; CI runs it on every push and PR.
- Lint: `selene src` (config in `selene.toml`), if selene is available.
- Tools are pinned in `rokit.toml` (install with [Rokit](https://github.com/rojo-rbx/rokit)).
- Sync with Roblox Studio: `rojo serve` here, then connect with the Rojo
  plugin in Studio.
