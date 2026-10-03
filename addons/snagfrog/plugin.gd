@tool
extends EditorPlugin

const AUTOLOAD_NAME := "SnagFrog"
const AUTOLOAD_PATH := "res://addons/snagfrog/snagfrog.gd"

const SETTINGS := [
	["snagfrog/app_slug", "", TYPE_STRING],
	["snagfrog/public_key", "", TYPE_STRING],
	["snagfrog/base_url", "https://snagfrog.com", TYPE_STRING],
	["snagfrog/hotkey", "F9", TYPE_STRING],
	["snagfrog/include_log", true, TYPE_BOOL],
	["snagfrog/include_screenshot", true, TYPE_BOOL],
	["snagfrog/detect_crashes", true, TYPE_BOOL],
]


func _enter_tree() -> void:
	var added := false
	for s in SETTINGS:
		if not ProjectSettings.has_setting(s[0]):
			ProjectSettings.set_setting(s[0], s[1])
			added = true
		ProjectSettings.set_initial_value(s[0], s[1])
		ProjectSettings.add_property_info({"name": s[0], "type": s[2]})
	if added:
		ProjectSettings.save()


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
