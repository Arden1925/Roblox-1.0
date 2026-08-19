# Design Language & Color

Read this before touching any color, GUI, effect, or world-building code in
this repo. It defines the palette system, the concrete named palettes for
TIDETOWN and the hub game ("+1 Size Escape"), the UI token set, verified
text-contrast pairs, and the game-feel catalog. Hex values marked "existing"
are already in code — treat them as canon; new values extend them.

---

## 1. The palette system

Rules, in priority order. Every scene and screen must pass all of them.

1. **Value first, hue second, saturation last.** Players parse lightness
   before color. In playable space: darkest values = ground/walls
   (non-interactive), mid values = structure, brightest + most saturated =
   interactables and rewards. The hub already does this
   (`src/server/MapGenerator.lua`: walls `#57606F` dark, steps `#DFE4EA`
   light, pads/coins full-sat) — keep it deliberate everywhere.
2. **Saturation budget.** Environment masses sit at 30–60% saturation.
   Reserve 90–100% saturation for pickups, glows, CTA buttons, and phase
   alerts. Constant max saturation fatigues players inside an hour and is
   the #1 cause of muddy candy-color scenes.
3. **60-30-10 per scene/screen.** 60% dominant zone family (ground + sky,
   low-mid sat), 30% secondary (structures, one adjacent hue), 10% accent
   (complement or triad, full sat — gold coins, coral, glows). UI panels:
   60% white/ice interior, 30% navy outline + header tint, 10% action color.
4. **One hue family per zone, one unifier across all zones.** Each zone gets
   a parent hue with ±20–30° of drift. The constants that make every zone
   read as one game: outline navy `#1F294A` and the reward-gold family.
   Never restyle those per zone.
5. **Outlines are never black.** Dark desaturated navy (`#1F294A`) shifted
   toward the fill's hue keeps brights luminous; black greys out neighbors.
   Same rule for shadows: shadow variants rotate toward blue/violet, not
   toward black (dry sand `#EEDCA5` → wet `#D8C391` → shadow `#A99070`).
6. **Lighting unifies, parts don't.** Mood and phase changes go through
   `Atmosphere`, `OutdoorAmbient`, and `ColorCorrectionEffect` tweens —
   never by recoloring parts. `EnvironmentController.lua` (hub) and
   `TideController.lua`'s `HIGH_TIDE_AMBIENT #609EA8` lerp (alpha 0.4) are
   the canonical pattern. Keep `Atmosphere.Density` 0.15–0.25 outdoors so
   color survives distance. Grading limits: `Contrast` +0.1..0.2,
   `Saturation` +0.1..0.15 max (past ~0.2 is where mud starts), tween
   `TintColor` per mood.
7. **Whites do the heavy lifting.** Foam, clouds, panel interiors are the
   neutral that lets saturated accents pop without competing. Two full-sat
   complements touching at equal value vibrate — separate them with a value
   step or a neutral (sand, foam, navy outline).
8. **Reserved hues.** Hazard/threat red (`#FF4757` hub, `#FF3C32` reef enemy
   eyes) is never used decoratively. Checkpoint teal `#00CEC9` never changes
   hue — Ember Foundry depends on it as the lone cool complement.

---

## 2. Palette A — TIDETOWN

Constants across all phases and zones: outline `#1F294A`, reward gold
`#FFC75C`/`#FFB300`, panel ice `#F4FAFF`. Phase chip colors exist in
`tidetown/client/HudGui.lua`; ground anchors in
`tidetown/server/MapBuilder.lua`.

### Per tide phase

Drive every phase shift via ColorCorrection `TintColor` + Atmosphere tweens
(pattern in `tidetown/client/TideController.lua`) — never repaint the map.

**LOW — "golden hour flats"** (warm; 60% sand family)

| Hex | Role |
|---|---|
| `#EEDCA5` | ground dominant — dry sand (existing) |
| `#D8C391` | ground secondary — wet sand (existing) |
| `#7FD4C9` | receded shallow water (desaturated so pools pop) |
| `#FFD166` | glow / sun sparkle / wet-highlight |
| `#EF6C4D` | accent: starfish, buckets, sun-warm coral |
| `#D6A860` | UI phase chip (existing) — **navy text** |

