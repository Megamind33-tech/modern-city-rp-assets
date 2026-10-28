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

