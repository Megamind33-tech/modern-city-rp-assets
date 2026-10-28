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