Grading: TintColor `#FFF2DC`, ClockTime ~16.5, warm ambient `#B99F82`.

**RISING — "foam wall"** (energetic; the highest-contrast moment)

| Hex | Role |
|---|---|
| `#2BB3C0` | advancing water dominant |
| `#EAF7FA` | foam / crest — the neutral that sells the saturation |
| `#0094B0` | deep water band + UI chip (existing) |
| `#FFCA3A` | accent: siren flash, surge sparks (existing SPARK_GOLD) |
| `#1F6E85` | shadow water / crest underside |

Grading: TintColor neutral-cool `#EAF4F6`; fog starts closing.

**HIGH — "teal-navy flood"** (submerged; coolest and darkest)

| Hex | Role |
|---|---|
| `#123B5C` | depth dominant / distant fog wall (white text 11.6:1 AAA) |
| `#1B7F98` | mid water column |
| `#609EA8` | ambient tint (existing HIGH_TIDE_AMBIENT — keep) |
| `#48DBD1` | glow: caustics, bio-sparkle (existing LoadingGui ACCENT_TEAL) |
| `#FF6E5C` | accent: buoys, catch markers — the ONLY complement, ~10% |
| `#006894` | UI phase chip (existing, white text AA) |

Grading: TintColor `#CFE6E8`, Saturation +0.05 only — flood should feel
heavier, not brighter. FogEnd 700 (existing).

**FALLING — "silver ebb"** (calm; lowest saturation — the palate cleanser)

| Hex | Role |
|---|---|
| `#D7E1E8` | sky/overcast dominant |
| `#56B0BC` | retreating water + UI chip (existing) — **navy text** |
| `#C9CFC2` | drying sand-silver |
| `#EFF7F9` | mirror-sheen highlights on wet flats |
| `#E4C87E` | accent: revealed treasure/shells (muted gold — full gold returns at Low) |

Grading: TintColor `#E4EBEE`, Saturation −0.05 — deliberate desat sells
"silver".

### Per zone

Ground anchors already in `tidetown/server/MapBuilder.lua`.

**Tidepool Flats (Beach)** — parent hue: warm sand ↔ aqua.
`#EEDCA5` dry sand / `#D8C391` wet sand (ground) · `#80DEEA` pools
(existing) · `#40B4B6` sea (existing) · `#F08080` coral perch accent
(existing) · `#78B05C` dune grass (existing) · UI banner `#0094B0`.

**Old Tidetown (drowned town)** — parent hue: weathered pastel + warm wood
against teal flood. `#856446` wood / `#967352` rails (existing) · pastel
house set (existing, keep verbatim: `#ECBEB4 #B2D2E0 #E2DCB4 #C4DEBE
#DEC4E0` — all five sit at the same ~82% value; that equal-value discipline
IS the pastel look) · `#C46A4A` rust/barnacle accent · `#5C8A4E` kelp drape
(white text 4.04:1 — large text only) · flood water `#2E93A8` · UI banner
`#006894`.

**Glowcave Shallows** — parent hue: violet-slate dark + neon; value
inversion — glows are the light source. `#696276` cave floor (existing) ·
`#4A4458` walls (darker, violet-shifted, NOT black) · glow trio `#66FFFF`
cyan / `#BA68C8` violet / `#81D4FA` blue (existing GLOW set) · `#1E6E78`
cave water · `#FFD54F` catch-marker gold (existing MARKER_GOLD) · UI banner
`#5E35B1` (existing Tidepedia purple, white text AAA). Keep glow coverage
≤10% of surface area or the cave's value structure collapses.

**Abyssal Deep Reef** — parent hue: ink navy + treasure. `#525C69` deep
floor (existing) · `#16243E` abyss walls/backdrop · `#0B3448` water column ·
`#48DBD1` bioluminescent veins (on `#08111C` cover = 11.1:1 AAA — legible
glow) · `#FFC75C` salvage gold (on `#16243E` = 10.0:1 AAA) · `#FF3C32`
enemy eye-glow (existing ENEMY_LIGHT_COLOR — red is threat-only here) · UI
banner `#123B5C`.

---

## 3. Palette B — Hub game ("+1 Size Escape") worlds

