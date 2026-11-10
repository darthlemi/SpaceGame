extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	var art := EditorFields.scan_png_basenames(EditorFields.ART_DIR)
	if art.is_empty() or not art.has("ring_2"):
		failures.append("scan_png_basenames: expected the stations art list to include ring_2, got %s" % [art])
	for i in range(1, art.size()):
		if art[i - 1] > art[i]:
			failures.append("scan_png_basenames: expected a sorted result, got %s" % [art])
			break
	var planets := EditorFields.scan_png_basenames("res://assets/sprites/backgrounds/planets")
	if not planets.has("planet_earthlike"):
		failures.append("scan_png_basenames: expected planet_earthlike in the planets folder, got %s" % [planets])
	var folders := EditorFields.scan_subfolders("res://assets/sprites/backgrounds")
	if not folders.has("planets") or not folders.has("asteroids"):
		failures.append("scan_subfolders: expected planets and asteroids under backgrounds, got %s" % [folders])
	return failures
