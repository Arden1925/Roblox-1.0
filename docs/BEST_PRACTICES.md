# Roblox Engineering Best Practices

Read this before writing or reviewing any code in this repo. It ranks the
practices that change decisions HERE — two games (`src/` = +1 Size Escape,
`tidetown/` = TIDETOWN) that build maps entirely server-side at boot, move
anchored models via per-service Heartbeat `PivotTo`, wire services through a
hand-written composition root with injected dependencies, declare all remotes
in a registry, and refuse to save when load failed. Style rules live in
STYLE_GUIDE.md; this file is about performance, safety, and scale.

## 1. Networking and replication — the biggest scaling risk here

Server-scripted CFrame changes replicate as property updates to every
client, and Roblox throttles replication at roughly 50 KB/s per player
(measured humanoid replication hits ~40 KB/s at just 75 NPCs — DevForum NPC
replication tips, Feb 2026). Anchored parts get no physics interpolation:
every server write is raw traffic.

- Per-frame server `PivotTo` of anchored models is fine at dozens of movers,
  and will NOT scale past ~50–100 continuously moving parts per player.
  When entity counts grow, switch to the standard architecture: simulate in
  plain Luau tables server-side, send compact state at ~10 Hz over
  `UnreliableRemoteEvent`, lerp visuals client-side (`CFrame:Lerp`, or
  `workspace:BulkMoveTo()` for many parts — skips per-property change
  events).
- `UnreliableRemoteEvent`: ~900-byte payload cap (larger fires are silently
  dropped; Studio logs it). Unordered, droppable — use for continuous state
  (positions, tide level) only, never purchases or inventory. Pair with the
  `buffer` type or `Vector3int16` for bit-packed state (CFrame ≈ 20 bytes;
  int16 pos+rot ≈ 12).
- Reliable remotes replicate on CHANGE only, never per frame. Rate-limit
  input-driven RemoteEvents server-side.
- Never call `RemoteFunction:InvokeClient()` — a client error or leave hangs
  the server forever. Client→server RemoteFunctions are fine.
- Remote argument gotchas (create.roblox.com remote docs): mixed
  string/number keys corrupt, `nil` holes truncate arrays, metatables are
  stripped (prototype-class instances arrive as plain tables), functions and
  non-replicated Instances become nil. Send plain data tables only.
- Prefer attributes over ValueObjects for replicated scalar state: measured
  ~18x faster to update, ~240x faster to delete, cheaper to replicate
  (DevForum attributes-vs-values benchmark). Never introduce ValueObjects in
  new code.
- Purely visual effects run client-side, triggered by one small remote.

How this maps to our code: `ReefService`, `MountService`, `CreatureService`
(follower lerp), and `SurgeService` all do per-frame server `PivotTo` — the
first candidates for the 10 Hz + client-lerp rewrite when counts rise.
`SurgeEvent`/`TideChanged`/`SyncState` in `tidetown/shared/TidetownRemotes.lua`
are the unreliable-remote candidates. Rate-limit `DeflectTap`,
`SetDesiredSize`, `SetDesiredSpeed`. FX are already client-side
(`PortalFx.lua`, `TideController.lua`) — keep new FX there.

## 2. Streaming — decide explicitly, because our maps are server-built

New places default `StreamingEnabled = true`, and neither
`default.project.json` nor `tidetown.project.json` sets Workspace
properties, so the shipped place file silently decides. Set it explicitly in
the project JSON (`"Workspace": {"$properties": {...}}`) so the choice is
version-controlled.

If streaming is on (it should be — it is the single biggest memory lever on
phones):

- Server-built maps stream exactly like Studio-placed ones (create.roblox.com
  streaming docs) — `MapGenerator`/`MapBuilder` output is fully compatible.
- Clients may not see map parts at join; `WaitForChild` on far geometry can
  yield forever. Mark gameplay-critical anchors (surge lanes, reef pads,
  checkpoints from `CheckpointService`) `Atomic` or `Persistent` (sparingly);
  leave scenery (`SceneryService`, MapBuilder town dressing) Nonatomic.
- Never cache client-side references to workspace parts without
  re-resolving; streamed-out instances are parented to nil and can return.
  Listen for `ChildRemoved` on the parent, not on the instance.
