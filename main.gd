extends Node
## Example: press F9 or call SnagFrog.report(). With --headless this runs a smoke test.


func _ready() -> void:
	SnagFrog.set_context("level", "demo")
	if DisplayServer.get_name() != "headless":
		return
	var d: Dictionary = SnagFrog._diagnostics({"score": 12})
	print("DIAG ", d)
	print("FALLBACK ", SnagFrog._fallback_url("https://snagfrog.com", "test", d))
	SnagFrog.report_failed.connect(func(e): print("FAILED ", e))
	SnagFrog.report_opened.connect(func(u): print("OPENED ", u); get_tree().quit())
	SnagFrog.report()
