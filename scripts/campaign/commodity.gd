class_name Commodity
extends RefCounted

enum Type { ORE, FOOD, FUEL, HULL_PARTS, WEAPONS, LUXURY_GOODS }

const BASE_PRICE := {
	Type.ORE: 10.0,
	Type.FOOD: 8.0,
	Type.FUEL: 12.0,
	Type.HULL_PARTS: 40.0,
	Type.WEAPONS: 60.0,
	Type.LUXURY_GOODS: 50.0,
}

const TARGET_STOCK := {
	Type.ORE: 100.0,
	Type.FOOD: 100.0,
	Type.FUEL: 100.0,
	Type.HULL_PARTS: 40.0,
	Type.WEAPONS: 40.0,
	Type.LUXURY_GOODS: 40.0,
}

const NAMES := {
	Type.ORE: "Ore",
	Type.FOOD: "Food",
	Type.FUEL: "Fuel",
	Type.HULL_PARTS: "Hull Parts",
	Type.WEAPONS: "Weapons",
	Type.LUXURY_GOODS: "Luxury Goods",
}
