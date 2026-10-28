# EMERGENCY CREW — Devlog

Newest entries at the bottom. Each entry: what changed, why, evidence.

## Day 1 · 11:26 — Kickoff & toolchain
- Empty repo; container had JDK 21 + Gradle, no engine, no Android SDK, no KVM (no emulator).
- **Engine feasibility (time-boxed):** Unity 6 needs a licensed Unity ID activation for unattended builds — not available. Unreal 5 needs an Epic account and ~100 GB toolchain. Godot 4.7.2 stable: MIT licence, 146 MB editor, export templates downloadable, GDScript, headless import/export.
- **Decision:** Godot 4.7.2 + Mobile renderer + GDScript. Locked for the vertical slice. Android SDK (platform 35/36, build-tools 35.0.1/36) installed via cmdline-tools.

## Day 1 · 11:35 — Core simulation first
- Built rules as plain RefCounted classes (no scenes) so every rule is unit-testable headless: `GameModel`, `IncidentDirector` (data-driven, seeded), `WorldState` (diff-only persistent facts), `Economy`, `CrewRoster`, `Community`, `StoryDirector` (authored fragments, condition-driven — no LLM at runtime), `SaveSystem` (versioned, md5-checksummed payload, atomic write, `.bak` fallback, migrations).
- First incident: **Tree down** (debris removal) with deterministic severity, weather and a *live wire* complication that blocks cutting until the utility isolates it.
- Evidence: 16/16 tests passing (`godot --headless -s res://tests/run_tests.gd`).

## Day 1 · 11:45 — First playable loop (primitives)
- Station → call alert → dispatch (drive or quick) → on scene → delegate Theo to cone off → take chainsaw → radio utility → cut (hold, ease off before the chain binds) → carry logs to verge pile → reopen road → outcome & payout → return → story fragment → station board (upgrade/repair) → end shift → next call.
- Failure is fair, not random: timer or abandon → roof damage persists until the player funds a repair; road reopens overnight.
- Autoplay bot (`-- --autoplay`) plays the real scene through the same input paths as touch. Evidence: PASS on seeds 4242/7/99 (drive) and seed 2 (live wire, 38 checks).

## Day 1 · 12:00 — First visual review
- Rendered screenshots (Xvfb + llvmpipe GL) show: washed-out lighting, chase camera clipping into the station, missing crew name tag, roof tarp hidden inside roof mesh. 265 draw calls on scene (too many — primitives aren't batched).
- Fixes: SpringArm3D camera, name fix, tarp re-pitched to roof slope, toast moved. Installed Mesa lavapipe so screenshots use the real **Mobile (Vulkan)** renderer.

## Day 1 · 12:20 — Art direction approved: "Living Diorama"
- Director approved Living Diorama + latest Blender (5.2). Wrote `ART_BIBLE.md`: one 8×8 palette atlas shared by every asset (one material → batching, consistent look across Kenney/Quaternius/custom sources), soft bevels, ~5-head characters, colour reserved for hazards/emergency kit, damage as swap-in pieces.
- **Global-work strategy (one-day deadline):** no per-asset hand work. A single Blender pipeline script normalises *any* source model (scale, pivot, axis, re-palette to atlas, bevel/normals, AO→vertex colour, budget check, LOD, glb export, manifest row, contact-sheet render). Parametric Blender generators produce families (houses, trees, station) in one pass. Godot side loads assets by logical id via `AssetLib` with primitive fallback, so gameplay never breaks while art lands.
- Second agent ("asset hand") owns sourcing, Blender pipeline, baking and import; I own integration, Android build, gameplay and docs. Disjoint file ownership to avoid conflicts.

## Day 1 · 12:25 — Android pipeline: first APK
- `tools/build_android.sh`: writes SDK/JDK paths into Godot editor settings, generates a local debug keystore (never committed), exports headlessly, verifies the signature with apksigner.
- Result: `build/EmergencyCrew-debug.apk` — 57.7 MB, `org.emergencycrew.prototype` 0.1.0, arm64-v8a + armeabi-v7a (32-bit kept for cheap phones), compile/target SDK 36, debug-signed. Not yet run on hardware: no device or emulator available here (RISKS R1).

## Day 1 · 12:40 — Second hands-on family: flooded cellar
- Story incident on day 2 at Rosa's: carry the pump to the cellar steps → couple hose sections to the drain → clear the drain grate → **pull-start in rhythm** (pull while the needle is in the green; early pulls fail) → water visibly drops while it pumps → check the cellar is safe. Fuse-box hazard means radioing the utility first.
- **Consequences carry forward:** if the tree beat you and Rosa's roof is still damaged, the tarp leaks — severity +1 and Rosa says so. If you saved her road, Tomás turns up with a torch and pumping runs 25% faster. Authored outcome texts are data, not code.
- Generalised the model rather than writing a second rules engine: incident eligibility conditions, once-only story incidents that take priority, condition-driven modifiers, and timed "auto" tasks the player can't skip by hand (a test caught that gap).
- Refactored sites onto a shared `IncidentSite` base (cones, meter, messages, hold-interactions), so the next incident type is mostly authoring.

## Day 1 · 13:10 — One-command verification
- `tools/test.sh [seeds]`: import (registers new classes — a missed import cost a hung run), 21 unit tests, then autoplay in drive and quick-dispatch modes per seed. The three-day autoplay plays the tree rescue, the day-2 flood and a day-3 failure end to end (49 checks on seed 2).
- Gave the bot shortest-path routing around the parked truck. This was a test-harness fix: players walk around it naturally.

## Day 1 · 13:20 — Batch A art integrated
- The asset hand delivered Batch A through the Blender 5.2 pipeline: station hall, 4 house variants (+ damage/patch overlays authored on the shared roof slope), 3 tree types, bush, cone, chainsaw, log section, root plate, canopy, log pile, rescue truck with separate light-bar nodes. 24.3k tris total, all within budget. Contact sheet: `docs/asset_renders/A.png`.
- Every glb imports onto the two shared materials `palette.tres` / `palette_emissive.tres`, so `AssetLib` no longer overrides materials.
- Town, truck, chainsaw, cones and tree-incident props now load art by id; houses rotate to face their street; primitives remain as fallback (`-- --no-art` for A/B perf comparisons).

## Day 1 · 13:15 — Emulator attempt, first in-game art review
- Installed the Android emulator; `emulator -accel-check` → "KVM requires a CPU that supports vmx or svm". The container CPU exposes no virtualisation, so no Android image can boot here. Device testing needs a physical phone or a device farm (RISKS R1).
- Full three-day run with Batch A art on the **Forward Mobile** renderer (lavapipe software Vulkan): PASS, 62 checks. Screenshots in `docs/screenshots/` (01–18).
- Art cut on-scene draw calls 267 → 155 and station 142 → 88 (fewer, merged meshes). On-scene primitives rose 20k → 71k: still well under the 150k budget.
- Review fixes: lane houses moved back 1 m so the deeper house models don't crowd the log-pile verge; Theo's "Saw's all yours" line now only plays at tree incidents.
- Still placeholder: characters (capsules) until Batch B lands; ground and roads are flat palette-coloured primitives.
