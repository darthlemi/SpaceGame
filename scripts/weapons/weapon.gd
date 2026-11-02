class_name Weapon
extends Resource

enum MountType { FIXED, TURRET }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC }

@export var weapon_name: String = "Kinetic Cannon"
@export var damage: float = 10.0
@export var fire_rate: float = 1.0
@export var weapon_range: float = 300.0
@export var projectile_scene: PackedScene

@export var shield_mult: float = 1.0
@export var hull_mult: float = 1.0
@export var pierce_pct: float = 0.0
@export var component_damage: float = 0.0
@export var mount_type: MountType = MountType.TURRET
@export var fire_arc_degrees: float = 360.0
@export var rarity: Rarity = Rarity.COMMON
@export var submissile_count: int = 1
@export var projectile_speed: float = 0.0
