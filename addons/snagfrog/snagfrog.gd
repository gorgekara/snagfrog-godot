extends Node
## SnagFrog: in-game bug reports.
##
## Call SnagFrog.report() (or press the hotkey) to stage a screenshot, the tail of the
## log file and diagnostics on SnagFrog, then open the report page in the browser. The
## player reviews and confirms there; nothing is submitted until they do.
##
## If the previous session did not exit cleanly, reports also carry that session's log and
## are marked as a crash; see crashed_last_session.

signal report_opened(url: String)
signal report_failed(error: String)
## Emitted once after startup when the previous session did not exit cleanly (a crash, a
## freeze the player force-quit, or a power loss). Connect to offer the player a report.
signal crashed_last_session

const MAX_LOG_BYTES := 256 * 1024
const MAX_SCREENSHOT_BYTES := 3 * 1024 * 1024
const MAX_EDGE := 1920
const TIMEOUT_SECONDS := 15.0
const MARKER_PATH := "user://snagfrog_session.marker"

var _context: Dictionary = {}
var _busy := false
var _hotkey: int = KEY_NONE
var _crashed_last_session := false
var _previous_log := ""
var _previous_log_time := 0


func _ready() -> void:
	# Reports and the hotkey must work from a pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var hotkey := str(_setting("hotkey", "F9")).strip_edges()
	if not hotkey.is_empty():
		_hotkey = OS.find_keycode_from_string(hotkey)
	_start_session_marker()


## True when the previous session did not exit cleanly. Reports sent in this session then
## carry the previous session's log and are marked as a crash.
func has_crashed_last_session() -> bool:
	return _crashed_last_session


# A marker file is written at startup and removed on a clean exit. Finding it at the next
# startup means the last session ended unexpectedly.
func _start_session_marker() -> void:
	if not _detects_crashes():
		return
	if FileAccess.file_exists(MARKER_PATH):
		# A second copy of the game started while the first is running also lands here; Godot
		# cannot tell whether another process is alive, so that rare case reads as a crash.
		_crashed_last_session = true
		_previous_log = _find_previous_log()
		if not _previous_log.is_empty():
			_previous_log_time = FileAccess.get_modified_time(_previous_log)
		crashed_last_session.emit.call_deferred()
	var f := FileAccess.open(MARKER_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(str(OS.get_process_id()))
		f.close()


func _detects_crashes() -> bool:
	if Engine.is_editor_hint() or OS.has_feature("web") or not bool(_setting("detect_crashes", true)):
		return false
	# Stopping a game from the editor kills it, which would look like a crash on the next run.
	return not OS.has_feature("editor") or OS.get_environment("SNAGFROG_DETECT_CRASHES") == "1"


func _end_session_marker() -> void:
	if not FileAccess.file_exists(MARKER_PATH):
		return
	if int(FileAccess.get_file_as_string(MARKER_PATH)) == OS.get_process_id():
		DirAccess.remove_absolute(MARKER_PATH)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		_end_session_marker()


# Godot renames the last session's log to <name><timestamp>.log at startup, next to the
# current one. The newest of those is the previous session's log.
func _find_previous_log() -> String:
	if not bool(ProjectSettings.get_setting("debug/file_logging/enable_file_logs", false)):
		return ""
	var path := str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))
	var dir_path := path.get_base_dir()
	var current := path.get_file()
	var stem := current.get_basename()
	var ext := current.get_extension()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
	var best := ""
	var best_time := -1
	for file_name in dir.get_files():
		if file_name == current or not file_name.begins_with(stem) or file_name.get_extension() != ext:
			continue
		var candidate := dir_path.path_join(file_name)
		var modified := FileAccess.get_modified_time(candidate)
		if modified > best_time:
			best = candidate
			best_time = modified
	return best


## Adds a value that is sent with every report, e.g. set_context("level", "forest_3").
func set_context(key: String, value: Variant) -> void:
	_context[key] = value


