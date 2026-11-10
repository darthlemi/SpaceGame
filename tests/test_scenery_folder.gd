extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	if SceneryFolder.type_to_folder("planet") != "planets":
		failures.append("scenery folder: expected type_to_folder('planet') == 'planets'")
	if SceneryFolder.folder_to_type("asteroids") != "asteroid":
		failures.append("scenery folder: expected folder_to_type('asteroids') == 'asteroid'")
	if SceneryFolder.is_scenery_folder("starfield"):
		failures.append("scenery folder: expected is_scenery_folder('starfield') == false")
	if not SceneryFolder.is_scenery_folder("planets"):
		failures.append("scenery folder: expected is_scenery_folder('planets') == true")
	return failures
