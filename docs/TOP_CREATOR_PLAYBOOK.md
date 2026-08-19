# What the Top Roblox Creators Teach Us

Read before designing content or live-ops for either
game in this repo: **TIDETOWN** (`tidetown/`, ROGER_7.0.md) and
**+1 Size Escape** (`src/`, GAME_DESIGN.md). Everything here transfers
*mechanics and styles, never IP*. Both games are zero pay-to-win by design
(disjoint currencies, narrow power band — `TidetownConfig`); every pattern
below is adapted to survive that constraint, not fight it.

---

## Studios studied

**BIG Games (Pet Simulator 99).** Retention engine is 140+ consecutive
weekly updates, each with one headline noun ("Fantasy World!"). Always ≥3
concurrent progression bars (ranks, rebirths, mastery, zones, egg RNG) so
every session visibly moves something. Ships an official public database
(db.biggames.io) — treats its economy as a spectator sport. Visuals:
ultra-chunky low-poly, near-max saturation, screen-filling hatch VFX,
compact zones crossed in seconds (BIG Games dev blogs; db.biggames.io).

**Do Big Studios / Splitting Point (Grow a Garden).** 21.9M CCU record,
fastest game to 1B visits. Crops grow while you are offline AND while you
are elsewhere in-server — returning always means good news. Single-verb
core learnable in under 60 seconds; rotating seed shop on a short real-time
timer creates appointment play; weather events are server-wide and
unmissable; no fail state at all. Soft pastel look; growth shown by literal
plant size, not numbers (Wikipedia; Eneba CCU report).

**Uplift Games (Adopt Me!, 42B+ visits).** Pivoted from family roleplay to
pets when the data said pets — follow the fun, rename nothing. Pet needs
turn idle time into caretaking micro-tasks; aging pets are a time-gated
rarity multiplier; visitable homes make status spatial. Trading is the real
endgame — and the platform's biggest scam/dupe magnet (see warnings).
Icon-forward, pre-reader-friendly UI (Wikipedia; Uplift devforum posts).

**LSPLASH (Doors).** Door-by-door loop is a metronome; every entity
telegraphs with a distinct audio/visual tell (Rush = flicker + distant
roar) before punishing the wrong response — conditioning, not random
jumpscares. Death teaches: the Guiding Light hint system converts failure
into a lesson. Numbered doors 1–100 are a progress bar built into the level
itself. Near-monochrome palette so signal colors carry meaning; the sound
mix does half the design work (Wikipedia; Endsights horror-design study).

**MiniToon (Piggy).** Episodic "books/chapters" with cliffhangers as a
content cadence — the whole community shows up on release day; chapter
launches spiked CCU past a million at the 2020 peak. Cute-made-hostile
contrast is instantly memeable; one player becomes the monster, so
asymmetric roles come from one asset set. Bright flat colors on horror content — the dissonance IS the
brand (Piggy wiki).

**Dress to Impress team (DTI, 6B+ visits).** Timed rounds (theme → dress →
catwalk → peer vote) manufacture a shareable artifact every round — the
outfit — which fed a TikTok flywheel that doubled Roblox streaming
viewership. Zero-instruction onboarding: the wardrobe IS the tutorial.
Monetization is premium cosmetics only. UI dense in the dressing room,
invisible on the runway (Stream Hatchet; ScreenRant).

**Easy.gg (BedWars, Islands).** Metronomic Friday 3PM update the community
schedules around; seasons and kit metas keep a PvP game evergreen. The
buy-defend-destroy loop makes your lose condition (your bed) a physical
object you can see and fortify (Easy.gg wiki).

**Gamefam (Sonic Speed Simulator).** Brand IP delivered through a proven
Roblox-native loop, not a ported console design; biggest launch of its era
(275K CCU week one) because the fantasy lands in second one — you run fast
immediately, upgrades only widen it. Speed conveyed with FOV stretch,
trails, and blur (Wikipedia; Gamefam case study).

