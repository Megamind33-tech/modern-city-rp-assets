# Asset pipeline devlog

## 2026-10-28 — Pipeline up, Batch A delivered

**Tooling.** Blender 5.2.3 LTS (/opt/blender, headless). Pipeline lives in `tools/blender/`:
`palette.py` (palette.png/json from the ART_BIBLE table), `lib.py` (bmesh builder with a per-face
`pal` attribute, materials, CIELAB nearest-palette), `generators.py` (parametric Living-Diorama
families), `pipeline.py` (finalize + export), `render_sheet.py` + `stitch.py` (contact sheets),
`make_index.py` (asset_index.json + ASSET_MANIFEST.csv), `godot_import.py` (Godot import settings),
`assets.json` (one spec per asset), `build_all.sh` (rebuild everything idempotently).

**Decisions.**
- Batch A is 100% procedural. CC0 kits (Kenney/Quaternius) were considered, but none matched the
  exact brief (22 m two-bay station with tower, swap-in roof damage that registers with house roofs,
  log with exact 1.0 m length/cut faces) and every import would still need re-palette and fixes.
  Generators author straight onto palette cells, so licensing is trivially clean (original work, CC0).
- Orientation: author front = Blender +Y; glTF exporter (+Y up) writes it as -Z. Verified with a
  Godot render from the -Z side (house door visible). No per-asset rotation needed.
- Finalize order: bevel (1 seg, 40 deg angle limit; auto-dropped if it would break the budget) ->
  weighted normals (hard surface) or flat shading (nature) -> budget decimation -> UV collapse to
  cell centres from the face `pal` attribute (after modifiers, so bevel faces never interpolate
  between cells) -> Cycles AO bake to COLOR_0 (temp ground plane; distance 0.2 x size, capped 1.2 m;
  remapped to 1-s*(1-ao), s=0.45 env / 0.5 others) -> glb.
- Godot: glTF import does NOT set vertex_color_use_as_albedo, so every glb .import maps glTF
  materials `palette`/`palette_emissive` to shared `res://assets/materials/palette.tres` /
  `palette_emissive.tres` (albedo palette.png x vertex colour, nearest filter, roughness 0.85) and
  discards the embedded image copy. palette.png kept lossless (no VRAM compression).
- Overlays (`roof_damage` = Tarp + Limb nodes, `roof_patch` = Patch) are authored in house-local
  space on the shared front roof slope (all houses: 7x8 m, walls 6 m, 35 deg pitch, ridge along X),
  so they take the house transform as-is. house_d originally had a front cross-gable; it clashed
  with the fallen limb, so it became porch + bay window instead.
- Station bay doors are separate nodes `BayDoor1/2` with pivot at the top-centre of each opening
  (translate +Y / scale Y to open); a dark interior box sits behind them.

**Problems.** Coplanar trim slabs gave AO=0 (black roof) on the station -> replaced with parapet
rings. bmesh icosphere `subdivisions=1` is a 20-face icosahedron in 5.2 (canopies were too faceted)
-> subdiv 2. First Godot run of `--import` extracted a `<id>_palette.png` per glb -> fixed by
`godot_import.py` (embedded_image_handling=0) and removed.

**Numbers (tris).** station_hall 5327, house_a 2642, house_b 2106, house_c 2106, house_d 2194, roof_damage 1178, roof_patch 352, tree_oak_a 651, tree_oak_b 731, tree_street 332, bush_a 340, traffic_cone 104, chainsaw 600, log_section 188, root_plate 280, canopy_cluster 600, log_pile 560, rescue_truck 3968. Batch A total 24259 tris; all within budget.
Contact sheets: `docs/asset_renders/A.png`, `docs/asset_renders/A_overlays.png`.
Validation: `godot --headless --import` clean, every glb loads, surfaces resolve to the shared materials.

## 2026-10-28 — Batch B (characters) delivered

**Sources (all CC0 1.0, licence files checked inside each zip, author Quaternius):**
Universal Base Characters [Standard] (bodies + hair, https://quaternius.itch.io/universal-base-characters),
Universal Animation Library [Standard] and Universal Animation Library 2 [Standard]
(https://quaternius.itch.io/universal-animation-library, -2). Same 65-bone UE-style skeleton across all
three, so clips apply by bone name with no retargeting. Downloads are scripted
(`tools/blender/fetch_sources.sh`, free itch.io flow) into gitignored `tools/asset_sources/`.

**Pipeline (`tools/blender/characters.py`).** Head x1.1 (child x1.32) and hands x1.1 baked into the mesh
with the rest pose untouched; finger weights merged into `hand_l/r`, finger + leaf bones removed
(65 -> 23 bones); body decimated to budget after the hair; body bisected at region lines so bands have
straight edges; palette regions painted from dominant bone weight + height bands (skin / top / sleeves /
bottom / shoes, crew hi-vis waist, cuff and shin bands); eyes + brows painted on the nearest
front-facing head faces; helmet (Maren) and beanie (Theo) built procedurally and skinned to `Head`;
everything joined into one skinned mesh `Body` (1 draw call). Height is set by the `Armature` node
scale and the facing by a 180 deg Y rotation on the same node (source faces +Z in glTF); clips stay valid.

**Clips (embedded in every character glb, identical names):** idle (UAL1 Idle_Loop), walk (Walk_Loop),
run (Jog_Fwd_Loop), carry_walk (UAL2 Walk_Carry_Loop), work (procedural: two-handed tool held at waist,
push/pull + buzz, built on Idle_Loop), interact (Interact), wave / cheer / sad (procedural pose-space
layers over Idle_Loop), plus extras pickup (PickUp_Table), talk (Idle_Talking_Loop),
phone (UAL2 Idle_TalkingPhone_Loop, usable for the radio), kneel_work (Fixing_Kneeling),
chop (UAL2 TreeChopping_Loop). In-place (non root-motion) versions. Loop flags are set in the
.import files (everything loops except interact and pickup).

**Problems.** glTF importer leaves objects in quaternion rotation mode, so the first facing fix was
silently ignored (characters faced away) -> set rotation_mode first. Decimated triangles made jagged
"flame" band edges -> bisect planes before painting (~+400 tris, reserved in the budget).
The bodies are the athletic Superhero base; with no clothing meshes in the free tier, garments are
paint-only (skin-tight read). Good enough at gameplay distance; a clothed base would be an upgrade.

**Numbers.** crew_player 4714, crew_theo 4571, crew_maren 4573, crew_priya 4727, resident_rosa 2914, resident_tomas 2898, resident_arthur 2902. Batch B total 27299 tris, 23 bones each, all within budget.
Sheets: `docs/asset_renders/B.png` (idle pose), `docs/asset_renders/B_clips.png` (all clips, crew_player).

## 2026-10-28 — Batch C (street props) delivered

All procedural on the palette (same generator approach as Batch A). `lamp_post` and `road_barrier`
carry a separate `Light` node on `palette_emissive`. `fence_section` and `road_barrier` are 2.0 m along X
(tile them at 2 m). `resident_car` 4.05 x 1.96 x 1.5 m, front -Z, single `Body` node.

**Numbers.** lamp_post 568, bench 660, bin 348, flower_tub 364, fence_section 750, utility_pole 240, mailbox 464, road_barrier 708, station_board 792, resident_car 1440, radio_handset 400. Batch C total 6734 tris, all within budget.
Sheet: `docs/asset_renders/C.png`.