Atmosphere palettes exist in `src/client/EnvironmentController.lua`
(indexed 1–4 = Meadow/Vent/Ember/Cloud); these ground + accent sets
complete them. Shared across worlds: coin gold `#FDCB6E`, checkpoint teal
`#00CEC9`, grow pad `#4CD137`, shrink pad `#00A8FF`, hazard `#FF4757`.

**Sprout Meadows** — green family, warm 13:30 light (atmo `#C7D6C7`, decay
`#FFDC82`, ambient `#96A08C` existing). `#7CBF4E` grass dominant ·
`#5E9A3C` grass shadow (hue-shifted dark, not black-mixed) · `#EFE6C8`
cream paths · `#FF79C6` flower accent (existing bounce pink) · `#FFDC82`
sun glow · `#8A6D4B` trunks.

**Vent City** — steel-blue family, cool 10:00 haze (atmo `#B4BECD`, decay
`#8CA0B9`, ambient `#828C9B` existing). `#57606F` steel walls dominant
(existing WALL) · `#2F3640` girder dark (existing BORDER) · `#DFE4EA`
platforms (existing STEP) · `#00CEC9` vent-glow accent · `#FFA801` caution
stripe (existing CRACK) — amber is THE warm pop here, ration it · haze
`#8CA0B9`.

**Ember Foundry** — orange family, 17:36 sunset (atmo `#D7AA9B`, decay
`#FF6E28`, ambient `#AA7864` existing). `#3A3540` charcoal ground dominant
(violet-shifted dark keeps orange luminous) · `#636E72` machine metal
(existing) · `#FF6E28` ember glow / lava seams · `#FFC048` molten highlight
· `#E84118` gate red (existing GATE) · `#00CEC9` checkpoints read twice as
strong here (complement) — the reason checkpoint teal never changes hue.

**Cloud Capital** — blue-white family, noon clarity (atmo `#CDE1FF`, decay
`#FFF5DC`, ambient `#B4C3D7` existing). `#F5F6FA` cloud dominant (existing)
· `#C9D9F0` cloud shadow (blue-shifted, never grey) · `#74B9FF` sky
platforms · `#00A8FF` deep-sky accent (existing SHRINK) · `#FDCB6E` gold
trim (existing COIN) · `#FF79C6` sparse festival accent.

World value ramp is intentional: Meadow → Vent → Ember (darkest) → Cloud
(lightest) gives the 4-world loop a readable arc. Preserve it when adding
worlds or reordering.

---

## 4. UI color tokens (navy-outline cartoon system, both games)

Core, all existing — keep verbatim: `OUTLINE_NAVY #1F294A` (2–2.5px stroke
on everything + all text on light fills) · `PANEL_ICE #F4FAFF` ·
`CARD_BLUE #E8F4FC` · `WHITE #FFFFFF` · warm card `#F8F0DC` (EggGui).

| Token | Hex | Text | Ratio | Use |
|---|---|---|---|---|
| ACTION_TEAL | `#0094B0` | white, bold/large or stroked | 3.58 | primary buttons (existing) |
| ACTION_TEAL_DEEP | `#007A93` | white, any size | 4.99 AA | same button, small/thin label |
| CONFIRM_GREEN | `#2E7D32` | white | 5.13 AA | buy/claim (existing) |
| DANGER_RED | `#EB452C` | white bold | 3.87 | close/remove (existing); small text → `#D93B22` (4.57 AA) |
| GOLD | `#FFB300` / `#FFCA3A` | **navy** | 7.94 / 9.33 AAA | premium, streaks — never white text |
| ORANGE_CTA | `#E8590C` | white bold | 3.58 | shop/bounty headers — replaces white-text `#FF8F00`/`#F0783C` fails; or keep those fills with navy text (6.23 AA on `#FF8F00`) |
| RARE_VIOLET | `#5E35B1` | white | 8.02 AAA | tidepedia/rare (existing) |
| SLATE_CHIP | `#546E7A` | white | 5.40 AA | idle tabs (existing) |
| DISABLED | `#9098A1` | **navy** | 4.88 AA | disabled buttons — white fails (2.92) |
| TEXT_MUTED | `#44507A` | on `#F4FAFF` | 7.47 AAA | secondary copy (new — desat navy, stays in family) |
| INFO_NAVY | `#26466E` | white | 9.62 AAA | toasts (existing) |
| COVER_DEEP | `#08111C`→`#123B5C` grad | white / `#48DBD1` | 11+ AAA | loading/reveal covers |

