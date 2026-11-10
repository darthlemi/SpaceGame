class_name SceneryFolder
extends RefCounted

# Folders under assets/sprites/backgrounds/ that hold placeable scenery (planets, asteroids,
# and future additions); "starfield" holds the background tile categories instead and is
# excluded. The document's scenery "type" is the singular form of the folder name.

const EXCLUDED_FOLDERS := ["starfield"]
const DIR := "res://assets/sprites/backgrounds"

static func type_to_folder(type: String) -> String:
	return "%ss" % type

static func folder_to_type(folder: String) -> String:
	return folder.trim_suffix("s")

static func is_scenery_folder(folder: String) -> bool:
	return not EXCLUDED_FOLDERS.has(folder)
