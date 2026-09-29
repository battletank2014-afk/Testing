# Roblox Obby — Full Production Plan

A complete plan for building, testing, and publishing a Roblox obstacle course ("obby") game.

---

## 1. Concept & Pillars

**Working title:** `Skyward Sprint` (placeholder — swap freely)

**One-line pitch:** A brightly colored, checkpoint-based obby with 60 hand-tuned stages split across 4 themed worlds, a global fastest-completion leaderboard, and a "skip stage" convenience pass.

**Design pillars** (every decision should serve these):

1. **Readable at a glance** — a player should instantly know where to go next. No pixel-perfect jumps required to *understand* the level.
2. **Fast failure, faster retry** — respawn at the last checkpoint in under 2 seconds. Downtime kills obbies.
3. **Escalating skill curve** — teach a mechanic in isolation, then combine it with a previously learned one.
4. **Fair monetization** — sell convenience and cosmetics, never pay-to-win or pay-to-progress-block.

**Target audience:** ages 8–14, mobile-first. Assume touch controls; design jumps that work with a virtual joystick.

---

## 2. Scope

| Item | Decision |
|---|---|
| Platforms | PC, mobile, console (Roblox handles all) |
| Players per server | 20 (obby servers are social; keep it crowded) |
| Stage count at launch | 60 (4 worlds × 15) |
| Session length target | 8–15 min for a first-time full run |
| Persistence | DataStore — save furthest stage, wins, best time |
| Monetization | 1 game pass, 2 developer products, optional cosmetics |
| Live-ops | Seasonal world swap every 6–8 weeks |

**Explicitly out of scope for v1:** PvP, trading, custom avatar items, procedural levels, cross-server tournaments. Revisit after launch metrics.

---

## 3. Tech Stack & Repository Layout