System rules: fills flat and saturated, interiors ice-white, EVERY element
strokes navy (`TidetownUi.stroke` / `UiBuilder`), corner radius consistent.
Phase/zone identity enters UI only through header fills and chips —
panel/card/outline never change per zone. That constancy is what keeps 20+
GUIs reading as one game.

---

## 5. Contrast-checked text pairs

Ratios computed with the WCAG 2.1 relative-luminance formula. WCAG targets:
4.5:1 body text, 3:1 large/bold (≥18pt, or 14pt bold) and UI components. A
text stroke counts as foreground — the house 2.5px navy stroke on white
text legitimately rescues mid-value fills, but never rely on it for small
text.

Verified-safe (keep):

| Pair (as coded) | Ratio | Verdict |
|---|---|---|
| white on `#1F294A` | 14.24 | AAA — safe everywhere |
| `#1F294A` on `#F4FAFF` / `#E8F4FC` / white | 13.5 / 12.7 / 14.2 | AAA |
| white on `#0094B0` | 3.58 | large/bold only |
| white on `#2E7D32` | 5.13 | AA |
| white on `#EB452C` | 3.87 | large/bold only |
| white on `#006894` | 6.16 | AA |
| white on `#5E35B1` / `#7E57C2` | 8.02 / 5.21 | AAA / AA |
| white on `#546E7A` | 5.40 | AA |

Known failures in current code (fix on next touch):

| Pair | Ratio | Fix |
|---|---|---|
| white on gold `#FFB300` | 1.79 | navy text (7.94 AAA) |
| white on orange `#FF8F00` (BountyGui) | 2.29 | navy text (6.23 AA) |
| white on disabled `#9098A1` | 2.92 | navy text (4.88 AA) |
| white on shop header `#F0783C` | 2.82 | `#E8590C` fill (3.58) or navy text |
| white on Low chip `#D6A860` (HudGui) | 2.18 | navy text (6.53 AA) |
| white on Falling chip `#56B0BC` (HudGui) | 2.52 | navy text (5.65 AA) |

**The tri-state label rule.** Any fill lighter than ~50% luma (golds,
ambers, light teals, silvers, sand) takes `OUTLINE_NAVY` text. Fills at
≥4.5:1 against white take white body text. Fills at 3:1–4.5:1 take white
ONLY at large/bold sizes or with the 2.5px navy stroke. Apply this to every
new chip, button, and banner without re-deriving it.

---

## 6. Game-feel & juice catalog

Existing toolkit (`src/client/UiBuilder.lua` =
`tidetown/client/TidetownUi.lua` modulo naming): `hoverPop` (Elastic-in /
Back-out UIScale + rotation shake with token invalidation), `popOpen`
(0.7→1 Back), `pulse`, `shineText`, `shimmer`, `gloss`, `cartoonify` /
`cartoonizeWindow` (FredokaOne + navy UIStroke + bevel gradient), `bubbly`
(staggered list pop-in + rubber-band overscroll), `slider`. Elsewhere: FOV
shrink-kick + growth particles (`EffectsController.lua`), egg-drop
cinematic (`EggGui.lua`), pitch-scaled rarity SFX (`EggGui.lua:450`),
SFX/Music SoundGroup buses (`SoundController.lua`), single-label Toast,
vignette flash (`WheelGui.lua:421`), rarity aura strokes
(`BackpackGui.lua:360`).

Governing principles: every player action gets ≥2 senses of feedback
(visual + audio; haptic on mobile/gamepad). Anticipation → impact → settle.
Effects scale strictly with value; big shakes stay rare so they keep
meaning. Always cancel-by-token (the `hoverPop`/`Toast` pattern is house
style); destroy one-shot Instances in `.Completed`.

Each entry: technique → exact API recipe → where it belongs.

1. **Press-down squash** → on `MouseButton1Down` tween the existing UIScale
   to 0.92 (`TweenInfo.new(0.08, Quad, Out)`); on `Activated` tween 1.06
   then settle 1 Back-out → add inside `hoverPop` itself so every button in
   both games inherits it. Highest-value single addition: clicks currently
   feel identical to hovers.
