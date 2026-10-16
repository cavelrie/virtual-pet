extends Node2D
## The friend's pet as it appears on YOUR desktop.
## It's a puppet: just a sprite, a name tag and a speech bubble. It has no stats or menu.
## It never needs the friend's screen coordinates: it hangs out near your pet and changes
## behaviour through set_mode():
##   "idle"     stands around near your pet, strolls a short way every now and then
##   "together" walks right up next to your pet (chats, fights, make-ups)
##   "play"     runs around your pet in short bursts (tag and friends)
##   "away"     keeps its distance (sulking after a fight, or giving your pet space to talk to you)
##   "still"    stands exactly where it is (the friend is talking to their pet)
##   "game"     steered by pet_mover.gd (tag / hide and seek, driven from social_manager.gd)
##
## There is one of these per friend in the room. social_manager.gd creates and frees them.

const BubbleScript = preload("res://pet_bubble.gd")
const PetFx = preload("res://pet_fx.gd")
const MoverScript = preload("res://pet_mover.gd")

const IDLE_MIN_DIST: float = 130.0
const IDLE_MAX_DIST: float = 230.0
const IDLE_SPEED: float = 38.0
const REST_MIN: float = 8.0          # it stands around for a good while between strolls
const REST_MAX: float = 20.0
const TOGETHER_SPEED: float = 120.0
const PLAY_SPEED: float = 200.0
const PLAY_MIN: float = 90.0
const PLAY_MAX: float = 190.0
const AWAY_MIN: float = 320.0
const AWAY_MAX: float = 420.0
const CATCH_UP_SPEED: float = 170.0  # when your pet wandered off and it has to hurry
const TINT := Color(0.8, 0.9, 1.2)   # fallback tint (each friend gets their own hue, see set_profile)
const SLOT_ANGLE: float = 0.9        # in a group game the visitors fan out around your pet

var pet                              # the companion node (needs .sprite and ._pet_bounds())
var sprite: Sprite2D
var name_label: Label
var bubble
var display_name: String = "Friend"

var mode: String = "idle"
var arrived: bool = false            # true once it reached its spot in "together" mode
var mover = MoverScript.new()        # steering used in "game" mode
var other_getter: Callable = Callable()   # "game" mode: returns the position of the pet to chase / run from
var together_slot: int = 0           # "together" mode: 0 = right next to your pet, 1, 2... = further round it

var sweetheart: bool = false        # my pet's partner: stays closer and wears a heart on its name tag
var _level: int = 1

var dragged: bool = false           # true while the player carries this visitor around (it stops moving by itself)
var roam_enabled: bool = true       # false = it stays where it is instead of strolling / following your pet around

var _target: Vector2 = Vector2.ZERO
var _moving: bool = false
var _next_pick: float = 0.0
var _mode_until: float = 0.0
var _side: float = 1.0
var _bob: float = 0.0
var _tween: Tween
var _fx_tween: Tween

func setup(companion) -> void:
	pet = companion
	visible = false

	sprite = Sprite2D.new()
	sprite.texture = pet.sprite.texture
	sprite.scale = pet.sprite.scale
	sprite.modulate = TINT
	add_child(sprite)

	name_label = Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 4)
	add_child(name_label)

	bubble = BubbleScript.new()
	bubble.speaker_getter = func() -> String: return display_name
	add_child(bubble)

func set_profile(profile: Dictionary) -> void:
	display_name = str(profile.get("name", "Friend"))
	_level = int(profile.get("level", 1))
	# a different colour for every friend, so a crowd of identical sprites can still be told apart
	var fid: String = str(profile.get("id", ""))
	var chosen: String = str(profile.get("color", ""))
	if chosen != "" and chosen.is_valid_html_color():
		sprite.modulate = Color(chosen)   # the colour their player picked
	elif fid != "":
		sprite.modulate = Color.from_hsv(float(absi(fid.hash()) % 360) / 360.0, 0.3, 1.1)
	_update_label()

func _update_label() -> void:
	name_label.text = "%s  Lv %d%s" % [display_name, _level, "  <3" if sweetheart else ""]
	name_label.reset_size()
	_place_name_label()

func set_sweetheart(on: bool) -> void:
	if sweetheart == on:
		return
	sweetheart = on
	_update_label()

