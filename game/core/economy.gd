class_name Economy
extends RefCounted
## Station funding. Money only changes through earn()/spend() so every change is ledgered.

signal money_changed(money: int, delta: int, reason: String)

const LEDGER_LIMIT := 40

var money: int = 0
var ledger: Array = []


func can_afford(cost: int) -> bool:
	return cost >= 0 and money >= cost


func spend(cost: int, reason: String, day: int = 0) -> bool:
	if not can_afford(cost):
		return false
	_apply(-cost, reason, day)
	return true


func earn(amount: int, reason: String, day: int = 0) -> void:
	if amount <= 0:
		return
	_apply(amount, reason, day)


func _apply(delta: int, reason: String, day: int) -> void:
	money += delta
	ledger.append({"day": day, "delta": delta, "reason": reason})
	if ledger.size() > LEDGER_LIMIT:
		ledger = ledger.slice(ledger.size() - LEDGER_LIMIT)
	money_changed.emit(money, delta, reason)


## Council callout funding for a resolved incident. Pure function so it can be tested.
static func mission_payout(def: Dictionary, inst: Dictionary) -> Dictionary:
	var lines: Array = []
	var severity: int = int(inst.get("severity", 1))
	var base := int(def.get("base_reward", 0))
	var flags: Dictionary = inst.get("flags", {})
	if inst.get("outcome", "") == "success":
		var callout := int(round(base * (1.0 + 0.25 * (severity - 1))))
		lines.append({"label": "Council callout funding", "amount": callout})
		var limit := float(inst.get("time_limit", 300))
		if float(inst.get("elapsed", 0.0)) <= limit * 0.6:
			lines.append({"label": "Fast reopening bonus", "amount": 60})
		if flags.get("secured", false) and not flags.get("unsafe_cut", false):
			lines.append({"label": "Safe scene commendation", "amount": 40})
	else:
		lines.append({"label": "Attendance funding", "amount": int(base * 0.3)})
	lines.append({"label": "Fuel", "amount": -int(def.get("fuel_cost", 0))})
	var total := 0
	for l in lines:
		total += int(l["amount"])
	return {"lines": lines, "total": total}
