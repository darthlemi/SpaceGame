class_name Order
extends RefCounted

enum Type { MOVE_TO, ATTACK_TARGET, HOLD, RETREAT, HOLD_POSITION, FLEE }

var type: Type
var target_position: Vector2
var target_ship: Node2D

static func move_to(pos: Vector2) -> Order:
	var o := Order.new()
	o.type = Type.MOVE_TO
	o.target_position = pos
	return o

static func attack_target(ship: Node2D) -> Order:
	var o := Order.new()
	o.type = Type.ATTACK_TARGET
	o.target_ship = ship
	return o

static func hold() -> Order:
	var o := Order.new()
	o.type = Type.HOLD
	return o

static func retreat(from_position: Vector2) -> Order:
	var o := Order.new()
	o.type = Type.RETREAT
	o.target_position = from_position
	return o

static func hold_position() -> Order:
	var o := Order.new()
	o.type = Type.HOLD_POSITION
	return o

static func flee() -> Order:
	var o := Order.new()
	o.type = Type.FLEE
	return o
