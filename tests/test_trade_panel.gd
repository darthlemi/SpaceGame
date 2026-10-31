extends RefCounted

const TradePanelScene = preload("res://scenes/campaign/trade_panel.tscn")
const BaseEconomy = preload("res://scripts/campaign/base_economy.gd")
const EconomyRole = preload("res://scripts/campaign/economy_role.gd")
const Commodity = preload("res://scripts/campaign/commodity.gd")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()

	var panel: Control = TradePanelScene.instantiate()
	tree.root.add_child(panel)
	await tree.process_frame

	if panel.visible:
		failures.append("TradePanel: expected hidden by default")

	var economy := BaseEconomy.new()
	economy.slots = [EconomyRole.trade_hub()]
	economy.stock = {Commodity.Type.ORE: 100.0}
	var fleet := CampaignFleet.new()
	fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	panel.open_for(economy, fleet)
	if not panel.visible:
		failures.append("TradePanel: expected visible after open_for")

	var buy_button: Button = panel._rows[Commodity.Type.ORE]["buy_button"]
	var ore_buy_price: float = economy.price_for(Commodity.Type.ORE)
	var credits_before: float = campaign_state.credits
	buy_button.pressed.emit()
	if campaign_state.credits != credits_before - ore_buy_price:
		failures.append("TradePanel: expected pressing Buy to call CampaignState.buy, credits before=%s after=%s" % [credits_before, campaign_state.credits])
	if fleet.cargo.get(Commodity.Type.ORE, 0.0) != 1.0:
		failures.append("TradePanel: expected pressing Buy to add 1 Ore to fleet cargo")

	var sell_button: Button = panel._rows[Commodity.Type.ORE]["sell_button"]
	var credits_before_sell: float = campaign_state.credits
	sell_button.pressed.emit()
	if campaign_state.credits <= credits_before_sell:
		failures.append("TradePanel: expected pressing Sell to call CampaignState.sell and increase credits")
	if fleet.cargo.get(Commodity.Type.ORE, 0.0) != 0.0:
		failures.append("TradePanel: expected pressing Sell to remove the Ore from fleet cargo")

	# Buy disabled on insufficient credits
	campaign_state.credits = 0.0
	panel.refresh()
	if not buy_button.disabled:
		failures.append("TradePanel: expected Buy disabled when credits are insufficient")

	# Restore credits, then buy disabled on insufficient stock
	campaign_state.credits = 1000.0
	economy.stock[Commodity.Type.ORE] = 0.0
	panel.refresh()
	if not buy_button.disabled:
		failures.append("TradePanel: expected Buy disabled when stock is insufficient")

	# Restore stock, then buy disabled when cargo is at capacity
	economy.stock[Commodity.Type.ORE] = 100.0
	fleet.cargo = {Commodity.Type.FUEL: fleet.cargo_capacity()}
	panel.refresh()
	if not buy_button.disabled:
		failures.append("TradePanel: expected Buy disabled when cargo is at capacity")

	# Sell disabled when fleet holds none of that commodity
	fleet.cargo = {}
	panel.refresh()
	if not sell_button.disabled:
		failures.append("TradePanel: expected Sell disabled when fleet holds none of the commodity")

	# Buttons re-enable when conditions are met again
	fleet.cargo = {Commodity.Type.ORE: 1.0}
	panel.refresh()
	if buy_button.disabled:
		failures.append("TradePanel: expected Buy re-enabled when credits/stock/capacity are fine")
	if sell_button.disabled:
		failures.append("TradePanel: expected Sell re-enabled when fleet holds the commodity")

	campaign_state.credits = 1000.0
	panel.close()
	if panel.visible:
		failures.append("TradePanel: expected hidden after close")

	campaign_state.reset()
	panel.queue_free()
	return failures