2. **Universal interaction audio** → extend `hoverPop`/`popOpen` to call
   `SoundController.playSfx` with pitch jitter
   `playbackSpeed = 1 + (math.random() - 0.5) * 0.12`; streaks step a
   semitone: `2 ^ (streak / 12)` clamped ~1.5 (generalize `EggGui.lua:450`)
   → both UiBuilder variants; hover tick ~0.15 vol, press pop, window
   whoosh.
3. **Odometer counters** → roll displayed value on `Heartbeat`:
   `shown += (target - shown) * math.min(1, dt * 8)`, write `math.floor`;
   on increase tween counter UIScale 1.15→1 Back-out 0.2s + flash
   TextColor3 toward gold; big deltas roll 0.5–1s → `CurrencyHud.lua`,
   TIDETOWN HudGui coin/pearl counters. Never snap currency text.
4. **Fly-to-HUD collect trails** → spawn 5–10 coin ImageLabels at the
   source screen point (`Camera:WorldToViewportPoint` for world pickups),
   random offset burst, then tween Position to the counter's
   `AbsolutePosition`, stagger `task.delay(i * 0.04)`, Quad-In; each
   arrival destroys the coin, bumps the odometer, ticks with rising pitch;
   curve = two chained tweens (up-out, then to target) → hub coin pickups,
   TIDETOWN catch rewards and surge payouts.
