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

const ICON_TEXTURES := {
	Type.ORE: "res://assets/sprites/commodities/ore.png",
	Type.FOOD: "res://assets/sprites/commodities/food.png",
	Type.FUEL: "res://assets/sprites/commodities/fuel.png",
	Type.HULL_PARTS: "res://assets/sprites/commodities/hull_parts.png",
	Type.WEAPONS: "res://assets/sprites/commodities/weapons.png",
	Type.LUXURY_GOODS: "res://assets/sprites/commodities/luxury_goods.png",
}
