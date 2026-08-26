extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []

	var s := AIController.next_state(AIController.State.APPROACH, 1.0, 0.25, false)
	if s != AIController.State.APPROACH:
		failures.append("expected to stay APPROACH when out of range, got %s" % s)

	s = AIController.next_state(AIController.State.APPROACH, 1.0, 0.25, true)
	if s != AIController.State.ENGAGE:
		failures.append("expected APPROACH->ENGAGE when in range, got %s" % s)

	s = AIController.next_state(AIController.State.ENGAGE, 0.2, 0.25, true)
	if s != AIController.State.RETREAT:
		failures.append("expected ENGAGE->RETREAT when hp low, got %s" % s)

	s = AIController.next_state(AIController.State.RETREAT, 0.9, 0.25, false)
	if s != AIController.State.APPROACH:
		failures.append("expected RETREAT->APPROACH when healed, got %s" % s)

	s = AIController.next_state(AIController.State.RETREAT, 0.3, 0.25, false)
	if s != AIController.State.RETREAT:
		failures.append("expected to stay RETREAT until healed past threshold, got %s" % s)

	return failures
