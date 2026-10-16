extends Node2D

# --- Top Level Nodes ---
@onready var sprite: Sprite2D = $Sprite2D
@onready var hover_info: Control = $"hover info"
@onready var alert_button: Button = $"hover info/menu popup"
@onready var hover_name_label: Label = $"hover info/name"
@onready var hover_lvl_label: Label = $"hover info/lvl"
@onready var menu_panel: Control = $"menu panel"
@onready var content_container: Control = $"menu panel/content container"

# --- Info Panel Controls ---
@onready var name_input: LineEdit = $"menu panel/content container/info panel/info control/horiz container/name_input"
@onready var birthday_label: Label = $"menu panel/content container/info panel/info control/horiz container/birthday"
@onready var lvl_bar: ProgressBar = $"menu panel/content container/info panel/info control/bar container/lvl_bar"
@onready var happiness_bar: ProgressBar = $"menu panel/content container/info panel/info control/bar container/happiness_bar"
@onready var hunger_bar: ProgressBar = $"menu panel/content container/info panel/info control/bar container/hunger_bar"
@onready var boredom_bar: ProgressBar = $"menu panel/content container/info panel/info control/bar container/boredom_bar"

# --- Inventory & Shop Containers ---
@onready var inv_coin_label: Label = $"menu panel/content container/inventory panel/inventory container/coins"
@onready var inv_list: Control = $"menu panel/content container/inventory panel/inventory container/ScrollContainer/inventory list"
@onready var inv_empty_label: Label = $"menu panel/content container/inventory panel/inventory container/Label"

@onready var shop_coin_label: Label = $"menu panel/content container/shop panel/shop container/coins"
@onready var shop_list: Control = $"menu panel/content container/shop panel/shop container/ScrollContainer/shop list"

# --- Direct Button-to-Panel Mapping ---
@onready var tabs := {
	$"menu panel/menu button container/info button": $"menu panel/content container/info panel",
	$"menu panel/menu button container/inventory button": $"menu panel/content container/inventory panel",
	$"menu panel/menu button container/shop button": $"menu panel/content container/shop panel",
	$"menu panel/menu button container/games button": $"menu panel/content container/games panel",
	$"menu panel/menu button container/settings button": $"menu panel/content container/settings panel"
}

# --- Games Panel ---
# NOTE: the scene tree cut off "game screen contain..." -- adjust that node name if yours differs
@onready var games_panel: Control = $"menu panel/content container/games panel"
@onready var games_container: Control = $"menu panel/content container/games panel/games container"
@onready var games_list: Control = $"menu panel/content container/games panel/games container/ScrollContainer/games list"
@onready var games_empty_label: Label = $"menu panel/content container/games panel/games container/Label"
@onready var game_screen: Control = $"menu panel/content container/games panel/game screen container"
@onready var game_close_button: Button = $"menu panel/content container/games panel/game screen container/close button"
@onready var game_title: Label = $"menu panel/content container/games panel/game screen container/title"
@onready var game_name_score: Label = $"menu panel/content container/games panel/game screen container/name score label"
@onready var game_you_score: Label = $"menu panel/content container/games panel/game screen container/you score label"
@onready var ttt_grid: GridContainer = $"menu panel/content container/games panel/game screen container/tic tac toe"

# --- Pet FX (hop / shake / wiggle + floating <3 :D etc., see pet_fx.gd) ---
const PetFx = preload("res://pet_fx.gd")
const TAP_EMOTE_COOLDOWN: float = 0.3
var _fx_tween: Tween
var _fx_base_offset: Vector2 = Vector2.ZERO
var _emotes: Array = []                 # my pet's floating emotes (kept in the click-through area)
var _last_tap_emote: float = -10.0
# Little hop-walk while the pet moves (wander, glides, tag...)
const WALK_BOB_HEIGHT: float = 4.0      # pixels
const WALK_BOB_SPEED: float = 12.0      # higher = quicker hops
const BREATH_HEIGHT: float = 1.5       # pixels, slow idle breathing while standing still
const BREATH_SPEED: float = 2.2
var _walk_bob: float = 0.0
var _breath: float = 0.0
var _last_sprite_pos: Vector2 = Vector2.ZERO

# --- Stats & Data ---
var stats: petstats
var pet_name: String = "Companion"
var pet_dob: String = ""
var pet_color: Color = Color.WHITE      # tint of my axolotl (white = the original sprite), friends see it too
const SAVE_PATH: String = "user://companion_save.cfg"

# --- Dialogue System ---
const DIALOGUE_RESOURCE = preload("res://friend_dialogue.dialogue")
const BALLOON_MIN_WIDTH: float = 300.0
const BALLOON_GAP: float = 24.0
var current_balloon: Node = null
var current_balloon_control: Control = null
var dialogue_timer: Timer
var _last_balloon_rect: Rect2 = Rect2()

# --- Drag & Hover State Variables ---
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
const HOVER_DISTANCE: float = 140.0

# --- Click-through (passthrough region) ---
# The window is click-through everywhere EXCEPT inside _hit_rects. On Windows this region also CLIPS what is
# drawn, so everything visible (pets, name tags, bubbles, emotes, menu) has to be inside it. It is built from
# several small rectangles (one per object) instead of one big box, so the space between objects stays
# click-through. It is applied once per frame, after everything moved (see _update_passthrough).
const HITBOX_PADDING: float = 8.0       # around buttons, menu, balloons, labels
const SPRITE_PAD: float = 10.0          # around a pet at rest
const SPRITE_PAD_FX: float = 16.0       # sides / bottom while a hop / shake / wiggle plays
const SPRITE_PAD_FX_TOP: float = 32.0   # top while it plays (a hop goes ~22 px up)
const DEBUG_DRAW_HITBOXES: bool = false # true = draw every passthrough rectangle in red
var _hit_rects: Array[Rect2] = []       # everything visible / clickable, in canvas coordinates
var _debug_overlay: Node2D = null
var _hitbox_dirty: bool = false
var _last_polygon: PackedVector2Array = PackedVector2Array()
var _passthrough_cleared: bool = false  # true while dragging (whole window is clickable then)
var _passthrough_queued: bool = false
var _last_fx_active: bool = false

# Tap vs Drag Tracking
var click_start_time: float = 0.0
var click_start_pos: Vector2 = Vector2.ZERO
const TAP_MAX_DURATION: float = 0.25
const TAP_MAX_DISTANCE: float = 12.0

# Circular Gesture Detection
var drag_history: Array[Vector2] = []
var accumulated_angle: float = 0.0

# Window / Panel Alignment
var menu_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	# One transparent window that covers ALL monitors, so the pet can move between them
	_fit_window_to_desktop()
	get_tree().root.transparent_bg = true
	# Make sure no old polygon region is set (it would clip drawing on Windows)
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array(), 0)
	
	# Instantiate and wire stats engine
	stats = petstats.new()
	add_child(stats)
	_fx_base_offset = sprite.offset
	
	stats.stats_changed.connect(_on_stats_changed)
	stats.level_up.connect(_on_level_up)
	stats.xp_gained.connect(_on_xp_gained)
	stats.warning_triggered.connect(_on_warning_received)
	stats.coins_changed.connect(_on_coins_changed)
	stats.inventory_changed.connect(_on_inventory_changed)
	
	load_game_data()
	_setup_dialogue_timer()
	
	hover_info.visible = false
	menu_panel.visible = false
	
	_reposition_hover_info()
	
	if alert_button:
		alert_button.pressed.connect(_on_alert_button_pressed)
		
	for btn in tabs.keys():
		if btn:
			btn.pressed.connect(_show_panel.bind(tabs[btn]))
			
	if name_input:
		name_input.text = pet_name
		name_input.text_submitted.connect(_on_name_submitted)
		
	if hover_name_label:
		hover_name_label.text = pet_name
		
	if birthday_label:
		birthday_label.text = pet_dob
	
	if hover_lvl_label:
		hover_lvl_label.text = str(stats.level)
	if lvl_bar:
		lvl_bar.max_value = stats.get_xp_for_next_level()
		lvl_bar.value = stats.current_xp

	_update_name_and_level_layout()
	_build_color_picker()
	_populate_shop_ui()
	_update_inventory_ui()
	_update_coin_displays(stats.coins)

	# Games: tic tac toe + commentary bubble
	ttt = preload("res://tic_tac_toe.gd").new()
	add_child(ttt)
	ttt.setup(ttt_grid, game_title, game_name_score, game_you_score, stats)
	ttt.commentary.connect(_on_ttt_commentary)
	game_close_button.pressed.connect(_close_game_screen)
	game_screen.visible = false
	games_container.visible = true
	_populate_games_ui()
	_setup_comment_timer()
	_setup_wander()
	_build_text_prompt()

	# Friends: visitor pet, Friends tab, gift / mood prompts (networking lives in the PetNetwork autoload)
	social = preload("res://social_manager.gd").new()
	add_child(social)
	social.setup(self, stats, content_container, $"menu panel/menu button container")

	_show_panel($"menu panel/content container/info panel")
	_setup_debug_overlay()
	update_clickable_hitbox()
	_print_display_debug()

# DEBUG: prints what the window / screen look like (useful when something only breaks on one PC).
# Delete this and the call above once the clipping problem is solved.
func _print_display_debug() -> void:
	await get_tree().process_frame
	var w := get_window()
	print("window size: ", w.size, " pos: ", w.position)
	print("screen size: ", DisplayServer.screen_get_size())
	print("usable rect: ", DisplayServer.screen_get_usable_rect())
	print("viewport rect: ", get_viewport().get_visible_rect())
	print("final transform: ", get_viewport().get_final_transform())
	print("renderer: ", ProjectSettings.get_setting("rendering/renderer/rendering_method"))

func _process(delta: float) -> void:
	_handle_proximity_hover()
	_update_pet_motion()
	_update_walk_bob(delta)
	if not _emotes.is_empty():
		update_clickable_hitbox()   # floating emotes move, keep them inside the visible region
	var fx_now: bool = _fx_is_active()
	if fx_now != _last_fx_active:
		_last_fx_active = fx_now
		update_clickable_hitbox()   # a hop / shake needs more room around the sprite
	if text_prompt_open():
		_reposition_text_prompt()
		var text_rect: Rect2 = _text_panel.get_global_rect()
		if text_rect != _last_text_rect:
			_last_text_rect = text_rect
			update_clickable_hitbox()
	if is_instance_valid(current_balloon_control):
		_reposition_dialogue_balloon()
		
		# Keep the clickable region in sync with the balloon.
		var panel := _get_balloon_panel()
		if panel:
			var r: Rect2 = panel.get_global_rect()
			if r != _last_balloon_rect:
				_last_balloon_rect = r
				update_clickable_hitbox()
	# apply the region at the END of the frame, after the visitors have moved too
	if not _passthrough_queued:
		_passthrough_queued = true
		_update_passthrough.call_deferred()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		save_game_data()

