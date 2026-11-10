class_name StarfieldAssignment
extends RefCounted

const CATEGORIES := ["sparse", "light", "medium", "dense", "clustered"]
const SEED_COUNT := 5

# Narrowed pools so combat and the system view don't read as too busy. Callers can still
# pass a custom pool (or CATEGORIES) if a future background wants the full spread.
const COMBAT_CATEGORIES := ["sparse"]
const SYSTEM_CATEGORIES := ["sparse", "medium"]

static func pick(id: String, categories: Array = CATEGORIES, override: Dictionary = {}) -> Dictionary:
	if override.has("category") and override.has("seed"):
		return {"category": override["category"], "seed": override["seed"]}
	var category: String = categories[abs(hash(id)) % categories.size()]
	var seed_index: int = abs(hash(id + "_seed")) % SEED_COUNT + 1
	return {"category": category, "seed": seed_index}

static func base_texture_path(id: String, categories: Array = CATEGORIES, override: Dictionary = {}) -> String:
	var choice := pick(id, categories, override)
	return "res://assets/sprites/backgrounds/starfield/%s/%s_%02d.png" % [choice.category, choice.category, choice.seed]
