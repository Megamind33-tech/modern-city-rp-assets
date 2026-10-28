class_name SaveSystem
extends RefCounted
## Versioned, checksummed, atomically written save files with a rolling backup.
## File layout: {"format": "emergency-crew-save", "version": N, "checksum": md5(payload), "payload": "<json>"}
## The payload is stored as a string so the checksum covers exactly the bytes written.

const FORMAT := "emergency-crew-save"
const VERSION := 1

## version -> Callable(Dictionary) -> Dictionary, upgrading a payload from that version to the next.
static var MIGRATIONS: Dictionary = {
	0: _migrate_v0_to_v1,
}


static func save(model: GameModel, path: String) -> Error:
	var payload := JSON.stringify(model.to_dict())
	var doc := {"format": FORMAT, "version": VERSION, "checksum": payload.md5_text(), "payload": payload}
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(doc))
	f.close()
	if FileAccess.file_exists(path):
		var bak_err := DirAccess.copy_absolute(path, path + ".bak")
		if bak_err != OK:
			push_warning("SaveSystem: backup failed (%d)" % bak_err)
	return DirAccess.rename_absolute(tmp, path)


## Returns {"model": GameModel or null, "source": "main"|"backup"|"", "error": String}.
static func load_game(path: String) -> Dictionary:
	for candidate in [[path, "main"], [path + ".bak", "backup"]]:
		var r := _read(candidate[0])
		if r.has("data"):
			var model := GameModel.new()
			model.from_dict(r["data"])
			return {"model": model, "source": candidate[1], "error": ""}
		if candidate[1] == "main" and r["error"] != "missing":
			push_warning("SaveSystem: main save unusable (%s), trying backup" % r["error"])
	return {"model": null, "source": "", "error": "no valid save"}


## Type-insensitive canonical form (JSON has one number type) for state comparisons.
static func canonical(v: Variant) -> String:
	return JSON.stringify(_numbers_to_float(v), "", true)


static func _numbers_to_float(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _numbers_to_float(v[k])
		return out
	if v is Array:
		return v.map(_numbers_to_float)
	if v is int:
		return float(v)
	return v


static func exists(path: String) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")


static func delete(path: String) -> void:
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "missing"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"error": "unreadable"}
	var doc: Variant = JSON.parse_string(f.get_as_text())
	if not doc is Dictionary or doc.get("format", "") != FORMAT:
		return {"error": "not a save file"}
	var payload: Variant = doc.get("payload", null)
	if not payload is String or payload.md5_text() != doc.get("checksum", ""):
		return {"error": "checksum mismatch"}
	var data: Variant = JSON.parse_string(payload)
	if not data is Dictionary:
		return {"error": "corrupt payload"}
	var version := int(doc.get("version", -1))
	if version > VERSION:
		return {"error": "save from newer game version %d" % version}
	var migrated := migrate(data, version)
	if migrated.is_empty():
		return {"error": "no migration from version %d" % version}
	return {"data": migrated}


static func migrate(data: Dictionary, from_version: int) -> Dictionary:
	var d := data
	var v := from_version
	while v < VERSION:
		if not MIGRATIONS.has(v):
			return {}
		d = MIGRATIONS[v].call(d)
		v += 1
	return d


## v0 was the pre-release prototype schema: money was called "funds" and there was no equipment table.
static func _migrate_v0_to_v1(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	if out.has("funds"):
		out["money"] = out["funds"]
		out.erase("funds")
	if not out.has("equipment"):
		out["equipment"] = {"chainsaw": 1}
	return out