# --- Mouse position that keeps working while the window is click-through ---
# When the mouse is outside the passthrough region the window gets no mouse events, so
# get_local_mouse_position() goes stale. This asks the OS directly and converts the result
# into canvas coordinates (the same space as sprite.global_position).
func _window_mouse() -> Vector2:
	var in_window := Vector2(DisplayServer.mouse_get_position() - DisplayServer.window_get_position())
	return get_viewport().get_final_transform().affine_inverse() * in_window

# Stretches the window over every monitor (the bounding box of all of them).
func _fit_window_to_desktop() -> void:
	var desktop := Rect2i()
	for i in DisplayServer.get_screen_count():
		var s := Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i))
		desktop = s if i == 0 else desktop.merge(s)
	var win := get_window()
	win.position = desktop.position
	win.size = desktop.size - Vector2i(0, 1)   # 1px short so Windows doesn't treat it as fullscreen

# The usable area (no taskbar) of the monitor the pet is on, in canvas coordinates (the same space as
# sprite.global_position). The window covers every monitor, so wandering, menus and games are kept to
# the pet's own monitor instead of the gaps between monitors. Drag the pet onto the other monitor and
# everything follows it there.
func _screen_rect_canvas() -> Rect2:
	return _screen_rect_at(sprite.global_position if sprite != null else Vector2.ZERO)

# Usable area of every monitor, in canvas coordinates
func _monitor_rects_canvas() -> Array[Rect2]:
	var win_pos := Vector2(DisplayServer.window_get_position())
	var inv: Transform2D = get_viewport().get_final_transform().affine_inverse()
	var rects: Array[Rect2] = []
	for i in DisplayServer.get_screen_count():
		var usable := Rect2(DisplayServer.screen_get_usable_rect(i))
		var tl: Vector2 = inv * (usable.position - win_pos)
		var br: Vector2 = inv * (usable.end - win_pos)
		rects.append(Rect2(tl, br - tl))
	return rects

# The monitor (canvas coordinates) closest to a canvas point
func _screen_rect_at(p: Vector2) -> Rect2:
	var best := Rect2()
	var best_dist: float = INF
	for r in _monitor_rects_canvas():
		var nearest := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		var dist: float = nearest.distance_to(p)
		if dist < best_dist:
			best_dist = dist
			best = r
	return best

func _fx_is_active() -> bool:
	return _fx_tween != null and _fx_tween.is_valid() and _fx_tween.is_running()

# Padding around a pet sprite (mine and the visitors'). A hop / shake / wiggle moves the sprite outside its
# normal rectangle (up to ~22 px up), so the padding is only big while such an effect is playing.
func pad_sprite_rect(r: Rect2, fx_active: bool) -> Rect2:
	var side: float = SPRITE_PAD_FX if fx_active else SPRITE_PAD
	var top: float = SPRITE_PAD_FX_TOP if fx_active else SPRITE_PAD
	return Rect2(r.position - Vector2(side, top), r.size + Vector2(side * 2.0, top + side))

# Runs once per frame (deferred, so after every node has moved). Only calls the OS when the region changed.
func _update_passthrough() -> void:
	_passthrough_queued = false
	var dragging: bool = is_dragging or (social != null and social.is_dragging_visitor())
	if dragging:
		# while a pet is being dragged the whole window takes mouse events (nothing can lag behind or get clipped)
		if not _passthrough_cleared:
			_passthrough_cleared = true
			_last_polygon = PackedVector2Array()
			DisplayServer.window_set_mouse_passthrough(PackedVector2Array(), 0)
		return
	if _passthrough_cleared:
		_passthrough_cleared = false
		_hitbox_dirty = true
	if not _hitbox_dirty:
		return
	_hitbox_dirty = false
	var polygon: PackedVector2Array = _build_passthrough_polygon()
	if polygon == _last_polygon:
		return
	_last_polygon = polygon
	DisplayServer.window_set_mouse_passthrough(polygon, 0)

# The OS only takes ONE polygon, so all rectangles are joined into a single outline: each rectangle is
# walked around once, and zero-width "bridges" (walked there and back, so they enclose no area) connect them.
# Rectangles that overlap are merged first. An empty result means "the whole window is clickable" (safe fallback).
func _build_passthrough_polygon() -> PackedVector2Array:
	var xf: Transform2D = get_viewport().get_final_transform()
	var bounds := Rect2(Vector2.ZERO, Vector2(get_window().size))
	var win_rects: Array[Rect2] = []
	for r in _hit_rects:
		var w: Rect2 = (xf * r).intersection(bounds)
		if w.size.x > 0.5 and w.size.y > 0.5:
			win_rects.append(w)
	var merged: Array[Rect2] = _merge_overlapping(win_rects)
	var poly := PackedVector2Array()
	if merged.is_empty():
		return poly
	var starts: Array[Vector2] = []
	for r in merged:
		var tl: Vector2 = r.position
		poly.append(tl)
		poly.append(Vector2(r.end.x, r.position.y))
		poly.append(r.end)
		poly.append(Vector2(r.position.x, r.end.y))
		poly.append(tl)
		starts.append(tl)
	for i in range(starts.size() - 2, -1, -1):
		poly.append(starts[i])
	return poly

