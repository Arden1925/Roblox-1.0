# +1 Size Escape — Design

The approved v1 design. Update this document when the design changes so the
code and the plan never drift apart.

## Concept

You spawn tiny. Standing on **Grow Pads** raises your Size, which physically
scales your character. Barriers gate progress in both directions:

- **Size Gates** open only for characters that are big enough.
- **Squeeze Cracks** are passable only for characters that are small enough.

**Shrink Pads** temporarily shrink you so you can squeeze through, and you
regrow automatically afterward. Every room asks: do I need to be big or
small right now?

## The fairness rule

Two separate numbers per player:

| Number | Meaning |
| --- | --- |
| **Max Size** | Permanent progress. Only ever goes up. Saved, shown on the leaderboard. |
| **Current Size** | The body right now. Shrink Pads lower it; it regrows to Max Size over time. |

Shrinking never costs progress. It is a tactical tool, not a punishment.

## Rebirth

At the required Max Size (rises with each rebirth), a player can rebirth:
Max Size resets to 0 in exchange for a permanent growth multiplier.

## Architecture rules

1. The server is the only authority on Size. Clients display; they never
   decide.
2. Every tunable number lives in `src/shared/GameConfig.lua`.
3. DataStore calls are wrapped in `pcall` with retries. If a load fails, the
   session never saves, so real data is never overwritten with defaults.
4. Nothing yields on the main task; anything that waits runs in `task.spawn`.
5. Map elements are driven by CollectionService tags and attributes, so the
   map can be built and decorated freely in Studio:

| Tag | Attribute | Meaning |
| --- | --- | --- |
| `GrowPad` | — | Standing on it raises Size |
| `ShrinkPad` | — | Standing on it lowers Current Size |
| `SizeGate` | `RequiredSize` | Opens for players at or above the size |
| `SqueezeCrack` | `MaxAllowedSize` | Passable for players at or below the size |

`MapGenerator` builds a three-zone starter map only when the workspace
contains no tagged parts, so a hand-built map always wins.

## Game passes

Configured in `GameConfig.passes`. IDs are 0 until the passes are created on
the Roblox website; entries with ID 0 show as "coming soon" in the shop.
v1 wires two passes: **2x Growth** and **Instant Shrink**. The whole game
stays completable without spending — passes sell speed and convenience,
never access.
