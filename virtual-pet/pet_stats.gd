class_name petstats
extends Node

signal stats_changed(hunger: float, boredom: float, happiness: float)
signal level_up(new_level: int)
signal xp_gained(current_xp: int, target_xp: int)
signal warning_triggered(warning_type: String, message: String)
signal coins_changed(new_amount: int)
signal inventory_changed()

# Core attributes
var level: int = 1
var current_xp: int = 0
var last_spin_time: float = -10.0

var hunger: float = 80.0
var boredom: float = 20.0
var coins: int = 50

# Decay rates (points per SECOND; tuned for an idle game that can be left open)
# Hunger: 80 -> 35 (starts asking for food) in ~1.25 hours, empty after ~2.2 hours
# Boredom: 20 -> 60 (starts asking to play) in ~45 minutes, maxed after ~1.5 hours
const HUNGER_DECAY_RATE: float = 0.010
const BOREDOM_GROWTH_RATE: float = 0.015
const SPIN_COOLDOWN: float = 1.5

# Alert thresholds & debounce tracking
var warned_hunger: bool = false
var warned_boredom: bool = false

# --- Personality & Memory System ---
var personality: Dictionary = {
	"cheerfulness": 0,
	"curiosity": 0,
	"affection": 0,
	"energy": 0,
	"calmness": 0
}
var player_answers: Dictionary = {}
# Things the player TYPED (nickname, hobby, ...). Kept apart from player_answers on purpose:
# player_answers are short multiple-choice values that get sent to friends' pets and dropped into
# sentences, free text must never end up there.
var player_notes: Dictionary = {}
var dominant_trait: String = "Balanced"

# Item Catalog
const ITEM_DB := {
	"apple": {
		"name": "Apple",
		"price": 10,
		"hunger_restore": 25.0,
		"boredom_relief": 0.0,
		"desc": "Restores 25 Hunger."
	},
	"treat": {
		"name": "Tasty Treat",
		"price": 25,
		"hunger_restore": 40.0,
		"boredom_relief": 10.0,
		"desc": "Restores 40 Hunger & 10 Boredom."
	},
	"ball": {
		"name": "Yarn Ball",
		"price": 15,
		"hunger_restore": 0.0,
		"boredom_relief": 30.0,
		"desc": "Relieves 30 Boredom."
	}
}

var inventory: Dictionary = {
	"apple": 1
}

func _process(delta: float) -> void:
	_tick_stats(delta)

func _tick_stats(delta: float) -> void:
	hunger = clamp(hunger - (HUNGER_DECAY_RATE * delta), 0.0, 100.0)
	boredom = clamp(boredom + (BOREDOM_GROWTH_RATE * delta), 0.0, 100.0)
	
	stats_changed.emit(hunger, boredom, get_happiness())
	_check_warning_thresholds()

func get_happiness() -> float:
	return clamp((hunger + (100.0 - boredom)) / 2.0, 0.0, 100.0)

# --- Dialogue & Personality Logic ---
func adjust_personality(trait_name: String, amount: int) -> void:
	if personality.has(trait_name):
		personality[trait_name] += amount
		_recalculate_dominant_trait()
		add_xp(5)

func record_answer(key: String, value: Variant) -> void:
	player_answers[key] = value

func record_note(key: String, value: String) -> void:
	player_notes[key] = value

func _recalculate_dominant_trait() -> void:
	var top_trait = "Balanced"
	var max_val = 2
	for t in personality.keys():
		if personality[t] > max_val:
			max_val = personality[t]
			top_trait = t.capitalize()
	dominant_trait = top_trait

func get_time_period() -> String:
	var hour = Time.get_time_dict_from_system().hour
	if hour >= 5 and hour < 12:
		return "morning"
	elif hour >= 12 and hour < 17:
		return "afternoon"
	elif hour >= 17 and hour < 22:
		return "night"
	else:
		return "latenight"

func get_season() -> String:
	var month: int = Time.get_date_dict_from_system().month
	if month >= 3 and month <= 5:
		return "spring"
	elif month >= 6 and month <= 8:
		return "summer"
	elif month >= 9 and month <= 11:
		return "autumn"
	return "winter"
	
# --- XP, Leveling & Coins ---
func get_xp_for_next_level() -> int:
	return level * 100

func add_xp(amount: int) -> void:
	current_xp += amount
	var needed = get_xp_for_next_level()
	
	while current_xp >= needed:
		current_xp -= needed
		level += 1
		var reward = level * 20
		add_coins(reward)
		level_up.emit(level)
		needed = get_xp_for_next_level()
		
	xp_gained.emit(current_xp, needed)

func add_coins(amount: int) -> void:
	coins = max(0, coins + amount)
	coins_changed.emit(coins)

# --- Inventory & Shop Operations ---
func buy_item(item_id: String) -> bool:
	if not ITEM_DB.has(item_id):
		return false
	var cost = ITEM_DB[item_id]["price"]
	if coins >= cost:
		coins -= cost
		inventory[item_id] = inventory.get(item_id, 0) + 1
		coins_changed.emit(coins)
		inventory_changed.emit()
		return true
	return false

func use_item(item_id: String) -> bool:
	if inventory.get(item_id, 0) <= 0:
		return false
		
	var data = ITEM_DB[item_id]
	if data["hunger_restore"] > 0.0:
		feed_pet(data["hunger_restore"])
	if data["boredom_relief"] > 0.0:
		boredom = max(boredom - data["boredom_relief"], 0.0)
		
	inventory[item_id] -= 1
	if inventory[item_id] <= 0:
		inventory.erase(item_id)
		
	inventory_changed.emit()
	return true

# --- Interactions ---
func tap_pet() -> void:
	boredom = max(boredom - 4.0, 0.0)
	add_xp(5)

func feed_pet(amount: float = 25.0) -> void:
	hunger = min(hunger + amount, 100.0)
	warned_hunger = false
	add_xp(15)

func spin_pet() -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	boredom = max(boredom - 8.0, 0.0)
	
	if current_time - last_spin_time >= SPIN_COOLDOWN:
		last_spin_time = current_time
		add_xp(2)

func complete_game(score_multiplier: float = 1.0) -> void:
	boredom = max(boredom - 40.0, 0.0)
	add_xp(int(50 * score_multiplier))

# --- Warnings ---
func _check_warning_thresholds() -> void:
	if hunger <= 20.0 and not warned_hunger:
		warned_hunger = true
		warning_triggered.emit("hunger", "I'm starving! Feed me soon...")
	elif hunger > 30.0:
		warned_hunger = false
		
	if boredom >= 80.0 and not warned_boredom:
		warned_boredom = true
		warning_triggered.emit("boredom", "I'm so bored... Play with me!")
	elif boredom < 70.0:
		warned_boredom = false