func _merge_overlapping(rects: Array[Rect2]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	out.append_array(rects)
	var changed: bool = true
	while changed:
		changed = false
		for i in range(out.size()):
			for j in range(i + 1, out.size()):
				if out[i].intersects(out[j], true):
					out[i] = out[i].merge(out[j])
					out.remove_at(j)
					changed = true
					break
			if changed:
				break
	return out

# --- Dialogue Setup & Placement ---
func _setup_dialogue_timer() -> void:
	dialogue_timer = Timer.new()
	dialogue_timer.one_shot = true
	dialogue_timer.timeout.connect(_on_dialogue_timer_timeout)
	add_child(dialogue_timer)
	_reset_dialogue_timer()

	_wait_timer = Timer.new()
	_wait_timer.one_shot = true
	_wait_timer.timeout.connect(_on_wait_timer_timeout)
	add_child(_wait_timer)

func _reset_dialogue_timer() -> void:
	# Random timer trigger between 45 and 90 seconds
	dialogue_timer.wait_time = randf_range(45.0, 90.0)
	dialogue_timer.start()

func _on_dialogue_timer_timeout() -> void:
	if not menu_panel.visible and not is_instance_valid(current_balloon):
		start_dialogue()
	_reset_dialogue_timer()

# --- Talking to the player vs. the friend's pet ---
# The pet only talks to its player when it is NOT in the middle of something with the friend's pet.
# If a conversation is due while a scene is running, it waits (checking every 1.5 s) until the scene is over.
var _wait_timer: Timer
var _dialogue_waiting: bool = false
var _waiting_title: String = ""

func has_dialogue_waiting() -> bool:
	return _dialogue_waiting

func _queue_dialogue(title: String) -> void:
	if not _dialogue_waiting:
		_dialogue_waiting = true
		_waiting_title = title
		_wait_timer.start(1.5)
	elif title != "":
		_waiting_title = title  # a specific topic (a need like need_food) beats a random one

func _on_wait_timer_timeout() -> void:
	if menu_panel.visible or is_instance_valid(current_balloon):
		_dialogue_waiting = false  # the player is already busy with the menu: drop it
		_waiting_title = ""
		return
	if social != null and social.is_pet_busy():
		_wait_timer.start(1.5)  # still in a scene, keep waiting
		return
	_dialogue_waiting = false
	var title: String = _waiting_title
	_waiting_title = ""
	start_dialogue(title)

# --- Topic Picker (shuffle bags: nothing repeats until everything else has played) ---
# Every "id" must match a "~ id" title in friend_dialogue.dialogue
#   "key"    = the answer this question records (skipped once answered, until all are answered)
#   "needs"  = only eligible once that answer has been recorded
#   "months" = only eligible in those months (1-12)
#   "min_boredom" = only eligible once boredom is at least this high (used for game invites)
const TOPIC_POOLS := {
	"ramble": [
		{"id": "ramble_time_aware"},
		{"id": "ramble_desktop_life"},
		{"id": "ramble_cozy_thoughts"},
		{"id": "ramble_existential_silly"},
		{"id": "ramble_stat_reactions"},
		{"id": "ramble_wellness"},
		{"id": "ramble_progress"},
		{"id": "ramble_pet_life"},
		{"id": "ramble_compliments"},
		{"id": "ramble_seasonal"},
		{"id": "ramble_fun_facts"},
		{"id": "ramble_spooky", "months": [10]},
		{"id": "ramble_tiny_hobbies"},
		{"id": "ramble_snack_philosophy"},
		{"id": "ramble_night_thoughts"},
		{"id": "ramble_pet_opinions"},
		{"id": "ramble_keyboard_music"},
		{"id": "ramble_other_pets"},
	],
	# Questions the player ANSWERS BY TYPING. "note_key" = the key in stats.player_notes the answer is
	# saved under (skipped once answered, until all are answered). The dialogue line does
	# `do queue_text("<note_key>")`, the box opens when the balloon closes, and the pet then plays
	# the "reply_<note_key>" title, which can use {{last_text}}.
	"typed": [
		{"id": "type_nickname", "note_key": "nickname"},
		{"id": "type_hobby", "note_key": "hobby"},
		{"id": "type_fav_food", "note_key": "fav_food"},
		{"id": "type_today_goal", "note_key": "today_goal"},
		{"id": "type_comfort_place", "note_key": "comfort_place"},
		{"id": "type_proud", "note_key": "proud_of"},
		{"id": "type_fav_show", "note_key": "fav_show"},
		{"id": "type_birthday_wish", "note_key": "birthday_wish"},
		{"id": "type_pet_name_idea", "note_key": "name_idea"},
		{"id": "type_mind"},
	],
	"question": [
		{"id": "chat_snack", "key": "favorite_snack"},
		{"id": "chat_mood"},
		{"id": "chat_adventure", "key": "fav_spot"},
		{"id": "chat_weather", "key": "weather_pref"},
		{"id": "chat_music", "key": "music_pref"},
		{"id": "chat_superpower", "key": "superpower"},
		{"id": "chat_sleep_habit", "key": "sleep_type"},
		{"id": "chat_animal", "key": "pet_animal"},
		{"id": "chat_drink", "key": "drink_pref"},
		{"id": "chat_unwind", "key": "unwind_style"},
		{"id": "chat_dream_room", "key": "dream_room"},
		{"id": "chat_planner", "key": "planner_type"},
		{"id": "chat_pizza", "key": "pizza_take"},
		{"id": "chat_game_style", "key": "game_style"},
		{"id": "chat_wyr_pet", "key": "wyr_pet"},
		{"id": "chat_color", "key": "color_pref"},
		{"id": "chat_small_win"},
		{"id": "chat_morning_routine", "key": "morning_routine"},
		{"id": "chat_season_fav", "key": "season_fav"},
		{"id": "chat_social_battery", "key": "social_battery"},
		{"id": "chat_wyr_time", "key": "wyr_time"},
		{"id": "chat_comfort_food", "key": "comfort_food"},
		{"id": "chat_desk_style", "key": "desk_style"},
	],
	"invite": [
		{"id": "invite_tictactoe", "min_boredom": 30.0},
	],
	"memory": [
		{"id": "remember_weather", "needs": "weather_pref"},
		{"id": "remember_snack", "needs": "favorite_snack"},
		{"id": "remember_spot", "needs": "fav_spot"},
		{"id": "remember_music", "needs": "music_pref"},
		{"id": "remember_sleep", "needs": "sleep_type"},
		{"id": "remember_animal", "needs": "pet_animal"},
		{"id": "remember_drink", "needs": "drink_pref"},
		{"id": "remember_unwind", "needs": "unwind_style"},
		{"id": "remember_dream_room", "needs": "dream_room"},
		{"id": "remember_color", "needs": "color_pref"},
		{"id": "remember_season", "needs": "season_fav"},
		{"id": "remember_comfort_food", "needs": "comfort_food"},
		{"id": "remember_nickname", "needs_note": "nickname"},
		{"id": "remember_hobby", "needs_note": "hobby"},
		{"id": "remember_fav_food", "needs_note": "fav_food"},
		{"id": "remember_today_goal", "needs_note": "today_goal"},
		{"id": "remember_comfort_place", "needs_note": "comfort_place"},
		{"id": "remember_proud", "needs_note": "proud_of"},
		{"id": "remember_fav_show", "needs_note": "fav_show"},
		{"id": "remember_birthday_wish", "needs_note": "birthday_wish"},
		{"id": "chat_personality_check"},
	],
}
# Roughly 27% rambles, 27% questions, 20% typed questions, 13% memories / personality, 13% game invites
# (an invite that isn't eligible yet, e.g. pet isn't bored, falls back to a ramble; "typed" is
# skipped once everything has been answered a few times, see _eligible_topics)
const CATEGORY_WEIGHTS := {"ramble": 4, "question": 4, "typed": 3, "memory": 2, "invite": 2}

var _topic_bags: Dictionary = {}
var _last_topic: String = ""

# --- Stage 2: missing the friends it met in multiplayer (see pet_memory.gd, social_manager.gd) ---
# The dialogue title "miss_friend" reads these. They are filled in by _begin_miss_topic().
const PetMemory = preload("res://pet_memory.gd")
const MISS_WEIGHT: int = 3                   # like a typed question: about 1 in 5 conversations while somebody is missed
const MISS_GLOBAL_COOLDOWN: float = 1800.0   # at most one "i miss them" talk every 30 minutes (each friend has their own cooldown too)
var miss_name: String = ""                   # the friend's pet name (raw)
var miss_kind: String = ""
var miss_line: String = ""
var miss_yes: String = ""
var miss_later: String = ""
var miss_memory: String = ""
var miss_follow_up: String = ""
var _last_miss_time: float = -100000.0
var _pending_invite: bool = false            # set by dialogue (queue_invite), launched when the balloon closes

# Prepares everything the "miss_friend" dialogue says and returns its title ("" = nothing to say)
func _begin_miss_topic(info: Dictionary) -> String:
	if info.is_empty() or social == null:
		return ""
	miss_name = str(info["name"])
	miss_kind = str(info["kind"])
	# the name is free text from another player and ends up in a rich-text balloon: no "[" allowed
	var safe: String = miss_name.replace("[", "[lb]")
	var away: int = int(info["away"])
	miss_line = PetMemory.miss_line(miss_kind, safe, away)
	miss_yes = PetMemory.yes_line(miss_kind, safe)
	miss_later = PetMemory.later_line()
	miss_follow_up = PetMemory.follow_up_line()
	miss_memory = PetMemory.memory_line(miss_kind, safe, away, int(info["level"]))
	social.mark_missed(str(info["fid"]))
	_last_miss_time = Time.get_ticks_msec() / 1000.0
	return "miss_friend"

# Starts the "i miss them" talk right now (used by the debug button). false = nobody is missed.
func start_miss_talk() -> bool:
	if social == null:
		return false
	var info: Dictionary = social.peek_missed_friend()
	var title: String = _begin_miss_topic(info)
	if title.is_empty():
		return false
	start_dialogue(title)
	return true

# Called from dialogue: `do queue_invite()`. Opens the Friends tab and the Steam invite once the balloon has closed.
func queue_invite() -> void:
	_pending_invite = true

func _launch_pending_invite() -> void:
	_pending_invite = false
	if social == null:
		return
	if not menu_panel.visible:
		await open_menu()
	_show_panel(social.panel)
	social.start_invite_flow(miss_name)

func _pick_next_topic() -> String:
	# A pressing need (hungry / bored) always goes first
	var need: String = _pick_need_topic()
	if not need.is_empty():
		_last_topic = need
		return need

	# Weighted roll for the category
	# Stage 2: a friend my pet misses (only when somebody really is missed, and never twice in a short while)
	var miss: Dictionary = {}
	if social != null and Time.get_ticks_msec() / 1000.0 - _last_miss_time >= MISS_GLOBAL_COOLDOWN:
		miss = social.peek_missed_friend()
	var weights: Dictionary = CATEGORY_WEIGHTS.duplicate()
	if not miss.is_empty():
		weights["miss"] = MISS_WEIGHT
	var total: int = 0
	for weight in weights.values():
		total += weight
	var roll: int = randi() % total
	var category: String = "ramble"
	for c in weights.keys():
		roll -= weights[c]
		if roll < 0:
			category = c
			break
	
	var topic: String = _begin_miss_topic(miss) if category == "miss" else _draw_topic(category)
	if topic.is_empty():
		topic = _draw_topic("ramble")
	if topic.is_empty():
		topic = "random_chatter"
	_last_topic = topic
	return topic

func _draw_topic(category: String) -> String:
	var eligible: Array[String] = _eligible_topics(category)
	if eligible.is_empty():
		return ""
	
	var bag: Array = _topic_bags.get(category, [])
	# Drop anything that stopped being eligible (e.g. a question that just got answered)
	bag = bag.filter(func(id): return id in eligible)
	
	if bag.is_empty():
		bag = eligible.duplicate()
		bag.shuffle()
		# Don't open a fresh bag with the topic that just played
		if bag.size() > 1 and bag.back() == _last_topic:
			bag.push_front(bag.pop_back())
	
	var topic: String = bag.pop_back()
	_topic_bags[category] = bag
	return topic

func _eligible_topics(category: String) -> Array[String]:
	var month: int = Time.get_date_dict_from_system().month
	var out: Array[String] = []
	var fresh: Array[String] = []  # evergreen or not-yet-answered questions
	var any_unanswered: bool = false
	
	for entry in TOPIC_POOLS[category]:
		if entry.has("months") and not (month in entry["months"]):
			continue
		if entry.has("min_boredom") and stats.boredom < entry["min_boredom"]:
			continue
		if entry.has("needs") and not stats.player_answers.has(entry["needs"]):
			continue
		if entry.has("needs_note") and not stats.player_notes.has(entry["needs_note"]):
			continue
		
		out.append(entry["id"])
		
		var unanswered: bool = false
		if entry.has("key"):
			unanswered = not stats.player_answers.has(entry["key"])
		elif entry.has("note_key"):
			unanswered = not stats.player_notes.has(entry["note_key"])
		if unanswered:
			any_unanswered = true
		if not (entry.has("key") or entry.has("note_key")) or unanswered:
			fresh.append(entry["id"])
	
	# Questions: ask the ones you haven't heard answers to first.
	# Once everything is answered, everything is fair game again (typed questions are then
	# asked again, so the player can update their answer).
	if (category == "question" or category == "typed") and any_unanswered:
		return fresh
	return out

func _get_balloon_panel() -> Control:
	if not is_instance_valid(current_balloon):
		return null
	return current_balloon.find_child("PanelContainer", true, false) as Control

func start_dialogue(title: String = "") -> void:
	if is_instance_valid(current_balloon):
		return
	# Never in the middle of a scene with the friend's pet: wait until it is over
	if social != null and social.is_pet_busy():
		_queue_dialogue(title)
		return
	
	# No title given? Draw the next topic from the shuffle bags
	if title.is_empty():
		title = _pick_next_topic()
		
	# Pass both self (for pet_name) and stats (for personality & memories)
	current_balloon = DialogueManager.show_dialogue_balloon(DIALOGUE_RESOURCE, title, [self, stats])
	if not current_balloon:
		return

	# The friend's pet backs off and the friend is told, so the pet is alone with its player
	if social != null:
		social.player_talking_changed(true)

	if _motion_kind == "wander":
		_stop_pet_motion()  # stand still while talking

	# Extract visual Control root from the Dialogue CanvasLayer
	current_balloon_control = null
	for child in current_balloon.get_children():
		if child is Control:
			current_balloon_control = child
			break
			
	if not current_balloon_control and current_balloon is Control:
		current_balloon_control = current_balloon

	if current_balloon_control:
		# Detach full-screen anchors so it behaves like a floating speech card
		current_balloon_control.set_anchors_preset(Control.PRESET_TOP_LEFT)
		current_balloon_control.grow_horizontal = Control.GROW_DIRECTION_END
		current_balloon_control.grow_vertical = Control.GROW_DIRECTION_END
		current_balloon_control.mouse_filter = Control.MOUSE_FILTER_PASS
		current_balloon_control.clip_contents = false

		# Make intermediate panels click-through so desktop clicks pass through
		_configure_balloon_mouse_filters(current_balloon_control)
		
		# Keep the bubble the same width whether it's plain text or has choices
		var panel := _get_balloon_panel()
		if panel:
			panel.custom_minimum_size.x = BALLOON_MIN_WIDTH

	_hook_responses(current_balloon)

	current_balloon.tree_exited.connect(func():
		current_balloon = null
		current_balloon_control = null
		_last_balloon_rect = Rect2()
		_comment_balloon_active = false
		if social != null:
			social.player_talking_changed(false)
		save_game_data()
		update_clickable_hitbox()
		# The player said yes to a game invite: launch it now that the balloon is gone
		if _pending_game != "":
			_launch_pending_game.call_deferred()
		# The player said yes to "invite them!": open the Friends tab and the invite dialog
		if _pending_invite:
			_launch_pending_invite.call_deferred()
		# The dialogue asked for a typed answer: open the input box now that the balloon is gone
		if not _pending_text.is_empty():
			_open_text_prompt.call_deferred()
	)
	
	# Wait two frames for Dialogue Manager font/layout to calculate bounds
	await get_tree().process_frame
	await get_tree().process_frame
	_reposition_dialogue_balloon()
	update_clickable_hitbox()

# Answering a question makes the pet happy (:D). Finds the responses menu inside whatever balloon
# scene you use by looking for its "response_selected" signal, so it doesn't depend on node names.
func _hook_responses(node: Node) -> void:
	if node.has_signal("response_selected"):
		node.connect("response_selected", func(_response = null): _on_player_responded())
	for child in node.get_children():
		_hook_responses(child)

func _on_player_responded() -> void:
	show_emote("happy")
	play_fx("hop")

# --- Typed answers ---
# A dialogue line says `do queue_text("hobby")`. When the balloon has closed, a small input box opens
# next to the pet. What the player types is saved in stats.player_notes[key] (NOT in player_answers:
# those are shared with friends' pets, free text never is) and the pet answers with the
# "reply_<key>" dialogue title, which can use {{last_text}}. Enter = send, Esc / "skip" = skip.
const TEXT_MAX_LEN: int = 60
const TEXT_PANEL_WIDTH: float = 300.0
var last_text: String = ""
var _pending_text: Dictionary = {}
var _text_key: String = ""
var _text_panel: PanelContainer
var _text_edit: LineEdit
var _last_text_rect: Rect2 = Rect2()

func queue_text(key: String) -> void:
	_pending_text = {"key": key}

func text_prompt_open() -> bool:
	return _text_panel != null and _text_panel.visible

func _build_text_prompt() -> void:
	_text_panel = PanelContainer.new()
	_text_panel.visible = false
	_text_panel.z_index = 100
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_text_panel.add_child(vbox)

	_text_edit = LineEdit.new()
	_text_edit.max_length = TEXT_MAX_LEN
	_text_edit.placeholder_text = "type here, then press enter"
	_text_edit.custom_minimum_size.x = TEXT_PANEL_WIDTH
	_text_edit.text_submitted.connect(_submit_text)
	vbox.add_child(_text_edit)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 6)
	vbox.add_child(row)
	var skip_btn := Button.new()
	skip_btn.text = "skip"
	skip_btn.focus_mode = Control.FOCUS_NONE
	skip_btn.pressed.connect(_skip_text)
	row.add_child(skip_btn)
	var send_btn := Button.new()
	send_btn.text = "send"
	send_btn.focus_mode = Control.FOCUS_NONE
	send_btn.pressed.connect(func(): _submit_text(_text_edit.text))
	row.add_child(send_btn)
	add_child(_text_panel)

