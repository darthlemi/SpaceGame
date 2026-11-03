class_name RefitCatalog
extends RefCounted

const HOME_CATALOG: Array[String] = [
	"res://resources/weapons/kinetic_cannon.tres",
	"res://resources/weapons/mass_driver.tres",
	"res://resources/weapons/seeker_missile.tres",
	"res://resources/weapons/pulse_laser.tres",
	"res://resources/weapons/pd_flak_turret.tres",
	"res://resources/shields/shield_standard.tres",
	"res://resources/shields/shield_light.tres",
	"res://resources/engines/engine_standard.tres",
]

const DOMINION_CATALOG: Array[String] = [
	"res://resources/weapons/kinetic_cannon.tres",
	"res://resources/weapons/mass_driver.tres",
	"res://resources/weapons/flak_cannon.tres",
	"res://resources/weapons/railgun.tres",
	"res://resources/weapons/pulse_laser.tres",
	"res://resources/weapons/heavy_beam.tres",
	"res://resources/weapons/disruptor_beam.tres",
	"res://resources/weapons/lance_graser.tres",
	"res://resources/shields/shield_dominion_aegis.tres",
	"res://resources/shields/shield_dominion_bulwark.tres",
	"res://resources/engines/engine_dominion_heavy.tres",
	"res://resources/engines/engine_dominion_titan.tres",
]

const FREEHOLD_CATALOG: Array[String] = [
	"res://resources/weapons/seeker_missile.tres",
	"res://resources/weapons/swarm_missile.tres",
	"res://resources/weapons/torpedo.tres",
	"res://resources/weapons/emp_missile.tres",
	"res://resources/weapons/pd_flak_turret.tres",
	"res://resources/weapons/pd_laser_turret.tres",
	"res://resources/shields/shield_freehold_patch.tres",
	"res://resources/shields/shield_freehold_capacitor.tres",
	"res://resources/engines/engine_freehold_scout.tres",
	"res://resources/engines/engine_freehold_racer.tres",
]

static func for_faction(faction: CampaignFleet.Faction) -> Array[String]:
	match faction:
		CampaignFleet.Faction.DOMINION:
			return DOMINION_CATALOG
		CampaignFleet.Faction.FREEHOLD:
			return FREEHOLD_CATALOG
		_:
			return HOME_CATALOG
