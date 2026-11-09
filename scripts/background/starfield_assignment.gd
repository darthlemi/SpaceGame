class_name StarfieldAssignment
extends RefCounted

const CATEGORIES := ["sparse", "light", "medium", "dense", "clustered"]
const SEED_COUNT := 5

static func pick(id: String) -> Dictionary:
	var category: String = CATEGORIES[abs(hash(id)) % CATEGORIES.size()]
	var seed_index: int = abs(hash(id + "_seed")) % SEED_COUNT + 1
	return {"category": category, "seed": seed_index}

static func base_texture_path(id: String) -> String:
	var choice := pick(id)
	return "res://assets/sprites/backgrounds/starfield/%s/%s_%02d.png" % [choice.category, choice.category, choice.seed]
