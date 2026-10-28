# DECISIONS
| # | Date | Decision | Why | Reversible? |
|---|---|---|---|---|
| D1 | Day 1 | **Godot 4.7.2 stable, Mobile renderer, GDScript** | No licence activation for headless CI (Unity), no 100 GB toolchain/Epic login (Unreal); MIT licence; headless import/export works in the container. | Locked for vertical slice |
| D2 | Day 1 | Rules in plain `RefCounted` classes, scenes are views | Headless unit tests, deterministic seeds, save = one dict | Yes |
| D3 | Day 1 | Save = JSON payload string + md5 + version, atomic rename, `.bak` fallback, migration table | Corruption-safe on Android kill; versioned | Yes |
| D4 | Day 1 | Story = authored fragments + conditions over flags/world/history; no runtime LLM | Cost, determinism, quality control | Yes |
| D5 | Day 1 | First mechanic family: debris removal (chainsaw bind timing + log carrying) | Physical, readable, cheap to simulate; second family (flood pump) next | Yes |
| D6 | Day 1 | Failure = persistent, repairable consequence (roof damage), never random | "Learn from mistakes", consequences that matter | Yes |
| D7 | Day 1 | Quick dispatch + optional driving; resume puts you back on scene | No forced long journeys; interruption recovery | Yes |
| D8 | Day 1 | Package id `org.emergencycrew.prototype`, debug-signed APK, arm64+armv7 | Low-end device coverage; final id/keystore before store | Change before release |
| D9 | Day 1 | Art: **Living Diorama**, single 8×8 palette atlas, Blender 5.2 pipeline | Approved by director; one material → batching + consistency across mixed sources | Style locked |
| D10 | Day 1 | Assets loaded by logical id via `AssetLib` with primitive fallback | Art and gameplay can land independently; tests never depend on art | Yes |
| D11 | Day 1 | Second agent owns asset sourcing/baking/import, disjoint file ownership, Godot runs serialised with `flock /tmp/godot.lock` | Parallel work without merge conflicts | Yes |
| D12 | Day 1 | Currency £, British small-town setting "Kettleford" | Tone (warm, wry), distinct from ALTERLANE | Yes |