func _half_size() -> Vector2:
	return (sprite.texture.get_size() * sprite.scale) / 2.0

func _place_name_label() -> void:
	var w: float = name_label.get_minimum_size().x
	name_label.position = Vector2(-w / 2.0, -_half_size().y - 26.0)

# --- Show / hide with a little pop (same feel as the menu) ---
func appear() -> void:
	if visible:
		return
	var pet_pos: Vector2 = pet.sprite.global_position
	global_position = _clamp_to_bounds(pet_pos + Vector2.from_angle(randf() * TAU) * 170.0)
	scale = Vector2.ONE * 0.05
	visible = true
	set_mode("idle", 0.0)
	_next_pick = _now() + 3.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func disappear() -> void:
	if not visible:
		return
	bubble.hide_bubble()
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE * 0.05, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_tween.finished.connect(func(): visible = false)

func say(text: String, seconds: float = 4.0) -> void:
	if not visible:
		return   # off screen (hide and seek): nothing to show a bubble on
	bubble.say(text, seconds)

func play_fx(fx: String) -> void:
	_fx_tween = PetFx.play_fx(self, sprite, Vector2.ZERO, fx, _fx_tween)

# Where emotes should float up from (top right of the head). While a speech bubble is up it sits
# right above the head and would cover the emote, so the emote floats up beside the pet instead.
func head_global() -> Vector2:
	var half: Vector2 = _half_size()
	if bubble.visible:
		return global_position + Vector2(half.x + 20.0, -half.y * 0.2)
	return global_position + Vector2(half.x * 0.6, -half.y)

# Change what the visitor is doing. `seconds` is how long before it drifts back to "idle".
func set_mode(new_mode: String, seconds: float = 0.0) -> void:
	mode = new_mode
	_mode_until = _now() + seconds
	arrived = false
	_moving = false
	_next_pick = _now() + 1.0
	if pet == null:
		return
	if mode == "together":
		# stand on whichever side of your pet has more room
		var b: Rect2 = pet._pet_bounds()
		var pet_x: float = pet.sprite.global_position.x
		_side = 1.0 if (b.end.x - pet_x) >= (pet_x - b.position.x) else -1.0
	elif mode == "away":
		_next_pick = 0.0

# --- Movement ---
func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _clamp_to_bounds(p: Vector2) -> Vector2:
	var b: Rect2 = pet._pet_bounds()
	return Vector2(clamp(p.x, b.position.x, b.end.x), clamp(p.y, b.position.y, b.end.y))

func _pick_around(center: Vector2, min_d: float, max_d: float) -> void:
	_target = _clamp_to_bounds(center + Vector2.from_angle(randf() * TAU) * randf_range(min_d, max_d))
	_moving = true

# Moves toward _target. Returns true when it got there.
func _walk(speed: float, delta: float) -> bool:
	global_position = global_position.move_toward(_target, speed * delta)
	return global_position.distance_to(_target) < 2.0

func _process(delta: float) -> void:
	if not visible or pet == null:
		return
	var now: float = _now()
	var pet_pos: Vector2 = pet.sprite.global_position
	if mode != "idle" and now >= _mode_until:
		set_mode("idle", 0.0)

	if dragged:
		_moving = false
		_update_bob(delta)
		bubble.place_above(global_position - Vector2(0.0, _half_size().y + 28.0))
		return

	match mode:
		"together":
			var gap: float = (pet.sprite.texture.get_width() * pet.sprite.scale.x) / 2.0 + _half_size().x + 10.0
			var offset := Vector2(_side * gap, 0.0).rotated(together_slot * SLOT_ANGLE * _side)
			_target = _clamp_to_bounds(pet_pos + offset)
			_moving = not _walk(TOGETHER_SPEED, delta)
			arrived = global_position.distance_to(_target) < 8.0
		"play":
			if not _moving or now >= _next_pick:
				_pick_around(pet_pos, PLAY_MIN, PLAY_MAX)
				_next_pick = now + randf_range(0.7, 1.4)
				if randf() < 0.4:
					play_fx("hop")
			if _walk(PLAY_SPEED, delta):
				_moving = false
		"away":
			if now >= _next_pick and global_position.distance_to(pet_pos) < AWAY_MIN * 0.7:
				_pick_around(pet_pos, AWAY_MIN, AWAY_MAX)
				_next_pick = now + 3.0
			if _moving and _walk(IDLE_SPEED * 1.4, delta):
				_moving = false
		"still":
			pass
		"game":
			var before: Vector2 = global_position
			var other: Vector2 = other_getter.call() if other_getter.is_valid() else pet_pos
			global_position = mover.step(global_position, other, delta, pet._pet_bounds())
			_moving = before.distance_to(global_position) > 0.05
		_:
			_process_idle(delta, pet_pos, now)

	_update_bob(delta)
	bubble.place_above(global_position - Vector2(0.0, _half_size().y + 28.0))