**Starboard Studios (The Wild West).** Paid-access launch filtered for an
older, invested audience; open-world role choice with a player-driven
bounty economy; muted palette and realistic scale. Proof Roblox supports
"serious" atmosphere when the audience is teen+ (Roblox wiki; Medium
review).

**AAA showcases (Frontlines-class).** Minimal loop, maximal fidelity —
great marketing, weak retention. The lesson is negative: fidelity alone
does not retain on Roblox. Spend the polish budget on the loop's feedback
first.

**2025 breakout meta (Steal a Brainrot, 99 Nights in the Forest).**
Buy-steal-defend triangle: your collection earns per second, is physically
stealable, and defense is a spend sink; being robbed creates revenge
sessions. Day/night phase clock alternates safe-build vs. dangerous-raid —
a direct structural cousin of TIDETOWN's tide clock. Weekly meme
collectibles with escalating rarity tiers, Common→Secret (Hardware Insider
2025 overview).

---

## Pattern library

### Loop and progression

- One-noun weekly update, announced by a physical in-world object
  (BIG Games, Easy.gg).
- Fixed public update slot the community can set a watch by — never slip
  silently (Easy.gg Friday 3PM; Adopt Me Thursday 4PM GMT).
- Core verb playable within 10 seconds of spawn, zero text (Gamefam, DTI).
- Return-to-good-news: something accrues while away and greets you at spawn
  as a moment, never a silent balance change (Grow a Garden, Adopt Me).
- Appointment timers shorter than a session — rotating shop stock, periodic
  bloom (Grow a Garden seed shop).
- Shared server-wide phase clock that changes what the whole map IS; no
  phase-agnostic features (Steal a Brainrot, Grow a Garden weather).
- Threats telegraph with a learnable cue before they hit; players should
  dodge by ear by session three (Doors).
- Failure pays differently, never zero (Doors' Guiding Light; TIDETOWN
  salvage piles already do this).
- Numbered spatial progress bar built into the world itself (Doors door
  numbers; +1SE boundary walls).
