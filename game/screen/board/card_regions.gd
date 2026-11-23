extends RefCounted

# This fucking sucks actually
const LAYOUTS := {
  "jevil": {
	"content": 0.54498,
	"regions": [
	  {
		"kind": "attack",
		"index": 0,
		"rect": [
		  0.045,
		  0.58038,
		  0.91,
		  0.11675
		]
	  },
	  {
		"kind": "attack",
		"index": 1,
		"rect": [
		  0.045,
		  0.69713,
		  0.91,
		  0.18756
		]
	  }
	]
  },
  "electro_dasher": {
	"content": 0.51714,
	"regions": [
	  {
		"kind": "ability",
		"index": 0,
		"rect": [
		  0.045,
		  0.54095,
		  0.91,
		  0.21333
		]
	  },
	  {
		"kind": "attack",
		"index": 0,
		"rect": [
		  0.045,
		  0.75429,
		  0.91,
		  0.13048
		]
	  }
	]
  },
  "water_cooler": {
	"content": 0.68762,
	"regions": [
	  {
		"kind": "attack",
		"index": 0,
		"rect": [
		  0.045,
		  0.72095,
		  0.91,
		  0.16381
		]
	  }
	]
  },
  "miss_mizzle": {
	"content": 0.68933,
	"regions": [
	  {
		"kind": "ability",
		"index": 0,
		"rect": [
		  0.045,
		  0.704,
		  0.91,
		  0.26067
		]
	  }
	]
  },
  "guei": {
	"content": 0.66,
	"regions": [
	  {
		"kind": "attack",
		"index": 0,
		"rect": [
		  0.045,
		  0.69714,
		  0.91,
		  0.18762
		]
	  }
	]
  },
  "cuptain": {
	"content": 0.50857,
	"regions": [
	  {
		"kind": "ability",
		"index": 0,
		"rect": [
		  0.045,
		  0.52857,
		  0.91,
		  0.21905
		]
	  },
	  {
		"kind": "attack",
		"index": 0,
		"rect": [
		  0.045,
		  0.74762,
		  0.91,
		  0.13714
		]
	  }
	]
  },
  "shuttah": {
	"content": 0.58476,
	"regions": [
	  {
		"kind": "attack",
		"index": 0,
		"rect": [
		  0.045,
		  0.6181,
		  0.91,
		  0.26667
		]
	  }
	]
  },
  "tenna": {
	"content": 0.56476,
	"regions": [
	  {
		"kind": "ability",
		"index": 0,
		"rect": [
		  0.045,
		  0.58667,
		  0.91,
		  0.1619
		]
	  },
	  {
		"kind": "attack",
		"index": 0,
		"rect": [
		  0.045,
		  0.74857,
		  0.91,
		  0.13619
		]
	  }
	]
  },
  "titan": {
	"content": 0.56714,
	"regions": [
	  {
		"kind": "ability",
		"index": 0,
		"rect": [
		  0.045,
		  0.59095,
		  0.91,
		  0.14286
		]
	  },
	  {
		"kind": "attack",
		"index": 0,
		"rect": [
		  0.045,
		  0.73381,
		  0.91,
		  0.15095
		]
	  }
	]
  },
  "titan_spawn": {
	"content": 0.51429,
	"regions": [
	  {
		"kind": "ability",
		"index": 0,
		"rect": [
		  0.045,
		  0.5381,
		  0.91,
		  0.17714
		]
	  },
	  {
		"kind": "attack",
		"index": 0,
		"rect": [
		  0.045,
		  0.71524,
		  0.91,
		  0.16952
		]
	  }
	]
  },
  "old_man": {
	"content": 0.50095,
	"regions": [
	  {
		"kind": "ability",
		"index": 0,
		"rect": [
		  0.045,
		  0.52095,
		  0.91,
		  0.22476
		]
	  },
	  {
		"kind": "attack",
		"index": 0,
		"rect": [
		  0.045,
		  0.74571,
		  0.91,
		  0.13905
		]
	  }
	]
  },
  "hammer_of_justice": {
	"content": 0.75133,
	"regions": [
	  {
		"kind": "attack",
		"index": 0,
		"rect": [
		  0.17,
		  0.76867,
		  0.66,
		  0.196
		]
	  }
	]
  },
  "dummy": {
	"content": 0.69143,
	"regions": [
	  {
		"kind": "attack",
		"index": 0,
		"rect": [
		  0.045,
		  0.72476,
		  0.91,
		  0.16
		]
	  }
	]
  },
  "balthizard": {
	"content": 0.52344,
	"regions": [
	  {
		"kind": "ability",
		"index": 0,
		"rect": [
		  0.045,
		  0.54545,
		  0.91,
		  0.25837
		]
	  },
	  {
		"kind": "attack",
		"index": 0,
		"rect": [
		  0.045,
		  0.80383,
		  0.91,
		  0.08086
		]
	  }
	]
  },
  "koody": {
	"content": 0.54286,
	"regions": [
	  {
		"kind": "ability",
		"index": 0,
		"rect": [
		  0.045,
		  0.56667,
		  0.91,
		  0.19619
		]
	  },
	  {
		"kind": "attack",
		"index": 0,
		"rect": [
		  0.045,
		  0.76286,
		  0.91,
		  0.1219
		]
	  }
	]
  },
  "addison": {
	"content": 0.50905,
	"regions": [
	  {
		"kind": "ability",
		"index": 0,
		"rect": [
		  0.045,
		  0.52905,
		  0.91,
		  0.22095
		]
	  },
	  {
		"kind": "attack",
		"index": 0,
		"rect": [
		  0.045,
		  0.75,
		  0.91,
		  0.13476
		]
	  }
	]
  }
}

static func content_start(id: String) -> float:
	return float(LAYOUTS.get(id, {}).get("content", 0.52))

static func regions(id: String) -> Array:
	return LAYOUTS.get(id, {}).get("regions", [])
