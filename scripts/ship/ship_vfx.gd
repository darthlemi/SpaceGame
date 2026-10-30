class_name ShipVfx
extends Node2D

static func should_emit_smoke(hp_ratio: float, threshold: float) -> bool:
	return hp_ratio <= threshold
