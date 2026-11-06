extends RefCounted

const CampaignStateScript = preload("res://scripts/campaign/campaign_state.gd")

# A new game opens makers overstocked (cheap) and burners short (dear), so the player has trades.
static func run() -> Array[String]:
	var failures: Array[String] = []
	var state := CampaignStateScript.new()
	state.new_game()
	var makers := 0
	var burners := 0
	for station in state.galaxy.stations:
		var net: Dictionary = station.economy.net_commodities()
		for commodity in net:
			if station.starting_stock.has(commodity):
				continue
			var stock: float = station.economy.stock[commodity]
			var target: float = Commodity.TARGET_STOCK[commodity]
			if net[commodity] > 0.0:
				makers += 1
				if not is_equal_approx(stock, target * CampaignStateScript.STARTING_STOCK_PRODUCED):
					failures.append("%s %s: maker should open at %.1fx target, got %.1f" % [station.id, commodity, CampaignStateScript.STARTING_STOCK_PRODUCED, stock])
			elif net[commodity] < 0.0:
				burners += 1
				if not is_equal_approx(stock, target * CampaignStateScript.STARTING_STOCK_CONSUMED):
					failures.append("%s %s: burner should open at %.2fx target, got %.1f" % [station.id, commodity, CampaignStateScript.STARTING_STOCK_CONSUMED, stock])
	if makers == 0 or burners == 0:
		failures.append("expected both makers and burners, got %d / %d" % [makers, burners])
	var ore_buy := BaseEconomy.new()
	var ore_sell := BaseEconomy.new()
	ore_buy.stock[Commodity.Type.ORE] = Commodity.TARGET_STOCK[Commodity.Type.ORE] * CampaignStateScript.STARTING_STOCK_PRODUCED
	ore_sell.stock[Commodity.Type.ORE] = Commodity.TARGET_STOCK[Commodity.Type.ORE] * CampaignStateScript.STARTING_STOCK_CONSUMED
	if ore_sell.sell_price_for(Commodity.Type.ORE) <= ore_buy.price_for(Commodity.Type.ORE):
		failures.append("expected a maker-to-burner ore haul to profit")
	return failures
