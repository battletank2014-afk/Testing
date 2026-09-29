# Skyward Sprint

A checkpoint-based Roblox obby: 60 stages across 4 themed worlds, server-authoritative
progression, and a data-driven stage catalogue.

This repo is the **code** half of the project. Level geometry is authored by hand in
Roblox Studio under `Workspace.Level`; everything else lives here as Luau source.

## Status

Working core loop. `rojo build` produces a playable place file, and the stage
catalogue is covered by tests that run outside Studio.

## Requirements

- [Rokit](https://github.com/rojo-rbx/rokit) (toolchain manager) — or install Rojo manually
- [Rojo](https://rojo.space) 7.x
- [Lune](https://lune-org.github.io/docs) — only needed to run the tests
- Roblox Studio — only needed to author levels

```bash
rokit install          # installs Rojo at the pinned version
rojo build default.project.json -o build/SkywardSprint.rbxlx
```

## Layout

```
src/
├── server/            -> ServerScriptService.Server
│   ├── init.server.luau        boot order + catalogue validation
│   ├── StageService.luau       progression, server-authoritative
│   ├── CheckpointService.luau  respawn resolution, checkpoint touches
│   ├── DataService.luau        profiles, session-locked DataStores
│   ├── LeaderstatsService.luau leaderstats mirror
│   ├── MonetizationService.luau passes + idempotent receipt handling
│   └── LevelBuilder.luau       placeholder geometry (dev only)
├── client/            -> StarterPlayer.StarterPlayerScripts.Client
│   ├── init.client.luau        end-pad detection + server handshake
│   ├── HudController.luau      stage counter, timer, toast, skip button
│   └── EffectsController.luau  chime, confetti, camera punch
└── shared/            -> ReplicatedStorage.Shared
    ├── Config.luau             all tunables (pure, testable)
    ├── Presentation.luau       Color3 / Material values (Roblox-only)
    ├── Net.luau                remote registry
    └── StageDefinitions.luau   the stage catalogue (pure, injectable)
```

## Tests

```bash
lune run tests/StageDefinitions.spec.luau
```

`StageDefinitions` and `Config` deliberately avoid Roblox globals and take config by
injection, which is what lets them be tested headlessly. Anything that touches
`Instance`, `workspace`, or services needs Studio to test.

## Design rules enforced by the tests

- Exactly `Config.TotalStages` stages, ids contiguous from 1
- Difficulty stays in 1..5 and never rises by more than +1 between consecutive stages
- Every 5th stage in a world is a breather (drops one difficulty point)
- Checkpoint count scales with difficulty (1/1/2/3/4)
- Every stage names at least one mechanic
- `build()` is pure — same config in, same catalogue out

## Working with Studio

Level geometry is **owned by Studio**, code is **owned by this repo**. Keep that split
and Rojo's Sync In / Sync Out can never clobber your art.

Each stage needs a Model named `Stage_<id>` under `Workspace.Level` containing at
minimum:

- `StartPad` (BasePart) — where the player spawns for that stage
- `EndPad` (BasePart) — triggers completion; the client detects it, the server validates
- optional checkpoint parts tagged `ObbyCheckpoint` with attributes `StageId` and
  `CheckpointIndex`

Set `Config.GeneratePlaceholderLevels = false` once real levels exist, otherwise the
server generates placeholder geometry for any stage that has no Model.

```bash
rojo serve             # then connect the Rojo plugin in Studio (localhost:34872)
```

## Anti-exploit model

The client never decides progression. It detects that it is standing on an EndPad and
asks the server; the server independently checks stage ordering, that the player is
within `Config.MaxCheckpointDistance` of that stage's EndPad, a per-player cooldown,
and a sliding one-minute rate limit.

## Not done yet

- Levels are placeholders (generated boxes), not designed courses
- Game pass / product IDs in `Config` are all `0` — fill these in before publishing
- No lobby, shop UI, leaderboard board, or onboarding tutorial
- `MonetizationService` grants are in-memory; a server crash between grant and save
  loses the purchase. Persist `PurchaseId`s in the profile for production.
