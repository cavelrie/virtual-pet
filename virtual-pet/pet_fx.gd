extends RefCounted
## Small visual helpers shared by your pet and the visitor pet:
##  - play_fx():     hop / shake / wiggle on a sprite (uses Sprite2D.offset so it never fights with dragging)
##  - spawn_emote(): little floating "<3", "!!", ":D" labels

const EMOTES := {
	"heart": ["<3", Color(1.0, 0.45, 0.62)],
	"angry": ["!!", Color(1.0, 0.3, 0.25)],
	"sad": ["...", Color(0.6, 0.78, 1.0)],
	"happy": [":D", Color(1.0, 0.88, 0.3)],
	"spark": ["*", Color(1.0, 0.9, 0.5)],
	"think": ["?", Color(1.0, 1.0, 1.0)],
	"laugh": ["haha", Color(1.0, 0.85, 0.4)],
	"gift": ["+1", Color(0.5, 1.0, 0.6)],
}
const EMOTE_KEYS: Array = ["heart", "hearts", "angry", "sad", "happy", "spark", "think", "laugh", "gift"]
const FX_KEYS: Array = ["hop", "shake", "wiggle"]

# Plays an effect on `sprite` and returns the tween so the caller can replace it next time.
static func play_fx(owner: Node, sprite: Sprite2D, base_offset: Vector2, fx: String, old: Tween) -> Tween:
	if old != null and old.is_valid():
		old.kill()
	sprite.offset = base_offset
	sprite.rotation = 0.0
	if not FX_KEYS.has(fx):
		return null
	var s: float = maxf(sprite.scale.x, 0.01)   # offsets are in texture pixels, so undo the sprite scale
	var t: Tween = owner.create_tween()
	match fx:
		"hop":
			var h: float = 22.0 / s
			for height in [h, h * 0.55]:
				t.tween_property(sprite, "offset:y", base_offset.y - height, 0.14) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				t.tween_property(sprite, "offset:y", base_offset.y, 0.14) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		"shake":
			var d: float = 6.0 / s
			for i in 8:
				t.tween_property(sprite, "offset:x", base_offset.x + (d if i % 2 == 0 else -d), 0.045)
			t.tween_property(sprite, "offset:x", base_offset.x, 0.045)
		"wiggle":
			for angle in [0.16, -0.16, 0.12, -0.12, 0.0]:
				t.tween_property(sprite, "rotation", angle, 0.09)
	return t

# Floating emote above `at` (global position). Returns the created labels so the caller can
# include them in the click-through area while they are on screen.
static func spawn_emote(parent: Node, at: Vector2, key: String, delay: float = 0.0) -> Array:
	var made: Array = []
	if key == "hearts":
		for i in 3:
			made.append_array(spawn_emote(parent, at + Vector2((i - 1) * 24.0, -(i % 2) * 8.0), "heart", i * 0.18))
		return made
	if not EMOTES.has(key):
		return made
	var data: Array = EMOTES[key]
	var l := Label.new()
	l.text = data[0]
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", data[1])
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 80
	l.modulate.a = 0.0
	parent.add_child(l)
	l.reset_size()
	l.global_position = at - Vector2(l.size.x / 2.0, l.size.y)
	var t: Tween = l.create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_property(l, "modulate:a", 1.0, 0.12)
	t.parallel().tween_property(l, "global_position:y", l.global_position.y - 38.0, 1.5)
	t.tween_property(l, "modulate:a", 0.0, 0.35)
	t.tween_callback(l.queue_free)
	made.append(l)
	return made
