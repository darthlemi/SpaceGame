extends RefCounted

const RefitCatalog = preload("res://scripts/campaign/refit_catalog.gd")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	for catalog_name in ["HOME_CATALOG", "DOMINION_CATALOG", "FREEHOLD_CATALOG"]:
		var catalog: Array = RefitCatalog.get_catalog(catalog_name)
		if catalog.is_empty():
			failures.append("%s: expected a non-empty catalog" % catalog_name)
		var seen := {}
		for path in catalog:
			if seen.has(path):
				failures.append("%s: duplicate entry %s" % [catalog_name, path])
			seen[path] = true
			if not ResourceLoader.exists(path):
				failures.append("%s: path does not exist: %s" % [catalog_name, path])

	if RefitCatalog.for_faction(CampaignFleet.Faction.DOMINION) != RefitCatalog.DOMINION_CATALOG:
		failures.append("for_faction: expected DOMINION to return DOMINION_CATALOG")
	if RefitCatalog.for_faction(CampaignFleet.Faction.FREEHOLD) != RefitCatalog.FREEHOLD_CATALOG:
		failures.append("for_faction: expected FREEHOLD to return FREEHOLD_CATALOG")
	if RefitCatalog.for_faction(CampaignFleet.Faction.PLAYER) != RefitCatalog.HOME_CATALOG:
		failures.append("for_faction: expected any non-power faction to fall back to HOME_CATALOG")

	return failures
