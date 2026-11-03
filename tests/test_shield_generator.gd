extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	var shield: ShieldGenerator = load("res://resources/shields/shield_dominion_bulwark.tres")
	if shield == null:
		failures.append("shield_dominion_bulwark.tres: failed to load")
		return failures
	if not is_equal_approx(shield.max_shield, 50.0):
		failures.append("shield_dominion_bulwark: expected max_shield 50.0, got %s" % shield.max_shield)
	if shield.rarity != PartRarity.Tier.RARE:
		failures.append("shield_dominion_bulwark: expected rarity RARE, got %s" % shield.rarity)

	var paths := [
		"res://resources/shields/shield_standard.tres",
		"res://resources/shields/shield_light.tres",
		"res://resources/shields/shield_dominion_aegis.tres",
		"res://resources/shields/shield_dominion_bulwark.tres",
		"res://resources/shields/shield_freehold_patch.tres",
		"res://resources/shields/shield_freehold_capacitor.tres",
	]
	for path in paths:
		if not ResourceLoader.exists(path):
			failures.append("ShieldGenerator pool: missing resource %s" % path)
	return failures
