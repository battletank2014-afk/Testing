# Linking Roblox Studio to the Agent

Two mechanisms. They solve different problems — you'll likely want both.

| | A. Git bridge | B. Live Rojo bridge |
|---|---|---|
| Studio sees code changes | on `git pull` | instantly |
| Agent can see your level edits | via `git push` | yes, live |
| Works today with zero setup on your side | yes | needs port + plugin config |
| Robust to restarts | yes | no (dies with the session) |
| Best for | code, review, history, releases | level art, live debugging |

**Recommended: use A as the source of truth, B for live level work.**

---

## Part A — Git bridge (the reliable one)

This is the workflow to standardize on. Code flows through GitHub; Studio pulls it.

### A1. Get the repo onto your machine

```bash
git clone https://github.com/<owner>/<repo>.git
cd <repo>
```

### A2. Install the Rojo CLI (server side)

```bash
# Rokit is Rojo's own toolchain manager (recommended)
rokit add rojo-rbx/rojo
rokit install
```

Alternatives: download a prebuilt binary from
<https://github.com/rojo-rbx/rojo/releases>, or `cargo install rojo --version ^7`.

### A3. Install the Rojo Studio plugin

In Studio: **Toolbar → Plugins tab → Plugins Folder** opens the plugin directory.
Then either:

```bash
rojo plugin install     # installs the matching plugin version for you
```

or install "Rojo" from the Roblox plugin marketplace.

### A4. Open the place

In Studio: **File → Open from File** and pick your `.rbxl`/`.rbxlx`, *or* connect to
the published experience. Keep this Studio session open — it is the live target.

### A5. Start the Rojo server and sync

```bash
rojo serve
```

This watches the repo and listens on **`localhost:34872`** (Rojo's default port).

In Studio, open the Rojo plugin panel and press **Connect**.

The plugin will offer:

- **Connect** — live-syncs files as they change on disk.
- **Sync In** — writes the repo's tree *into* Studio (repo wins).
- **Sync Out** — writes Studio's tree back *to disk* (Studio wins).

> ⚠️ **Decide which side owns what before you sync.** Sync In and Sync Out
> overwrite each other. Recommended split:
> - **Repo owns:** `src/` (all code), `StageDefinitions.luau`, config.
> - **Studio owns:** level geometry, terrain, lighting, imported models.
>
> Keep level geometry in folders that `default.project.json` maps as
> *unmanaged* (or simply don't map them), so a Sync In never deletes your art.

### A6. Daily loop

```bash
git pull                # pick up code changes the agent pushed
rojo serve              # sync into Studio
# ... work in Studio ...
git add -A && git commit -m "..." && git push   # push your level edits
```

I see your pushes immediately and can build on them.

---

## Part B — Live Rojo bridge (real-time, needs port routing)

Goal: I run `rojo serve` inside my container and **your** Studio connects to it
directly, so file changes appear in Studio without you pulling anything.

This works because the container exposes ports **12000** and **12001** to the
internet:

```
https://work-1-dorhcudalhsszwqp.prod-runtime.all-hands.dev/   → container port 12000
https://work-2-dorhcudalhsszwqp.prod-runtime.all-hands.dev/   → container port 12001
```

(Verified: a server bound to `0.0.0.0:12000` is reachable through the public URL.)

### The problem

- Rojo serves HTTP over **TCP on 34872** by default — not 12000/12001.
- The public hostname terminates **HTTPS**; Rojo's plugin speaks plain **HTTP**.
- Rojo's plugin supports a custom **host**, but a TLS-terminating hostname is not
  a drop-in replacement for `localhost:34872`.

So a direct public-URL connection is **not guaranteed to work**. The two ways to
bridge it, in order of likelihood:

### B-option 1: SSH tunnel (most reliable)

On your machine:

```bash
ssh -L 34872:localhost:12000 <user>@<container-host>
```

Then in the Rojo plugin, connect to **`localhost:34872`**. The tunnel forwards to
the container's port 12000, where I run Rojo. Requires SSH access to the container.

### B-option 2: Local relay on your machine

If no SSH is available, run a tiny proxy on your PC that forwards
`localhost:34872` → the container's public URL, rewriting HTTPS to HTTP in the
process. Then point the Rojo plugin at `localhost:34872`.

### B-option 3: Just use Part A

If neither bridge works, Part A gives you the same end result with one `git pull`
instead of a live socket. For code work the difference is seconds, not minutes.

### I will do when you say go

```bash
cd /workspace/project
rojo serve --address 0.0.0.0 --port 12000    # bind to the exposed port
```

Then I hand you the exact connect details for whichever bridge option you picked.

### B caveats

- The bridge dies whenever my session ends or the container restarts.
- It is a live, unauthenticated write path into your place while it's running —
  fine for a private workspace, don't leave it open on a shared project.
- Part A remains the durable source of truth regardless.

---

## Part C — Headless publish (no Studio needed)

Once the repo builds, I can ship a place file straight to Roblox:

```bash
rojo build -o build/game.rbxlx

curl -X POST \
  "https://apis.roblox.com/universes/v1/<universeId>/places/<placeId>/versions?versionType=Published" \
  -H "x-api-key: $ROBLOX_OPEN_CLOUD_API_KEY" \
  -H "Content-Type: application/xml" \
  --data-binary "@build/game.rbxlx"
```

- `versionType=Published` publishes; `versionType=Saved` saves without publishing.
- Content type: `application/octet-stream` for `.rbxl`, `application/xml` for `.rbxlx`.
- The API key needs the **`universe-places:write`** scope.
- A publish will **conflict if the place is currently open in Studio** — close the
  Studio session first, or publish from a CI job rather than by hand.

I need from you: **Universe ID**, **Place ID**, and the API key (register it as a
secret here — it is never committed).

---

## Prerequisites checklist

- [ ] Repo exists on GitHub and is cloned locally
- [ ] Rojo CLI installed (`rojo --version`)
- [ ] Rojo Studio plugin installed
- [ ] Place opened in Studio
- [ ] `default.project.json` present and mapping `src/` to the right services
- [ ] Agreed split of repo-owned vs Studio-owned folders
- [ ] (Part C only) Universe ID, Place ID, Open Cloud key with `universe-places:write`
