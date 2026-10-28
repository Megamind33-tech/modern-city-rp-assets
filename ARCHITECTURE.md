# ARCHITECTURE
```
game/
  core/       pure simulation (no scene dependency) — unit-tested
    game_model.gd        GameState: day, flags, equipment, projects, effects, story queue
    incident_director.gd IncidentDirector: data → seeded instance; offered→en_route→on_scene→resolved
    world_state.gd       WorldState: "object.property" → value diffs (roof, road, log piles)
    economy.gd           Economy: ledgered earn/spend, payout formula
    crew_roster.gd       CrewAI stats: skills, fatigue, morale, trust, xp
    community.gd         CharacterRelationships: affinity + memories
    story_director.gd    StoryDirector: trigger + conditions → authored fragments
    save_system.gd       SaveSystem: versioned, checksummed, atomic, backup, migrations
    game.gd (autoload)   owns model + save slot; saves on app pause
    audio_manager.gd     AudioManager (autoload): synthesised placeholders
  gameplay/   scene objects (views + interaction)
    player.gd, truck.gd (VehicleController), crew_agent.gd (crew FSM), camera_rig.gd
    interactable.gd (InteractionSystem), fallen_tree_site.gd (HazardSimulation view)
    town_builder.gd (WorldState → visuals), asset_lib.gd (art by id), autoplay.gd (E2E bot)
  ui/         hud.gd (UIManager), touch_stick.gd, hold_button.gd
  data/       incidents, locations, characters, projects, story_events (JSON)
  scenes/     main.tscn/main.gd — flow orchestration
  tests/      run_tests.gd + test_*.gd
```
**Rule flow:** UI/touch → Player/Interactable → `GameModel.progress_task()` → validates via IncidentDirector → effects (WorldState/Economy/Crew/Community) → story triggers → signals → views refresh.
**Stable ids:** crew/resident/location/house ids in data; incident uids `INC-0001`; world keys `<id>.<property>`.
**Effects** are data: `world`, `overnight`, `flag`, `relationship`, `memory`, `crew`, `equipment` with `{location}/{house}/{resident}` placeholders.
**Cross-game (future):** an `IncidentEnvelope` {incident_id, source_game, location_ref, category, severity, casualties, hazards, required_services, status, responders, deadline, outcome, consequence_permissions} will map onto `IncidentDirector.generate()` inputs via a server-authoritative service; local play never depends on it.
**Performance hooks:** crew decisions on 0.25 s timer, interaction scan 0.1 s, quality presets (low/med/high: shadows, 3D scale, FPS cap, rain density).
