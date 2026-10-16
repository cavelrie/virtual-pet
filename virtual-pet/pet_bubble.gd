extends Node
## Speech bubble for the friend's pet and for your pet during friend interactions.
## It uses YOUR dialogue balloon (the one Dialogue Manager is set up with), the same one companion.gd
## shows when your pet talks to you, so every bubble in the game looks the same.
##
## Same small API as before: say(), hide_bubble(), place_above(), visible, get_global_rect().
## The text is NOT written into a dialogue file. A tiny one-line dialogue is compiled once and the text
## goes in through variables, so whatever a friend sends is never read as dialogue code.

# Keep in sync with BALLOON_MIN_WIDTH in companion.gd
const BALLOON_MIN_WIDTH: float = 300.0
const SCREEN_MARGIN: float = 10.0
const TEMPLATE: String = "~ bubble\n{{bubble_name}}: {{bubble_text}}\n=> END\n"

# --- How long a bubble stays up ---------------------------------------------------------------
# A bubble used to stay up for a fixed number of seconds, however long the text was, so long lines were
# swept away before they had finished typing (or before anybody could read them). Now every bubble stays up
# for at least as long as it takes to TYPE the text out in your balloon and then READ it.
const READ_BASE: float = 0.8              # seconds before a reader gets going
const READ_SECONDS_PER_CHAR: float = 0.05 # ~20 characters per second
const AFTER_TYPING: float = 1.2           # a short beat to take it in once the last letter has appeared
const MAX_HOLD: float = 14.0
# The balloon's typing speed. These are the Dialogue Manager defaults; the real values are read from your
# balloon's DialogueLabel the first time a bubble is shown (so they match whatever you set in the editor).
static var type_step: float = 0.02        # seconds per character
static var type_pause: float = 0.3        # extra pause after . ? ! (when followed by a space or the end)
static var pause_chars: String = ".?!"

# Seconds a bubble with this text should stay up. `minimum` is the old fixed time: never shorter than that.
static func hold_time(text: String, minimum: float = 0.0) -> float:
	var n: int = text.length()
	var pauses: int = 0
	for i in n:
		if pause_chars.contains(text[i]) and (i == n - 1 or text[i + 1] == " "):
			pauses += 1
	var typing: float = n * type_step + pauses * type_pause
	var reading: float = READ_BASE + n * READ_SECONDS_PER_CHAR
	return clampf(maxf(minimum, maxf(typing + AFTER_TYPING, reading)), minimum, maxf(minimum, MAX_HOLD))

# Read by the dialogue line above (Dialogue Manager looks these up on the game states we pass in)
var bubble_name: String = ""
var bubble_text: String = ""

# Set by the owner: returns the speaker's name for the character label ("" = no name)
var speaker_getter: Callable = Callable()

var _resource: Resource
var _balloon: Node = null
var _control: Control = null
var _panel: Control = null
var _timer: Timer
var _place_calls: int = 0     # the balloon stays see-through until it has been placed (layout needs ~2 frames)

# True while a balloon is on screen (also turns false if the player clicked it away)
var visible: bool:
	get:
		return is_instance_valid(_balloon) and not _balloon.is_queued_for_deletion()

func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(hide_bubble)
	add_child(_timer)

func _exit_tree() -> void:
	hide_bubble()

func say(text: String, seconds: float = 4.0) -> void:
	seconds = hold_time(text, seconds)
	hide_bubble()
	if _resource == null:
		_resource = DialogueManager.create_resource_from_text(TEMPLATE)
	bubble_text = _safe(text)
	bubble_name = _safe(str(speaker_getter.call())) if speaker_getter.is_valid() else ""

	_balloon = DialogueManager.show_dialogue_balloon(_resource, "bubble", [self])
	if not is_instance_valid(_balloon):
		return
	_place_calls = 0
	_learn_typing_speed()

	# Same treatment companion.gd gives its balloon: a floating card instead of a full screen control
	_control = null
	for child in _balloon.get_children():
		if child is Control:
			_control = child
			break
	if _control == null and _balloon is Control:
		_control = _balloon
	if _control == null:
		return
	_control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_control.grow_horizontal = Control.GROW_DIRECTION_END
	_control.grow_vertical = Control.GROW_DIRECTION_END
	_control.mouse_filter = Control.MOUSE_FILTER_PASS
	_control.clip_contents = false
	_configure_mouse_filters(_control)
	_panel = _balloon.find_child("PanelContainer", true, false) as Control
	if _panel == null:
		_panel = _control
	_panel.custom_minimum_size.x = BALLOON_MIN_WIDTH
	_control.modulate.a = 0.0     # revealed by place_above() once it sits in the right spot
	_timer.start(seconds)