func _open_text_prompt() -> void:
	var key: String = str(_pending_text.get("key", ""))
	_pending_text = {}
	if key.is_empty() or _text_panel == null:
		return
	_text_key = key
	_text_edit.text = ""
	_text_panel.visible = true
	_stop_pet_motion()
	if social != null:
		social.player_talking_changed(true)   # friends' pets give us room, like during a normal chat
	await get_tree().process_frame
	await get_tree().process_frame
	if not text_prompt_open():
		return
	_reposition_text_prompt()
	_text_edit.grab_focus()
	update_clickable_hitbox()

func _reposition_text_prompt() -> void:
	if not text_prompt_open():
		return
	var s: Vector2 = _text_panel.get_combined_minimum_size().max(_text_panel.size)
	var half: Vector2 = (sprite.texture.get_size() * sprite.scale) / 2.0
	var screen_rect: Rect2 = _screen_rect_canvas()
	var x: float = sprite.global_position.x - s.x / 2.0
	var y: float = sprite.global_position.y - half.y - s.y - BALLOON_GAP
	if y < screen_rect.position.y + 10.0:
		y = sprite.global_position.y + half.y + BALLOON_GAP
	x = clamp(x, screen_rect.position.x + 10.0, max(screen_rect.position.x + 10.0, screen_rect.end.x - s.x - 10.0))
	y = clamp(y, screen_rect.position.y + 10.0, max(screen_rect.position.y + 10.0, screen_rect.end.y - s.y - 10.0))
	_text_panel.global_position = Vector2(x, y)

func _close_text_prompt() -> void:
	if _text_panel == null or not _text_panel.visible:
		return
	_text_panel.visible = false
	_text_edit.release_focus()
	_last_text_rect = Rect2()
	if social != null:
		social.player_talking_changed(false)
	update_clickable_hitbox()

func _skip_text() -> void:
	_close_text_prompt()
	start_dialogue("reply_skip")

# Free text is shown in speech balloons: no BBCode / dialogue code, one line only
func _clean_typed(raw: String) -> String:
	var t: String = raw.strip_edges().replace("\n", " ").replace("\t", " ")
	for ch in ["[", "]", "{", "}"]:
		t = t.replace(ch, "")
	return t.substr(0, TEXT_MAX_LEN).strip_edges()

func _submit_text(raw: String) -> void:
	if not text_prompt_open():
		return
	var clean: String = _clean_typed(raw)
	var key: String = _text_key
	if clean.is_empty():
		_skip_text()
		return
	_close_text_prompt()
	last_text = clean
	stats.record_note(key, clean)
	stats.add_xp(10)
	stats.boredom = max(stats.boredom - 5.0, 0.0)
	show_emote("happy")
	play_fx("hop")
	await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(current_balloon):
		start_dialogue("reply_" + key)
	save_game_data()

func _configure_balloon_mouse_filters(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			child.mouse_filter = Control.MOUSE_FILTER_STOP
		elif child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_PASS
		_configure_balloon_mouse_filters(child)

func _reposition_dialogue_balloon() -> void:
	if not is_instance_valid(current_balloon_control):
		return

	var panel := _get_balloon_panel()
	if not panel:
		return

	# Real size of the visible panel (size can lag a frame when choices appear)
	var panel_size: Vector2 = panel.get_combined_minimum_size().max(panel.size)
	
	# Where the visible panel actually sits relative to the root control
	var inset: Vector2 = panel.global_position - current_balloon_control.global_position

	var spr_half_h: float = (sprite.texture.get_height() * sprite.scale.y) / 2.0
	var spr_pos: Vector2 = sprite.global_position
	var screen_rect: Rect2 = _screen_rect_canvas()

	# Centered horizontally on the pet
	var target_x: float = spr_pos.x - (panel_size.x / 2.0)

	# Prefer above the pet, flip below if it would go off the top
	var above_y: float = spr_pos.y - spr_half_h - panel_size.y - BALLOON_GAP
	var below_y: float = spr_pos.y + spr_half_h + BALLOON_GAP
	var top_limit: float = screen_rect.position.y + 10.0
	var target_y: float = above_y if above_y >= top_limit else below_y

	if above_y < top_limit and game_screen.visible:
		# No room above the pet during a game: sit beside it instead of covering the board
		var spr_half_w: float = (sprite.texture.get_width() * sprite.scale.x) / 2.0
		target_y = spr_pos.y - panel_size.y / 2.0
		target_x = spr_pos.x + spr_half_w + BALLOON_GAP
		if target_x + panel_size.x > screen_rect.end.x - 10.0:
			target_x = spr_pos.x - spr_half_w - BALLOON_GAP - panel_size.x

	# Keep it on the pet's monitor
	target_x = clamp(target_x, screen_rect.position.x + 10.0, max(screen_rect.position.x + 10.0, screen_rect.end.x - panel_size.x - 10.0))
	target_y = clamp(target_y, screen_rect.position.y + 10.0, max(screen_rect.position.y + 10.0, screen_rect.end.y - panel_size.y - 10.0))

	# Move the root so the *panel* lands on the target
	current_balloon_control.global_position = Vector2(target_x, target_y) - inset

# --- 1. Dynamic Layout Adjustments ---
func _update_name_and_level_layout() -> void:
	if not hover_name_label or not hover_lvl_label:
		return

	var name_width = hover_name_label.get_minimum_size().x
	var spr_w = sprite.texture.get_width() * sprite.scale.x
	var default_lvl_x = spr_w - hover_lvl_label.size.x
	var pushed_lvl_x = hover_name_label.position.x + name_width + 8.0
	hover_lvl_label.position.x = max(default_lvl_x, pushed_lvl_x)

# --- 2. Save & Load System ---
func save_game_data() -> void:
	var config = ConfigFile.new()
	
	config.set_value("profile", "name", pet_name)
	config.set_value("profile", "dob", pet_dob)
	config.set_value("profile", "color", pet_color.to_html(false))
	config.set_value("mind", "topic_bags", _topic_bags)
	config.set_value("mind", "last_topic", _last_topic)
	config.set_value("settings", "wander", wander_enabled)
	
	if stats:
		config.set_value("stats", "level", stats.level)
		config.set_value("stats", "current_xp", stats.current_xp)
		config.set_value("stats", "hunger", stats.hunger)
		config.set_value("stats", "boredom", stats.boredom)
		config.set_value("economy", "coins", stats.coins)
		config.set_value("economy", "inventory", stats.inventory)
		config.set_value("mind", "personality", stats.personality)
		config.set_value("mind", "player_answers", stats.player_answers)
		config.set_value("mind", "player_notes", stats.player_notes)
		
	config.save(SAVE_PATH)

func load_game_data() -> void:
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	
	if err == OK:
		pet_name = config.get_value("profile", "name", "Companion")
		pet_dob = config.get_value("profile", "dob", "")
		var saved_color: String = str(config.get_value("profile", "color", "ffffff"))
		pet_color = Color(saved_color) if saved_color.is_valid_html_color() else Color.WHITE
		_topic_bags = config.get_value("mind", "topic_bags", {})
		_last_topic = config.get_value("mind", "last_topic", "")
		wander_enabled = bool(config.get_value("settings", "wander", true))
		
		if stats:
			stats.level = config.get_value("stats", "level", 1)
			stats.current_xp = config.get_value("stats", "current_xp", 0)
			stats.hunger = config.get_value("stats", "hunger", 80.0)
			stats.boredom = config.get_value("stats", "boredom", 20.0)
			stats.coins = config.get_value("economy", "coins", 50)
			stats.inventory = config.get_value("economy", "inventory", {"apple": 1})
			stats.personality = config.get_value("mind", "personality", stats.personality)
			stats.player_answers = config.get_value("mind", "player_answers", {})
			stats.player_notes = config.get_value("mind", "player_notes", {})
			stats._recalculate_dominant_trait()
	else:
		pet_name = "Companion"
		pet_dob = Time.get_date_string_from_system()
		save_game_data()
		
	if hover_name_label:
		hover_name_label.text = pet_name
	sprite.modulate = pet_color
	_update_name_and_level_layout()

# --- 2b. Pet colour (swatches in the Info tab; friends see it through the profile) ---
func _build_color_picker() -> void:
	var info_control: Control = get_node_or_null("menu panel/content container/info panel/info control")
	if info_control == null:
		return
	# "info control" is a plain Control (its children are placed by hand), so nothing is laid out for us:
	# the picker is one VBox that gets positioned under the existing content once that has been laid out.
	var holder := VBoxContainer.new()
	holder.name = "color picker"
	holder.add_theme_constant_override("separation", 4)
	info_control.add_child(holder)
	var label := Label.new()
	label.text = "Colour"
	holder.add_child(label)

	# Plain swatch buttons instead of a ColorPickerButton: its popup is a separate window, which the
	# click-through window would swallow.
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 3)
	flow.add_theme_constant_override("v_separation", 4)
	holder.add_child(flow)

	var swatches: Array[Color] = [Color.WHITE]   # white = the original colour
	for hue in [0.0, 0.07, 0.14, 0.33, 0.47, 0.55, 0.62, 0.75, 0.85, 0.93]:
		swatches.append(Color.from_hsv(hue, 0.4, 1.0))
	for c in swatches:
		var b := Button.new()
		b.custom_minimum_size = Vector2(24.0, 24.0)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "original" if c == Color.WHITE else "#" + c.to_html(false)
		for state in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = c
			sb.set_corner_radius_all(5)
			sb.set_border_width_all(2 if state == "normal" else 3)
			sb.border_color = Color(0.0, 0.0, 0.0, 0.5) if state == "normal" else Color.WHITE
			b.add_theme_stylebox_override(state, sb)
		b.pressed.connect(set_pet_color.bind(c))
		flow.add_child(b)

	# Layout (see companion.tscn): "info control" holds hand-anchored children: title, "horiz container"
	# (name | birthday), "text container" (the Level / Happiness... labels) and "bar container".
	# The picker goes right under the name row; the labels and the bars are pushed down TOGETHER by the same
	# amount, and only as much as the picker needs. Everything here uses LOCAL coordinates, because the
	# menu panel is scaled (0.8) and global positions would not match the local sizes.
	await get_tree().process_frame
	await get_tree().process_frame
	var horiz: Control = info_control.get_node_or_null("horiz container")
	var texts: Control = info_control.get_node_or_null("text container")
	var bars: Control = info_control.get_node_or_null("bar container")
	if horiz == null or texts == null or bars == null:
		holder.queue_free()   # unknown layout: skip the picker rather than draw it over something
		return
	var font_size: int = 24
	for l in texts.find_children("*", "Label", true, false):
		font_size = (l as Label).get_theme_font_size("font_size")
		break
	label.add_theme_font_size_override("font_size", font_size)
	var w: float = maxf(horiz.size.x, 260.0)
	holder.custom_minimum_size.x = w
	holder.size.x = w
	holder.position = Vector2(horiz.position.x, horiz.position.y + horiz.size.y + 6.0)
	await get_tree().process_frame
	var holder_bottom: float = holder.position.y + holder.get_combined_minimum_size().y + 8.0
	var below_top: float = minf(texts.position.y, bars.position.y)
	var overlap: float = holder_bottom - below_top
	if overlap > 0.0:
		texts.position.y += overlap
		bars.position.y += overlap