# How far from my pet this visitor stands while idle. My pet's sweetheart stays right beside it.
func _idle_range() -> Vector2:
	if not sweetheart:
		return Vector2(IDLE_MIN_DIST, IDLE_MAX_DIST)
	var gap: float = (pet.sprite.texture.get_width() * pet.sprite.scale.x) / 2.0 + _half_size().x
	return Vector2(gap + 20.0, gap + 90.0)

func _process_idle(delta: float, pet_pos: Vector2, now: float) -> void:
	if not roam_enabled:
		_moving = false      # roaming is switched off: stand still, don't stroll, don't follow your pet
		return
	var span: Vector2 = _idle_range()
	var limit: float = span.y + 90.0
	var catching_up: bool = global_position.distance_to(pet_pos) > limit
	# Your pet wandered away: pick somewhere near it again and hurry over
	if catching_up and (not _moving or _target.distance_to(pet_pos) > limit - 20.0):
		_pick_around(pet_pos, span.x, span.y)
	if _moving:
		if _walk(CATCH_UP_SPEED if catching_up else IDLE_SPEED, delta):
			_moving = false
			_next_pick = now + (randf_range(REST_MIN, REST_MAX) * (0.4 if sweetheart else 1.0))
	elif now >= _next_pick:
		_pick_around(pet_pos, span.x, span.y)

# Tiny hop-walk while moving, slow breathing while standing
func _update_bob(delta: float) -> void:
	_bob += delta * (13.0 if _moving else 2.2)
	if _moving:
		sprite.position.y = -absf(sin(_bob)) * 3.0
	else:
		sprite.position.y = sin(_bob) * 1.2

# Hide and seek: the visitor vanishes off screen / comes back in from the edge
func hide_away() -> void:
	bubble.hide_bubble()
	visible = false

func emerge_at(pos: Vector2) -> void:
	global_position = pos
	scale = Vector2.ONE
	_moving = false
	visible = true

# Everything of this visitor that is VISIBLE (sprite with room for a hop, and the name tag). The window's
# passthrough region has to cover all of it or it would be clipped. Bigger than get_click_rects().
func get_visible_rects() -> Array:
	if not visible:
		return []
	var half: Vector2 = _half_size() * scale
	var fx_active: bool = _fx_tween != null and _fx_tween.is_valid() and _fx_tween.is_running()
	return [
		pet.pad_sprite_rect(Rect2(global_position - half, half * 2.0), fx_active),
		name_label.get_global_rect().grow(4.0),
	]

# Is `point` on the sprite or the name tag?
func contains_point(point: Vector2) -> bool:
	for r in get_click_rects():
		if r.has_point(point):
			return true
	return false

# Called when the player lets go of a dragged visitor: wait a moment before strolling again
func dropped() -> void:
	dragged = false
	_moving = false
	_next_pick = _now() + 3.0

# The parts of this visitor the player can click: the sprite and the name tag as two TIGHT rectangles
# (not one big box), so the empty space around a visitor stays click-through. Empty while hidden.
func get_click_rects() -> Array:
	if not visible:
		return []
	var half: Vector2 = _half_size() * scale
	return [
		Rect2(global_position - half, half * 2.0),
		name_label.get_global_rect(),
	]

# Everything that should count as "visible window area" (bounding box of sprite, name tag and bubble)
func get_global_extent() -> Rect2:
	if not visible:
		return Rect2()
	var half: Vector2 = _half_size()
	var r := Rect2(global_position - half, half * 2.0)
	r = r.merge(name_label.get_global_rect())
	if bubble.visible:
		r = r.merge(bubble.get_global_rect())
	return r
