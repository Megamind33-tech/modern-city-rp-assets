extends Node
## Autoload "Game": owns the active GameModel and its save slot.
## Scenes talk to the model through this node; tests use GameModel directly.

signal model_replaced(model: GameModel)
signal saved(ok: bool)

const SAVE_PATH := "user://slot0.save"
const SETTINGS_PATH := "user://settings.cfg"

var model: GameModel
var save_path := SAVE_PATH
var quality := "medium"
var volume := 0.8


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		quality = cfg.get_value("video", "quality", quality)
		volume = cfg.get_value("audio", "volume", volume)
	Audio.set_master_volume(volume)
	var user_args := OS.get_cmdline_user_args()
	for a in user_args:
		if a.begins_with("--save-path="):
			save_path = a.get_slice("=", 1)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "quality", quality)
	cfg.set_value("audio", "volume", volume)
	cfg.save(SETTINGS_PATH)


func has_save() -> bool:
	return SaveSystem.exists(save_path)


func new_game(seed_value: int = -1) -> void:
	if seed_value < 0:
		seed_value = int(Time.get_unix_time_from_system()) % 1000000
	model = GameModel.new()
	model.new_game(seed_value)
	model_replaced.emit(model)
	save_game()


func continue_game() -> bool:
	var r := SaveSystem.load_game(save_path)
	if r["model"] == null:
		push_warning("Game: %s" % r["error"])
		return false
	if r["source"] == "backup":
		push_warning("Game: restored from backup save")
	model = r["model"]
	model_replaced.emit(model)
	return true


func save_game() -> bool:
	if model == null:
		return false
	var err := SaveSystem.save(model, save_path)
	saved.emit(err == OK)
	if err != OK:
		push_error("Game: save failed (%d)" % err)
	return err == OK


func _notification(what: int) -> void:
	# Android may kill a paused app without warning: save whenever we lose the foreground.
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		save_game()