# Changes my axolotl's colour, saves it and tells everyone in the room.
func set_pet_color(c: Color) -> void:
	pet_color = c
	sprite.modulate = c
	save_game_data()
	if social != null:
		social.refresh_profile()

# What goes into my profile: "" for the original colour (friends then use their own per-friend tint)
func pet_color_hex() -> String:
	return "" if pet_color.is_equal_approx(Color.WHITE) else pet_color.to_html(false)

# --- 3. Shop & Inventory UI ---
func _update_coin_displays(amount: int) -> void:
	if inv_coin_label:
		inv_coin_label.text = "Coins: %d" % amount
	if shop_coin_label:
		shop_coin_label.text = "Coins: %d" % amount

func _populate_shop_ui() -> void:
	if not shop_list:
		return
	for c in shop_list.get_children():
		c.queue_free()
		
	for item_id in stats.ITEM_DB.keys():
		var data = stats.ITEM_DB[item_id]
		
		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(90, 85)
		
		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		
		var title_lbl = Label.new()
		title_lbl.text = data["name"]
		title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		
		var price_lbl = Label.new()
		price_lbl.text = "%d c" % data["price"]
		price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		
		var buy_btn = Button.new()
		buy_btn.text = "Buy"
		buy_btn.pressed.connect(func():
			if stats.buy_item(item_id):
				print("Purchased: ", item_id)
		)
		
		vbox.add_child(title_lbl)
		vbox.add_child(price_lbl)
		vbox.add_child(buy_btn)
		
		card.add_child(vbox)
		shop_list.add_child(card)

func _update_inventory_ui() -> void:
	if not inv_list:
		return
	for c in inv_list.get_children():
		c.queue_free()
		
	var is_empty = stats.inventory.is_empty()
	if inv_empty_label:
		inv_empty_label.visible = is_empty
		
	if is_empty:
		return
		
	for item_id in stats.inventory.keys():
		var count = stats.inventory[item_id]
		var data = stats.ITEM_DB[item_id]
		
		var slot = PanelContainer.new()
		slot.custom_minimum_size = Vector2(80, 80)
		
		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		
		var item_lbl = Label.new()
		item_lbl.text = "%s\nx%d" % [data["name"], count]
		item_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		
		var use_btn = Button.new()
		use_btn.text = "Use"
		use_btn.pressed.connect(func():
			stats.use_item(item_id)
		)
		
		vbox.add_child(item_lbl)
		vbox.add_child(use_btn)
		
		slot.add_child(vbox)
		inv_list.add_child(slot)

func _on_coins_changed(amount: int) -> void:
	_update_coin_displays(amount)

func _on_inventory_changed() -> void:
	_update_inventory_ui()
	save_game_data()

# --- 4. Proximity Hover Check ---
func _handle_proximity_hover() -> void:
	if is_dragging:
		return
		
	# Uses the OS mouse position: get_local_mouse_position() freezes while the window is click-through
	var dist = _window_mouse().distance_to(sprite.global_position)
	
	var should_show = (dist <= HOVER_DISTANCE) or menu_panel.visible or is_instance_valid(current_balloon)
	if hover_info.visible != should_show:
		hover_info.visible = should_show
		update_clickable_hitbox()

## --- 5. Input Handling ---
func _input(event: InputEvent) -> void:
	# Esc closes the typed-answer box
	if text_prompt_open() and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_skip_text()
		get_viewport().set_input_as_handled()
		return
	# Clicking / dragging a friend's pet (only moves the puppet on this screen). Returns false for
	# anything that is not about a visitor, e.g. clicks on my own pet, the menu or the desktop.
	if social != null and social.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			var click_pos = get_global_mouse_position()
			var spr_size = sprite.texture.get_size() * sprite.scale
			var spr_rect = Rect2(sprite.global_position - (spr_size / 2.0), spr_size)
			
			# Check if clicking on the pet to drag
			if spr_rect.has_point(click_pos):
				is_dragging = true
				_stop_pet_motion()  # grabbing the pet cancels any glide / wander
				click_start_time = Time.get_ticks_msec() / 1000.0
				click_start_pos = click_pos
				drag_offset = sprite.global_position - click_pos
				
				accumulated_angle = 0.0
				drag_history.clear()
				# (while dragging, _update_passthrough opens the whole window so nothing can get clipped)
				get_viewport().set_input_as_handled()
				return
			
			if menu_panel.visible:
				var menu_rect = menu_panel.get_global_rect()
				var alert_rect = alert_button.get_global_rect()
				var over_social_ui: bool = social != null and social.is_point_over_ui(click_pos)
				if not menu_rect.has_point(click_pos) and not alert_rect.has_point(click_pos) and not over_social_ui:
					close_menu()
		else:
			if is_dragging:
				var release_time = Time.get_ticks_msec() / 1000.0
				var dist_moved = click_start_pos.distance_to(get_global_mouse_position())
				
				if (release_time - click_start_time) <= TAP_MAX_DURATION and dist_moved <= TAP_MAX_DISTANCE:
					_on_pet_tapped()
					
				is_dragging = false
				drag_history.clear()
				accumulated_angle = 0.0
				update_clickable_hitbox()
				if game_screen.visible:
					_perch_pet_on_game_window()  # during a game the pet glides back to the window
				else:
					_schedule_wander(4.0, 9.0)
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and is_dragging:
		sprite.global_position = get_global_mouse_position() + drag_offset
		_reposition_hover_info()
		_reposition_dialogue_balloon()
		# Normally the menu follows the pet. During a game it stays put,
		# and the pet glides back to it when you let go.
		if not game_screen.visible:
			_reposition_menu_panel()
		_track_circular_drag()
		get_viewport().set_input_as_handled()

# --- 6. Pet Gesture Handlers ---
func _on_pet_tapped() -> void:
	if stats:
		stats.tap_pet()
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_tap_emote >= TAP_EMOTE_COOLDOWN:
		_last_tap_emote = now
		show_emote("heart")
		play_fx("hop")
	if not is_instance_valid(current_balloon) and randf() < 0.05:
		start_dialogue()

func _track_circular_drag() -> void:
	var local_cursor = get_local_mouse_position()
	drag_history.append(local_cursor)
	
	if drag_history.size() > 8:
		drag_history.pop_front()
		
	if drag_history.size() >= 3:
		var v_prev = drag_history[-2] - sprite.position
		var v_curr = drag_history[-1] - sprite.position
		
		if v_prev.length() > 25.0 and v_curr.length() > 25.0:
			var angle_delta = v_prev.angle_to(v_curr)
			
			if (accumulated_angle >= 0.0 and angle_delta >= 0.0) or (accumulated_angle <= 0.0 and angle_delta <= 0.0):
				accumulated_angle += angle_delta
			else:
				accumulated_angle = angle_delta
			
			if abs(accumulated_angle) >= TAU:
				accumulated_angle = 0.0
				if stats:
					stats.spin_pet()