**Stack:** Roblox Studio for level art, [Rojo](https://rojo.space) to sync a Git repo into Studio, Luau for all logic, GitHub for version control and CI.

Why Rojo: it lets code live in `.lua`/`.luau` files under Git, so you get real diffs, code review, and rollbacks — instead of the default binary `.rbxl` files that merge terribly.

```
project/
├── default.project.json        # Rojo project definition (maps folders -> services)
├── PLAN.md                     # this file
├── README.md
├── src/
│   ├── server/                 # -> ServerScriptService
│   │   ├── init.server.luau
│   │   ├── StageService.luau        # stage progression, validation
│   │   ├── CheckpointService.luau   # checkpoint touch handling
│   │   ├── DataService.luau         # DataStore load/save + session lock
│   │   ├── LeaderstatsService.luau
│   │   └── MonetizationService.luau # passes, products, receipt handling
│   ├── client/                 # -> StarterPlayer/StarterPlayerScripts
│   │   ├── init.client.luau
│   │   ├── HudController.luau       # stage counter, timer, skip button
│   │   └── EffectsController.luau   # checkpoint particles, sound, camera shake
│   ├── shared/                 # -> ReplicatedStorage
│   │   ├── StageDefinitions.luau    # data table: 60 stages
│   │   ├── Config.luau              # tunables (respawn time, colors, IDs)
│   │   ├── Net.luau                 # RemoteEvent/Function registry
│   │   └── Util.luau
│   └── assets/                 # models, sounds, UI (imported via Rojo where possible)
├── tests/                      # TestEZ specs (run in Studio or via run-in-roblox)
└── .github/workflows/          # lint + test on PR
```

**Plugin/tooling:** Rojo, [Selene](https://kampfkarren.github.io/selene/) (Luau linter), [StyLua](https://github.com/JohnnyMorganz/StyLua) (formatter), [Wally](https://wally.run) if you pull community packages, TestEZ for unit tests.

---

## 4. Architecture

### 4.1 Server-authoritative progression

The server owns truth. The client only *requests* and *renders*.

```
Client (touch checkpoint / reach pad)
  -> RemoteEvent: RequestStageComplete(stageId)
Server (StageService)
  -> validate: player is alive, stageId == currentStage + 1,
              player within N studs of the stage's end pad, cooldown elapsed
  -> on success: increment stage, set checkpoint CFrame, update leaderstats,
                 broadcast to HudController, mark DataStore dirty
  -> on failure: ignore (and log for anti-cheat review)
```

Never trust a client-sent position as authoritative. Validate against the server's known geometry.

### 4.2 Stage data model

Every stage is data, not bespoke code. This is the single most important design decision — it makes 60 stages manageable and lets you reorder/tune without touching logic.

```lua
-- src/shared/StageDefinitions.luau (shape)
export type Stage = {
    id: number,
    world: string,            -- "Grasslands" | "Caverns" | ...
    name: string,
    difficulty: number,       -- 1..5
    mechanics: { string },    -- e.g. {"jump","moving_platform"}
    startPad: CFrame,
    checkpoints: { CFrame },
    endPad: CFrame,
    timeLimit: number?,       -- nil = untimed
}
```

Level *geometry* lives in Studio (built by hand for quality); *progression metadata* lives in this table. Keep the two in sync with a validation script that asserts every stage ID has geometry named `Stage_<id>`.

### 4.3 Services & modules

- **DataService** — `DataStoreService` with session locking, retry/backoff, and `BindToClose` flush. Store `{ furthestStage, wins, bestTimeSec, totalDeaths, cosmetics }`. Handle load failure by giving a temp profile and retrying, never by wiping.
- **CheckpointService** — `Touched` handlers on checkpoint parts, or `ProximityPrompt` for a deliberate "press to save" feel. Debounce per player.
- **MonetizationService** — validate `ProcessReceipt` server-side, idempotent grants (check `PurchaseId` before granting), and `MarketplaceService:UserOwnsGamePassAsync` for passes.
- **Net** — one module that creates/names all remotes so client and server never drift on string names.
- **EffectsController** — checkpoint chime, confetti burst, brief camera punch. Juice is what makes an obby feel good.

### 4.4 Anti-exploit baseline

- Server-validated stage completion (distance + ordering + cooldown).
- Rate-limit every remote (e.g. max 1 completion request per 0.5s per player).
- Clamp: reject any completion request for a stage the player hasn't reached.
- `Workspace.FallenPartsDestroyHeight` tuned so falling always respawns at checkpoint, not spawn.
- Never replicate client-controlled values (speed, jump height) — those come from the server/StarterPlayer settings.

---

## 5. Level Design Plan

### 5.1 Worlds

| # | World | Palette | New mechanic introduced | Stages |
|---|---|---|---|---|
| 1 | Grasslands | greens, warm sky | jump, gaps, basic truss | 1–15 |
| 2 | Neon Caverns | purple/cyan, dark | moving platforms, conveyor | 16–30 |
| 3 | Frozen Peaks | white/blue, fog | disappearing platforms, ice (low friction) | 31–45 |
| 4 | Lava Core | red/black, particles | pendulum timing, kill-brick mazes, speed sections | 46–60 |

### 5.2 The teaching pattern

For every new mechanic, use three consecutive stages:

1. **Introduce** — mechanic in isolation, no time pressure, generous platform sizes. Failure is nearly impossible.
2. **Practice** — same mechanic, tighter spacing, one variant (e.g. platform moves horizontally instead of vertically).
3. **Test** — combine the new mechanic with the previous world's mechanic. This is the "gate" stage; it's allowed to be hard.

### 5.3 Difficulty curve rules

- Difficulty rating 1–5 per stage; never jump more than +1 between consecutive stages.
- Every 5th stage is a **breather**: short, easy, and visually rewarding (a vista, a shortcut unlock).
- No stage requires more than ~90 seconds of sustained precision.
- Checkpoint density scales with difficulty: 1 checkpoint on easy stages, up to 4 on gate stages.

### 5.4 Mechanic catalog

| Mechanic | Implementation sketch |
|---|---|
| Kill brick | `Touched` -> `Humanoid.Health = 0` (or teleport-to-checkpoint for a softer feel) |
| Moving platform | `TweenService` on an anchored part; optionally carry players via `AssemblyLinearVelocity` |
| Disappearing platform | Toggle `CanCollide`/`Transparency` on a loop; give a 0.5s telegraph |
| Conveyor | `BasePart.AssemblyLinearVelocity` or a `VectorForce` |
| Truss climb | `TrussPart`, standard Roblox climbing |
| Ice | `PhysicalProperties` with low friction on the material/custom properties |
| Pendulum | Anchored hinge (`HingeConstraint`) + `AngularVelocity`, or tweened rotation |
| Timed door | Server-synced countdown, opens for all players in the stage |
| Speed section | Temporary `WalkSpeed` boost applied server-side on pad touch |
| Wall jump | Scripted: detect a wall raycast while airborne, apply upward+outward impulse |

### 5.5 Level-building workflow

1. Block out the stage with plain parts in Studio at correct scale (1 stud = 1 unit; player is ~5 studs tall, jump clears ~5 studs up / ~7 studs across).
2. Playtest the blockout until the *path* is fun — ignore art entirely at this stage.
3. Add the metadata entry to `StageDefinitions.luau`.
4. Dress it (materials, colors, decals, lighting).
5. Re-playtest after dressing — geometry often "reads" differently with texture.

---

## 6. Player Experience & UI

- **Lobby** — spawn area with a leaderboard board (top 10 fastest full runs), a practice/stage-select room, and the shop.
- **HUD** — top center: `Stage 23 / 60`. Top right: run timer (starts on stage 1, stops at 60). Bottom right: "Skip Stage" button (mobile-friendly, thumb reach).
- **Checkpoint feedback** — chime + confetti + `Stage 23` toast. This is the core dopamine loop; make it loud and clear.
- **Death feedback** — quick fade, respawn at checkpoint, "Deaths: 14" counter increments.
- **Onboarding** — first stage is a 20-second walk-and-jump tutorial with floating text prompts; no menu, no reading wall.
- **Accessibility** — colorblind-safe palette, subtitles for any voice/text cues, option to disable camera shake.

---

## 7. Monetization

| Product | Type | Price (Robux, suggested) | What it does |
|---|---|---|---|
| Skip Stage | Game pass | 199 | Unlocks one free skip per stage; button in HUD |
| 2x Coins | Game pass | 149 | Doubles any currency earned |
| Checkpoint Save | Dev product | 25 | Persist current checkpoint to DataStore instantly (useful for long stages) |
| Trail Effect | Dev product | 99 | Cosmetic trail, 1 hour |
| VIP Tag | Game pass | 499 | Chat tag + lobby cosmetic |

Rules: no product ever *blocks* progression. Skip Stage must be purchasable but the game must be fully completable for free. Validate all receipts server-side and make grants idempotent.

---

## 8. Analytics & Live-Ops

Instrument from day one via Roblox analytics events:

- `stage_enter` / `stage_complete` / `stage_fail` with `stageId` — gives you the exact funnel and the rage-quit stages.
- `checkpoint_reached`, `death`, `session_end` with `furthestStage`.
- `purchase_started` / `purchase_completed` per product.
- D1/D7 retention, average session length, average stages per session.

**Live-ops cadence:** review the stage funnel weekly. Any stage with a >40% fail rate at the same spot gets a geometry tweak (move the platform 1–2 studs closer, add a checkpoint). Seasonal world rotation every 6–8 weeks keeps returning players engaged.

---

## 9. Milestones & Timeline

| Phase | Deliverable | Estimate |
|---|---|---|
| **P0 — Foundation** | Rojo project, Git repo, lint/format CI, empty place syncing | 1–2 days |
| **P1 — Core loop** | 1 world (15 stages) playable end-to-end, checkpoints, respawn, HUD, stage counter | 1 week |
| **P2 — Persistence** | DataStore save/load, session locking, leaderstats, leaderboard board | 3–4 days |
| **P3 — Mechanics** | Full mechanic catalog implemented + all 4 worlds built | 2–3 weeks |
| **P4 — Polish** | Effects, sound, UI pass, onboarding tutorial, accessibility options | 1 week |
| **P5 — Monetization** | Passes/products, receipt validation, shop UI, test purchases | 3–4 days |
| **P6 — QA & Balance** | Playtest with real players, tune the difficulty funnel, fix softlocks | 1 week |
| **P7 — Launch** | Publish, thumbnails, icon, description, tags, social push | 2–3 days |

Roughly **6–8 weeks** for a solo dev, faster with a second person on level art.

---

## 10. QA Checklist (must pass before publish)

- [ ] Every stage is completable without exploiting; verified by a clean full run.
- [ ] No softlocks: every stage has a reachable checkpoint and a way out.
- [ ] Falling always respawns at the correct checkpoint (test after each checkpoint on 5 random stages).
- [ ] DataStore: progress survives rejoin, server shutdown, and a simulated DataStore outage (progress isn't wiped).
- [ ] Remotes: a scripted client spamming `RequestStageComplete` cannot skip stages.
- [ ] Mobile: all jumps doable with touch controls; HUD doesn't overlap thumb zones.
- [ ] Console: gamepad navigation works for menus and the shop.
- [ ] Purchases: test each product in Studio test mode; grants are idempotent on repeat receipts.
- [ ] Performance: 60 stages loaded but only the active world streamed (`StreamingEnabled`), stable 60 FPS on a mid-tier phone.
- [ ] Text: no unlocalized strings, no placeholder names like `Stage_47`.
- [ ] Rating/age compliance: chat filter respected, no external links, Roblox TOS reviewed.

---

## 11. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| 60 stages is a lot of content | Data-driven stages + reusable mechanic kit; blockout-first workflow |
| Players skip via exploits | Server-authoritative validation from day one, not bolted on later |
| Data loss destroys trust | Session locking, retries, `BindToClose`, never wipe on load failure |
| Difficulty spikes kill retention | Analytics-driven funnel review; checkpoint density scales with difficulty |
| Obby market is saturated | Strong art identity (neon/lava contrast) + a real speedrun leaderboard as the hook |
| Studio/Git workflow friction | Rojo from P0; never hand-merge `.rbxl` files |

---

## 12. Immediate Next Steps

1. Install Rojo and initialize `default.project.json` in this repo.
2. Create the Roblox place in Studio and connect it via `rojo serve`.
3. Scaffold `src/shared/StageDefinitions.luau` with the first 5 Grasslands stages.
4. Implement `StageService` + `CheckpointService` for the core loop (P1).
5. Playtest stage 1–5 and confirm the checkpoint/respawn feel before building more.
