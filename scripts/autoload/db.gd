extends Node
## Static game data loaded from res://data/*.json.

const STATS: Array[String] = ["hp", "defense", "dodge", "speed", "move", "crit", "attack", "accuracy", "range", "resolve"]
const STAT_NAMES := {
	"hp": "HP", "defense": "Defense", "dodge": "Dodge", "speed": "Speed", "move": "Movement",
	"crit": "Crit", "attack": "Attack", "accuracy": "Accuracy", "range": "Range", "resolve": "Resolve",
}
const TIERS: Array[String] = ["Mediocre", "Normal", "Skilled", "Genius"]
const TIER_MULT: Array[float] = [0.88, 1.0, 1.1, 1.2]
const TIER_GROWTH: Array[float] = [0.75, 1.0, 1.3, 1.6]
const TIER_WAGE: Array[float] = [0.75, 1.0, 1.4, 1.9]
const POTENTIAL_MULT: Array[float] = [0.0, 0.65, 1.0, 1.45]
const LEVEL_CAP := 20
const SUBCLASS_LEVEL := 10

var classes: Dictionary = {}
var skills: Dictionary = {}
var traits: Dictionary = {}
var races: Dictionary = {}
var statuses: Dictionary = {}
var subclasses: Dictionary = {}
var enemies: Dictionary = {}
var items: Dictionary = {}
var facilities: Dictionary = {}
var factions: Dictionary = {}
var regions: Dictionary = {}
var missions: Dictionary = {}
var story: Dictionary = {}
var events: Dictionary = {}
var names: Dictionary = {}
var units: Dictionary = {}


func _ready() -> void:
	load_all()


func load_all() -> void:
	classes = _load("classes")
	skills = _load("skills")
	traits = _load("traits")
	races = _load("races")
	statuses = _load("statuses")
	subclasses = _load("subclasses")
	enemies = _load("enemies")
	items = _load("items")
	facilities = _load("facilities")
	factions = _load("factions")
	regions = _load("regions")
	missions = _load("missions")
	story = _load("story")
	events = _load("events")
	names = _load("names")
	units = _load_path("res://assets/sprites/units/units.json")


func _load(name: String) -> Dictionary:
	return _load_path("res://data/%s.json" % name)


func _load_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing data file: " + path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if parsed == null or not parsed is Dictionary:
		push_error("Bad JSON: " + path)
		return {}
	return parsed


func skill(id: String) -> Dictionary:
	return skills.get(id, {})


func xp_to_next(level: int) -> int:
	return 60 + 30 * level


func base_classes() -> Array:
	return ["warrior", "rogue", "ranger", "mystic"]


func color_of(arr) -> Color:
	if arr is Array and arr.size() >= 3:
		return Color8(int(arr[0]), int(arr[1]), int(arr[2]))
	return Color.WHITE