func _unhandled_input(event: InputEvent) -> void:
	if _hotkey == KEY_NONE or Engine.is_editor_hint():
		return
	# Single key, no modifiers.
	if event is InputEventKey and event.pressed and not event.echo \
			and not (event.shift_pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed):
		if event.keycode == _hotkey or event.physical_keycode == _hotkey:
			get_viewport().set_input_as_handled()
			report()


## Stages the report on SnagFrog and opens the report page. `extra` adds diagnostics.
## If staging fails, report_failed is emitted and then the prefilled page is opened (report_opened).
func report(extra: Dictionary = {}) -> void:
	if _busy:
		return
	_busy = true
	var base := _base_url()
	var slug := str(_setting("app_slug", "")).strip_edges()
	if slug.is_empty():
		_busy = false
		report_failed.emit("snagfrog/app_slug is not set")
		return

	var diagnostics := _diagnostics(extra)
	# On web the browser may block a tab opened after a network request, and the sessions
	# API is not CORS-enabled, so open the prefilled report page right away.
	if OS.has_feature("web"):
		_busy = false
		_open(_fallback_url(base, slug, diagnostics))
		return

	var files: Array = []
	if _setting("include_screenshot", true):
		var shot := _screenshot()
		if not shot.is_empty():
			files.append(_file("screenshot.png", "image/png", shot))
	if _setting("include_log", true):
		var log_bytes := _log_tail()
		if not log_bytes.is_empty():
			files.append(_file("godot.log", "text/plain", log_bytes))
		if _crashed_last_session and not _previous_log.is_empty():
			var previous := _tail(_previous_log)
			if not previous.is_empty():
				files.append(_file("godot-previous-session.log", "text/plain", previous))

	var key := str(_setting("public_key", "")).strip_edges()
	var error := "no public key set"
	if not key.is_empty():
		var result: Dictionary = await _create_session(base, key, diagnostics, files)
		if result.has("url"):
			_busy = false
			_open(str(result["url"]))
			return
		error = str(result.get("error", "unknown error"))

	# Fall back to a prefilled report page so the player can still report.
	_busy = false
	report_failed.emit(error)
	_open(_fallback_url(base, slug, diagnostics))


func _open(url: String) -> void:
	OS.shell_open(url)
	report_opened.emit(url)


func _create_session(base: String, key: String, diagnostics: Dictionary, files: Array) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	add_child(http)
	var body := JSON.stringify({"diagnostics": diagnostics, "files": files})
	var headers := PackedStringArray([
		"Authorization: Bearer " + key,
		"Content-Type: application/json",
	])
	var err := http.request(base + "/api/v1/sessions", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return {"error": "request failed to start (%d)" % err}
	var res: Array = await http.request_completed
	http.queue_free()
	var status: int = res[1]
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "network error (%d)" % res[0]}
	if status != 201:
		return {"error": "HTTP %d" % status}
	var parsed: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if parsed is Dictionary and parsed.has("url") and str(parsed["url"]).begins_with("http"):
		return {"url": str(parsed["url"])}
	return {"error": "unexpected response"}


func _file(filename: String, content_type: String, bytes: PackedByteArray) -> Dictionary:
	return {
		"filename": filename,
		"contentType": content_type,
		"data": Marshalls.raw_to_base64(bytes),
	}


func _screenshot() -> PackedByteArray:
	var viewport := get_viewport()
	if viewport == null or DisplayServer.get_name() == "headless":
		return PackedByteArray()
	var tex := viewport.get_texture()
	if tex == null:
		return PackedByteArray()
	var image := tex.get_image()
	if image == null or image.is_empty():
		return PackedByteArray()
	if image.is_compressed():
		image.decompress()
	var edge := maxi(image.get_width(), image.get_height())
	if edge > MAX_EDGE:
		var f := float(MAX_EDGE) / float(edge)
		image.resize(maxi(1, int(image.get_width() * f)), maxi(1, int(image.get_height() * f)), Image.INTERPOLATE_LANCZOS)
	var png := image.save_png_to_buffer()
	# Shrink until it fits; PNGs of busy frames can be large.
	var tries := 0
	while png.size() > MAX_SCREENSHOT_BYTES and tries < 4:
		image.resize(maxi(1, int(image.get_width() * 0.7)), maxi(1, int(image.get_height() * 0.7)), Image.INTERPOLATE_LANCZOS)
		png = image.save_png_to_buffer()
		tries += 1
	if png.size() > MAX_SCREENSHOT_BYTES:
		return PackedByteArray()
	return png