- Client-local tweaks to server parts are lost on stream-out/in
  (`EnvironmentController`-style dressing must be reapplied).
- Before teleporting a character across the map, call
  `Player:RequestStreamAroundAsync(position)` first, and set
  `StreamingIntegrityMode = PauseOutsideLoadedArea` (relevant to
  `PortalGui`/hub flows).
- Set `Workspace.ModelStreamingBehavior = Improved` — far models stream out
  fully, which directly cuts the fan-out cost of Tidetown's server
  `PivotTo`s. `StreamOutBehavior = Opportunistic` helps low-end phones.

## 3. Rendering and physics on low-end phones

Design for the phone first; Studio on a desktop lies to you.

- Draw calls dominate. The engine auto-instances identical meshes with
  identical asset IDs into one draw call — the
  `ReplicatedStorage.Assets.Models` + `Clone()` pattern in
  `CreatureModels.lua`/`PetModels.lua` is exactly right. Never upload a
  near-duplicate mesh under a second ID; it defeats instancing AND doubles
  memory.
- MeshPart > Union > pile of Parts for triangle counts (DevForum
  unions-vs-meshparts). Keep per-model part counts modest: fewer parts also
  means cheaper FastCluster rebuilds every time a model moves — which is
  every frame for our `PivotTo`-driven movers. `RenderFidelity` = Automatic
  or Performance for props, never Precise.
- `CastShadow = false` on small/decorative parts; quality < 4 (typical phone)
  disables shadows anyway — never design readability around them.