# Reads the typing speed from the balloon's DialogueLabel (Dialogue Manager's label node), if it has one
func _learn_typing_speed() -> void:
	var label: Node = _balloon.find_child("DialogueLabel", true, false)
	if label == null:
		return
	var step = label.get("seconds_per_step")
	if step != null:
		type_step = float(step)
	var pause = label.get("seconds_per_pause_step")
	if pause != null:
		type_pause = float(pause)
	var chars = label.get("pause_at_characters")
	if chars is String:
		pause_chars = chars
	elif chars is Array or chars is PackedStringArray:
		pause_chars = "".join(chars)

func hide_bubble() -> void:
	if _timer != null:
		_timer.stop()
	if is_instance_valid(_balloon):
		_balloon.queue_free()
	_balloon = null
	_control = null
	_panel = null

# The monitor (in canvas coordinates) closest to a canvas point. The window spans every monitor, so
# bubbles are kept on the monitor their pet is on. Falls back to the whole viewport.
func _monitor_rect_at(p: Vector2) -> Rect2:
	var win_pos := Vector2(DisplayServer.window_get_position())
	var inv: Transform2D = get_viewport().get_final_transform().affine_inverse()
	var best: Rect2 = get_viewport().get_visible_rect()
	var best_dist: float = INF
	for i in DisplayServer.get_screen_count():
		var usable := Rect2(DisplayServer.screen_get_usable_rect(i))
		var tl: Vector2 = inv * (usable.position - win_pos)
		var br: Vector2 = inv * (usable.end - win_pos)
		var r := Rect2(tl, br - tl)
		var nearest := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		var d: float = nearest.distance_to(p)
		if d < best_dist:
			best_dist = d
			best = r
	return best

# Centre the bubble above a point (e.g. the top of a sprite), kept inside its monitor
func place_above(anchor: Vector2, gap: float = 8.0) -> void:
	if not visible or _control == null or _panel == null:
		return
	var s: Vector2 = _panel.get_combined_minimum_size().max(_panel.size)
	var inset: Vector2 = _panel.global_position - _control.global_position
	var screen: Rect2 = _monitor_rect_at(anchor)
	var pos := Vector2(anchor.x - s.x / 2.0, anchor.y - s.y - gap)
	pos.x = clamp(pos.x, screen.position.x + SCREEN_MARGIN, max(screen.position.x + SCREEN_MARGIN, screen.end.x - s.x - SCREEN_MARGIN))
	pos.y = clamp(pos.y, screen.position.y + SCREEN_MARGIN, max(screen.position.y + SCREEN_MARGIN, screen.end.y - s.y - SCREEN_MARGIN))
	_control.global_position = pos - inset
	_place_calls += 1
	if _place_calls == 2:
		_control.modulate.a = 1.0

# The visible card, for the click-through area (empty until it has been placed)
func get_global_rect() -> Rect2:
	if not visible or _panel == null or _place_calls < 2:
		return Rect2()
	return _panel.get_global_rect()

# Friends can send any text. "[" is turned into a literal bracket so it can't become BBCode or an
# inline dialogue command ([do ...], [wait=..]).
func _safe(text: String) -> String:
	return text.replace("[", "[lb]")

func _configure_mouse_filters(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			child.mouse_filter = Control.MOUSE_FILTER_STOP
		elif child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_PASS
		_configure_mouse_filters(child)