# Bounces the sprite while it moves and gently breathes while it stands still
# (via offset, so it never fights with dragging).
func _update_walk_bob(delta: float) -> void:
	var moving: bool = not is_dragging and sprite.global_position.distance_to(_last_sprite_pos) > 0.05
	_last_sprite_pos = sprite.global_position
	if _fx_tween != null and _fx_tween.is_valid() and _fx_tween.is_running():
		return   # a hop / shake / wiggle is playing and owns the offset
	var s: float = maxf(sprite.scale.x, 0.01)   # offsets are in texture pixels
	if moving:
		_walk_bob += delta * WALK_BOB_SPEED
		sprite.offset.y = _fx_base_offset.y - absf(sin(_walk_bob)) * WALK_BOB_HEIGHT / s
	else:
		_breath += delta * BREATH_SPEED
		sprite.offset.y = _fx_base_offset.y + sin(_breath) * BREATH_HEIGHT / s

# --- 6b. Pet FX (used in singleplayer too; social_manager.gd calls these for friend scenes) ---
func play_fx(fx: String) -> void:
	_fx_tween = PetFx.play_fx(self, sprite, _fx_base_offset, fx, _fx_tween)

func show_emote(key: String) -> void:
	var labels: Array = PetFx.spawn_emote(self, _emote_anchor(), key)
	for l in labels:
		_emotes.append(l)
		l.tree_exited.connect(func():
			_emotes.erase(l)
			update_clickable_hitbox()
		)
	update_clickable_hitbox()

# Emotes float up from the top right of the head. A speech balloon sits right above the head and
# would hide them, so while one is showing they float up beside the pet instead.
func _emote_anchor() -> Vector2:
	var half: Vector2 = (sprite.texture.get_size() * sprite.scale) / 2.0
	var balloon_up: bool = is_instance_valid(current_balloon) or (social != null and social.my_bubble.visible)
	if balloon_up:
		return sprite.global_position + Vector2(half.x + 20.0, -half.y * 0.2)
	return sprite.global_position + Vector2(half.x * 0.6, -half.y)

# --- 7. Stat & UI Handlers ---
func _on_name_submitted(new_name: String) -> void:
	pet_name = new_name.strip_edges()
	if pet_name.is_empty():
		pet_name = "Companion"
		
	if hover_name_label:
		hover_name_label.text = pet_name
	if name_input:
		name_input.text = pet_name
		name_input.release_focus()
		
	_update_name_and_level_layout()
	update_clickable_hitbox()
	save_game_data()
	if social:
		social.refresh_profile()  # tell the friend about the new name

func _on_stats_changed(h: float, b: float, happy: float) -> void:
	if not menu_panel.visible:
		return
	if hunger_bar:
		hunger_bar.value = h
	if boredom_bar:
		boredom_bar.value = b
	if happiness_bar:
		happiness_bar.value = happy

func _on_xp_gained(curr_xp: int, target_xp: int) -> void:
	if lvl_bar:
		lvl_bar.max_value = target_xp
		lvl_bar.value = curr_xp

func _on_level_up(new_level: int) -> void:
	if hover_lvl_label:
		hover_lvl_label.text = str(new_level)
	_update_name_and_level_layout()
	update_clickable_hitbox()

func _on_warning_received(warning_type: String, message: String) -> void:
	hover_info.visible = true
	update_clickable_hitbox()
	print("[ALERT - %s]: %s" % [warning_type.to_upper(), message])

	# A pressing need jumps the queue: say it right away (once per cooldown)
	var topic: String = "need_food" if warning_type == "hunger" else "need_play"
	var now: float = Time.get_ticks_msec() / 1000.0
	if menu_panel.visible or is_instance_valid(current_balloon):
		return
	if now - _need_last_time.get(topic, -1000.0) < NEED_COOLDOWN:
		return
	_need_last_time[topic] = now
	start_dialogue(topic)

# --- 8. Positioning Logic ---
func _reposition_hover_info() -> void:
	var spr_half_w = (sprite.texture.get_width() * sprite.scale.x) / 2.0
	var spr_half_h = (sprite.texture.get_height() * sprite.scale.y) / 2.0
	var spr_top_left = sprite.global_position - Vector2(spr_half_w, spr_half_h)
	hover_info.global_position = spr_top_left

# --- 9. Modal & Tab Switching ---
func _on_alert_button_pressed() -> void:
	if menu_panel.visible:
		close_menu()
	else:
		open_menu()

func open_menu() -> void:
	_stop_pet_motion()  # wandering stops instantly; the menu docks beside the pet where it stands
	menu_panel.visible = true

	if stats:
		_on_stats_changed(stats.hunger, stats.boredom, stats.get_happiness())
		_on_xp_gained(stats.current_xp, stats.get_xp_for_next_level())
		_update_coin_displays(stats.coins)
		_update_inventory_ui()

	_reposition_menu_panel()

	await get_tree().process_frame
	update_clickable_hitbox()

# Where the menu sits when docked beside the pet. `pet_pos` lets us ask
# "where would it dock if the pet were over there?" (used while the pet is gliding).
func _menu_dock_position(pet_pos: Vector2 = Vector2.INF) -> Vector2:
	if pet_pos == Vector2.INF:
		pet_pos = sprite.global_position
	var shift: Vector2 = pet_pos - sprite.global_position
	var screen_rect: Rect2 = _screen_rect_canvas()

	var spr_half_w: float = (sprite.texture.get_width() * sprite.scale.x) / 2.0
	var spr_half_h: float = (sprite.texture.get_height() * sprite.scale.y) / 2.0
	var spr_pos: Vector2 = pet_pos

	var panel_size: Vector2 = menu_panel.get_combined_minimum_size().max(menu_panel.size)
	var gap: float = 16.0

	# Find the true outer right edge (incorporating the ! button / hover container)
	var right_boundary: float = spr_pos.x + spr_half_w
	if is_instance_valid(alert_button) and alert_button.visible:
		right_boundary = max(right_boundary, alert_button.global_position.x + shift.x + alert_button.size.x)
	elif is_instance_valid(hover_info):
		right_boundary = max(right_boundary, hover_info.global_position.x + shift.x + hover_info.size.x)

	# --- Horizontal: Default to right (with gap); flip to left if overflowing ---
	var right_x: float = right_boundary + gap
	var left_x: float = (spr_pos.x - spr_half_w) - panel_size.x - gap
	var target_x: float = right_x

	if right_x + panel_size.x > float(screen_rect.end.x) - 10.0:
		target_x = left_x

	# --- Vertical: Default to top-aligned; flip upward if overflowing bottom ---
	var top_y: float = spr_pos.y - spr_half_h
	var target_y: float = top_y

	if top_y + panel_size.y > float(screen_rect.end.y) - 10.0:
		target_y = (spr_pos.y + spr_half_h) - panel_size.y

	# Clamp inside usable screen boundaries
	target_x = clamp(target_x, float(screen_rect.position.x) + 10.0, max(float(screen_rect.position.x) + 10.0, float(screen_rect.end.x) - panel_size.x - 10.0))
	target_y = clamp(target_y, float(screen_rect.position.y) + 10.0, max(float(screen_rect.position.y) + 10.0, float(screen_rect.end.y) - panel_size.y - 10.0))

	return Vector2(target_x, target_y)

func _reposition_menu_panel() -> void:
	if not menu_panel.visible:
		return
	_stop_menu_motion()  # a drag / re-dock takes over from any menu animation
	menu_panel.global_position = _menu_dock_position()
	menu_offset = menu_panel.global_position - sprite.global_position

func close_menu() -> void:
	_close_game_screen()  # no-op unless a game is open
	_stop_menu_motion()   # also makes sure the menu isn't left faded out / shrunk
	menu_panel.visible = false
	update_clickable_hitbox()

func _show_panel(target_panel: Control) -> void:
	for panel in content_container.get_children():
		panel.visible = (panel == target_panel)
	# Leaving the games tab ends any game in progress
	if target_panel != games_panel:
		_close_game_screen()

# --- 9b. Games (Tic Tac Toe) ---
const GAME_PERCH_OVERLAP: float = 12.0  # how far the pet sinks into the game window's top edge
const GAME_PERCH_GAP: float = 12.0      # gap when the pet has to sit beside the window instead

var ttt  # TicTacToe instance (untyped so the script still loads if the class cache is stale)
var social  # SocialManager instance (friends tab, visitor pet, gifts)
var _pending_game: String = ""          # set by dialogue (queue_game), launched when the balloon closes
var _game_opening: bool = false         # true while the pop-away / pop-in sequence is running
var _game_flow_id: int = 0              # bumped to cancel an in-progress open sequence

func _populate_games_ui() -> void:
	if not games_list:
		return
	for c in games_list.get_children():
		c.queue_free()

	# Add future games here: id -> {name, start callable}
	var games := {
		"tictactoe": {"name": "Tic Tac Toe", "start": _open_tic_tac_toe},
	}

	if games_empty_label:
		games_empty_label.visible = games.is_empty()

	for game_id in games.keys():
		var data: Dictionary = games[game_id]

		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(90, 85)

		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER

		var title_lbl = Label.new()
		title_lbl.text = data["name"]
		title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		var play_btn = Button.new()
		play_btn.text = "Play"
		play_btn.pressed.connect(data["start"])

		vbox.add_child(title_lbl)
		vbox.add_child(play_btn)
		card.add_child(vbox)
		games_list.add_child(card)

func _open_tic_tac_toe() -> void:
	if game_screen.visible or _game_opening:
		return
	_game_opening = true
	_game_flow_id += 1
	var flow: int = _game_flow_id

	# 1. The menu pops away
	_animate_menu_pop(false)
	await menu_motion_ended
	if flow != _game_flow_id or not menu_panel.visible:
		return  # closed / cancelled while we were waiting

	# 2. While it's hidden, swap to the game screen and let the layout settle
	games_container.visible = false
	game_screen.visible = true
	ttt.start_new_match(pet_name)
	await get_tree().process_frame
	await get_tree().process_frame
	if flow != _game_flow_id or not menu_panel.visible:
		return

	# 3. It pops back up in the middle of the screen
	_animate_menu_pop(true, _menu_center_position())
	await menu_motion_ended
	if flow != _game_flow_id or not menu_panel.visible:
		return

	# 4. THEN the pet slowly glides up onto the top edge of the window
	_game_opening = false
	_perch_pet_on_game_window()
	update_clickable_hitbox()

