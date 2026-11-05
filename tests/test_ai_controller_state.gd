extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	var corvette := ShipType.Kind.CORVETTE
	var capital := ShipType.Kind.CAPITAL
	var freighter := ShipType.Kind.FREIGHTER

	if not AIController.should_flee(corvette, 60.0, 21.0, true, 100.0):
		failures.append("corvette_flees_after_65pct_of_start: expected flee at 21 of 60")
	if AIController.should_flee(corvette, 60.0, 22.0, true, 100.0):
		failures.append("corvette_flees_after_65pct_of_start: expected no flee at 22 of 60")

	if not AIController.should_flee(capital, 220.0, 33.0, true, 100.0):
		failures.append("capital_flees_after_85pct: expected flee at 33 of 220")
	if AIController.should_flee(capital, 220.0, 34.0, true, 100.0):
		failures.append("capital_flees_after_85pct: expected no flee at 34 of 220")

	if AIController.should_flee(corvette, 20.0, 20.0, true, 100.0):
		failures.append("damaged_arrival_does_not_flee: a ship at its starting hull must not flee")

	if not AIController.should_flee(freighter, 80.0, 80.0, false, 499.0):
		failures.append("unarmed_flees_on_contact: expected flee with an enemy edge at 499")
	if AIController.should_flee(freighter, 80.0, 80.0, false, 501.0):
		failures.append("unarmed_flees_on_contact: expected no flee with an enemy edge at 501")

	if AIController.should_flee(corvette, 0.0, 0.0, true, 100.0):
		failures.append("zero_start_never_flees: start 0 must never flee")

	# An armed custom freighter has no loss-fraction key: it must fall back, not crash.
	if AIController.should_flee(freighter, 100.0, 100.0, true, 100.0):
		failures.append("armed_freighter_falls_back: a full-hull armed freighter must not flee")
	if not AIController.should_flee(freighter, 100.0, 30.0, true, 100.0):
		failures.append("armed_freighter_falls_back: expected the corvette fraction for an armed freighter")

	return failures
