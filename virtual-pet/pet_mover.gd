extends RefCounted
## Movement brain for the tag / hide-and-seek games. Pure maths: hand it where this pet is and where
## the other pet is, and it hands back the next position. It is used for BOTH pets (yours and the
## visitor), so chasing and fleeing behave the same on either side.
##   stand()   do nothing (counting, waiting)
##   chase()   run at the other pet, aiming a little ahead of where it is going
##   flee()    run away across the whole screen, dodging, and slowly getting tired
##   follow()  walk through a list of points one after another (hiding off screen, searching)

enum Mode { STAND, CHASE, FLEE, FOLLOW }

var mode: int = Mode.STAND
var speed: float = 180.0
var catch_distance: float = 60.0
var elapsed: float = 0.0
var caught: bool = false       # CHASE: reached the other pet
var path_done: bool = true     # FOLLOW: reached the last point

var _path: Array = []
var _pause_time: float = 0.0
var _pause_left: float = 0.0
var _flee_target: Vector2 = Vector2.ZERO
var _flee_repick: float = 0.0
var _last_other: Vector2 = Vector2.ZERO
var _other_velocity: Vector2 = Vector2.ZERO
var _have_last: bool = false

func stand() -> void:
	mode = Mode.STAND
	path_done = true

func chase(new_speed: float) -> void:
	mode = Mode.CHASE
	speed = new_speed
	elapsed = 0.0
	caught = false
	_have_last = false
	_other_velocity = Vector2.ZERO

func flee(new_speed: float) -> void:
	mode = Mode.FLEE
	speed = new_speed
	elapsed = 0.0
	_flee_repick = 0.0

func follow(points: Array, new_speed: float, pause: float = 0.0) -> void:
	mode = Mode.FOLLOW
	speed = new_speed
	_path = points.duplicate()
	_pause_time = pause
	_pause_left = 0.0
	path_done = _path.is_empty()

# Returns where this pet should be after `delta` seconds.
func step(pos: Vector2, other: Vector2, delta: float, bounds: Rect2) -> Vector2:
	# how fast is the other pet moving? (so a chaser can aim ahead of it)
	if _have_last and delta > 0.0:
		_other_velocity = _other_velocity.lerp((other - _last_other) / delta, 0.15).limit_length(400.0)
	_last_other = other
	_have_last = true

	match mode:
		Mode.CHASE:
			return _step_chase(pos, other, delta, bounds)
		Mode.FLEE:
			return _step_flee(pos, other, delta, bounds)
		Mode.FOLLOW:
			return _step_follow(pos, delta)
	return pos

func _step_chase(pos: Vector2, other: Vector2, delta: float, bounds: Rect2) -> Vector2:
	elapsed += delta
	var dist: float = pos.distance_to(other)
	if dist <= catch_distance:
		caught = true
		return pos
	var s: float = speed * (1.0 + minf(elapsed * 0.03, 0.5))   # gets a bit faster the longer it goes on
	var lead: float = minf(dist / maxf(s, 1.0), 0.5)
	var aim: Vector2 = _clamp(other + _other_velocity * lead, bounds)
	return _clamp(pos.move_toward(aim, s * delta), bounds)

func _step_flee(pos: Vector2, other: Vector2, delta: float, bounds: Rect2) -> Vector2:
	elapsed += delta
	var tired: float = clampf(1.0 - elapsed * 0.035, 0.55, 1.0)
	_flee_repick -= delta
	if _flee_repick <= 0.0 or pos.distance_to(_flee_target) < 10.0:
		_flee_target = _pick_flee_target(pos, other, bounds)
		# when the chaser is close it changes direction more often (dodging)
		_flee_repick = randf_range(0.25, 0.5) if pos.distance_to(other) < 170.0 else randf_range(0.8, 1.5)
	return _clamp(pos.move_toward(_flee_target, speed * tired * delta), bounds)

# Looks at a few random spots on the whole screen and picks one that is far from the chaser,
# doesn't make us run past the chaser, and isn't tucked into a corner.
func _pick_flee_target(pos: Vector2, other: Vector2, bounds: Rect2) -> Vector2:
	var best: Vector2 = pos
	var best_score: float = -INF
	for i in 12:
		var c := Vector2(randf_range(bounds.position.x, bounds.end.x), randf_range(bounds.position.y, bounds.end.y))
		var far: float = c.distance_to(other)
		var past: float = other.distance_to(Geometry2D.get_closest_point_to_segment(other, pos, c))
		var edge: float = minf(minf(c.x - bounds.position.x, bounds.end.x - c.x), minf(c.y - bounds.position.y, bounds.end.y - c.y))
		var score: float = far + minf(past, 350.0) * 1.5 + minf(edge, 150.0) * 0.5 + randf() * 80.0
		if c.distance_to(pos) < 120.0:
			score -= 500.0   # too short a run to be worth it
		if score > best_score:
			best_score = score
			best = c
	return best

func _step_follow(pos: Vector2, delta: float) -> Vector2:
	if path_done:
		return pos
	if _pause_left > 0.0:
		_pause_left -= delta
		return pos
	var target: Vector2 = _path[0]
	var next: Vector2 = pos.move_toward(target, speed * delta)
	if next.distance_to(target) < 2.0:
		_path.pop_front()
		_pause_left = _pause_time
		if _path.is_empty():
			path_done = true
	return next

func _clamp(p: Vector2, bounds: Rect2) -> Vector2:
	return Vector2(clampf(p.x, bounds.position.x, bounds.end.x), clampf(p.y, bounds.position.y, bounds.end.y))