func _cancel_game_flow() -> void:
	_game_flow_id += 1
	_game_opening = false

func _close_game_screen() -> void:
	var was_opening: bool = _game_opening
	_cancel_game_flow()
	if was_opening:
		_stop_menu_motion()  # un-hide the menu if we interrupted the pop animation
	if not game_screen.visible:
		return
	ttt.stop()
	say_comment("ttt_quit", true)

	game_screen.visible = false
	games_container.visible = true

	# The menu and pet stay in the middle of the screen. The panel just changed size
	# (games list vs. game board), so let layout settle, then nudge both to the new
	# centre with the same duration + easing so they move as one.
	await get_tree().process_frame
	await get_tree().process_frame
	if not menu_panel.visible or game_screen.visible:
		return
	var new_pos: Vector2 = _menu_center_position()
	_animate_menu_to(new_pos, MENU_RECENTER_TIME)
	_glide_pet_to(_perch_target(new_pos), MENU_RECENTER_TIME, "game")
	update_clickable_hitbox()

func _perch_pet_on_game_window() -> void:
	if not menu_panel.visible or not game_screen.visible:
		return
	_glide_pet_to(_perch_target(menu_panel.global_position), GAME_GLIDE_TIME, "game")

# Where the pet should sit (centre point) when the menu's top-left corner is at `menu_pos`
func _perch_target(menu_pos: Vector2) -> Vector2:
	var spr_half: Vector2 = (sprite.texture.get_size() * sprite.scale) / 2.0
	var panel_size: Vector2 = menu_panel.get_combined_minimum_size().max(menu_panel.size)
	var panel_rect := Rect2(menu_pos, panel_size)
	var screen_rect: Rect2 = _screen_rect_canvas()

	var target: Vector2
	var above_y: float = panel_rect.position.y - spr_half.y + GAME_PERCH_OVERLAP
	if above_y - spr_half.y >= screen_rect.position.y + 10.0:
		# Sit on the top edge of the window, centered
		target = Vector2(panel_rect.get_center().x, above_y)
	else:
		# No room above (window is near the top of the screen): sit beside it
		var left_x: float = panel_rect.position.x - spr_half.x - GAME_PERCH_GAP
		var right_x: float = panel_rect.end.x + spr_half.x + GAME_PERCH_GAP
		var side_x: float = left_x if left_x - spr_half.x >= screen_rect.position.x + 10.0 else right_x
		target = Vector2(side_x, panel_rect.position.y + spr_half.y)

	var min_p: Vector2 = screen_rect.position + spr_half + Vector2(10.0, 10.0)
	var max_p: Vector2 = screen_rect.end - spr_half - Vector2(10.0, 10.0)
	target.x = clamp(target.x, min_p.x, max(min_p.x, max_p.x))
	target.y = clamp(target.y, min_p.y, max(min_p.y, max_p.y))
	return target

# Called from dialogue: `do queue_game("tictactoe")`
# The game launches once the dialogue balloon has closed.
func queue_game(game_id: String) -> void:
	_pending_game = game_id

func _launch_pending_game() -> void:
	var game_id: String = _pending_game
	_pending_game = ""
	if game_id.is_empty():
		return
	if not menu_panel.visible:
		await open_menu()
	_show_panel(games_panel)
	match game_id:
		"tictactoe":
			_open_tic_tac_toe()

# --- 9c. In-game commentary (uses the normal dialogue balloon) ---
# Lines live in friend_dialogue.dialogue ("ttt_*" titles). They are shown with the
# same balloon as every other dialogue, and close themselves after a few seconds
# (click the balloon to dismiss it sooner).
const COMMENT_COOLDOWN: float = 2.5          # minimum seconds between non-essential comments
const COMMENT_SECONDS: float = 4.0           # how long a normal comment stays up
const COMMENT_SECONDS_IMPORTANT: float = 5.5 # results / quit comments stay a bit longer

# Chance that a game event gets a comment (events not listed here never comment)
const TTT_COMMENT_CHANCE := {
	"player_move": 0.15,
	"player_block": 0.5,
	"pet_move": 0.15,
	"pet_block": 0.6,
	"pet_slip": 0.5,
	"next_you": 0.6,
	"next_pet": 0.6,
}
# These always comment, ignore the cooldown, and may replace a comment still on screen
const TTT_ALWAYS_COMMENT: Array[String] = ["start", "player_win", "pet_win", "draw", "quit"]

var comment_timer: Timer
var _comment_balloon_active: bool = false  # true while the open balloon is a game comment
var _last_comment_time: float = -100.0

func _setup_comment_timer() -> void:
	comment_timer = Timer.new()
	comment_timer.one_shot = true
	comment_timer.timeout.connect(_end_comment_balloon)
	add_child(comment_timer)

func _on_ttt_commentary(event: String) -> void:
	if event in TTT_ALWAYS_COMMENT:
		say_comment("ttt_" + event, true)
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_comment_time < COMMENT_COOLDOWN:
		return
	if randf() < TTT_COMMENT_CHANCE.get(event, 0.0):
		say_comment("ttt_" + event)

func say_comment(title: String, important: bool = false) -> void:
	if social != null and social.is_pet_busy():
		return  # a scene with the friend's pet is running: skip the comment
	if is_instance_valid(current_balloon):
		# Never interrupt a real conversation. A game comment is only replaced by an important one.
		if not (_comment_balloon_active and important):
			return
		await _close_current_balloon()
		if is_instance_valid(current_balloon):
			return  # something else opened in the meantime

	start_dialogue(title)
	if not is_instance_valid(current_balloon):
		return
	_comment_balloon_active = true
	_last_comment_time = Time.get_ticks_msec() / 1000.0
	comment_timer.start(COMMENT_SECONDS_IMPORTANT if important else COMMENT_SECONDS)

func _end_comment_balloon() -> void:
	if _comment_balloon_active and is_instance_valid(current_balloon):
		current_balloon.queue_free()  # the balloon's tree_exited handler does the cleanup

func _close_current_balloon() -> void:
	if not is_instance_valid(current_balloon):
		return
	var old: Node = current_balloon
	old.queue_free()
	await old.tree_exited

# --- 9c2. Menu animation (slide to the middle for games, slide back after) ---
signal menu_motion_ended

const MENU_POP_OUT_TIME: float = 0.2     # menu shrinks away
const MENU_POP_IN_TIME: float = 0.45     # menu pops back up (with a little overshoot)
const MENU_POP_MIN_SCALE: float = 0.05   # "gone" size (not 0, to avoid singular transforms)
const MENU_RECENTER_TIME: float = 0.6    # shared by menu + pet when re-centering after a game

var _menu_tween: Tween
var _menu_animating: bool = false

# Centre of the usable screen, nudged down a bit so the pet sitting on top still fits
func _menu_center_position() -> Vector2:
	var screen_rect: Rect2 = _screen_rect_canvas()
	var panel_size: Vector2 = menu_panel.get_combined_minimum_size().max(menu_panel.size)
	var pet_height: float = sprite.texture.get_height() * sprite.scale.y
	var pos: Vector2 = screen_rect.get_center() - panel_size / 2.0
	pos.y += (pet_height - GAME_PERCH_OVERLAP) / 2.0
	pos.x = clamp(pos.x, screen_rect.position.x + SCREEN_MARGIN, max(screen_rect.position.x + SCREEN_MARGIN, screen_rect.end.x - panel_size.x - SCREEN_MARGIN))
	pos.y = clamp(pos.y, screen_rect.position.y + pet_height + SCREEN_MARGIN, max(screen_rect.position.y + pet_height + SCREEN_MARGIN, screen_rect.end.y - panel_size.y - SCREEN_MARGIN))
	return pos