- Particles: low quality levels throttle per-emitter emission hard
  (community measurements put phones near ~100 particles/s per emitter —
  not an official number; verify on device). Cost is overdraw —
  big transparent overlapping particles, not count. Keep Rate low
  (MapBuilder's Rate = 3 is right), Size small, prefer `Emit()` bursts over
  always-on emitters, and verify at Studio Editor Quality Level 1.
- Textures ≤256px where possible; 1024² costs 4x the memory of 512².
- Physics: everything that doesn't simulate stays Anchored (already true —
  which is why §1 is the cost center, not the solver). Set
  `CanCollide/CanQuery/CanTouch = false` on decorative parts — saves
  broadphase AND memory (spatial structures aren't built). Note
  `CanQuery=false` keeps `CatchService` raycasts from hitting scenery, and
  also deliberately breaks raycast/`GetPartsInPart` detection on that part.
- Collision groups (`PhysicsService:RegisterCollisionGroup`) to mass-exempt
  classes (creatures vs creatures), not per-pair constraints.
- `Touched` never fires anchored-vs-anchored. Surge hit detection must stay
  distance math in Heartbeat (`SurgeService` already does this — keep it).

## 4. Memory

- One asset ID reused N times = one memory copy. Keep the clone-from-
  ReplicatedStorage pattern.
- Pool models that spawn/despawn repeatedly (`SurgeService` already pools
  enemy records across waves and forbids allocation in Heartbeat — extend
  that pattern to any wave/projectile system). One-offs: `Destroy()`, never
  `.Parent = nil` long-term — `Destroy` disconnects the instance's own
  connections.
- BUT: connections your object holds on OTHER objects (Player, character,
  RunService) leak past `Destroy()`. The litmus test (sleitnick/Trove): for
  every `:Connect`, name the line that disconnects it — no answer = leak.
  Give every long-lived object a `_connections` list and a `destroy()` that
  is provably called; disconnect player-tied connections in the composition
  root's leave path.
- Clear per-player table entries on leave: every `playerState`-style dict in
  `DataService`, `TidetownData`, per-plot tables in `ReefService`. This is
  the #1 source of server memory creep and session-length decay.
- Enable `Workspace.PlayerCharacterDestroyBehavior = Enabled`. Watch LuaHeap
  and InstanceCount growth in the Dev Console per §9.
- Audio: `ContentProvider:PreloadAsync` ONLY latency-critical one-shots (UI
  clicks, catch confirms, hatch stingers) during `LoadingGui`; never music or
  the whole Workspace. Known 2025 bug: Sounds under `SoundService` don't
  respect `IsLoaded`/preload — parent preloadable SFX to ReplicatedStorage or
  the part. Route volume through `SoundGroup`s so `SettingsGui` scales one
  group, not every `Sound.Volume`.

## 5. Luau craft — typed Luau, tables, allocation

- `--!strict` on every new file. Types are erased at runtime (free) and are
  the INPUT to native-codegen quality. Annotate public signatures fully.
  Confine `::` casts to boundary adapters; `:: any` inside logic is a review
  flag.
- The house typed-prototype pattern (`src/shared/Stack.lua`) is exactly what
  the new type solver (GA 2025) handles well. Keep `__index` pointing
  directly at a table — one hop; `__index` functions defeat the inline-cache
  fastpath.
- Derive ID types from data: `keyof<typeof(Catalog)>` gives a typo-safe key
  union from `PetCatalog`/`GameConfig`-shaped tables, layered on the runtime
  throwing-`__index` guard (`GamePhase.lua`). `table.freeze` every static
  catalog at module `return`.
- Zero allocations in per-frame code. Hoist closures, scratch tables, and
  format strings out of Heartbeat handlers; reuse scratch tables with
  `table.clear` (keeps capacity). Allocation rate drives GC assists that
  throttle ALL scripts (luau.org/performance).
- Construct objects as one complete table literal (all fields set in the
  constructor) — table-template optimization plus monomorphic shapes for the
  solver and JIT. Append with `size += 1; items[size] = v` or
  `t[#t + 1] = v`; preallocate with `table.create(n)` for known counts (map
  cells, per-player lists). Keep arrays dense; never mix array and hash keys
  (the style rule is also a perf rule).
- Bulk numeric state (hundreds+ homogeneous records): parallel arrays (SoA)
  or a `buffer`, not arrays of small tables — per-table header + GC tracking
  dominates. `Vector3` is a native value type; prefer whole-vector ops.
- Don't micro-cache: `obj:Method()` (namecall) and `math.floor(x)`
  (fastcall) are already the fast paths; localizing methods/builtins is a
  Lua 5.1 habit to unlearn. Build big strings with
  `table.concat`/`string.format`, never `..` in loops.
- Spatial queries at scale use a partition (octree/grid), not per-frame
  `Magnitude` loops over all entities — relevant the moment
  followers/obstacles/NPCs exceed a few dozen.
- `@native` only on measured hot pure-Luau math (e.g. `SizeFormula`,
  `MapGenerator` math), per-function, never blanket `--!native`: there is a
  global native-code budget, and unannotated params force slow re-check
  paths. Verify with Script Profiler's `<native>` marker.
- Parallel Luau only for embarrassingly parallel heavy compute (chunked map
  generation is the sole plausible candidate here), many small Actors,
  `require` in serial phase, Instance writes after `task.synchronize()`.
  Service logic stays single-threaded — per-actor VM isolation breaks
  shared-module assumptions.

## 6. Task scheduling and signals

- `task.defer` by default; `task.spawn` only when code must run before the
  caller continues. Legacy `spawn`/`delay`/`wait` are banned (throttled,
  unordered); where STYLE_GUIDE.md's Yielding section names `delay`, read
  it as `task.delay` — the intent (never yield the main task) is
  unchanged.
- `task.wait(n)` resumes on the first Heartbeat after n — use its return
  value for real elapsed time; never assume frame durations.
- Frame order (client): RenderStepped → Stepped → Heartbeat. RenderStepped
  blocks the frame render — camera/input only; game logic on Heartbeat.
- Set `Workspace.SignalBehavior = Deferred` explicitly in the project JSON
  (templates already ship it; `Default` will flip eventually) and write
  handlers re-entrancy-safe: never fire a signal and immediately assume its
  handlers ran.
- Async API contract (house rule, keep it): every public async function
  returns `success, result` or a Promise; none yield the caller implicitly.
  Document yielding in the function's block comment; wrap throwing calls in
  `pcall` with a comment naming the expected errors.
- Cancellation is part of async design: any retry loop, tween chain, or
  `task.delay` tied to an entity must be registered in that entity's cleanup
  container — a delayed callback firing after its target died is a logic-bug
  factory.

How this maps to our code: every service `step*` function already runs on
Heartbeat from the composition root — keep that, and keep the two-phase
lifecycle: require-time is pure (no `Instance.new`, no connections, no
yields); behavior starts at `start(deps)`; ordering constraints get a WHY
comment at the call site in `init.server.lua`.

## 7. DataStore discipline

Refuse-save-on-failed-load is THE core rule, and `DataService`'s file
comment states it better than most references: saving defaults over real
data is how games destroy years of progress; failing to save nothing is the
safer error. The nil-propagating snapshot (any subsystem returns nil → the
whole save is refused) extends the invariant to runtime state. Preserve both
in every new service, and implement the join/save/leave triple
(`initializePlayer` / `snapshot` / `removePlayer`) wired in the composition
root — services never subscribe to player lifecycle events themselves.

Ranked open work (creator-code research, verified against this repo):

1. Port `TidetownData`'s hardening back to `src/server/DataService.lua` —
   the repo already contains its own best practice: (a) save-eligibility
   keyed by Player INSTANCE, not UserId boolean, so a fast rejoiner can't
   inherit or lose eligibility from a stale leave-save; (b) a
   `pendingSaves` counter drained in `BindToClose`, saves parallelized then
   drained (src saves sequentially against the ~30s shutdown budget).
2. Receipt idempotency: `src/server/ShopService.lua` grants then returns
   `PurchaseGranted` with no persisted `PurchaseId` log. ProcessReceipt
   redelivers after crashes — record `receiptInfo.PurchaseId` in saved
   data, return `NotProcessedYet` until a save containing grant + id
   succeeded, check the log before granting. As-is, a crash can eat a paid
   product or redeliver a granted one.
3. Session locking: both data modules use `GetAsync` + `SetAsync`
   (last-write-wins) — an old server's autosave landing after a new
   server's load silently rolls the player back. Industry answer
   (ProfileStore): store `sessionId` + `lastSeenAt` in the record, save via
   `UpdateAsync` that aborts when the stored session isn't ours, take the
   lock on load. Adopt (~100-line house version) or document the accepted
   risk — defensible today (single place, no trading), indefensible the day
   trading or multi-place teleports ship.
4. Add `schemaVersion` now (cheap) so future breaking changes get numbered
   forward-only migrations instead of ever-growing implicit fold-ins (the
   legacy `equippedPet` → `equippedPets` fold is a migration in spirit).
   Keep `sanitize()` as tolerant-reader backstop; emit telemetry when it
   drops unrecognized fields — silent dropping masks corruption and your
   own schema mistakes.
5. All DataStore access stays inside the one wrapper service, with retry +
   exponential backoff and per-key queueing. Feature services never touch
   DataStore APIs directly.

## 8. Anti-exploit architecture

The client is hostile; it submits intent, the server rolls the dice and
reads its own clock. `CatchService` is the model implementation — point new
code at it: server rolls the ring, times taps by `os.clock()` with clamped
RTT allowance, and re-checks every gate (zone, tide phase, unlock, mount,
cooldown) no matter what the client claims. `RequestInstantShrink`
re-checks pass ownership; size/speed setters clamp to server-known bounds.

Layered defense, in order:

1. Type/shape checks at the remote boundary. The registry
   (`Remotes.lua`/`TidetownRemotes.lua`, declare-all + `createAll()` +
   asserting `get()`) already kills the typo/infinite-yield class. REFINE:
   validation is per-handler and ad-hoc (NaN guard in
   `SizeService.setDesiredSize`, string check in CatchService). Add ONE
   shared argument-guard helper (number-in-range, no-NaN/inf,
   string-with-max-length) applied at the top of every handler so a new
   remote can't forget the NaN check. Client strings that get persisted
   (`RenamePet`, `RenameCreature`) need length + charset caps HERE — they
   flow into DataStore records. Any user-entered string shown to other
   players must also pass text filtering — the
   `GetNonChatStringForBroadcastAsync` call in `PetService.lua:701` is the
   pattern; it is a platform requirement, not a nicety.
2. Sanity bounds against server-known world state (already present).
3. Generic per-player rate limiting — the missing layer. One shared
   token-bucket module for both games; `SetDesiredSize`/`SetDesiredSpeed`
   are spammable cost amplifiers (each call does character scaling +
   replication work).
4. Behavioral heuristics — already sophisticated: CatchService flags >60%
   perfect taps over a ≥20-cast rolling sample; per-action cooldowns on the
   server clock. Keep building these.

Soft flags over instant punishment: increment per-player flags and escalate
(kick after repeated flags in a window) to avoid lag-spike false positives.
GAP: current detections are silent denials and `warn()`; neither game uses
AnalyticsService (verified by grep). Add a tiny injected `Telemetry` module
counting refused saves, failed loads, rate-limit hits, perfect-cap flags,
and receipt anomalies — most data-loss incidents go undetected for days
because the game silently fails to save. Uniform handler protocol stays:
every RemoteFunction handler is `(Player, ...any) -> (boolean, any)`.

## 9. Profiling workflow

Measure before optimizing; nothing in §1–§5 justifies a rewrite until a
profiler says so. In order:

1. Developer Console (F9): Server Jobs → Heartbeat steps/s (target 60);
   Memory tab → LuaHeap / Instances / per-script memory (finds the leaking
   service); Server Stats → ping.
2. MicroProfiler (Ctrl+Alt+F6): 16.67 ms frame budget. Watch `Heartbeat`
   (all our `step*` functions land there), `ProcessPackets` / `Allocate
   Bandwidth` / `Run Senders` (replication cost of the PivotTo pattern),
   `updateInvalidatedFastClusters` > 4 ms = model-rebuild churn from moving
   many-part models. Wrap each service step in
   `debug.profilebegin("SurgeStep")`/`profileend()` so costs are
   attributable — cheap and style-compatible.
3. ScriptProfiler (Dev Console tab): sampled CPU by function — compare
   `stepFollowers`/`stepTanks`/`onHeartbeat` under load; confirms `<native>`
   for `@native` functions.
4. Ctrl+Alt+F7 / Shift+Ctrl+F1–F5 overlays: FPS, recv/send KB/s (verify the
   ~50 KB/s ceiling isn't near), memory.
5. On-device: MicroProfiler runs on phones (in-experience settings; dumps
   frames over local network to a browser). Healthy = 60 FPS client, server
   memory < 50%. Always sanity-test a low-end device profile, not just
   Studio.

## 10. Repo-wide structural rules (recap)

- No frameworks, no service locators — the industry ran that experiment
  (Knit, archived July 2024) and reversed it because string-resolved
  services can't leverage Luau types. Hand-written composition roots +
  typed `Dependencies` tables are the pattern; a server service never
  `require`s another server service (`SizeService` requiring `ShopService`
  is the exception to stop repeating, not a precedent).
- Bind world-object behavior to CollectionService tags (construct on
  tag-added, destroy on tag-removed) rather than scanning Workspace or
  hardcoding paths — survives streaming, cloning, and map regeneration.
- Extract shared code before game #3: `Remotes` vs `TidetownRemotes`,
  `DataService` vs `TidetownData` (~90% identical and already divergent —
  the divergence IS the bug list in §7.1), `SoundController`/`Toast`/
  `LoadingGui`/`EggGui` twins. A `lib/` mapped into both Rojo projects
  should hold: remotes-registry factory, data-module factory, argument
  guard, token bucket, Telemetry, Toast.
- CI runs StyLua + `luau-lsp analyze` on both games — treat new analyzer
  warnings as merge-blockers. GAP: zero tests. The safety-critical code is
  pure or DI-injected (`sanitize()`, `SizeFormula`, `CatchRules`,
  perfect-cap logic) — testable outside Roblox via Lune. First tests:
  sanitize round-trips (corrupt input → defaults; `equippedPet` fold-in)
  and "refuse save when load never succeeded."

Priority order for acting on this doc: port TidetownData fixes to src →
receipt idempotency → UpdateAsync session guard → shared arg-guard + rate
limiter → dedupe into lib/ → Lune test job → telemetry → schemaVersion →
explicit StreamingEnabled/SignalBehavior in project JSON.

Sources: create.roblox.com performance-optimization, streaming, remote,
scheduler, native-code-gen, multithreading, and type-checking docs;
luau.org/performance; DevForum threads on UnreliableRemoteEvents, NPC
replication (Feb 2026), occlusion culling, model streaming, deferred
events, attributes-vs-values, SoundService preload bug, unions-vs-meshparts;
Knit ARCHIVAL.md; Nevermore/ServiceBag docs; ProfileStore docs; Pet
Simulator and Adopt Me engineering postmortems.
