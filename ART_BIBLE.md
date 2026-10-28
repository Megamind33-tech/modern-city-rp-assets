# ART BIBLE — "Living Diorama"

Kettleford should look like a premium hand-built model town you could pick up: warm, chunky, readable from an elevated camera on a phone.

## Pillars
1. **Silhouette first.** Every object must read at 6 m camera distance on a 6" screen. Tools and hazards are oversized ~15%.
2. **One palette, one material.** All world assets sample a single 256×256 palette atlas (flat colour per face). No per-asset textures unless approved.
3. **Soft bevels, no hard CG edges.** Bevel 2–5 cm on hard-surface edges (1 segment), weighted normals.
4. **Colour means something.** Saturated red/amber/orange/blue only on emergency kit, hazards and interactables. Homes are soft pastels; nature is muted greens.
5. **Damage is a state, not a texture.** Damage/repair are separate swap-in pieces (tarp, stump, patch) driven by WorldState.

## Proportions & scale
- Units: metres, Y up. In Godot the asset's **front faces −Z**; pivot at base centre (ground contact at y=0).
- Characters: ~5 heads tall, 1.75 m adult, slightly enlarged hands/head (×1.1). Child ~1.25 m.
- Doors 2.1 m, storeys 3 m, road lane 4 m, kerb 0.12 m.

## Palette atlas (`game/assets/palette.png`)
8×8 grid of 32 px cells. Index = row×8+col. UV for a cell = ((col+0.5)/8, (row+0.5)/8) — UVs collapse to the cell centre.

| Row | Use | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Brand/station | navy #1D2A3A | signal red #E24B3B | red dark #B8352A | amber #F2A93B | cream #F6EBD9 | teal #2E9C9A | steel #B8BCC4 | tyre #1F2023 |
| 1 | Walls | butter #F3DFB5 | sage #CFE0D6 | peach #F0C8A8 | lavender #DCD6EA | sand #E6D3B3 | brick #B5503E | plaster #EDE8DE | pale blue #CFDDE8 |
| 2 | Roof/structure | slate #5B5F6B | roof brown #5C4B4B | terracotta #B8654A | dark wood #6B4A30 | light wood #C49E6B | glass #9FD0E0 | door navy #2B3A55 | door green #3E6B4F |
| 3 | Nature | grass #6B9E5B | grass dark #557F48 | leaf #4E8541 | leaf light #7FAE5C | bark #66472E | soil #7A5C40 | flower pink #D96C8C | flower yellow #E8C547 |
| 4 | Ground | asphalt #3E4047 | asphalt light #5A5D66 | kerb #B3AEA2 | pavement #CFC9BC | line white #F2EAD3 | line yellow #E8B83A | concrete #A9A69E | gravel #8E8A80 |
| 5 | Skin/hair | skin1 #F1C9A5 | skin2 #D9A27C | skin3 #A86F4C | skin4 #6E4630 | hair dark #2E2420 | hair brown #6A4428 | hair blonde #D8B46A | hair grey #A8A39C |
| 6 | Clothing | hi-vis #D9E04A | uniform navy #273449 | denim #4D6A8F | knit red #A8443C | cardigan green #5E7F5A | shirt white #EEE9E0 | mustard #C99A3A | plum #6E4A6A |
| 7 | Hazard/FX/damage | tarp blue #3368C4 | cone orange #F26B1D | warning red #D93A2B | emissive amber #FFB547 | emissive blue #4A7BFF | spark #FFE38A | char #2B2725 | water #5F9FBF |

Shared material (Godot): albedo = palette.png, vertex colour multiplies albedo (baked AO), roughness 0.85, metallic 0. Emissive parts (light bars, beacon) use a second shared emissive material and must be separate named nodes.

## Budgets (provisional until Android profiling)
| Category | Tris (LOD0) | Notes |
|---|---|---|
| Player / crew | ≤ 5k | Humanoid rig, ≤ 40 bones |
| Resident | ≤ 3k | Same rig |
| Rescue truck | ≤ 10k | Named nodes: `LightL`, `LightR`, `Body` |
| Car | ≤ 4k | |
| House | ≤ 3k | Roof separate node `Roof` |
| Tree | ≤ 1.2k | |
| Props | ≤ 800 | Cone ≤ 150, log ≤ 300 |
Scene targets: ≤ 150 draw calls, ≤ 150k visible tris on scene.

## Lighting & mood
Warm key sun (5500 K feel), soft sky fill, one real-time shadow cascade on Medium. Weather changes grade + fog, not geometry. Night is out of scope for the vertical slice.

## Characters
Crew: navy uniform + hi-vis band + role accent (Maren: white helmet; Theo: red beanie; Priya: amber overalls). Residents wear civvies from row 6. Faces: simple painted eyes/brows via palette cells, no facial rig; emotion via body animation.

## Sourcing rules
CC0 first (Kenney, Quaternius, Poly Haven). CC-BY allowed with credits entry. Never NC/ND, never ripped game assets, never Schedule I / ALTERLANE content. Every asset → row in `ASSET_MANIFEST.csv` before integration. Everything passes the Blender pipeline (re-palette, bevel, normals, AO bake, budget check) so mixed sources look like one set.