# Plain slide. Uses the same easing as the pet's glide so the two stay in sync.
func _animate_menu_to(target: Vector2, duration: float) -> void:
	_stop_menu_motion()
	_menu_animating = true
	_menu_tween = create_tween()
	_menu_tween.tween_property(menu_panel, "global_position", target, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_menu_tween.finished.connect(_on_menu_motion_finished)

# Pop animation. appear = false: shrink + fade away where it is (stays hidden afterwards).
# appear = true: jump to `target` and pop up from nothing with a slight overshoot.
func _animate_menu_pop(appear: bool, target: Vector2 = Vector2.INF) -> void:
	_stop_menu_motion()
	var panel_size: Vector2 = menu_panel.get_combined_minimum_size().max(menu_panel.size)
	menu_panel.pivot_offset = panel_size / 2.0
	var gone_scale: Vector2 = Vector2.ONE * MENU_POP_MIN_SCALE

	_menu_animating = true
	_menu_tween = create_tween().set_parallel(true)
	if appear:
		if target != Vector2.INF:
			menu_panel.global_position = target
		menu_panel.scale = gone_scale
		menu_panel.modulate.a = 0.0
		_menu_tween.tween_property(menu_panel, "scale", Vector2.ONE, MENU_POP_IN_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_menu_tween.tween_property(menu_panel, "modulate:a", 1.0, MENU_POP_IN_TIME * 0.4)
	else:
		_menu_tween.tween_property(menu_panel, "scale", gone_scale, MENU_POP_OUT_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		_menu_tween.tween_property(menu_panel, "modulate:a", 0.0, MENU_POP_OUT_TIME)
	_menu_tween.finished.connect(_on_menu_pop_finished)

func _on_menu_pop_finished() -> void:
	# Deliberately does NOT reset scale / alpha: after a pop-out the menu stays hidden
	# until the pop-in (or _stop_menu_motion) brings it back.
	_menu_animating = false
	_menu_tween = null
	update_clickable_hitbox()
	menu_motion_ended.emit()

func _on_menu_motion_finished() -> void:
	_menu_animating = false
	_menu_tween = null
	menu_panel.scale = Vector2.ONE
	update_clickable_hitbox()
	menu_motion_ended.emit()

func _stop_menu_motion() -> void:
	if _menu_tween and _menu_tween.is_valid():
		_menu_tween.kill()
	_menu_tween = null
	menu_panel.scale = Vector2.ONE
	menu_panel.modulate.a = 1.0
	if _menu_animating:
		_menu_animating = false
		menu_motion_ended.emit()

# --- 9d. Pet movement: glides + NPC-style wandering ---
signal pet_motion_ended

const WANDER_MIN_DELAY: float = 5.0    # seconds of standing around between walks
const WANDER_MAX_DELAY: float = 14.0
const WANDER_MIN_DIST: float = 80.0    # how far one walk goes
const WANDER_MAX_DIST: float = 320.0
const WANDER_SPEED: float = 70.0       # pixels per second
const GAME_GLIDE_TIME: float = 1.2     # seconds for the pet to glide up onto the game window
const SCREEN_MARGIN: float = 10.0
const MONITOR_HOP_CHANCE: float = 0.2   # chance a wander walks to another monitor (if there is one)

var wander_timer: Timer
var wander_enabled: bool = true         # switch in the Friends tab, saved with the pet
var _move_tween: Tween
var _pet_moving: bool = false
var _motion_kind: String = ""          # "wander" or "game"

func _setup_wander() -> void:
	wander_timer = Timer.new()
	wander_timer.one_shot = true
	wander_timer.timeout.connect(_on_wander_timer_timeout)
	add_child(wander_timer)
	_schedule_wander(3.0, 8.0)

func _schedule_wander(min_delay: float = WANDER_MIN_DELAY, max_delay: float = WANDER_MAX_DELAY) -> void:
	if wander_timer:
		wander_timer.start(randf_range(min_delay, max_delay))

# Turns my pet's wandering on / off. Switching it off stops a walk that is in progress.
func set_wander_enabled(on: bool) -> void:
	wander_enabled = on
	if not on and _motion_kind == "wander":
		_stop_pet_motion()
	save_game_data()

func _can_wander() -> bool:
	if not wander_enabled:
		return false
	if _pet_moving or is_dragging:
		return false
	if menu_panel.visible or game_screen.visible:
		return false
	if is_instance_valid(current_balloon) or text_prompt_open():
		return false
	if _pending_game != "" or not _pending_text.is_empty():
		return false
	if social != null and social.is_pet_busy():
		return false  # the friend's pet is playing / chatting with us, social_manager steers the pet
	# Don't wander off while the cursor is close, so the pet stays easy to click
	var dist: float = _window_mouse().distance_to(sprite.global_position)
	return dist > HOVER_DISTANCE

func _on_wander_timer_timeout() -> void:
	if _can_wander():
		_start_wander()  # the next timer is scheduled when the walk ends
	else:
		_schedule_wander(2.0, 5.0)

func _start_wander() -> void:
	# With several monitors, now and then walk over to another one
	var monitors: Array[Rect2] = _monitor_rects_canvas()
	if monitors.size() > 1 and randf() < MONITOR_HOP_CHANCE:
		var here: Rect2 = _screen_rect_canvas()
		var others: Array[Rect2] = []
		for m in monitors:
			if not m.is_equal_approx(here):
				others.append(m)
		if not others.is_empty():
			var dest: Rect2 = others[randi() % others.size()]
			var half: Vector2 = (sprite.texture.get_size() * sprite.scale) / 2.0
			var inner: Rect2 = dest.grow(-SCREEN_MARGIN)
			var hop := Vector2(
				randf_range(inner.position.x + half.x, max(inner.position.x + half.x, inner.end.x - half.x)),
				randf_range(inner.position.y + half.y, max(inner.position.y + half.y, inner.end.y - half.y)))
			var hop_dist: float = sprite.global_position.distance_to(hop)
			_glide_pet_to(hop, clamp(hop_dist / WANDER_SPEED, 1.5, 6.0), "wander")
			return
	var bounds: Rect2 = _pet_bounds()
	var dist: float = randf_range(WANDER_MIN_DIST, WANDER_MAX_DIST)
	var target: Vector2 = sprite.global_position + Vector2.from_angle(randf() * TAU) * dist
	target = Vector2(
		clamp(target.x, bounds.position.x, bounds.end.x),
		clamp(target.y, bounds.position.y, bounds.end.y)
	)
	var travel: float = sprite.global_position.distance_to(target)
	if travel < 30.0:
		_schedule_wander(1.0, 3.0)  # picked a spot against the edge, try again soon
		return
	_glide_pet_to(target, clamp(travel / WANDER_SPEED, 1.0, 5.0), "wander")

# The area the pet's centre is allowed to wander in (screen minus margins and the sprite's size)
func _pet_bounds() -> Rect2:
	var spr_half: Vector2 = (sprite.texture.get_size() * sprite.scale) / 2.0
	var area: Rect2 = get_viewport().get_visible_rect()
	var usable: Rect2 = _screen_rect_canvas()
	if usable.size.x > 0.0 and usable.size.y > 0.0:
		var inter: Rect2 = area.intersection(usable)
		if inter.size.x > 0.0 and inter.size.y > 0.0:
			area = inter
	area = area.grow(-SCREEN_MARGIN)
	return Rect2(area.position + spr_half, (area.size - spr_half * 2.0).max(Vector2.ZERO))

func _glide_pet_to(target: Vector2, duration: float, kind: String) -> void:
	_stop_pet_motion()
	if sprite.global_position.distance_to(target) < 2.0:
		sprite.global_position = target
		_reposition_hover_info()
		update_clickable_hitbox()
		return
	_pet_moving = true
	_motion_kind = kind
	_move_tween = create_tween()
	_move_tween.tween_property(sprite, "global_position", target, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_move_tween.finished.connect(_on_motion_finished)

func _on_motion_finished() -> void:
	var kind: String = _motion_kind
	_pet_moving = false
	_motion_kind = ""
	_move_tween = null
	_reposition_hover_info()
	update_clickable_hitbox()
	pet_motion_ended.emit()
	if kind == "wander":
		_schedule_wander()

# Stops any glide / wander instantly, wherever the pet currently is
func _stop_pet_motion() -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = null
	if not _pet_moving:
		return
	var kind: String = _motion_kind
	_pet_moving = false
	_motion_kind = ""
	pet_motion_ended.emit()
	if kind == "wander":
		_schedule_wander()  # resume wandering later (menu/drag/dialogue will block it until then)

# Runs every frame: keeps the hover info + click-through region following a moving pet
func _update_pet_motion() -> void:
	if _menu_animating:
		update_clickable_hitbox()
	if not _pet_moving:
		return
	# A wandering pet freezes as soon as you reach for it
	if _motion_kind == "wander" and hover_info.visible:
		_stop_pet_motion()
		return
	_reposition_hover_info()
	update_clickable_hitbox()

# --- 9e. Needs: a hungry / bored pet talks about it before any random topic ---
const NEED_HUNGER_BELOW: float = 35.0
const NEED_BORED_ABOVE: float = 60.0
const NEED_COOLDOWN: float = 900.0     # seconds (15 min) before the same need is mentioned again
var _need_last_time: Dictionary = {}

# Returns "need_food" / "need_play" (whichever is more urgent and off cooldown), or ""
func _pick_need_topic() -> String:
	var now: float = Time.get_ticks_msec() / 1000.0
	var urgency: Dictionary = {}
	if stats.hunger <= NEED_HUNGER_BELOW:
		urgency["need_food"] = (NEED_HUNGER_BELOW - stats.hunger) / NEED_HUNGER_BELOW
	if stats.boredom >= NEED_BORED_ABOVE:
		urgency["need_play"] = (stats.boredom - NEED_BORED_ABOVE) / (100.0 - NEED_BORED_ABOVE)

	var best: String = ""
	var best_urgency: float = -1.0
	for topic in urgency.keys():
		if now - _need_last_time.get(topic, -1000.0) < NEED_COOLDOWN:
			continue
		if urgency[topic] > best_urgency:
			best = topic
			best_urgency = urgency[topic]

	if not best.is_empty():
		_need_last_time[best] = now
	return best

# --- 10. Desktop Mouse Passthrough ---
# Collects one rectangle per visible object (pet, labels, menu, balloon, emotes, visitors, bubbles).
# They are joined into the passthrough polygon once per frame by _update_passthrough().
func update_clickable_hitbox() -> void:
	if is_dragging:
		return

	var rects: Array[Rect2] = []

	# My pet (more room while a hop / shake / wiggle plays)
	var spr_size: Vector2 = sprite.texture.get_size() * sprite.scale
	rects.append(pad_sprite_rect(Rect2(sprite.global_position - spr_size / 2.0, spr_size), _fx_is_active()))

	# Hover info: the container and the parts that are really there
	if hover_info.visible:
		rects.append(hover_info.get_global_rect().grow(HITBOX_PADDING))
		for c in [hover_name_label, hover_lvl_label, alert_button]:
			if is_instance_valid(c) and c.visible:
				rects.append(c.get_global_rect().grow(HITBOX_PADDING))

	if menu_panel.visible:
		var panel_size := Vector2(
			max(menu_panel.size.x, menu_panel.custom_minimum_size.x),
			max(menu_panel.size.y, menu_panel.custom_minimum_size.y)
		)
		# the pop animation overshoots the normal size, so give it extra room while it runs
		var extra: float = 40.0 if _menu_animating else 0.0
		rects.append(Rect2(menu_panel.global_position, panel_size).grow(HITBOX_PADDING + extra))

	# The balloon's real visible panel, not the root control
	var balloon_panel := _get_balloon_panel()
	if balloon_panel:
		rects.append(balloon_panel.get_global_rect().grow(HITBOX_PADDING))

	if text_prompt_open():
		rects.append(_text_panel.get_global_rect().grow(HITBOX_PADDING))

	for e in _emotes:
		if is_instance_valid(e):
			rects.append(e.get_global_rect().grow(HITBOX_PADDING))

	# The friends' pets, their name tags, emotes and speech bubbles
	if social:
		for r in social.get_click_rects():
			rects.append(r.grow(HITBOX_PADDING))

	_hit_rects = rects
	_hitbox_dirty = true
	if _debug_overlay:
		_debug_overlay.queue_redraw()

# Set DEBUG_DRAW_HITBOXES to true to see every passthrough rectangle drawn in red.
func _setup_debug_overlay() -> void:
	if not DEBUG_DRAW_HITBOXES:
		return
	_debug_overlay = Node2D.new()
	_debug_overlay.z_index = 4000
	add_child(_debug_overlay)
	_debug_overlay.draw.connect(_draw_debug_overlay)

func _draw_debug_overlay() -> void:
	for r in _hit_rects:
		var local := Rect2(_debug_overlay.to_local(r.position), r.size)
		_debug_overlay.draw_rect(local, Color(1.0, 0.0, 0.0, 0.2))
		_debug_overlay.draw_rect(local, Color(1.0, 0.0, 0.0, 0.9), false, 2.0)
