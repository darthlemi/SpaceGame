extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []

	var move := Order.move_to(Vector2(10, 20))
	if move.type != Order.Type.MOVE_TO:
		failures.append("move_to: expected type MOVE_TO, got %s" % move.type)
	if move.target_position != Vector2(10, 20):
		failures.append("move_to: expected position (10,20), got %s" % move.target_position)

	var attack := Order.attack_target(null)
	if attack.type != Order.Type.ATTACK_TARGET:
		failures.append("attack_target: expected type ATTACK_TARGET, got %s" % attack.type)

	var hold := Order.hold()
	if hold.type != Order.Type.HOLD:
		failures.append("hold: expected type HOLD, got %s" % hold.type)

	var retreat := Order.retreat(Vector2(5, 5))
	if retreat.type != Order.Type.RETREAT:
		failures.append("retreat: expected type RETREAT, got %s" % retreat.type)
	if retreat.target_position != Vector2(5, 5):
		failures.append("retreat: expected position (5,5), got %s" % retreat.target_position)

	var ally := Ship.new()
	var protect := Order.protect(ally)
	if protect.type != Order.Type.PROTECT or protect.target_ship != ally:
		failures.append("Order.protect: expected type PROTECT and target_ship set, got %s / %s" % [protect.type, protect.target_ship])
	ally.free()

	return failures