- Asymmetric spike moments one player briefly "stars" in, built from
  existing assets (Piggy's monster role).
- Episodic numbered lore so history accrues per cycle ("Tide 47: the cave
  opened") (Piggy books).
- Every cycle manufactures a shareable artifact — a look, a card, a
  scoreboard photo (DTI).
- Peer judging and visiting are free content: walkable plots + one-tap
  rating (DTI voting; Adopt Me house visits).
- Collection log granting small permanent account-wide buffs (PS99 mastery;
  Tidepedia already is this).
- Escalating rarity ladder with a visible top tier nobody has yet —
  silhouette shown from day one (Steal a Brainrot Common→Secret).
- Multiple concurrent progression bars; the HUD shows at least one tick
  every minute (BIG Games).
- Follow the fun the data shows, keep the name: instrument which activity
  wins early and reweight content toward it (Adopt Me pivot).

### Visual and production

- Chunky silhouettes, key objects ~10% more saturated than the environment
  — the platform's native look (BIG Games; classic-avatar trend data).
- Signal colors reserved exclusively for gameplay meaning, never reused
  decoratively (Doors light colors; BedWars team colors).
- Spectacle VFX budget goes to the loop's payoff moment, not ambience
  (BIG Games hatch bursts vs. the Frontlines lesson).
- Sound carries state the screen cannot: phase should be identifiable
  eyes-closed anywhere on the map (Doors).
- Icon-first, text-light UI for pre-readers; persistent HUD ≤5 elements for
  non-menu games (Adopt Me vs. PS99 density).
- Camera as feel: FOV punch for impact/speed, pulled back for scale,
  a brief cinematic pan for the big phase transition (Gamefam; DTI).
- Worlds scaled small: zones read at a glance and cross in under 45 seconds
  (BIG Games; Grow a Garden plots).

---

## Live-ops playbook (zero pay-to-win)

Grounded in shipped systems: 7-min authoritative tide cycle
(`TideClockService`, `phaseEndsAtUnix`), surge defense (`SurgeService`),
Tidepedia log (`TidepediaService`), pause-not-reset streaks
(`BountyService`), published egg odds (`EggService`), disjoint currencies —
Shells=time, Stormglass=skill (`TidetownConfig`), data-driven
`CreatureCatalog`.

1. **Fixed weekly slot.** Ship a "Tide Report" every Saturday; countdown
   board on the pier deck; content activates at the first Low tide after
   the hour so the tide clock delivers the update moment (PS99 Saturday;
   Adopt Me Thursday).
2. **Tease pipeline.** "Unidentified sighting" Tidepedia entry 3–4 days
   early — silhouette, `???` name — plus a washed-up object on the beach.
   One guarded `CreatureCatalog` entry with `revealed = false`.
3. **Seasonal variants, never power.** Seasonal tides retint water, swap
   ambience, ship look-only species variants inside the same power band —
   the narrow-band rule is the enforcement mechanism (PS99 events, healthy
   version).
4. **Dev appearances.** "The Keeper's Visit": off-schedule surge with a
   novel wave comp via `SurgeService`, freak double-high tide, rare-spawn
   window. Weekend bias, unannounced, hands out items/cosmetics — never
   currency (Grow a Garden "Admin Abuse").
5. **Tide Codes.** In-lore codes ("SPRINGTIDE") for Shells, egg charge, or
   cosmetics — **never Stormglass**; skill currency must stay skill-earned.
   Anniversary rewards run a full week to keep FOMO low.
6. **Streaks pause; comebacks pay.** `BountyService` already pauses —
   promise it in `BountyGui` copy ("Your streak waits for you"). Add a
   Returning Keeper bounty after 7+ days away. Never render a "streak
   lost" state (Roblox Streak Recovery rationale).
7. **Global shareable moments.** Server-wide toast + foghorn on Mythic logs
   and page completions (route through existing `pushToast`); generate a
   "catch card" stamped with tide phase + cycle number — unique to a
   moment (Sol's RNG broadcasts; Fisch).
8. **Server-wide co-op goals.** "Storm Front" surges: if all claimed reefs
   survive, everyone gets a salvage bonus — players who play socially
   retain far better than solo players (Roblox retention research; PS99
   group grinds).
9. **Gifting, not trading.** One-way gifts, small daily cap, no take-backs,
   no negotiation UI. Generosity loop with near-zero scam/dupe surface and
   no third-party value-list economy (Adopt Me scam/dupe cautionary).
10. **Update-note theater.** Harbor Notice Board renders the Tide Report
    in-character; every balance change carries one WHY sentence; never
    hide a nerf in a silent push (BIG Games changelog culture).
11. **Publish the odds; state the covenant.** Exact percentages in
    `EggGui`, no `???` rarities. Game description: "Stormglass cannot be
    bought. No creature is stronger for money. Odds are printed on every
    egg." A rule players can quote markets itself (PS99; Roblox paid-RNG
    disclosure mandate).
12. **Feed external infrastructure.** Export `CreatureCatalog` as public
    JSON so wikis and Discord bots bootstrap instantly; weekly Tide Chart
    post; community votes on which teased species ships next (BIG Games
    public DB).
13. **Anchor events to the tide clock — the unique hook.** "King Tide"
    every Nth cycle: higher `highWaterY`, rare spawn table, harder surge,
    bonus Stormglass. `phaseEndsAtUnix` makes the timetable computable —
    publish it and let players schedule sessions like real surfers.
14. **Anti-inflation discipline.** Events and admin visits grant items,
    never raw currency; keep rotating Shell sinks; log every currency
    grant server-side; build the gifting kill-switch before launch.
15. **First-minute FTUE.** Fun within 10 seconds, first reward within 60:
    guaranteed shallow-flat catch that works in any phase, first Tidepedia
    "NEW ENTRY!" inside a minute, and the first rising tide IS the
    tutorial beat, narrated live by `TutorialGui`.
16. **Competition pays identity, not power.** Weekly surge leaderboard
    awarding titles, barrier skins, pier flags; seasonal reset leaves a
    permanent commemorative Tidepedia stamp (PS99 leaderboard events).
17. **Content drought math.** A species-per-week drip beats a
    zone-per-quarter drop — `CreatureCatalog` makes a species a data edit
    plus a model. Bank a 4-week backlog BEFORE announcing the Saturday
    cadence; the cadence is a public promise.
18. **Never breach a stated promise (meta-rule).** Codify publicly: streak
    never resets, odds always printed, power never sold, owned creatures
    never weakened without a Tide Report explaining why. Treat each as an
    API contract with players.

Most of this ports to +1 Size Escape directly: weekly slot, codes,
paused streaks, shareable "day 1 vs. now" size snapshots, sizes-seen log
with tiny regrow buffs, and the same no-power-sales covenant.

---

## What kills games

- **Silent nerfs and retroactive devaluation.** The three trust breaches
  that killed goodwill in trading games: silent nerfs, devaluing earned
  items, scam-enabling systems. One breach costs more than a month of
  updates.
- **Trading without dupe defense.** Adopt Me's Bat Dragon dupe forced
  trading offline and cratered pet values. This repo's answer: gifting
  only, kill-switch ready, every grant logged.
- **Currency inflation.** Printed currency drowns sim economies. Disjoint
  currencies + item-only event rewards is the levee — defend it.
- **Bad FTUE.** No fun in 10 seconds and no reward in 60 means the player
  never comes back.
- **Content droughts.** "Stagnant content leads to ghost towns"; revival
  after a drought needs a full rebrand — far costlier than the drip.
- **Announcing a cadence you can't hold.** Missing a public weekly slot
  once costs more than starting a month later. Backlog first.
- **Fidelity without a loop.** The Frontlines lesson: polish the payoff
  feedback, not the ambience. AAA looks retain nobody by themselves.
- **FOMO abuse.** One-day exclusives punish the audience you want to keep.
  Run limited rewards a full week; keep limiteds cosmetic or lateral.

---

## Application shortlist: top 10 for TIDETOWN

1. **King Tide schedule (pattern 13).** Every Nth cycle escalate
   `highWaterY` + spawn table in `TideClockService`/`SurgeService`; publish
   the computable timetable from `phaseEndsAtUnix`.
2. **Saturday Tide Report (pattern 1).** Fixed weekly one-noun drop; pier
   countdown board part; content flips at first Low tide after the hour.
3. **Telegraphed surge waves (Doors).** Unique pre-arrival sound + water
   discoloration per feral wave type in `SurgeService`; dodge by ear by
   session three.
4. **Phase-audible soundscape (Doors).** `SoundController` plays gulls at
   Low, roar at High, everywhere on the map — tide state readable
   eyes-closed.
5. **Tidepedia tease pipeline (pattern 2).** `revealed = false` catalog
   entries render as silhouette + `???` in `TidepediaGui` 3–4 days before
   each drop; one Secret species per season visible from day one.
6. **Catch cards (DTI/Sol's RNG).** On Mythic log or page completion, fire
   a server-wide toast + foghorn and render a shareable card stamped with
   species, rarity, tide phase, cycle number.
7. **Guaranteed first-minute catch (pattern 15).** Phase-proof tide pool
   beside the pier spawn; first "NEW ENTRY!" stamp inside 60 seconds;
   first rising tide narrated by `TutorialGui` as the tutorial.
8. **Rotating pier shop per tide cycle (Grow a Garden).** `ShopService`
   cosmetic stock reshuffles each cycle — an appointment timer shorter
   than a session and a standing Shell sink.
9. **Storm Front co-op surge (pattern 8).** Occasional escalated High
   phase where all claimed reefs surviving pays every player a salvage
   bonus — one shared bar the whole server watches.
10. **Printed odds + covenant (pattern 11).** Exact percentages in
    `EggGui`; covenant text on the Harbor Notice Board and game
    description; never grant Stormglass from codes or events.

Signal-color rule while building all of the above: one hue owned by the
perfect-cast ring, one by surge-incoming, never reused decoratively.