5. **Trauma camera shake module** → single `RenderStepped` binding:
   `camera.CFrame *= CFrame.Angles(...)` with each angle
   `maxAngle * trauma^2 * math.noise(seed, os.clock() * freq)`; expose
   `Shake.add(trauma)` (0–1, clamped), decay `trauma -= dt * decayRate`;
   rotational only for UI events, max ~1.5°, settings-gated (reference:
   Sleitnick's RbxCameraShaker, MIT) → replaces ad-hoc tween shakes in
   `EggGui`; use for surge hits, tide-siren, reef enemy strikes.
6. **FOV punch helper** → `punchFov(delta)`: set
   `camera.FieldOfView += delta` instantly (or 0.05s Quad-out), tween back
   to cached base `TweenInfo.new(0.35, Back, Out)`; negative ~−4 for
   rewards/impact, +8–12 for speed/launch; one cancel-token, never stack →
   generalize the hardcoded shrink kick in `EffectsController.lua`; use on
   grow pads, mount boosts, legendary hatches.
7. **Modal blur + backdrop** → one `BlurEffect` in Lighting, tween Size
   0→14 on `popOpen`, back to 0 then `Enabled = false` on close; plus a
   full-screen scrim Frame tweened to `BackgroundTransparency = 0.45`;
   refcount opens so two closing windows don't double-remove → wire into
   `popOpen`/`cartoonizeWindow` in both UiBuilder variants. Absent today;
   the clearest amateur-vs-studio tell.
8. **World flash via ColorCorrection** → for big moments tween a shared
   `ColorCorrectionEffect`: `Brightness = 0.25, Saturation = 0.15` → both
   to 0 over 0.4s Quad-out; the 3D world flashes too, richer than a white
   Frame → hatch reveals, jackpot wheel; keep Frame flash for pure-UI.
9. **Rarity FX ladder** → codify one `RewardFx.celebrate(tier)`: Common =
   pop + soft sound; Rare = + ray burst + pitch-up; Epic = + confetti + FOV
   punch + haptic; Legendary = + shake (trauma 0.5) + music duck + server
   broadcast → shared module consumed by egg, wheel, quest, rebirth, and
   TIDETOWN catch/Tidepedia unlocks; stops the current per-GUI
   re-implementation.
10. **Music ducking** → `SoundController.duck(seconds)`: tween musicGroup
    Volume to 30% over 0.3s, restore over 1s → both SoundControllers
    already own the buses; use under hatch cinematics and surge climaxes.
11. **Rare-drop broadcast** → server fires
    `Remotes.RareDrop:FireAllClients({playerName, itemName, tier})` (names
    already filtered via `GetNonChatStringForBroadcastAsync`,
    `PetService.lua:701`); client banner slides from top
    `UDim2.new(0.5,0,0,-60)` → `(0.5,0,0,20)` Back-out, `shineText` on the
    item name, 4s auto-dismiss, queue max 3, server-side per-player
    cooldown → hub legendary pets; TIDETOWN mythic catches.
12. **Confetti** → ParticleEmitters cannot parent to ScreenGuis. (a)
    world-space: invisible Part CFramed ~6 studs ahead of camera each
    RenderStepped, emitter `Speed 15–25`,
    `Acceleration = Vector3.new(0,-30,0)`, Rotation/RotSpeed ranges,
    `emitter:Emit(80)` one-shot; (b) UI-space: 20–30 rotated Frames, random
    BackgroundColor3, tweened down-screen with `Rotation += 360–720`,
    destroyed on completion → (a) composes with 3D hatch reveals, (b)
    survives camera cuts (wheel, quest-complete).
13. **Accelerating anticipation + hitstop** → hatch grammar: loop Rotation
    tween pairs where each cycle's duration ×0.85 and angle ×1.15, 4–6
    cycles, then ~0.15s of dead stillness, then flash + reveal at scale
    0 → 1.2 → 1 Back-out → upgrade both EggGuis: they have drop + shake
    but constant-rate; the acceleration and the beat of silence sell it.
14. **Haptics** → `Instance.new("HapticEffect")` with
    `Type = Enum.HapticEffectType.UIClick` (or `GameplayExplosion` for
    jackpots), parent it to `workspace`, then `:Play()`; keep
    `HapticService:SetMotor(Gamepad1, Small, 0.4)` as gamepad fallback →
    press-down (tiny) + rarity ladder tiers. Zero visual cost, huge
    mobile-feel win; repo has none.
15. **Floating world text** → BillboardGui (`AlwaysOnTop = true`,
    ±1 stud `StudsOffsetWorldSpace` jitter so stacks don't overlap) +
    cartoonified TextLabel: UIScale 0 → 1.3 → 1, then StudsOffset up
    2 studs + text/stroke Transparency → 1 over 0.7s, destroy on Completed
    → "+1 Size" pickups, coin grabs, checkpoint bonuses, TIDETOWN catch
    values.
16. **Damped springs for retargetable motion** → step on Heartbeat:
    `velocity += (stiffness * (target - value) - damping * velocity) * dt;
    value += velocity * dt`; critically damped
    `damping = 2 * math.sqrt(stiffness)`, ~0.7× for bounce; inject
    `velocity += kick` on events so bars flinch → progress/health bars,
    drag release, pet-card follow. TweenService is fire-and-forget and
    cannot retarget mid-flight.
17. **Staggered window build-in** → generalize `bubbly` beyond
    ScrollingFrames: on `popOpen`, walk direct children by LayoutOrder,
    UIScale 0 + `task.delay(0.04 * index)` before Back-out to 1; cap total
    cascade at ~0.3s; header first, close button last → both UiBuilder
    variants' window open path.
18. **Attract wiggle, one-attractor rule** → every 4–6s run the `hoverPop`
    shake + 1.0→1.08→1.0 UIScale bounce on the single most important idle
    CTA; `UiBuilder.attract(button)` returns a release function and
    enforces one attractor at a time → claimable quest, free-egg timer at
    zero. Competing wiggles are the #1 juice failure; constant `pulse` on
    many buttons trains players to ignore it.

Smaller mandates:

- **Toast queue**: upgrade `Toast.lua` from newest-wins single label to up
  to 3 stacked slide-in cards (UIListLayout + per-card lifetime, height
  tween on collapse) — bursts currently drop messages.
- **Fonts**: FredokaOne stays the display/theme font; use Roblox Builder
  Sans (`Font.fromName("BuilderSans")`) for body/secondary text where
  FredokaOne goes muddy at small sizes.
- **Reduce-motion setting**: one boolean in each SettingsGui, consulted by
  every shake/flash/confetti path. Costs one `if`; expected by Roblox UX
  guidance and accessibility norms.

---

## 7. Artistic direction

This repo's look is "storybook coastal cartoon": flat saturated fills,
navy — never black — holding every shape, and white doing the quiet work.
Phases and worlds change through atmosphere and grading, never repainting,
so the world reads as weathered by tide and time. Everything else about
the direction is §§1–6, operationalized — when in doubt, reread rule 1.
