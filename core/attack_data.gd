class_name AttackData
extends RefCounted

var name: String = ""
var cost: Array[String] = []
var damage: int = 0


static func from_dict(raw: Dictionary) -> AttackData:
	var attack := AttackData.new()
	attack.name = str(raw.get("name", ""))
	attack.cost.assign(raw.get("cost", []) as Array)
	attack.damage = int(raw.get("damage", 0))
	return attack