func _log_tail() -> PackedByteArray:
	if not bool(ProjectSettings.get_setting("debug/file_logging/enable_file_logs", false)):
		return PackedByteArray()
	return _tail(str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log")))


func _tail(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var length := f.get_length()
	if length > MAX_LOG_BYTES:
		f.seek(length - MAX_LOG_BYTES)
	var bytes := f.get_buffer(mini(length, MAX_LOG_BYTES))
	f.close()
	return bytes


func _diagnostics(extra: Dictionary) -> Dictionary:
	var d := {}
	var game_name := str(ProjectSettings.get_setting("application/config/name", ""))
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	if not game_name.is_empty():
		d["game"] = game_name
	if not version.is_empty():
		d["app_version"] = version
	d["engine_version"] = str(Engine.get_version_info().get("string", ""))
	d["os_version"] = _os_version()
	var model := OS.get_model_name()
	if model != "GenericDevice" and not model.is_empty():
		d["device_model"] = model
	d["arch"] = Engine.get_architecture_name()
	d["locale"] = OS.get_locale()
	d["renderer"] = str(RenderingServer.get_current_rendering_method())
	if DisplayServer.get_name() != "headless":
		var size := DisplayServer.screen_get_size()
		d["screen_size"] = "%dx%d" % [size.x, size.y]
		d["gpu"] = RenderingServer.get_video_adapter_name()
	if _crashed_last_session:
		d["crash"] = "Previous session ended unexpectedly"
		if _previous_log_time > 0:
			d["crash_time"] = Time.get_datetime_string_from_unix_time(_previous_log_time) + "Z"
	for source in [_context, extra]:
		for k in source:
			var key := _clean_key(str(k))
			if not key.is_empty():
				d[key] = _stringify(source[k])
	return d


func _os_version() -> String:
	var v := OS.get_version()
	return OS.get_name() if v.is_empty() else "%s %s" % [OS.get_name(), v]


func _stringify(value: Variant) -> String:
	if value is String or value is StringName:
		return str(value)
	return var_to_str(value)


# The server accepts keys made of letters, digits, _ . - and space.
func _clean_key(key: String) -> String:
	var out := ""
	for c in key.strip_edges():
		var l := c.to_lower()
		if c == "_" or c == "." or c == "-" or c == " " or (c >= "0" and c <= "9") or (l >= "a" and l <= "z"):
			out += c
		else:
			out += "_"
	return out.substr(0, 64)


func _fallback_url(base: String, slug: String, d: Dictionary) -> String:
	var short := {"app_version": "v", "build": "build", "os_version": "os",
		"device_model": "model", "arch": "arch", "locale": "locale"}
	var parts := PackedStringArray()
	for k in d:
		var value := str(d[k]).substr(0, 200)
		if value.is_empty():
			continue
		var param: String = short.get(k, "d_" + str(k))
		parts.append(param.uri_encode() + "=" + value.uri_encode())
	# Keep the URL a sane length for browsers and shells.
	var query := "&".join(parts)
	while query.length() > 1800 and parts.size() > 1:
		parts.remove_at(parts.size() - 1)
		query = "&".join(parts)
	var url := "%s/r/%s" % [base, slug.uri_encode()]
	return url + ("?" + query if not query.is_empty() else "")


func _base_url() -> String:
	var base := str(_setting("base_url", "https://snagfrog.com")).strip_edges()
	if base.is_empty():
		base = "https://snagfrog.com"
	return base.rstrip("/")


func _setting(setting_name: String, default: Variant) -> Variant:
	return ProjectSettings.get_setting("snagfrog/" + setting_name, default)
