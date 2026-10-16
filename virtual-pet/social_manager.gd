extends Node
## Glue between the companion and PetNetwork. The pets run their own social life, now in a ROOM
## with any number of other pets:
##  - a "director" timer makes your pet do things with ONE other pet that is free: chat, play tag,
##    give gifts, ask to be friends, check on each other... and sometimes argue. Now and then it
##    asks EVERYONE who is free to join a game of tag or hide and seek instead
##  - nothing needs the PLAYER's permission. Your pet asks THEIR pet in speech bubbles and the
##    other pet answers (a decision based on friendship, shared tastes and a bit of luck)
##  - a friendship meter per friend is saved between sessions (user://friendships.cfg)
##  - the Friends tab lists everybody in the room and lets you nudge your pet ("go say hi")
##
## Created and set up by companion.gd. All the networking is in pet_network.gd,
## everything the pets say is in pet_chat.gd, visuals (hop / shake / emotes) are in pet_fx.gd.
##
## THE ONE RULE: a pet is in at most one thing at a time (_busy). A conversation is only ever
## between two pets. Everything that asks a pet to do something goes through an ask / answer
## handshake, and a pet that is busy answers "busy". So a third pet can never barge into a
## conversation (or a game); it can only talk to pets that are free. Scenes are only accepted from
## the pet you have agreed to do them with.
##
## How an interaction works (A = the pet that starts it, B = the other one):
##   ask-type  (befriend / gift / play / mood):
##       A says the question in its bubble and sends "ask"  ->  B thinks for a moment, answers in its
##       bubble and sends "answer"  ->  both games apply the same outcome (friendship, items, emotes)
##       -> a gift then sends "deliver", a play invitation makes A send a scripted scene.
##   scene-type (chat / fight / makeup): a silent "ask" first (just to claim B), then A writes the
##       whole script (with the outcome), sends it, and both games play it. Each game still only ever
##       changes its OWN stats / inventory.
##   group games (tag / hide and seek): A asks everybody who is free at once. Everybody that says yes
##       is claimed, A waits a few seconds for the answers, then sends ONE scene to all the yes-pets.

const VisitorScript = preload("res://visitor_pet.gd")
const BubbleScript = preload("res://pet_bubble.gd")
const PetChat = preload("res://pet_chat.gd")
const PetFx = preload("res://pet_fx.gd")
const PetMover = preload("res://pet_mover.gd")
const PetGossip = preload("res://pet_gossip.gd")   # STAGE 1: rumours, crushes, asking each other out
const PetMemory = preload("res://pet_memory.gd")   # STAGE 2: missing friends while playing alone

const BOOK_PATH: String = "user://friendships.cfg"
const START_FRIENDSHIP: float = 10.0
const SCENE_LINE_SECONDS: float = 3.6
const PROFILE_RESEND_SECONDS: float = 60.0
const THINK_TIME: float = 2.2          # how long the answering pet "thinks" before replying
const ASK_TIMEOUT: float = 14.0        # how long we wait for an answer
const FOLLOW_UP_TIMEOUT: float = 14.0  # how long we wait for the gift / play scene after saying yes
const GROUP_COLLECT_SECONDS: float = 8.0   # how long a group game's starter waits for the answers
const GROUP_PLAY_CHANCE: float = 0.3   # chance that the director asks everybody instead of one pet
const BUSY_MAX: float = 240.0          # safety net: never stay "busy" longer than this (games take ~1-2 min)
const FIRST_TICK_HOST: Vector2 = Vector2(8.0, 12.0)    # first hello after connecting (staggered so
const FIRST_TICK_GUEST: Vector2 = Vector2(20.0, 26.0)  # both pets don't start at the same moment)
# Quiet time between two things the pets do together. It is an idle game: they should feel like
# neighbours who hang out now and then, not like a talk show. Counted from the END of the last interaction.
const TICK_MIN: float = 150.0          # 2.5 minutes
const TICK_MAX: float = 360.0          # 6 minutes
const RECENT_VISIT_SECONDS: int = 900  # came back within 15 min: no "hi! nice to meet you" again
const MAX_TALKED: int = 200            # topics remembered per friend (oldest are forgotten first)
# tag / hide and seek
const TAG_RUN_SPEED: float = 220.0
const TAG_CHASE_SPEED: float = 200.0
const HIDE_RUN_SPEED: float = 300.0
const SEEK_SPEED: float = 170.0
const ASK_KINDS: Array = ["befriend", "gift", "play", "mood", "date", "rekindle"]   # the pet speaks these out loud
const SILENT_KINDS: Array = ["chat", "fight", "makeup", "gossip", "confront", "romance", "breakup"]   # only claim the other pet, then a scene follows
const DATE_THINK_TIME: float = 4.2     # being asked out is a big moment: think a little longer than usual
const BLAME_FRIENDSHIP_HIT: float = 6.0   # friendship lost with whoever spread a lie / a secret
const VENT_COOLDOWN: int = 3600        # a pet doesn't vent about the same pet to the same listener more than once an hour
const TIER_NAMES := {
	"stranger": "strangers",
	"acquaintance": "getting to know each other",
	"friend": "friends",
	"best": "best friends",
	"rival": "rivals",
	"partner": "sweethearts",
}
# Stage 3: couples
const COUPLE_TICK_FACTOR: float = 0.6     # sweethearts do things together more often (shorter quiet time)
const COUPLE_MOMENT_MIN: float = 40.0     # every so often the sweetheart snuggles up to my pet on its own
const COUPLE_MOMENT_MAX: float = 90.0

var pet
var stats
var my_bubble
var gifts_enabled: bool = true
var my_id: String = ""               # my saved id (goes in my profile)

# Everybody else in the room: peer id -> {
#   profile, fid (their saved id), visitor (the puppet node),
#   busy (they told us they're in something), talking_until (their player talks to them),
#   did_first_chat, grudge_until, needs_makeup, mood_text }
var _members: Dictionary = {}
var _selected_peer: int = 0          # who the Friends tab is looking at

# --- Friendship book (saved) ---
var _book: Dictionary = {}       # friend id -> {name, friendship, befriended, fights, met, level, last_seen, talked}

# --- UI ---
var panel: ScrollContainer
var status_label: Label
var host_btn: Button
var invite_btn: Button
var leave_btn: Button
var invite_box: VBoxContainer         # the Steam friend picker (opened by the invite button)
var invite_list: ItemList
var invite_msg: Label
var friend_box: VBoxContainer
var friend_list: ItemList
var relation_label: Label
var friendship_bar: ProgressBar
var chat_btn: Button
var play_btn: Button
var play_all_btn: Button
var gift_btn: Button
var befriend_btn: Button
var gifts_check: CheckBox
var info_label: Label
var mood_label: Label
var _list_sig: String = ""
var _say_end: Dictionary = {}        # peer id -> when their current speech bubble runs out (so nobody talks over it)

# --- Interaction state ---
var _busy: bool = false
var _scene_playing: bool = false
var _partner: int = 0                # the pet I am in a one-on-one thing with (0 = nobody)
var _pending: Dictionary = {}        # my outstanding ask: {what, item, peer, ctx}
var _group_pending: Dictionary = {}  # my outstanding "who wants to play?": {peers, answered, yes}
var _incoming_item: String = ""      # gift I said yes to and am waiting to receive
var _scene_players: Array = []       # the OTHER pets in the scene that is playing right now
var _my_talking: bool = false        # my player is talking to my pet
var _tick_timer: Timer
var _ask_timer: Timer
var _busy_timer: Timer
var _profile_timer: Timer
var _couple_timer: Timer
var _emotes: Array = []                # the VISITORS' floating emotes (my pet's live in companion.gd)
var _last_extra: Rect2 = Rect2()
var _last_click_rects: Array = []
var friends_roam: bool = true          # do the friends' pets stroll around? (applies to everybody, saved)
var wander_check: CheckBox
var friends_roam_check: CheckBox
var roam_list: VBoxContainer           # one wander checkbox per friend
var _roam_checks: Dictionary = {}      # peer id -> its CheckBox
var _roam_sig: String = ""
var _scene_id: int = 0                 # bumped whenever a scene starts or is cancelled (old coroutines stop)
# --- Stage 1: rumours / romance ---
var _rumors: Array = []                # what my pet has heard (see pet_gossip.gd new_rumor); saved in the book
var _scene_role: String = "a"          # in the scene that is playing: "a" = my pet started it, "b" = it was started with me
var _vent_last: Dictionary = {}        # "listener>about" -> unix time of the last vent (not saved)
var _my_mover = PetMover.new()         # steering for MY pet during tag / hide and seek
var _dummy_mover = PetMover.new()      # stands in for a pet that left in the middle of a game
var _my_driven: bool = false           # true while a game is steering my pet
var _other_of: Dictionary = {}         # game: peer id -> the peer it chases / runs from (0 = my pet)

func setup(companion, stats_ref, content_container: Control, button_container: Control) -> void:
	pet = companion
	stats = stats_ref
	_load_book()

	my_bubble = BubbleScript.new()
	my_bubble.speaker_getter = func() -> String: return pet.pet_name
	pet.add_child(my_bubble)

	_build_friends_panel(content_container, button_container)

	_tick_timer = _make_timer(_on_tick)
	_ask_timer = _make_timer(_on_ask_timeout)
	_busy_timer = _make_timer(_on_busy_timeout)
	_couple_timer = _make_timer(_on_couple_moment)
	_profile_timer = _make_timer(refresh_profile)
	_profile_timer.one_shot = false
	_profile_timer.wait_time = PROFILE_RESEND_SECONDS

	PetNetwork.status_changed.connect(func(_t): _refresh_all())
	PetNetwork.friend_connected.connect(_on_friend_connected)
	PetNetwork.friend_disconnected.connect(_on_friend_disconnected)
	PetNetwork.profile_received.connect(_on_profile_received)
	PetNetwork.act_received.connect(_on_act_received)
	PetNetwork.scene_received.connect(_on_scene_received)

	_refresh_all()
	# The connection may already be up if a launch argument / invite started it
	for id in PetNetwork.peers.keys():
		_on_friend_connected(int(id))

func _make_timer(callback: Callable) -> Timer:
	var t := Timer.new()
	t.one_shot = true
	t.timeout.connect(callback)
	add_child(t)
	return t

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _my_peer() -> int:
	return PetNetwork.my_id()

# =========================================================
#  The room: who is here
# =========================================================
func _profile(peer: int) -> Dictionary:
	return _members[peer]["profile"] if _members.has(peer) else {}

func _name_of(peer: int) -> String:
	return str(_profile(peer).get("name", "your friend's pet"))

func _vis(peer: int):
	return _members[peer]["visitor"] if _members.has(peer) else null

func _make_member(peer: int) -> Dictionary:
	var v = VisitorScript.new()
	pet.add_child(v)
	v.setup(pet)
	v.roam_enabled = friends_roam
	# in "game" mode the visitor steers itself towards / away from whoever _other_of says
	v.other_getter = func() -> Vector2: return _pos_of(int(_other_of.get(peer, 0)))
	var m := {
		"profile": {}, "fid": "", "visitor": v, "busy": false, "talking_until": 0.0,
		"did_first_chat": false, "grudge_until": 0.0, "needs_makeup": false, "mood_text": "",
	}
	_members[peer] = m
	return m

# Free to be asked: they are here, not in anything, and their player isn't talking to them.
# (Only a hint from their last "status" message. The pet itself has the final say and answers "busy".)
func _peer_free(peer: int) -> bool:
	if not _members.has(peer):
		return false
	var m: Dictionary = _members[peer]
	return not bool(m["busy"]) and _now() >= float(m["talking_until"])

func _free_peers() -> Array:
	var out: Array = []
	for p in _members.keys():
		if _peer_free(p):
			out.append(p)
	return out

# =========================================================
#  Friendship book
# =========================================================
func _new_rel(name: String) -> Dictionary:
	return {"name": name, "friendship": START_FRIENDSHIP, "befriended": false, "fights": 0, "met": false, "level": 0, "last_seen": 0, "talked": [],
		# Stage 1. All of these are MY pet's private feelings about that pet.
		"crush": 0.0, "dating": false, "romance_cd": 0, "blamed": false, "blame_why": "", "confided": [],
		# Stage 2: "sore" = we parted on bad terms (a make-up is still owed), "miss_last" = when my pet last talked about missing them
		"sore": false, "miss_last": 0,
		# Stage 3: "ex" = we were together and it ended ("ex_by": "me" = my pet ended it, "them" = they did);
		# "drift" = we have grown apart; "dating_since" = unix time we got together
		"ex": false, "ex_by": "", "ex_since": 0, "drift": false, "dating_since": 0}

func _load_book() -> void:
	var cfg := ConfigFile.new()
	cfg.load(BOOK_PATH)
	my_id = str(cfg.get_value("me", "id", ""))
	friends_roam = bool(cfg.get_value("me", "friends_roam", true))
	var changed: bool = false
	if my_id == "":
		my_id = "%08x%08x" % [randi(), randi()]
		changed = true
	for section in cfg.get_sections():
		if section.begins_with("friend:"):
			_book[section.substr(7)] = {
				"name": str(cfg.get_value(section, "name", "")),
				"friendship": float(cfg.get_value(section, "friendship", START_FRIENDSHIP)),
				"befriended": bool(cfg.get_value(section, "befriended", false)),
				"fights": int(cfg.get_value(section, "fights", 0)),
				"met": bool(cfg.get_value(section, "met", false)),
				"level": int(cfg.get_value(section, "level", 0)),
				"last_seen": int(cfg.get_value(section, "last_seen", 0)),
				"talked": Array(cfg.get_value(section, "talked", [])),
				"crush": float(cfg.get_value(section, "crush", 0.0)),
				"dating": bool(cfg.get_value(section, "dating", false)),
				"romance_cd": int(cfg.get_value(section, "romance_cd", 0)),
				"blamed": bool(cfg.get_value(section, "blamed", false)),
				"blame_why": str(cfg.get_value(section, "blame_why", "")),
				"confided": Array(cfg.get_value(section, "confided", [])),
				"sore": bool(cfg.get_value(section, "sore", false)),
				"miss_last": int(cfg.get_value(section, "miss_last", 0)),
				"ex": bool(cfg.get_value(section, "ex", false)),
				"ex_by": str(cfg.get_value(section, "ex_by", "")),
				"ex_since": int(cfg.get_value(section, "ex_since", 0)),
				"drift": bool(cfg.get_value(section, "drift", false)),
				"dating_since": int(cfg.get_value(section, "dating_since", 0)),
			}
	# rumours: forget the old and the settled ones
	_rumors = []
	var raw_rumors = cfg.get_value("me", "rumors", [])
	if raw_rumors is Array:
		var now: int = int(Time.get_unix_time_from_system())
		for r in raw_rumors:
			if r is Dictionary and r.has("id") and r.has("kind") and not bool(r.get("done", false)) \
					and now - int(r.get("heard", 0)) < PetGossip.RUMOR_MAX_AGE:
				_rumors.append(r)
	if changed:
		_save_book()

func _save_book() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("me", "id", my_id)
	cfg.set_value("me", "friends_roam", friends_roam)
	cfg.set_value("me", "rumors", _rumors)
	for id in _book.keys():
		var r: Dictionary = _book[id]
		var section: String = "friend:%s" % id
		cfg.set_value(section, "name", r["name"])
		cfg.set_value(section, "friendship", r["friendship"])
		cfg.set_value(section, "befriended", r["befriended"])
		cfg.set_value(section, "fights", r["fights"])
		cfg.set_value(section, "met", r["met"])
		cfg.set_value(section, "level", r["level"])
		cfg.set_value(section, "last_seen", r["last_seen"])
		cfg.set_value(section, "talked", r["talked"])
		cfg.set_value(section, "crush", r["crush"])
		cfg.set_value(section, "dating", r["dating"])
		cfg.set_value(section, "romance_cd", r["romance_cd"])
		cfg.set_value(section, "blamed", r["blamed"])
		cfg.set_value(section, "blame_why", r["blame_why"])
		cfg.set_value(section, "confided", r["confided"])
		cfg.set_value(section, "sore", r["sore"])
		cfg.set_value(section, "miss_last", r["miss_last"])
		cfg.set_value(section, "ex", r["ex"])
		cfg.set_value(section, "ex_by", r["ex_by"])
		cfg.set_value(section, "ex_since", r["ex_since"])
		cfg.set_value(section, "drift", r["drift"])
		cfg.set_value(section, "dating_since", r["dating_since"])
	cfg.save(BOOK_PATH)

# That pet's entry (a throw-away default if we don't know them)
func _rel(peer: int) -> Dictionary:
	var fid: String = str(_members[peer]["fid"]) if _members.has(peer) else ""
	if fid == "":
		return _new_rel("")
	if not _book.has(fid):
		_book[fid] = _new_rel(_name_of(peer))
	return _book[fid]

func _friendship(peer: int) -> float:
	return float(_rel(peer)["friendship"])

func _change_friendship(peer: int, delta: float) -> void:
	if not _members.has(peer):
		return
	var r: Dictionary = _rel(peer)
	r["friendship"] = clampf(float(r["friendship"]) + delta, 0.0, 100.0)
	_save_book()
	_refresh_all()

func _set_befriended(peer: int, value: bool) -> void:
	if not _members.has(peer):
		return
	var r: Dictionary = _rel(peer)
	r["befriended"] = value
	if not value:
		r["dating"] = false   # no longer friends = no longer together
	_save_book()
	_sync_sweetheart(peer)
	_refresh_all()

# =========================================================
#  STAGE 1 helpers: ids, crushes, rumours
# =========================================================
func _now_unix() -> int:
	return int(Time.get_unix_time_from_system())

func _fid_of(peer: int) -> String:
	return str(_members[peer]["fid"]) if _members.has(peer) else ""

func _peer_of_fid(fid: String) -> int:
	for p in _members.keys():
		if str(_members[p]["fid"]) == fid:
			return int(p)
	return 0

# The pet my pet is going out with ("" = nobody). Only one at a time.
func _partner_fid() -> String:
	for id in _book.keys():
		if bool(_book[id]["dating"]):
			return str(id)
	return ""

func _is_real_pet(id: String) -> bool:
	return not id.begins_with("debug:")   # the debug "ghost" is not somebody the pets know

func _known_people(exclude: Array = []) -> Array:
	var out: Array = []
	for id in _book.keys():
		if not (id in exclude) and str(_book[id]["name"]) != "" and id != my_id and _is_real_pet(str(id)):
			out.append({"fid": str(id), "name": str(_book[id]["name"])})
	return out

func _set_dating(peer: int, value: bool) -> void:
	if not _members.has(peer):
		return
	var r: Dictionary = _rel(peer)
	r["dating"] = value
	if value:
		r["dating_since"] = _now_unix()
		r["ex"] = false
		r["drift"] = false
		if _couple_timer.is_stopped():
			_couple_timer.start(randf_range(20.0, 40.0))
	else:
		r["dating_since"] = 0
	_save_book()
	_sync_sweetheart(peer)
	refresh_profile()   # everybody hears who my pet is going out with (or that it is single again)

# The visitor of my pet's partner wears a heart on its name tag and stays close
func _sync_sweetheart(peer: int) -> void:
	var v = _vis(peer)
	if v != null:
		v.set_sweetheart(bool(_rel(peer)["dating"]))

# The relationship with this pet is over. by_me = my pet ended it. crush_cap = what is left of the crush.
func _mark_ex(peer: int, by_me: bool, crush_cap: float) -> void:
	if not _members.has(peer):
		return
	var r: Dictionary = _rel(peer)
	r["dating"] = false
	r["dating_since"] = 0
	r["drift"] = false
	r["ex"] = true
	r["ex_by"] = "me" if by_me else "them"
	r["ex_since"] = _now_unix()
	r["crush"] = minf(float(r["crush"]), crush_cap)
	_save_book()
	_sync_sweetheart(peer)
	refresh_profile()

# A new couple, or exes who got back together
func _get_together(peer: int, again: bool) -> void:
	_set_befriended(peer, true)
	_set_dating(peer, true)
	_change_crush(peer, 12.0 if again else 15.0)
	_change_friendship(peer, maxf(0.0, 60.0 - _friendship(peer)))
	_celebrate(peer)
	_set_info("%s and %s are %s!" % [pet.pet_name, _name_of(peer), "back together" if again else "together now"])

func _change_crush(peer: int, delta: float) -> void:
	if not _members.has(peer):
		return
	var r: Dictionary = _rel(peer)
	r["crush"] = clampf(float(r["crush"]) + delta, 0.0, 100.0)
	_save_book()

# A crush only grows between real friends (and couples)
func _crush_allowed(peer: int) -> bool:
	var r: Dictionary = _rel(peer)
	if bool(r["dating"]):
		return true
	var taken_by: String = _partner_fid()
	if taken_by != "" and taken_by != _fid_of(peer):
		return false   # my pet only has eyes for its sweetheart
	return bool(r["befriended"]) and float(r["friendship"]) >= 35.0

func _crush_after_scene(kind: String, peer: int) -> void:
	if not PetGossip.CRUSH_BASE.has(kind) or not _crush_allowed(peer):
		return
	var r: Dictionary = _rel(peer)
	_change_crush(peer, PetGossip.crush_gain(kind, build_profile(), _profile(peer), float(r["friendship"])))
	if float(r["crush"]) >= PetGossip.CRUSH_FELT:
		_emote_mine("heart")   # a little hint that my pet is smitten

func _romance_text(peer: int) -> String:
	var r: Dictionary = _rel(peer)
	if bool(r["dating"]):
		return "\ntogether <3"
	if bool(r["ex"]):
		return "\nexes" + ("... still thinking about them" if float(r["crush"]) >= PetGossip.CRUSH_FELT else "")
	if float(r["crush"]) >= PetGossip.CRUSH_FELT:
		return "\n%s has a crush on them..." % pet.pet_name
	return ""

# --- rumours ---
func _add_rumor(r: Dictionary) -> void:
	# the same story heard again: refresh it instead of keeping two copies
	for old in _rumors:
		if old["kind"] == r["kind"] and old["subj"] == r["subj"] and old["about"] == r["about"] and not bool(old["done"]):
			old["heard"] = r["heard"]
			old["twisted"] = bool(old["twisted"]) or bool(r["twisted"])
			_save_book()
			return
	_rumors.append(r)
	while _rumors.size() > PetGossip.MAX_RUMORS:
		_rumors.pop_front()
	_save_book()

# How much does my pet believe it? Trusts the teller, defends its own friends.
func _belief(w: Dictionary, from_fid: String) -> bool:
	var p: float = 0.65
	if _book.has(from_fid):
		p += (float(_book[from_fid]["friendship"]) - 40.0) / 200.0
	var subj: String = str(w["subj"])
	if _book.has(subj):
		p -= maxf(0.0, float(_book[subj]["friendship"]) - 50.0) / 150.0
	if bool(w.get("secret", false)):
		p += 0.15
	return randf() < clampf(p, 0.15, 0.92)

func _store_gossip(w: Dictionary, teller: int) -> void:
	if w.is_empty() or str(w["subj"]) == my_id:
		return
	var from_fid: String = _fid_of(teller)
	_add_rumor(PetGossip.receive(w, from_fid, _name_of(teller), _now_unix(), _belief(w, from_fid)))

func _mark_told(rumor_id: String, listener_fid: String) -> void:
	for r in _rumors:
		if str(r["id"]) == rumor_id and not (listener_fid in r["told"]):
			r["told"].append(listener_fid)
	_save_book()

# The confrontation is over: this story (and any copy of it) is settled
func _resolve_rumor(rumor_id: String) -> void:
	var key: Dictionary = {}
	for r in _rumors:
		if str(r["id"]) == rumor_id:
			key = r
	for r in _rumors:
		if str(r["id"]) == rumor_id or (not key.is_empty() and r["kind"] == key["kind"] and r["subj"] == key["subj"] and r["about"] == key["about"]):
			r["done"] = true
	_rumors = _rumors.filter(func(r): return not bool(r["done"]))
	_save_book()

func _blame(fid: String, why: String) -> void:
	if fid == "" or fid == my_id or not _book.has(fid):
		return
	var r: Dictionary = _book[fid]
	r["blamed"] = true
	r["blame_why"] = why
	r["friendship"] = clampf(float(r["friendship"]) - BLAME_FRIENDSHIP_HIT, 0.0, 100.0)
	_save_book()

# What would my pet confront `peer` about right now? {} = nothing.
#   spreader : they spread a lie / my secret
#   insult / crush : a believed rumour that THEY said / feel something about ME
#   jealous : a believed rumour that they like MY PARTNER
func _plan_confront(peer: int) -> Dictionary:
	var fid: String = _fid_of(peer)
	if fid == "":
		return {}
	var rel: Dictionary = _rel(peer)
	if bool(rel["blamed"]):
		return {"mode": "spreader", "why": str(rel["blame_why"]) if str(rel["blame_why"]) != "" else "lie", "target_fid": fid}
	var now: int = _now_unix()
	var partner: String = _partner_fid()
	for r in _rumors:
		if bool(r["done"]) or not bool(r["believed"]) or str(r["subj"]) != fid or now - int(r["heard"]) < PetGossip.BROOD_SECONDS:
			continue
		if str(r["about"]) == my_id and not (fid == partner and r["kind"] == "crush"):
			return {"mode": "insult" if r["kind"] == "insult" else "crush", "rumor": r}
		if r["kind"] == "crush" and partner != "" and fid == partner and str(r["about"]) != my_id:
			return {"mode": "cheater", "rumor": r, "third_name": str(r["about_name"])}
		if r["kind"] == "crush" and partner != "" and str(r["about"]) == partner:
			return {"mode": "jealous", "rumor": r, "partner_name": str(r["about_name"])}
	return {}

# Why would my pet end it with its sweetheart right now? "" = no reason.
#   drifted : we have been apart for so long that we grew apart (set when they came back)
#   fading  : friendship has sunk too low for a couple
func _plan_breakup(peer: int) -> String:
	var fid: String = _fid_of(peer)
	if fid == "" or _partner_fid() != fid:
		return ""
	var r: Dictionary = _rel(peer)
	if not bool(r["dating"]):
		return ""
	if bool(r["drift"]):
		return "drifted"
	if float(r["friendship"]) < PetGossip.BREAKUP_FRIENDSHIP:
		return "fading"
	return ""

func _tell_plan(idx: int, peer: int) -> Dictionary:
	var r: Dictionary = _rumors[idx]
	var lfid: String = _fid_of(peer)
	var hearsay: bool = str(r["from"]) != str(r["subj"])
	var told: Dictionary = PetGossip.twist(r, lfid, _name_of(peer), hearsay, _known_people([lfid]))
	return {"mode": "tell", "rumor": told, "src_id": str(r["id"]), "me_fid": my_id, "you_fid": lfid}

# What could my pet gossip about with `peer`? {} = nothing.
#   tell    : pass on a rumour it heard (may get twisted on the way)
#   confide : a real friend gets to hear about my crush
#   vent    : complain about somebody it doesn't like
func _plan_gossip(peer: int) -> Dictionary:
	var lfid: String = _fid_of(peer)
	if lfid == "":
		return {}
	var tell_idx: int = PetGossip.pick_rumor(_rumors, lfid, _now_unix())
	if tell_idx >= 0 and randf() < 0.6:
		return _tell_plan(tell_idx, peer)
	var fr: float = _friendship(peer)
	if fr >= 45.0 and bool(_rel(peer)["befriended"]) and _partner_fid() == "":
		for id in _book.keys():
			var rr: Dictionary = _book[id]
			if id == lfid or id == my_id or not _is_real_pet(str(id)) or str(rr["name"]) == "" or float(rr["crush"]) < PetGossip.CRUSH_FELT or bool(rr["dating"]):
				continue
			if lfid in rr["confided"]:
				continue
			return {"mode": "confide", "about_fid": str(id), "about_name": str(rr["name"]), "me_fid": my_id, "you_fid": lfid}
	if fr >= 30.0:
		for id in _book.keys():
			var rv: Dictionary = _book[id]
			if id == lfid or id == my_id or not _is_real_pet(str(id)) or str(rv["name"]) == "":
				continue
			if float(rv["friendship"]) < 30.0 and (int(rv["fights"]) > 0 or float(rv["friendship"]) < 20.0):
				if _now_unix() - int(_vent_last.get("%s>%s" % [lfid, id], 0)) > VENT_COOLDOWN:
					return {"mode": "vent", "about_fid": str(id), "about_name": str(rv["name"]), "me_fid": my_id, "you_fid": lfid}
	if tell_idx >= 0:
		return _tell_plan(tell_idx, peer)
	return {}

func _plan_for(action: String, peer: int) -> Dictionary:
	match action:
		"gossip":
			return _plan_gossip(peer)
		"confront":
			return _plan_confront(peer)
	return {}

func _tier(peer: int) -> String:
	var r: Dictionary = _rel(peer)
	var fr: float = float(r["friendship"])
	if bool(r["dating"]):
		return "partner"
	if bool(r["befriended"]):
		return "best" if fr >= 85.0 else "friend"
	if int(r["fights"]) > 0 and fr < 15.0:
		return "rival"
	return "acquaintance" if fr >= 20.0 else "stranger"

# =========================================================
#  STAGE 2: my pet remembers the friends it met (singleplayer talk + "invite them" nudge)
#  companion.gd asks peek_missed_friend() when it picks what to say to its player. Nothing here
#  touches the network except the invite flow, which only opens a Steam room / the invite dialog.
# =========================================================
# How my pet feels about a friend: "dating" | "mad" | "crush" | "best" | "friend" | "met" | "" (nothing special)
func _miss_kind(r: Dictionary) -> String:
	var fr: float = float(r["friendship"])
	if bool(r["dating"]):
		return "dating"
	if bool(r["sore"]) or bool(r["blamed"]):
		return "mad"
	if bool(r["befriended"]):
		if float(r["crush"]) >= PetGossip.CRUSH_FELT:
			return "crush"
		return "best" if fr >= 85.0 else "friend"
	if bool(r["met"]) and fr >= 20.0:
		return "met"
	return ""

# Friends that are NOT in the room right now and that my pet has been missing for long enough.
# respect_cooldown = false is for the Friends tab (it shows who is missed, however recently it was mentioned).
func _missed_candidates(respect_cooldown: bool) -> Array:
	var out: Array = []
	var now: int = _now_unix()
	for id in _book.keys():
		var fid: String = str(id)
		var r: Dictionary = _book[fid]
		if fid == my_id or not _is_real_pet(fid) or str(r["name"]) == "" or _peer_of_fid(fid) != 0:
			continue
		var last: int = int(r["last_seen"])
		if last <= 0:
			continue
		var kind: String = _miss_kind(r)
		if kind == "":
			continue
		var away: int = now - last
		if away < int(PetMemory.MIN_AWAY[kind]):
			continue
		if respect_cooldown and now - int(r["miss_last"]) < int(PetMemory.COOLDOWN[kind]):
			continue
		out.append({"fid": fid, "name": str(r["name"]), "kind": kind, "away": away, "level": int(r["level"])})
	return out

# One friend my pet could bring up right now ({} = nobody). More attached = more likely.
func peek_missed_friend() -> Dictionary:
	var list: Array = _missed_candidates(true)
	if list.is_empty():
		return {}
	var total: float = 0.0
	for c in list:
		total += float(PetMemory.WEIGHT[c["kind"]])
	var roll: float = randf() * total
	for c in list:
		roll -= float(PetMemory.WEIGHT[c["kind"]])
		if roll < 0.0:
			return c
	return list[0]

# companion.gd calls this when it really starts talking about that friend (starts their cooldown)
func mark_missed(fid: String) -> void:
	if _book.has(fid):
		_book[fid]["miss_last"] = _now_unix()
		_save_book()

# Friends tab, while nobody is here: "<pet> misses <name>."
func _missing_text() -> String:
	var best: Dictionary = {}
	for c in _missed_candidates(false):
		if c["kind"] == "met" or c["kind"] == "mad":
			continue
		if best.is_empty() or float(PetMemory.WEIGHT[c["kind"]]) > float(PetMemory.WEIGHT[best["kind"]]):
			best = c
	if best.is_empty():
		return ""
	return "%s misses %s. invite their human over?" % [pet.pet_name, str(best["name"])]

# "yes, let's invite them!" in the singleplayer talk: opens a room if there isn't one, then shows the Steam
# friend picker in the Friends tab (the player picks the friend's human there).
var _invite_busy: bool = false
func start_invite_flow(who: String = "") -> void:
	if _invite_busy:
		return
	var hint: String = "pick %s's human in the invite list!" % who if who != "" else "pick a friend in the invite list!"
	if PetNetwork.lobby_id != 0:
		_open_invite_box(hint)
		return
	if not PetNetwork.steam_ok:
		_set_info("steam isn't running, so i can't invite anybody right now.")
		return
	_invite_busy = true
	_set_info("opening a room first...")
	PetNetwork.host_steam()
	var waited: float = 0.0
	while PetNetwork.lobby_id == 0 and waited < 8.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	_invite_busy = false
	if PetNetwork.lobby_id != 0:
		_open_invite_box(hint)
	else:
		_set_info("couldn't open a room. try the host room button.")

# =========================================================
#  UI (Friends tab)
# =========================================================
func _build_friends_panel(content_container: Control, button_container: Control) -> void:
	# The tab is a ScrollContainer (so it fits the menu however long the content gets); everything
	# goes into `content`, the VBoxContainer inside it.
	panel = ScrollContainer.new()
	panel.name = "friends panel"
	panel.visible = false
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content_container.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	panel.add_child(content)

	status_label = _make_label("")
	content.add_child(status_label)

	var row := HBoxContainer.new()
	content.add_child(row)
	host_btn = _make_button("host room", func(): PetNetwork.host_steam())
	invite_btn = _make_button("invite", _toggle_invite_box)
	leave_btn = _make_button("leave", func(): PetNetwork.leave())
	row.add_child(host_btn)
	row.add_child(invite_btn)
	row.add_child(leave_btn)

	# Steam friend picker: works without the Steam overlay (the overlay's own invite window only opens when the
	# game was started through Steam). Double-click a friend, or select one and press "send invite".
	invite_box = VBoxContainer.new()
	invite_box.add_theme_constant_override("separation", 4)
	invite_box.visible = false
	content.add_child(invite_box)
	invite_box.add_child(_make_label("steam friends online (double-click to invite):"))
	invite_list = ItemList.new()
	invite_list.custom_minimum_size = Vector2(240.0, 110.0)
	invite_list.select_mode = ItemList.SELECT_SINGLE
	invite_list.item_activated.connect(_send_invite_to)
	invite_box.add_child(invite_list)
	var invite_row := HBoxContainer.new()
	invite_box.add_child(invite_row)
	invite_row.add_child(_make_button("send invite", _send_invite_selected))
	invite_row.add_child(_make_button("refresh", _fill_invite_list))
	invite_row.add_child(_make_button("steam window", func(): PetNetwork.invite_friend()))
	invite_msg = _make_label("")
	invite_box.add_child(invite_msg)

	wander_check = CheckBox.new()
	wander_check.text = "my pet wanders around"
	wander_check.button_pressed = pet.wander_enabled
	wander_check.toggled.connect(func(on: bool): pet.set_wander_enabled(on))
	content.add_child(wander_check)

	friend_box = VBoxContainer.new()
	friend_box.add_theme_constant_override("separation", 6)
	friend_box.visible = false
	content.add_child(friend_box)

	# Who is in the room. (An ItemList, not a drop-down: a drop-down opens its own little window,
	# which the click-through window would swallow.)
	friend_list = ItemList.new()
	friend_list.custom_minimum_size = Vector2(240.0, 84.0)
	friend_list.select_mode = ItemList.SELECT_SINGLE
	friend_list.item_selected.connect(func(i: int):
		_selected_peer = int(friend_list.get_item_metadata(i))
		_refresh_all())
	friend_box.add_child(friend_list)

	relation_label = _make_label("")
	friend_box.add_child(relation_label)
	friendship_bar = ProgressBar.new()
	friendship_bar.max_value = 100.0
	friendship_bar.show_percentage = false
	friendship_bar.custom_minimum_size.y = 12.0
	friend_box.add_child(friendship_bar)

	var nudge_label := _make_label("your pets decide what to do on their own. you can nudge yours:")
	friend_box.add_child(nudge_label)

	var nudge_row := HBoxContainer.new()
	friend_box.add_child(nudge_row)
	chat_btn = _make_button("chat", func(): _nudge("chat"))
	play_btn = _make_button("play", func(): _nudge("play"))
	gift_btn = _make_button("give gift", func(): _nudge("gift"))
	befriend_btn = _make_button("be friends?", func(): _nudge("befriend"))
	nudge_row.add_child(chat_btn)
	nudge_row.add_child(play_btn)
	nudge_row.add_child(gift_btn)
	nudge_row.add_child(befriend_btn)

	play_all_btn = _make_button("play with everyone", func(): _nudge_all())
	friend_box.add_child(play_all_btn)

	gifts_check = CheckBox.new()
	gifts_check.text = "my pet may give gifts from my inventory"
	gifts_check.button_pressed = gifts_enabled
	gifts_check.toggled.connect(func(on: bool): gifts_enabled = on)
	friend_box.add_child(gifts_check)

	friends_roam_check = CheckBox.new()
	friends_roam_check.text = "all friends' pets wander around"
	friends_roam_check.button_pressed = friends_roam
	friends_roam_check.toggled.connect(func(on: bool):
		friends_roam = on
		for p in _members.keys():
			_members[p]["visitor"].roam_enabled = on
		_save_book()
		_refresh_all())
	friend_box.add_child(friends_roam_check)

	# One wander toggle for EVERY friend in the room (rebuilt when somebody joins / leaves / renames)
	roam_list = VBoxContainer.new()
	roam_list.add_theme_constant_override("separation", 2)
	friend_box.add_child(roam_list)

	info_label = _make_label("")
	friend_box.add_child(info_label)
	mood_label = _make_label("")
	friend_box.add_child(mood_label)

	var tab_button := Button.new()
	tab_button.text = "friends"
	button_container.add_child(tab_button)
	tab_button.pressed.connect(pet._show_panel.bind(panel))

func _open_invite_box(hint: String) -> void:
	invite_box.visible = true
	_fill_invite_list()
	_set_info(hint)

func _toggle_invite_box() -> void:
	invite_box.visible = not invite_box.visible
	if invite_box.visible:
		_fill_invite_list()

func _fill_invite_list() -> void:
	invite_list.clear()
	var shown: int = 0
	for f in PetNetwork.get_steam_friends():
		if not bool(f["online"]):
			continue
		var idx: int = invite_list.add_item(str(f["name"]))
		invite_list.set_item_metadata(idx, int(f["id"]))
		shown += 1
	if PetNetwork.lobby_id == 0:
		invite_msg.text = "open a room first (host room)."
	elif shown == 0:
		invite_msg.text = "none of your steam friends are online right now."
	else:
		invite_msg.text = ""

func _send_invite_selected() -> void:
	var picked: PackedInt32Array = invite_list.get_selected_items()
	if picked.is_empty():
		invite_msg.text = "pick a friend first."
		return
	_send_invite_to(picked[0])

func _send_invite_to(index: int) -> void:
	var steam_id: int = int(invite_list.get_item_metadata(index))
	var friend_name: String = invite_list.get_item_text(index)
	if PetNetwork.invite_steam_friend(steam_id):
		invite_msg.text = "invite sent to %s!" % friend_name
	else:
		invite_msg.text = "couldn't invite %s. is the room open?" % friend_name

func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 240.0
	return l

func _make_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	return b

func _refresh_all() -> void:
	if status_label == null:
		return
	var connected: bool = PetNetwork.is_connected_to_friend()
	var count: int = _members.size()
	if count > 0:
		status_label.text = "hanging out with %s" % ("1 pet" if count == 1 else "%d pets" % count)
	else:
		status_label.text = PetNetwork.status
		var missing: String = _missing_text()
		if missing != "":
			status_label.text += "\n" + missing
	friend_box.visible = count > 0
	host_btn.disabled = connected or PetNetwork.lobby_id != 0
	invite_btn.disabled = PetNetwork.lobby_id == 0 or PetNetwork.peers.size() >= PetNetwork.MAX_PLAYERS - 1
	if PetNetwork.lobby_id == 0:
		invite_box.visible = false
	_rebuild_friend_list()

	wander_check.set_pressed_no_signal(pet.wander_enabled)
	friends_roam_check.set_pressed_no_signal(friends_roam)
	_refresh_roam_list()

	var me_free: bool = not _busy and not _scene_playing
	var sel_ok: bool = me_free and _peer_free(_selected_peer)
	chat_btn.disabled = not sel_ok
	play_btn.disabled = not sel_ok
	gift_btn.disabled = not sel_ok
	befriend_btn.disabled = not sel_ok or bool(_rel(_selected_peer)["befriended"])
	play_all_btn.disabled = not me_free or _free_peers().is_empty()
	if _members.has(_selected_peer):
		var fr: float = _friendship(_selected_peer)
		relation_label.text = "%s: %s (%d/100)%s" % [_name_of(_selected_peer), TIER_NAMES[_tier(_selected_peer)], int(fr), _romance_text(_selected_peer)]
		friendship_bar.value = fr
		mood_label.text = str(_members[_selected_peer]["mood_text"])
	else:
		relation_label.text = ""
		mood_label.text = ""

# One "<name>'s pet wanders around" checkbox per friend. Only rebuilt when the set of friends / names
# changes; otherwise the boxes just follow each visitor's roam_enabled.
func _refresh_roam_list() -> void:
	var sig: String = ""
	for p in _members.keys():
		sig += "%d:%s;" % [p, _name_of(p)]
	if sig != _roam_sig:
		_roam_sig = sig
		for c in roam_list.get_children():
			roam_list.remove_child(c)
			c.queue_free()
		_roam_checks.clear()
		for p in _members.keys():
			var peer: int = int(p)
			var cb := CheckBox.new()
			cb.text = "%s's pet wanders around" % _name_of(peer)
			cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cb.custom_minimum_size.x = 240.0
			cb.toggled.connect(func(on: bool):
				var v = _vis(peer)
				if v != null:
					v.roam_enabled = on
				_refresh_all())
			roam_list.add_child(cb)
			_roam_checks[peer] = cb
	for p in _roam_checks.keys():
		var v = _vis(int(p))
		if v != null:
			_roam_checks[p].set_pressed_no_signal(v.roam_enabled)

# The list only gets rebuilt when something in it changed (rebuilding every refresh would flicker)
func _rebuild_friend_list() -> void:
	var sig: String = "sel%d|" % _selected_peer
	for p in _members.keys():
		sig += "%d:%s:%d:%s;" % [p, _name_of(p), int(_profile(p).get("level", 1)), str(_peer_free(p))]
	if sig == _list_sig:
		return
	_list_sig = sig
	friend_list.clear()
	var select_idx: int = -1
	for p in _members.keys():
		var idx: int = friend_list.add_item("%s (lv %d)%s" % [_name_of(p), int(_profile(p).get("level", 1)), "" if _peer_free(p) else "  - busy"])
		friend_list.set_item_metadata(idx, p)
		if not _peer_free(p):
			friend_list.set_item_custom_fg_color(idx, Color(1.0, 1.0, 1.0, 0.5))
		if p == _selected_peer:
			select_idx = idx
	if select_idx == -1 and friend_list.item_count > 0:
		select_idx = 0
		_selected_peer = int(friend_list.get_item_metadata(0))
	if select_idx >= 0:
		friend_list.select(select_idx)

func _set_info(text: String) -> void:
	if info_label != null:
		info_label.text = text

# =========================================================
#  Per-frame upkeep (bubbles, click-through area)
# =========================================================
func _process(delta: float) -> void:
	# a game (tag / hide and seek) is steering my pet; let go while the player drags it or plays a game
	if _my_driven and not pet.is_dragging and not pet.game_screen.visible:
		_drive_my_pet(delta)
	if my_bubble.visible:
		var half_h: float = (pet.sprite.texture.get_height() * pet.sprite.scale.y) / 2.0
		my_bubble.place_above(pet.sprite.global_position - Vector2(0.0, half_h + 10.0))
	# only speech bubbles are clickable now, so only rebuild the click areas when one of them changed
	var rects: Array = get_click_rects()
	if rects != _last_click_rects:
		_last_click_rects = rects
		pet.update_clickable_hitbox()

# Everything social that must stay clickable / visible in the click-through window.
# Rect2() (zero size) when there's nothing.
func get_extra_rect() -> Rect2:
	var result := Rect2()
	var has_any: bool = false
	var rects: Array = [_bubble_rect(my_bubble)]
	for p in _members.keys():
		rects.append(_members[p]["visitor"].get_global_extent())
	for e in _emotes:
		if is_instance_valid(e):
			rects.append(_control_rect(e))
	for rect in rects:
		if rect.size == Vector2.ZERO:
			continue
		result = rect if not has_any else result.merge(rect)
		has_any = true
	return result

# Everything social that is visible, one rectangle per object (visitor sprites and name tags, their emotes,
# speech bubbles). companion.gd turns them into the passthrough region, so nothing here gets clipped.
func get_click_rects() -> Array:
	var out: Array = []
	var mine: Rect2 = _bubble_rect(my_bubble)
	if mine.size != Vector2.ZERO:
		out.append(mine)
	for p in _members.keys():
		var v = _members[p]["visitor"]
		for vr in v.get_visible_rects():
			out.append(vr)
		if v.bubble.visible:
			var r: Rect2 = v.bubble.get_global_rect()
			if r.size != Vector2.ZERO:
				out.append(r)
	for e in _emotes:
		if is_instance_valid(e):
			var er: Rect2 = _control_rect(e)
			if er.size != Vector2.ZERO:
				out.append(er)
	return out

func _control_rect(c: Control) -> Rect2:
	return c.get_global_rect() if c.visible else Rect2()

# pet_bubble.gd is a plain Node now (it shows the dialogue balloon), so it has its own rect
func _bubble_rect(b) -> Rect2:
	return b.get_global_rect() if b.visible else Rect2()

# companion.gd asks this before closing the menu on an outside click: a click on a visitor is not "outside"
func is_point_over_ui(point: Vector2) -> bool:
	return visitor_at(point) != 0

# =========================================================
#  Clicking / dragging the visitor pets
#  Everything here only moves the PUPPET on my screen. Nothing is sent: the real pet on the
#  friend's screen is never affected, and dragging a visitor never moves anything on their side.
#    tap (quick click) -> a little <3 and a hop, like tapping my own pet
#    drag              -> carries the visitor around; afterwards it carries on depending on its mode
# =========================================================
const VISITOR_TAP_MAX_DURATION: float = 0.25
const VISITOR_TAP_MAX_DISTANCE: float = 12.0
const VISITOR_TAP_EMOTE_COOLDOWN: float = 0.3

var _vdrag_peer: int = 0
var _vdrag_offset: Vector2 = Vector2.ZERO
var _vdrag_start_time: float = 0.0
var _vdrag_start_pos: Vector2 = Vector2.ZERO
var _last_visitor_tap: float = -10.0

func is_dragging_visitor() -> bool:
	return _vdrag_peer != 0

# The visitor under `point` (0 = none). Later members are drawn on top, so look from the end.
func visitor_at(point: Vector2) -> int:
	var ids: Array = _members.keys()
	for i in range(ids.size() - 1, -1, -1):
		var v = _members[ids[i]]["visitor"]
		if v.contains_point(point):
			return int(ids[i])
	return 0

func _my_pet_rect() -> Rect2:
	var size: Vector2 = pet.sprite.texture.get_size() * pet.sprite.scale
	return Rect2(pet.sprite.global_position - size / 2.0, size)

# The menu, balloons and bubbles sit on top of the visitors and keep their own clicks
func _over_my_ui(point: Vector2) -> bool:
	if pet.text_prompt_open() and pet._text_panel.get_global_rect().has_point(point):
		return true
	if pet.menu_panel.visible and pet.menu_panel.get_global_rect().has_point(point):
		return true
	if pet.hover_info.visible and pet.alert_button.get_global_rect().has_point(point):
		return true
	var balloon: Control = pet._get_balloon_panel()
	if balloon != null and balloon.get_global_rect().has_point(point):
		return true
	if _bubble_rect(my_bubble).has_point(point):
		return true
	for p in _members.keys():
		if _bubble_rect(_members[p]["visitor"].bubble).has_point(point):
			return true
	return false

# Called first thing from companion.gd's _input. Returns true when the event was used here.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			if _vdrag_peer != 0:
				_end_visitor_drag(pet.get_global_mouse_position())   # a release got lost: let go first
			var point: Vector2 = pet.get_global_mouse_position()
			if pet.is_dragging or _my_pet_rect().has_point(point) or _over_my_ui(point):
				return false   # my own pet and the menus come first
			var peer: int = visitor_at(point)
			if peer == 0:
				return false
			var v = _vis(peer)
			_vdrag_peer = peer
			_vdrag_offset = v.global_position - point
			_vdrag_start_time = _now()
			_vdrag_start_pos = point
			v.dragged = true
			return true
		elif _vdrag_peer != 0:
			_end_visitor_drag(pet.get_global_mouse_position())
			return true
	elif event is InputEventMouseMotion and _vdrag_peer != 0:
		var v = _vis(_vdrag_peer)
		if v == null or not v.visible:
			_vdrag_peer = 0
			return false
		v.global_position = pet.get_global_mouse_position() + _vdrag_offset
		return true
	return false

func _end_visitor_drag(point: Vector2) -> void:
	var peer: int = _vdrag_peer
	_vdrag_peer = 0
	var v = _vis(peer)
	if v == null:
		return
	v.dropped()
	var quick: bool = _now() - _vdrag_start_time <= VISITOR_TAP_MAX_DURATION
	var still: bool = _vdrag_start_pos.distance_to(point) <= VISITOR_TAP_MAX_DISTANCE
	if quick and still:
		v.global_position = _vdrag_start_pos + _vdrag_offset   # it was a tap, not a drag: put it back
		if _now() - _last_visitor_tap >= VISITOR_TAP_EMOTE_COOLDOWN:
			_last_visitor_tap = _now()
			_emote_theirs(peer, "heart")
			v.play_fx("hop")

# =========================================================
#  Speaking + visual effects
# =========================================================
# Who hears my pet right now: the pets I'm doing something with. Everybody else's screen stays quiet,
# so two pets talking never spill onto a third player's screen.
func _audience() -> Array:
	if not _scene_players.is_empty():
		return _scene_players
	if not _group_pending.is_empty():
		return _group_pending["peers"]
	if _partner != 0:
		return [_partner]
	return []

# Your pet says something; the other screens in the audience show it too
func pet_say(text: String, seconds: float = 4.0, emote: String = "", fx: String = "", to: Array = []) -> void:
	var targets: Array = to if not to.is_empty() else _audience()
	_show_mine(text, seconds, emote, fx, targets)
	for p in targets:
		if _members.has(p):
			PetNetwork.send_say(text, emote, fx, int(p))

func _hide_bubble_of(peer: int) -> void:
	if peer == _my_peer():
		my_bubble.hide_bubble()
	elif _members.has(peer):
		_vis(peer).bubble.hide_bubble()

func _show_mine(text: String, seconds: float, emote: String = "", fx: String = "", listeners: Array = []) -> void:
	if text != "":
		for p in listeners:
			_hide_bubble_of(int(p))   # like a real conversation: only the one talking has a bubble
		var hold: float = BubbleScript.hold_time(text, seconds)
		_say_end[_my_peer()] = _now() + hold
		my_bubble.say(text, hold)
	if emote != "":
		_emote_mine(emote)
	if fx != "":
		_fx_mine(fx)

func _show_theirs(peer: int, text: String, seconds: float, emote: String = "", fx: String = "", listeners: Array = []) -> void:
	var v = _vis(peer)
	if v == null:
		return
	if text != "":
		if listeners.is_empty():
			my_bubble.hide_bubble()
		for p in listeners:
			_hide_bubble_of(int(p))
		var hold: float = BubbleScript.hold_time(text, seconds)
		_say_end[peer] = _now() + hold
		v.say(text, hold)
	if emote != "":
		_emote_theirs(peer, emote)
	if fx != "":
		v.play_fx(fx)

# My pet's hop / hearts etc. live in companion.gd now, so they also work without a friend
func _fx_mine(fx: String) -> void:
	pet.play_fx(fx)

func _emote_mine(key: String) -> void:
	pet.show_emote(key)

func _emote_theirs(peer: int, key: String) -> void:
	var v = _vis(peer)
	if v == null or not v.visible:
		return
	_track_emotes(PetFx.spawn_emote(pet, v.head_global(), key))

func _track_emotes(labels: Array) -> void:
	for l in labels:
		_emotes.append(l)
		l.tree_exited.connect(func(): _emotes.erase(l))

func _celebrate(peer: int) -> void:
	_emote_mine("hearts")
	_emote_theirs(peer, "hearts")
	_fx_mine("hop")
	var v = _vis(peer)
	if v != null:
		v.play_fx("hop")

# =========================================================
#  Profile / connection events
# =========================================================
func _feeling() -> String:
	if stats.hunger < 30.0:
		return "hungry"
	if stats.boredom > 65.0:
		return "bored"
	var happy: float = stats.get_happiness()
	if happy < 40.0:
		return "down"
	if happy >= 70.0:
		return "happy"
	return "okay"

func build_profile() -> Dictionary:
	var pf: String = _partner_fid()
	return {
		"partner": str(_book[pf]["name"]) if pf != "" else "",   # my sweetheart's name: the other pets hear about them
		"id": my_id,
		"name": pet.pet_name,
		"level": stats.level,
		"trait": stats.dominant_trait,
		"feeling": _feeling(),
		"fights": true,   # arguments are always on now (kept in the profile for older versions)
		"answers": stats.player_answers.duplicate(),
		"color": pet.pet_color_hex(),
	}

# Tells everybody in the room about my pet (name, level, mood...)
func refresh_profile() -> void:
	if PetNetwork.is_connected_to_friend():
		PetNetwork.send_profile(build_profile())
	_refresh_all()

func _status_data() -> Dictionary:
	return {"talking": _my_talking, "busy": _busy or _scene_playing}

# Lets the others know whether my pet is free. It's only a hint (to grey out the list and to stop the
# director from asking pets that would say "busy" anyway); the real check is the answer to the ask.
func _broadcast_status() -> void:
	if PetNetwork.is_connected_to_friend():
		PetNetwork.send_act("status", _status_data())

func _on_friend_connected(peer: int) -> void:
	PetNetwork.send_profile(build_profile(), peer)
	PetNetwork.send_act("status", _status_data(), peer)
	if _profile_timer.is_stopped():
		_profile_timer.start()
	_refresh_all()

func _on_friend_disconnected(peer: int) -> void:
	if not _members.has(peer):
		return
	var m: Dictionary = _members[peer]
	var their_name: String = _name_of(peer)
	var tier: String = _tier(peer)
	if str(m["fid"]) != "":
		_rel(peer)["last_seen"] = int(Time.get_unix_time_from_system())
		_rel(peer)["sore"] = bool(m["needs_makeup"])   # remembered for next time (and for the singleplayer "i miss them" talk)
		_save_book()

	# if they were part of what I'm doing, that thing is over
	var involved: bool = _partner == peer or peer in _scene_players or int(_pending.get("peer", 0)) == peer
	if involved:
		_reset_state()

	if _vdrag_peer == peer:
		_vdrag_peer = 0
	_members.erase(peer)
	if _selected_peer == peer:
		_selected_peer = 0
	var v = m["visitor"]
	v.disappear()
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		if is_instance_valid(v):
			v.queue_free())

	# I may have been waiting for their answer to "who wants to play?"
	if not _group_pending.is_empty():
		_group_pending["peers"].erase(peer)
		_group_pending["yes"].erase(peer)
		_group_pending["answered"].erase(peer)
		if _group_pending["peers"].is_empty() or _group_pending["answered"].size() >= _group_pending["peers"].size():
			_finish_group_collect()

	if not _busy and not _scene_playing:
		my_bubble.say(PetChat.bye_line(tier, their_name), 4.0)
	if _members.is_empty():
		_profile_timer.stop()
		_tick_timer.stop()
		_set_info("")
	_list_sig = ""
	_refresh_all()

# Throws away whatever I was in the middle of (a friend left, or something took too long)
func _reset_state() -> void:
	_busy = false
	_scene_playing = false
	_scene_id += 1          # any scene coroutine still running will notice and stop
	_stop_driving()
	_partner = 0
	_pending = {}
	_group_pending = {}
	_incoming_item = ""
	_scene_players = []
	_ask_timer.stop()
	_busy_timer.stop()
	for p in _members.keys():
		_members[p]["visitor"].together_slot = 0
		_settle_visitor(p)
	_broadcast_status()
	if not _members.is_empty():
		_tick_timer.start(_tick_delay())

func _on_profile_received(from: int, profile: Dictionary) -> void:
	var is_new: bool = not _members.has(from)
	var was_empty: bool = _members.is_empty()
	var m: Dictionary = _members[from] if not is_new else _make_member(from)
	m["profile"] = profile
	var fid: String = str(profile.get("id", ""))
	if fid == "":
		fid = "name:%s" % profile["name"]
	m["fid"] = fid
	var r: Dictionary = _rel(from)
	r["name"] = profile["name"]
	m["visitor"].set_profile(profile)
	_sync_sweetheart(from)
	if is_new:
		m["needs_makeup"] = bool(r["sore"])   # we parted on bad terms last time: a make-up is still owed
		# Stage 2: how long was this friend gone, and did my pet miss them?
		var away: int = _now_unix() - int(r["last_seen"]) if int(r["last_seen"]) > 0 else 0
		var miss_kind: String = _miss_kind(r)
		var reunion: String = ""
		if away >= PetMemory.REUNION_MIN_AWAY:
			reunion = PetMemory.reunion_line(miss_kind, str(profile["name"]))
		if bool(r["dating"]) and away >= PetGossip.NEGLECT_AWAY:
			r["drift"] = true   # being apart this long strains a relationship
			_save_book()
		if bool(r["dating"]) and _couple_timer.is_stopped():
			_couple_timer.start(randf_range(20.0, 40.0))
		m["visitor"].appear()
		if not _busy and not _scene_playing and reunion != "":
			my_bubble.say(reunion, 5.0)
			_emote_mine("hearts" if (miss_kind == "dating" or miss_kind == "crush") else "heart")
			_fx_mine("hop")
			_change_friendship(from, 2.0)
			if miss_kind == "dating" or miss_kind == "crush":
				_change_crush(from, 3.0)
		elif not _busy and not _scene_playing:
			var tier: String = _tier(from)
			if tier == "partner":
				my_bubble.say("%s!! you're here!! <3" % profile["name"], 4.0)
				_emote_mine("hearts")
			elif tier == "friend" or tier == "best":
				my_bubble.say("%s is here!! yay!" % profile["name"], 4.0)
				_emote_mine("heart")
			elif tier == "rival":
				my_bubble.say("oh. %s is here." % profile["name"], 4.0)
			else:
				my_bubble.say("oh! %s came to visit!" % profile["name"], 4.0)
		if was_empty or _tick_timer.is_stopped():
			var t: Vector2 = FIRST_TICK_HOST if PetNetwork.is_host else FIRST_TICK_GUEST
			_tick_timer.start(randf_range(t.x, t.y))
		_settle_visitor(from)
	_list_sig = ""
	_refresh_all()

# =========================================================
#  Where the visitors stand
# =========================================================
# Puts one visitor back into the right resting mode: near my pet (idle), keeping still (busy with
# somebody / their player is talking to them), or keeping its distance (sulking, my player is talking)
func _settle_visitor(peer: int) -> void:
	if not _members.has(peer):
		return
	var m: Dictionary = _members[peer]
	var v = m["visitor"]
	if _my_talking:
		v.set_mode("away", 600.0)    # give my pet space to talk to its player
	elif _now() < float(m["grudge_until"]):
		v.set_mode("away", float(m["grudge_until"]) - _now())
	elif _now() < float(m["talking_until"]) or bool(m["busy"]):
		v.set_mode("still", 120.0)   # in a conversation / talking to their player: just stands there
	else:
		v.set_mode("idle", 0.0)

# Every so often my pet's sweetheart walks over, snuggles up to it for a while and a heart floats up.
# (Purely visual and local: nothing is sent, and it never interrupts anything.)
func _on_couple_moment() -> void:
	var pf: String = _partner_fid()
	var peer: int = _peer_of_fid(pf) if pf != "" else 0
	if peer == 0 or not _members.has(peer):
		return   # they aren't here (the timer starts again when they come back)
	_couple_timer.start(randf_range(COUPLE_MOMENT_MIN, COUPLE_MOMENT_MAX))
	if _busy or _scene_playing or _my_talking or _player_is_busy() or not _peer_free(peer):
		return
	var m: Dictionary = _members[peer]
	if _now() < float(m["grudge_until"]) or bool(m["needs_makeup"]):
		return
	var v = _vis(peer)
	if v == null or not v.visible or v.dragged:
		return
	v.set_mode("together", randf_range(14.0, 28.0))
	_emote_theirs(peer, "heart")
	if randf() < 0.6:
		_emote_mine("heart")
	if randf() < 0.35:
		_fx_mine("hop")
		v.play_fx("hop")

# companion.gd asks this before it talks to the player: the pet only does that when it is not in
# the middle of something with another pet
func is_pet_busy() -> bool:
	return _busy or _scene_playing

# companion.gd tells us when the pet starts / stops talking to its player. The other pets give
# it space, and the other games are told so their pets don't start anything with it either.
func player_talking_changed(talking: bool) -> void:
	_my_talking = talking
	if _members.is_empty():
		return
	_broadcast_status()
	if talking:
		my_bubble.hide_bubble()
		for p in _members.keys():
			_members[p]["visitor"].bubble.hide_bubble()
			_settle_visitor(p)
	elif not _scene_playing:
		for p in _members.keys():
			_settle_visitor(p)

func _handle_status(from: int, data: Dictionary) -> void:
	var m: Dictionary = _members[from]
	m["talking_until"] = (_now() + 120.0) if bool(data.get("talking", false)) else 0.0
	m["busy"] = bool(data.get("busy", false))
	if not (from in _scene_players):
		_settle_visitor(from)
	_refresh_all()

# =========================================================
#  The director: what do the pets feel like doing?
# =========================================================
func _on_tick() -> void:
	if _members.is_empty() or not PetNetwork.is_connected_to_friend():
		return
	if _busy or _scene_playing or _player_is_busy():
		_tick_timer.start(randf_range(6.0, 12.0))
		return
	# only pets that are free and not sulking
	var candidates: Array = []
	for p in _free_peers():
		if _now() >= float(_members[p]["grudge_until"]):
			candidates.append(p)
	if candidates.is_empty():
		_tick_timer.start(randf_range(10.0, 20.0))   # everybody is busy or still sulking
		return

	# sometimes the pet asks everybody at once (but newcomers get a proper hello first)
	var all_greeted: bool = true
	for p in candidates:
		if not bool(_members[p]["did_first_chat"]):
			all_greeted = false
	if candidates.size() >= 2 and all_greeted and randf() < GROUP_PLAY_CHANCE:
		_ask_group_play(candidates)
		_tick_timer.start(_tick_delay())
		return

	var peer: int = _pick_partner(candidates)
	var action: String = _choose_action(peer)
	if action == "":
		_tick_timer.start(randf_range(10.0, 20.0))
		return
	_start(action, peer)
	_tick_timer.start(_tick_delay())

# Quiet time until the next thing my pet does with somebody. Sweethearts in the room make it shorter.
func _tick_delay() -> float:
	var d: float = randf_range(TICK_MIN, TICK_MAX)
	var pf: String = _partner_fid()
	if pf != "" and _peer_of_fid(pf) != 0:
		d *= COUPLE_TICK_FACTOR
	return d

# Newcomers first, then friends more often than strangers (and the sweetheart most of all)
func _pick_partner(candidates: Array) -> int:
	var w := {}
	for p in candidates:
		var weight: float = 1.0 + _friendship(p) / 50.0
		if bool(_rel(p)["befriended"]):
			weight += 1.0
		if bool(_rel(p)["dating"]):
			weight += 6.0
		if not bool(_members[p]["did_first_chat"]):
			weight += 4.0
		w[p] = weight
	var total: float = 0.0
	for p in w.keys():
		total += float(w[p])
	var roll: float = randf() * total
	for p in w.keys():
		roll -= float(w[p])
		if roll < 0.0:
			return int(p)
	return int(candidates[0])

# Don't start things while the player is talking to their pet / playing a game
func _player_is_busy() -> bool:
	return is_instance_valid(pet.current_balloon) or pet.game_screen.visible or pet.is_dragging \
		or pet.has_dialogue_waiting() or pet.text_prompt_open()

# What a chat needs to know so the pets don't greet each other every few minutes or repeat topics
func _chat_context(peer: int) -> Dictionary:
	var r: Dictionary = _rel(peer)
	var last_seen: int = int(r["last_seen"])
	var recently: bool = last_seen > 0 and int(Time.get_unix_time_from_system()) - last_seen < RECENT_VISIT_SECONDS
	var days_together: int = 0
	if bool(r["dating"]) and int(r["dating_since"]) > 0:
		days_together = (_now_unix() - int(r["dating_since"])) / 86400
	return {
		"days": days_together,
		"greet": not bool(_members[peer]["did_first_chat"]) and not recently,
		"met_before": bool(r["met"]),
		"talked": r["talked"],
		"prev_level": int(r["level"]),
	}

func _remember_scene(peer: int, scene: Dictionary) -> void:
	if not _members.has(peer):
		return
	var r: Dictionary = _rel(peer)
	r["met"] = true
	r["last_seen"] = int(Time.get_unix_time_from_system())
	var talked: Array = r["talked"]
	for tag in scene.get("topics", []):
		if not (tag in talked):
			talked.append(tag)
	while talked.size() > MAX_TALKED:
		talked.pop_front()
	r["talked"] = talked
	if str(scene.get("kind", "")) == "chat" and _profile(peer).has("level"):
		r["level"] = int(_profile(peer)["level"])
	_save_book()

func _choose_action(peer: int) -> String:
	var m: Dictionary = _members[peer]
	if _now() < float(m["grudge_until"]):
		return ""
	if not bool(m["did_first_chat"]):
		return "chat"
	if bool(m["needs_makeup"]) and randf() < 0.7:
		return "makeup"
	# drama first: a pet that believes a rumour about itself (or blames somebody for spreading one) goes and says so
	if not _plan_confront(peer).is_empty() and randf() < 0.85:
		return "confront"
	# a couple that has drifted apart or is falling out may end it
	if _plan_breakup(peer) != "" and randf() < 0.6:
		return "breakup"
	var r: Dictionary = _rel(peer)
	var befriended: bool = bool(r["befriended"])
	var fr: float = float(r["friendship"])
	var w := {"chat": 40.0, "mood": 8.0, "play": 12.0 + (14.0 if befriended else 0.0)}
	if not befriended and fr >= 25.0:
		w["befriend"] = 60.0 if fr >= 45.0 else 30.0
	if gifts_enabled and _pick_gift(peer, "") != "":
		w["gift"] = 20.0 if befriended else 4.0
	# Stage 1: couples hang out, a pet with a big crush may finally ask, and friends gossip
	if bool(r["dating"]):
		# sweethearts mostly do couple things together
		w["romance"] = 60.0
		w["chat"] = 14.0
	elif befriended and _partner_fid() == "" and _now_unix() >= int(r["romance_cd"]):
		if bool(r["ex"]):
			# exes may ask each other to try again (after some time apart, if feelings are left)
			var re_w: float = PetGossip.rekindle_weight(float(r["crush"]), fr, _now_unix() - int(r["ex_since"]), str(r["ex_by"]) == "me")
			if re_w > 0.0:
				w["rekindle"] = re_w
		else:
			var ask_w: float = PetGossip.ask_weight(float(r["crush"]), fr, str(stats.dominant_trait))
			if ask_w > 0.0:
				w["date"] = ask_w
	if fr >= 20.0 and not _plan_gossip(peer).is_empty():
		w["gossip"] = 14.0 + (6.0 if befriended else 0.0)
	# Arguments are always possible (never while a make-up is pending). Chance goes DOWN as they get closer,
	# but even best friends still bicker now and then. (chat is 40 and play 12-26 for comparison)
	if not bool(m["needs_makeup"]):
		w["fight"] = 24.0 if fr < 20.0 else (12.0 if befriended else 18.0)
		if fr >= 85.0 or bool(r["dating"]):
			w["fight"] = 5.0
	return _weighted(w)

func _weighted(w: Dictionary) -> String:
	var total: float = 0.0
	for k in w.keys():
		total += float(w[k])
	var roll: float = randf() * total
	for k in w.keys():
		roll -= float(w[k])
		if roll < 0.0:
			return str(k)
	return "chat"

# Starts something one-on-one with `peer`. Everything goes through the ask / answer handshake first.
func _start(action: String, peer: int) -> void:
	if not _members.has(peer):
		return
	var chat_ctx: Dictionary = _chat_context(peer)   # built before the visit counts as "greeted"
	_members[peer]["did_first_chat"] = true
	match action:
		"chat", "fight", "makeup", "play", "mood", "befriend", "date", "romance", "rekindle":
			_ask(peer, action, "", chat_ctx)
		"breakup":
			var reason: String = _plan_breakup(peer)
			if reason == "":
				_set_info("nothing to talk about right now.")
				return
			_ask(peer, "breakup", "", {"reason": reason})
		"gossip", "confront":
			var plan: Dictionary = _plan_for(action, peer)
			if plan.is_empty():
				_set_info("nothing to talk about right now.")
				return
			if action == "gossip" and plan["mode"] != "tell":
				_vent_last["%s>%s" % [_fid_of(peer), str(plan.get("about_fid", ""))]] = _now_unix()
			_ask(peer, action, "", {"plan": plan})
		"gift":
			var item: String = _pick_gift(peer, "")
			if item != "":
				_ask(peer, "gift", item)

# The player nudges their pet ("go say hi"). The pets still ask each other for everything.
func _nudge(action: String) -> void:
	var peer: int = _selected_peer
	if not _members.has(peer):
		return
	if _busy or _scene_playing:
		_set_info("%s is in the middle of something." % pet.pet_name)
		return
	if not _peer_free(peer):
		_set_info("%s is busy right now. try again in a bit." % _name_of(peer))
		return
	if action == "gift" and _pick_gift(peer, "") == "":
		_set_info("you don't have anything to give right now.")
		return
	# The chat button asks my pet to do whatever it would have decided to do on its own with this pet:
	# the exact same pick the director makes (_choose_action). That covers hellos and small talk, make-ups,
	# confrontations, gossip / venting / confiding, romance and asking out, arguments, gifts, mood checks,
	# befriending and play. Which one it is depends on the relationship, rumours, crushes and so on.
	if action == "chat":
		if _now() < float(_members[peer]["grudge_until"]):
			_set_info("%s is still upset with %s. give it a little while." % [_name_of(peer), pet.pet_name])
			return
		action = _choose_action(peer)
		if action == "gossip" or action == "confront":
			if _plan_for(action, peer).is_empty():
				action = "chat"   # the story went stale between the pick and now: plain chat
		if action == "":
			action = "chat"
	_start(action, peer)

func _nudge_all() -> void:
	if _busy or _scene_playing:
		_set_info("%s is in the middle of something." % pet.pet_name)
		return
	var free: Array = _free_peers()
	if free.is_empty():
		_set_info("everybody is busy right now. try again in a bit.")
		return
	_ask_group_play(free)

# =========================================================
#  Ask / answer interactions
# =========================================================
func _begin_busy() -> void:
	_busy = true
	_busy_timer.start(BUSY_MAX)
	_broadcast_status()
	_refresh_all()

func _end_busy() -> void:
	_busy = false
	_partner = 0
	_group_pending = {}
	_busy_timer.stop()
	_broadcast_status()
	_refresh_all()
	# the quiet time before the next interaction counts from the END of this one
	if not _members.is_empty() and PetNetwork.is_connected_to_friend():
		_tick_timer.start(_tick_delay())

func _on_busy_timeout() -> void:
	_reset_state()
	_refresh_all()

func _on_ask_timeout() -> void:
	if not _group_pending.is_empty():
		_finish_group_collect()
		return
	if not _pending.is_empty():
		_set_info("%s didn't answer." % _name_of(int(_pending.get("peer", 0))))
	_pending = {}
	_incoming_item = ""
	if not _scene_playing:
		_end_busy()

func _item_name(id: String) -> String:
	if stats.ITEM_DB.has(id):
		return str(stats.ITEM_DB[id]["name"]).to_lower()
	return "something"

# My pet picks something to give. Prefers what that pet seems to need.
func _pick_gift(peer: int, feeling: String) -> String:
	var ids: Array = []
	for id in stats.inventory.keys():
		if stats.ITEM_DB.has(id) and int(stats.inventory[id]) > 0:
			ids.append(id)
	if ids.is_empty():
		return ""
	var wanted: Array = []
	var need: String = feeling if feeling != "" else str(_profile(peer).get("feeling", ""))
	for id in ids:
		var d: Dictionary = stats.ITEM_DB[id]
		if need == "hungry" and float(d["hunger_restore"]) > 0.0:
			wanted.append(id)
		elif need == "bored" and float(d["boredom_relief"]) > 0.0 and float(d["hunger_restore"]) <= 0.0:
			wanted.append(id)
	return str(wanted.pick_random()) if not wanted.is_empty() else str(ids.pick_random())

func _ask(peer: int, what: String, item: String = "", ctx: Dictionary = {}) -> void:
	if _busy or not _members.has(peer):
		return
	_begin_busy()
	_partner = peer
	_pending = {"what": what, "item": item, "peer": peer, "ctx": ctx}
	if what in ASK_KINDS:
		var emote: String = "heart" if (what == "befriend" or what == "date" or what == "rekindle") else ""
		if what == "date":
			pet_say(PetGossip.ask_line(build_profile(), _profile(peer)), 6.0, emote, "wiggle")
		elif what == "rekindle":
			pet_say(PetGossip.rekindle_ask_line(build_profile(), _profile(peer)), 6.0, emote, "")
		else:
			pet_say(PetChat.ask_line(what, build_profile(), _profile(peer), _item_name(item)), 4.5, emote)
	PetNetwork.send_act("ask", {"what": what, "item": item}, peer)
	_ask_timer.start(ASK_TIMEOUT)

# "Who wants to play?" to everybody in `targets` at once. Every pet that says yes is claimed for the
# game; after a few seconds the yes-pets get ONE scene (see _finish_group_collect).
func _ask_group_play(targets: Array) -> void:
	if _busy or targets.is_empty():
		return
	_begin_busy()
	_group_pending = {"peers": targets.duplicate(), "answered": {}, "yes": []}
	pet_say(PetChat.ask_line("play", build_profile(), {"name": "everyone"}), 4.5)
	for p in targets:
		PetNetwork.send_act("ask", {"what": "play", "group": true}, int(p))
	_ask_timer.start(GROUP_COLLECT_SECONDS)

func _finish_group_collect() -> void:
	_ask_timer.stop()
	var yes: Array = []
	for p in _group_pending.get("yes", []):
		if _members.has(p):
			yes.append(p)
	_group_pending = {}
	if yes.is_empty():
		pet_say(PetChat.disappointed_line(), 4.0, "sad")
		_end_busy()
		return
	var profiles: Array = [build_profile()]
	var peers: Array = [_my_peer()]
	for p in yes:
		profiles.append(_profile(p))
		peers.append(p)
	_start_scene(PetChat.group_play_scene(profiles, peers), yes)

func _on_act_received(from: int, kind: String, data: Dictionary) -> void:
	if not _members.has(from):
		return   # no profile from them yet
	match kind:
		"say":
			# bubbles only from the pet I'm busy with (or from anybody when I'm free): a conversation
			# next door never talks over mine
			if (not _busy and not _scene_playing) or from == _partner or from in _scene_players \
					or from in _group_pending.get("peers", []):
				_show_theirs(from, str(data.get("text", "")), 4.0, str(data.get("emote", "")), str(data.get("fx", "")), [_my_peer()])
		"ask":
			_handle_ask(from, str(data.get("what", "")), str(data.get("item", "")))
		"answer":
			_handle_answer(from, data)
		"deliver":
			_handle_deliver(from, str(data.get("item", "")))
		"status":
			_handle_status(from, data)

# My pet decides how to answer another pet. No popup: it thinks for a moment and replies.
func _decide(from: int, what: String) -> bool:
	var p: float = 1.0
	match what:
		"befriend":
			var same: int = PetChat.same_count(build_profile(), _profile(from))
			p = clampf(0.3 + _friendship(from) / 100.0 * 0.6 + same * 0.05, 0.1, 0.95)
			if _friendship(from) < 20.0:
				p *= 0.6
		"gift":
			p = 0.92 if _friendship(from) >= 20.0 else 0.65
		"play":
			p = 0.88
			if stats.hunger < 20.0:
				p = 0.35
		"mood":
			p = 1.0
		"date":
			# MY pet decides on its own. Its own crush counts most; being taken is a hard no.
			var rr: Dictionary = _rel(from)
			var taken: bool = _partner_fid() != "" and _partner_fid() != _fid_of(from)
			if taken:
				return false   # never two partners at once (the 2% "luck" in date_acceptance used to allow it)
			p = PetGossip.date_acceptance(float(rr["crush"]), _friendship(from), PetChat.same_count(build_profile(), _profile(from)), taken)
			if not bool(rr["befriended"]):
				p *= 0.4
		"rekindle":
			var rk: Dictionary = _rel(from)
			if _partner_fid() != "" and _partner_fid() != _fid_of(from):
				return false   # never two partners at once
			p = PetGossip.rekindle_acceptance(float(rk["crush"]), _friendship(from), PetChat.same_count(build_profile(), _profile(from)), str(rk["ex_by"]) == "me")
			if not bool(rk["befriended"]):
				p *= 0.4
	if _now() < float(_members[from]["grudge_until"]):
		p = minf(p, 0.1)  # still angry
	return randf() < p

func _handle_ask(from: int, what: String, item: String) -> void:
	var silent: bool = what in SILENT_KINDS
	# THE RULE: busy pets say so, and that's the end of it. Nobody can break into a conversation.
	if not (what in ASK_KINDS or silent) or (what == "gift" and not stats.ITEM_DB.has(item)) \
			or _busy or _scene_playing or _player_is_busy():
		PetNetwork.send_act("answer", {"what": what, "ok": false, "busy": true, "item": item}, from)
		return
	_begin_busy()
	_partner = from
	_pending = {}
	if silent:
		# chat / fight / makeup: no bubble, I'm just claimed now and the scene is on its way
		PetNetwork.send_act("answer", {"what": what, "ok": true, "item": ""}, from)
		_ask_timer.start(FOLLOW_UP_TIMEOUT)
		return
	# think for a moment, but never answer before the question has been read to the end
	var think: float = DATE_THINK_TIME if (what == "date" or what == "rekindle") else THINK_TIME
	await get_tree().create_timer(maxf(think, minf(_bubble_left(from) + 0.6, ASK_TIMEOUT - 4.0))).timeout
	if not _members.has(from) or _partner != from:
		return  # they left (or something reset me) while we were thinking

	var ok: bool = _decide(from, what)
	var reply := {"what": what, "ok": ok, "item": item}
	var line: String = ""
	var emote: String = ""
	var fx: String = ""
	if what == "mood":
		if ok:
			var mood: Dictionary = build_mood()
			line = mood["line"]
			reply["feeling"] = _feeling()
			reply["summary"] = mood["summary"]
		else:
			line = PetChat.answer_line("mood", false)
	else:
		if what == "rekindle":
			line = PetGossip.rekindle_answer_line(ok, _partner_fid() != "" and _partner_fid() != _fid_of(from))
		elif what == "date":
			line = PetGossip.answer_line(ok, _partner_fid() != "" and _partner_fid() != _fid_of(from))
		else:
			line = PetChat.answer_line(what, ok)
		if what == "befriend" or what == "date" or what == "rekindle":
			emote = "heart" if ok else "sad"
		elif ok:
			emote = "happy"
			fx = "hop"
	pet_say(line, 4.5, emote, fx)
	PetNetwork.send_act("answer", reply, from)

	match what:
		"befriend":
			if ok:
				_set_befriended(from, true)
				_change_friendship(from, maxf(0.0, 40.0 - _friendship(from)))
				_celebrate(from)
				_set_info("you and %s are friends now!" % _name_of(from))
			else:
				_change_friendship(from, -2.0)
			_end_busy()
		"gift":
			if ok:
				_incoming_item = item
				_ask_timer.start(FOLLOW_UP_TIMEOUT)  # waiting for the delivery
			else:
				_end_busy()
		"play":
			if ok:
				_ask_timer.start(FOLLOW_UP_TIMEOUT)  # waiting for the play scene
			else:
				_end_busy()
		"date":
			# either way my pet now knows they asked: that is the kind of thing that gets talked about
			var asked: Dictionary = PetGossip.new_rumor("crush", _fid_of(from), _name_of(from), my_id, pet.pet_name, false, false, _fid_of(from), _name_of(from), _now_unix())
			asked["believed"] = false   # i was THERE: nothing to confront, it is only good for telling
			_add_rumor(asked)
			if ok:
				_set_befriended(from, true)
				_set_dating(from, true)
				_change_crush(from, 15.0)
				_change_friendship(from, maxf(0.0, 60.0 - _friendship(from)))
				_celebrate(from)
				_set_info("%s and %s are together now!" % [pet.pet_name, _name_of(from)])
				_ask_timer.start(FOLLOW_UP_TIMEOUT)  # waiting for the first-date scene
			else:
				_change_friendship(from, -1.0)
				_end_busy()
		"rekindle":
			if ok:
				_get_together(from, true)
				_ask_timer.start(FOLLOW_UP_TIMEOUT)  # waiting for the getting-back-together scene
			else:
				_change_friendship(from, -1.0)
				_rel(from)["romance_cd"] = _now_unix() + PetGossip.REKINDLE_NO_COOLDOWN
				_save_book()
				_end_busy()
		_:
			_end_busy()

func _handle_answer(from: int, data: Dictionary) -> void:
	var what: String = str(data.get("what", ""))
	var ok: bool = bool(data.get("ok", false))

	# an answer to "who wants to play?"
	if not _group_pending.is_empty():
		if what == "play" and from in _group_pending["peers"] and not _group_pending["answered"].has(from):
			_group_pending["answered"][from] = true
			if ok and not bool(data.get("busy", false)):
				_group_pending["yes"].append(from)
			if _group_pending["answered"].size() >= _group_pending["peers"].size():
				_finish_group_collect()
		return

	if _pending.is_empty() or int(_pending.get("peer", 0)) != from or _pending.get("what", "") != what:
		return
	var item: String = str(_pending.get("item", ""))
	var ctx: Dictionary = _pending.get("ctx", {})
	_pending = {}
	_ask_timer.stop()

	if bool(data.get("busy", false)):
		_set_info("%s was busy. maybe later." % _name_of(from))
		if what == "date" or what == "befriend" or what == "rekindle":
			_say_later(from, 1.0, "oh... they're busy right now. maybe later.", "sad", "")   # never leave an ask-out hanging in silence
		_end_busy()
		_tick_timer.start(randf_range(8.0, 20.0))   # try somebody else soon, not in 5 minutes
		return

	match what:
		"chat":
			_start_scene(PetChat.chat_scene(build_profile(), _profile(from), _tier(from), ctx), [from], {"a": _my_peer(), "b": from})
		"fight":
			var r: Dictionary = _rel(from)
			_start_scene(PetChat.fight_scene(build_profile(), _profile(from), float(r["friendship"]), bool(r["befriended"])), [from], {"a": _my_peer(), "b": from})
		"makeup":
			_start_scene(PetChat.makeup_scene(build_profile(), _profile(from)), [from], {"a": _my_peer(), "b": from})
		"gossip":
			_start_scene(PetGossip.gossip_scene(build_profile(), _profile(from), ctx.get("plan", {}), _now_unix()), [from], {"a": _my_peer(), "b": from})
		"confront":
			var rc: Dictionary = _rel(from)
			_start_scene(PetGossip.confront_scene(build_profile(), _profile(from), ctx.get("plan", {}), float(rc["friendship"]), bool(rc["befriended"])), [from], {"a": _my_peer(), "b": from})
		"romance":
			_start_scene(PetGossip.romance_scene(build_profile(), _profile(from), ctx), [from], {"a": _my_peer(), "b": from})
		"breakup":
			_start_scene(PetGossip.breakup_scene(build_profile(), _profile(from), str(ctx.get("reason", "drifted")), float(_rel(from)["friendship"])), [from], {"a": _my_peer(), "b": from})
		"rekindle":
			if ok:
				_get_together(from, true)
				_start_scene(PetGossip.rekindle_scene(build_profile(), _profile(from)), [from], {"a": _my_peer(), "b": from})
			else:
				_change_crush(from, -15.0)
				_rel(from)["romance_cd"] = _now_unix() + PetGossip.REKINDLE_NO_COOLDOWN
				_save_book()
				_say_later(from, 1.4, PetGossip.after_no_line(), "sad", "")
				_end_busy()
		"date":
			if ok:
				_set_befriended(from, true)
				_set_dating(from, true)
				_change_crush(from, 15.0)
				_change_friendship(from, maxf(0.0, 60.0 - _friendship(from)))
				_celebrate(from)
				_set_info("%s and %s are together now!" % [pet.pet_name, _name_of(from)])
				_start_scene(PetGossip.first_date_scene(build_profile(), _profile(from)), [from], {"a": _my_peer(), "b": from})
			else:
				_change_crush(from, -35.0)
				_rel(from)["romance_cd"] = _now_unix() + PetGossip.ASK_COOLDOWN
				_save_book()
				_say_later(from, 1.4, PetGossip.after_no_line(), "sad", "")
				_end_busy()
		"befriend":
			if ok:
				_set_befriended(from, true)
				_change_friendship(from, maxf(0.0, 40.0 - _friendship(from)))
				_celebrate(from)
				_set_info("you and %s are friends now!" % _name_of(from))
				_say_later(from, 1.4, PetChat.cheer_line(), "hearts", "hop")
			else:
				_change_friendship(from, -2.0)
				_say_later(from, 1.4, PetChat.disappointed_line(), "sad", "")
			_end_busy()
		"gift":
			if ok:
				if stats.inventory.get(item, 0) > 0 and stats.ITEM_DB.has(item):
					_remove_item(item)
					stats.add_xp(10)
					PetNetwork.send_act("deliver", {"item": item}, from)
					pet_say(PetChat.give_line(), 3.0, "gift", "hop")
					_change_friendship(from, 8.0)
					_crush_after_scene("chat", from)
					_set_info("you gave %s a %s." % [_name_of(from), _item_name(item)])
				else:
					PetNetwork.send_act("deliver", {"item": ""}, from)
					pet_say("oh no... i don't have it anymore!", 4.0, "sad")
			else:
				_change_friendship(from, -1.0)
				_say_later(from, 1.4, PetChat.disappointed_line(), "sad", "")
			_end_busy()
		"play":
			if ok:
				_start_scene(PetChat.group_play_scene([build_profile(), _profile(from)], [_my_peer(), from]), [from])
			else:
				_say_later(from, 1.4, PetChat.disappointed_line(), "sad", "")
				_end_busy()
		"mood":
			var feeling: String = str(data.get("feeling", ""))
			if ok and feeling != "":
				_profile(from)["feeling"] = feeling
				_members[from]["mood_text"] = "%s is feeling: %s" % [_name_of(from), str(data.get("summary", "")).trim_suffix(".")]
				_end_busy()
				_react_to_mood(from, feeling)
			else:
				_say_later(from, 1.4, PetChat.disappointed_line(), "sad", "")
				_end_busy()
		_:
			_end_busy()

# How long until this pet has finished saying what it is saying right now (0 = it isn't talking)
func _bubble_left(peer: int) -> float:
	return maxf(0.0, float(_say_end.get(peer, 0.0)) - _now())

# Says something to ONE pet a moment later (by then the ask is over, so there is no audience yet).
# It waits until that pet has finished its own line: its answer is never cut off by the reply.
func _say_later(peer: int, seconds: float, text: String, emote: String, fx: String) -> void:
	await get_tree().create_timer(maxf(seconds, _bubble_left(peer) + 0.5)).timeout
	if _members.has(peer):
		pet_say(text, 4.0, emote, fx, [peer])

# Caring pets: a hungry friend gets offered food, a bored one gets invited to play
func _react_to_mood(peer: int, feeling: String) -> void:
	await get_tree().create_timer(maxf(2.8, _bubble_left(peer) + 0.5)).timeout
	if not _members.has(peer) or _busy or _scene_playing or not _peer_free(peer):
		return
	match feeling:
		"hungry":
			var item: String = _pick_gift(peer, "hungry") if gifts_enabled else ""
			if item != "" and float(stats.ITEM_DB[item]["hunger_restore"]) > 0.0:
				_ask(peer, "gift", item)
			else:
				pet_say(PetChat.worry_line(), 4.0, "sad", "", [peer])
		"bored":
			if randf() < 0.7:
				_ask(peer, "play")
		"down":
			pet_say(PetChat.comfort_line(), 4.5, "heart", "", [peer])
			_change_friendship(peer, 1.0)

func _handle_deliver(from: int, item_id: String) -> void:
	if _incoming_item == "" or from != _partner:
		return
	var expected: String = _incoming_item
	_incoming_item = ""
	_ask_timer.stop()
	if item_id != expected or not stats.ITEM_DB.has(item_id):
		pet_say("oh... it didn't come through.", 4.0, "sad")
		_set_info("the gift didn't make it. sorry!")
		_end_busy()
		return
	stats.inventory[item_id] = stats.inventory.get(item_id, 0) + 1
	stats.inventory_changed.emit()
	stats.add_xp(10)
	_change_friendship(from, 8.0)
	_crush_after_scene("gift", from)   # being given something is the bigger deal
	# a hungry pet eats a food gift right away, a bored one plays with a toy
	var used: String = _maybe_use_gift(item_id)
	pet_say(PetChat.thanks_line(used), 4.5, "hearts", "hop")
	_set_info("you received a %s!" % _item_name(item_id))
	_end_busy()

func _maybe_use_gift(item_id: String) -> String:
	var d: Dictionary = stats.ITEM_DB[item_id]
	if float(d["hunger_restore"]) > 0.0 and stats.hunger < 45.0:
		stats.use_item(item_id)
		return "ate"
	if float(d["hunger_restore"]) <= 0.0 and float(d["boredom_relief"]) > 0.0 and stats.boredom > 55.0:
		stats.use_item(item_id)
		return "played"
	return ""

func _remove_item(item_id: String) -> void:
	stats.inventory[item_id] = stats.inventory.get(item_id, 0) - 1
	if stats.inventory[item_id] <= 0:
		stats.inventory.erase(item_id)
	stats.inventory_changed.emit()

# =========================================================
#  Scenes (chat / play / fight / makeup)
#  The pet that starts it writes the whole script and sends it to the pets that take part;
#  every game then plays it locally.
#    chat / fight / makeup : two pets. Lines say "a" (the starter) or "b" (the other one).
#    play (tag / hide...)  : two or more pets, see _play_game.
# =========================================================
# `others` = the pets that take part besides me. `ctx` says who "a" and "b" are (pair scenes only).
func _start_scene(scene: Dictionary, others: Array, ctx: Dictionary = {}) -> void:
	if _scene_playing or scene.is_empty() or others.is_empty():
		_end_busy()
		return
	_ask_timer.stop()
	_begin_busy()
	_scene_role = "a"
	PetNetwork.send_scene(scene, others)
	_play_scene(scene, others, ctx)

func _on_scene_received(from: int, scene: Dictionary) -> void:
	if not _members.has(from):
		return
	# THE RULE again: I only play a scene with a pet I have agreed to do it with (it asked, I said
	# yes, and I'm still waiting for exactly that). Everything else is ignored.
	if _scene_playing or _partner != from:
		return
	if is_instance_valid(pet.current_balloon):
		_end_busy()
		return  # my pet is talking to its player right now: skip this scene
	var others: Array = [from]
	var ctx: Dictionary = {"a": from, "b": _my_peer()}
	if scene.has("players"):
		var players: Array = scene["players"]
		if not (_my_peer() in players) or int(players[0]) != from:
			_end_busy()
			return  # not a game that includes me, or not started by the pet that asked me
		others = []
		for p in players:
			if int(p) != _my_peer():
				others.append(int(p))
		ctx = {}
	_members[from]["did_first_chat"] = true
	# Whatever I was waiting for is replaced by this scene
	_pending = {}
	_incoming_item = ""
	_ask_timer.stop()
	_begin_busy()
	_scene_role = "b"
	_play_scene(scene, others, ctx)

func _play_scene(scene: Dictionary, others: Array, ctx: Dictionary) -> void:
	var lines: Array = scene.get("lines", [])
	if _scene_playing or lines.is_empty() or others.is_empty():
		_end_busy()
		return
	_scene_playing = true
	_scene_id += 1
	var sid: int = _scene_id
	_scene_players = others.duplicate()
	_broadcast_status()
	_refresh_all()
	if pet.has_method("_stop_pet_motion"):
		pet._stop_pet_motion()  # stand still while the pets talk

	var kind: String = str(scene.get("kind", "chat"))
	var is_game: bool = kind == "play" and scene.has("rounds")
	var seconds: float = 900.0 if is_game else _scene_seconds(lines) + 10.0
	for i in others.size():
		var v = _vis(others[i])
		if v == null:
			continue
		v.together_slot = i if (is_game and others.size() > 1) else 0
		v.set_mode("together", seconds)
	# everybody who is NOT part of it keeps their distance
	for p in _members.keys():
		if not (p in others) and _now() >= float(_members[p]["talking_until"]):
			_members[p]["visitor"].set_mode("away", seconds)
	await _wait_for_visitors(others, 6.0)

	if is_game:
		await _play_game(scene, sid)
	else:
		for line in lines:
			if not _still_here(sid):
				break
			var hold: float = _say_line(line, ctx, SCENE_LINE_SECONDS)
			await get_tree().create_timer(hold + 0.3).timeout
	if sid != _scene_id:
		return  # somebody left (state was reset) while the scene was playing
	_finish_scene(scene, others)

# =========================================================
#  Scene helpers
# =========================================================
func _still_here(sid: int) -> bool:
	if sid != _scene_id or not PetNetwork.is_connected_to_friend():
		return false
	for p in _scene_players:
		if not _members.has(p):
			return false
	return true

# How long a scene's lines take in total (each line stays up long enough to be read)
func _scene_seconds(lines: Array) -> float:
	var total: float = 0.0
	for line in lines:
		total += BubbleScript.hold_time(str(line.get("text", "")), SCENE_LINE_SECONDS) + 0.3
	return total

# ctx = {"a": peer id, "b": peer id}: who the line's "a" and "b" are.
# `seconds` is the SHORTEST time the line stays up; long lines stay up longer. Returns the time it really stays up.
func _say_line(line: Dictionary, ctx: Dictionary, seconds: float) -> float:
	var who: String = str(line.get("who", "a"))
	var speaker: int = int(ctx.get(who, 0))
	var listener: int = int(ctx.get("b" if who == "a" else "a", 0))
	var emote: String = str(line.get("emote", ""))
	var fx: String = str(line.get("fx", ""))
	if speaker == _my_peer():
		_show_mine(line["text"], seconds, emote, fx, [listener])
	else:
		_show_theirs(speaker, line["text"], seconds, emote, fx, [listener])
	return BubbleScript.hold_time(str(line["text"]), seconds)

# Says each line in turn. Returns false if the scene was cancelled (somebody left).
func _say_lines(lines: Array, ctx: Dictionary, sid: int, seconds: float = SCENE_LINE_SECONDS, gap: float = 0.3) -> bool:
	for line in lines:
		if not _still_here(sid):
			return false
		var hold: float = _say_line(line, ctx, seconds)
		await get_tree().create_timer(hold + gap).timeout
	return _still_here(sid)

func _pause_for(seconds: float, sid: int) -> bool:
	await get_tree().create_timer(seconds).timeout
	return _still_here(sid)

# Polls `done` every 0.1 s for at most `max_seconds`. Returns false only if the scene was cancelled.
func _wait_until(done: Callable, max_seconds: float, sid: int) -> bool:
	var waited: float = 0.0
	while waited < max_seconds and not done.call():
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
		if not _still_here(sid):
			return false
	return _still_here(sid)

func _wait_for_visitors(others: Array, max_wait: float) -> void:
	var waited: float = 0.0
	while waited < max_wait and not _all_arrived(others) and not _members.is_empty():
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	await get_tree().create_timer(0.4).timeout

func _all_arrived(others: Array) -> bool:
	for p in others:
		var v = _vis(p)
		if v != null and not v.arrived:
			return false
	return true

# =========================================================
#  Games: tag and hide and seek, for any number of pets. The pets really run around the whole screen.
#  pet_mover.gd is the movement brain for every pet. The scene gives all screens the same players,
#  the same rounds, the same lines and the same hiding places, but the running itself is simulated
#  on each screen. Everything here is addressed by PEER ID (my own pet included).
# =========================================================
func _mover_of(peer: int) -> RefCounted:
	if peer == _my_peer():
		return _my_mover
	var v = _vis(peer)
	return v.mover if v != null else _dummy_mover

func _pos_of(peer: int) -> Vector2:
	if peer != _my_peer():
		var v = _vis(peer)
		if v != null:
			return v.global_position
	return pet.sprite.global_position

# make sure that pet is steered by its mover (mine: social_manager moves it, visitors: "game" mode)
func _drive(peer: int) -> void:
	if peer == _my_peer():
		_my_driven = true
	else:
		var v = _vis(peer)
		if v != null:
			v.set_mode("game", 900.0)

func _stand(peer: int) -> void:
	_drive(peer)
	_mover_of(peer).stand()

# `peer` runs away from `from_peer`
func _flee(peer: int, from_peer: int) -> void:
	_other_of[peer] = from_peer
	_drive(peer)
	_mover_of(peer).flee(TAG_RUN_SPEED)

# `peer` runs after `target`
func _chase(peer: int, target: int) -> void:
	_other_of[peer] = target
	_drive(peer)
	_mover_of(peer).chase(TAG_CHASE_SPEED)

func _follow(peer: int, points: Array, speed: float, pause: float = 0.0) -> void:
	_drive(peer)
	_mover_of(peer).follow(points, speed, pause)

func _caught(peer: int) -> bool:
	return _mover_of(peer).caught

func _path_done(peer: int) -> bool:
	return _mover_of(peer).path_done

func _all_paths_done(peers: Array) -> bool:
	for p in peers:
		if not _path_done(int(p)):
			return false
	return true

func _drive_my_pet(delta: float) -> void:
	var p: Vector2 = pet.sprite.global_position
	var other: Vector2 = _pos_of(int(_other_of.get(_my_peer(), 0)))
	var np: Vector2 = _my_mover.step(p, other, delta, pet._pet_bounds())
	if np != p:
		pet.sprite.global_position = np
		pet._reposition_hover_info()
		pet.update_clickable_hitbox()

# Stops steering my pet. If a game left it off screen, it walks back in.
func _stop_driving() -> void:
	_my_driven = false
	_other_of.clear()
	_my_mover.stand()
	var b: Rect2 = pet._pet_bounds()
	var p: Vector2 = pet.sprite.global_position
	var inside := Vector2(clampf(p.x, b.position.x, b.end.x), clampf(p.y, b.position.y, b.end.y))
	if p.distance_to(inside) > 1.0:
		pet._glide_pet_to(inside, 0.8, "game")

func _clamp_to_bounds(p: Vector2) -> Vector2:
	var b: Rect2 = pet._pet_bounds()
	return Vector2(clampf(p.x, b.position.x, b.end.x), clampf(p.y, b.position.y, b.end.y))

# A spot on one of the four screen edges (0 left, 1 right, 2 top, 3 bottom). `along` (0..1) is
# the position along that edge. outside = true puts it just OFF the screen (where a hider waits).
func _edge_point(edge: int, along: float, outside: bool) -> Vector2:
	var b: Rect2 = pet._pet_bounds()
	var scr: Rect2 = pet.get_viewport().get_visible_rect()
	var half: Vector2 = (pet.sprite.texture.get_size() * pet.sprite.scale) / 2.0
	var x: float = b.position.x + b.size.x * along
	var y: float = b.position.y + b.size.y * along
	match edge:
		0:
			return Vector2((-half.x - 60.0) if outside else b.position.x, y)
		1:
			return Vector2((scr.end.x + half.x + 60.0) if outside else b.end.x, y)
		2:
			return Vector2(x, (-half.y - 60.0) if outside else b.position.y)
	return Vector2(x, (scr.end.y + half.y + 60.0) if outside else b.end.y)

func _play_game(scene: Dictionary, sid: int) -> void:
	# "caught" distance based on the sprite size
	var w: float = pet.sprite.texture.get_width() * pet.sprite.scale.x
	var catch_distance: float = maxf(50.0, w * 0.9)
	_my_mover.catch_distance = catch_distance
	for p in _scene_players:
		_mover_of(int(p)).catch_distance = catch_distance
	if str(scene.get("game", "tag")) == "hide":
		await _game_hide(scene, sid)
	else:
		await _game_tag(scene, sid)

# Tag: a chain of rounds. In each round "a" is it and chases "b"; everybody else in the game runs
# away from "a" too. Whoever gets caught is "it" in the next round.
func _game_tag(scene: Dictionary, sid: int) -> void:
	var rounds: Array = scene["rounds"]
	var players: Array = [_my_peer()] + _scene_players
	for i in rounds.size():
		var r: Dictionary = rounds[i]
		var it: int = int(r["a"])
		var runner: int = int(r["b"])
		var script: Dictionary = r["script"]
		var ctx := {"a": it, "b": runner}
		if i == 0:
			if not await _say_lines(script.get("setup", []), ctx, sid, 2.8):
				return
		# whoever is "it" stands still and counts while the others get a head start
		for p in players:
			if p == it:
				_stand(p)
			else:
				_flee(p, it)
		if not await _say_lines(script.get("count", []), ctx, sid, 0.9, 0.2):
			return
		# the chase: "it" runs after the runner across the whole screen until it catches them
		_chase(it, runner)
		var taunts: Array = script.get("taunts", []).duplicate()
		var max_time: float = float(script.get("max", 16.0))
		var t: float = 0.0
		var gave_up: bool = false
		while t < max_time + 8.0 and not _caught(it):
			await get_tree().create_timer(0.1).timeout
			if not _still_here(sid):
				return
			t += 0.1
			if not taunts.is_empty() and t >= float(taunts[0].get("t", 0.0)):
				_say_line(taunts.pop_front(), ctx, 2.4)
			if t >= max_time and not gave_up:
				gave_up = true
				_stand(runner)   # the runner is out of breath: an easy catch
		for p in players:
			_stand(p)
		if not await _say_lines(script.get("caught", []), ctx, sid):
			return
		if script.has("end"):
			if not await _say_lines(script["end"], ctx, sid):
				return

# Hide and seek: "a" seeks in every round. All the others hide at the same time, and the seeker
# finds them one after another (round i = the i-th hider). Found hiders walk over and wait by the seeker.
func _game_hide(scene: Dictionary, sid: int) -> void:
	var rounds: Array = scene["rounds"]
	var first: Dictionary = rounds[0]
	var seeker: int = int(first["a"])
	var ctx0 := {"a": seeker, "b": int(first["b"])}
	var script0: Dictionary = first["script"]
	var hiders: Array = []
	for r in rounds:
		hiders.append(int(r["b"]))

	if not await _say_lines(script0.get("setup", []), ctx0, sid, 2.8):
		return
	# the seeker stands still and counts, the hiders run right off the screen (each to their own edge)
	_stand(seeker)
	for r in rounds:
		_follow(int(r["b"]), [_edge_point(int(r["edge"]), float(r["along"]), true)], HIDE_RUN_SPEED)
	if not await _say_lines(script0.get("count", []), ctx0, sid, 2.0, 0.2):
		return
	if not await _wait_until(func() -> bool: return _all_paths_done(hiders), 8.0, sid):
		return
	for h in hiders:
		var hv = _vis(h)
		if hv != null:
			hv.hide_away()   # off screen now: really gone

	# the seeker searches: some random spot, then a wrong edge...
	var b: Rect2 = pet._pet_bounds()
	var wander := Vector2(randf_range(b.position.x, b.end.x), randf_range(b.position.y, b.end.y))
	var spots: Array = [wander, _edge_point(int(first["decoy"]), float(first["decoy_along"]), false)]
	var decoy_lines: Array = script0.get("decoy", [])
	for i in spots.size():
		_follow(seeker, [spots[i]], SEEK_SPEED)
		if i == 0:
			if not await _say_lines(script0.get("search", []), ctx0, sid, 2.2, 0.0):
				return
		if not await _wait_until(func() -> bool: return _path_done(seeker), 14.0, sid):
			return
		if i < decoy_lines.size():
			var decoy_hold: float = _say_line(decoy_lines[i], ctx0, 2.2)
			if not await _pause_for(decoy_hold + 0.2, sid):
				return

	# ...and then the real hiding places, one hider at a time
	for i in rounds.size():
		var r: Dictionary = rounds[i]
		var hider: int = int(r["b"])
		var rctx := {"a": seeker, "b": hider}
		var edge: int = int(r["edge"])
		var along: float = float(r["along"])
		_follow(seeker, [_edge_point(edge, along, false)], SEEK_SPEED)
		if not await _wait_until(func() -> bool: return _path_done(seeker), 14.0, sid):
			return
		# found! the hider pops out from the edge and walks over to the seeker
		var hide_spot: Vector2 = _edge_point(edge, along, true)
		var hv = _vis(hider)
		if hv != null:
			hv.emerge_at(hide_spot)
		var meet: Vector2 = _clamp_to_bounds(_pos_of(seeker) + Vector2(110.0, 0.0).rotated(0.6 + i * 1.3))
		_follow(hider, [meet], 170.0)
		if not await _say_lines(r["script"].get("found", []), rctx, sid):
			return
		_stand(seeker)
		if not await _wait_until(func() -> bool: return _path_done(hider), 4.0, sid):
			return
		_stand(hider)
	var last: Dictionary = rounds[rounds.size() - 1]
	if not await _say_lines(last["script"].get("end", []), {"a": seeker, "b": int(last["b"])}, sid):
		return

func _finish_scene(scene: Dictionary, others: Array) -> void:
	_scene_playing = false
	_scene_players = []
	_stop_driving()
	var kind: String = str(scene.get("kind", "chat"))
	var present: Array = []
	for p in others:
		if _members.has(p):
			present.append(int(p))
	for p in _members.keys():
		_members[p]["visitor"].together_slot = 0

	if not present.is_empty() and PetNetwork.is_connected_to_friend():
		var delta: int = int(scene.get("delta", 0))
		var grudge: int = int(scene.get("grudge", 0))
		stats.add_xp(5)
		for p in present:
			_change_friendship(p, float(delta))
			_remember_scene(p, scene)
		if present.size() == 1:
			# chat / fight / makeup (or a game for two): the outcome is about this one friend
			var peer: int = present[0]
			var m: Dictionary = _members[peer]
			if kind == "fight" or (kind == "confront" and grudge > 0):
				var r: Dictionary = _rel(peer)
				r["fights"] = int(r["fights"]) + 1
				_save_book()
			if bool(scene.get("unfriend", false)):
				var was_together: bool = bool(_rel(peer)["dating"])
				_set_befriended(peer, false)
				if was_together:
					_mark_ex(peer, _scene_role == "a", 20.0)   # the argument ended the relationship too
			if grudge > 0:
				# stalemate: they stay mad for a while and keep their distance
				m["grudge_until"] = _now() + float(grudge)
				m["needs_makeup"] = true
				_rel(peer)["sore"] = true
				_save_book()
				_set_info("%s and %s had a fight..." % [pet.pet_name, _name_of(peer)])
			elif kind == "makeup" or ((kind == "fight" or kind == "confront") and delta > 0):
				m["needs_makeup"] = false
				m["grudge_until"] = 0.0
				_rel(peer)["sore"] = false
				_save_book()
				_celebrate(peer)
				_set_info("%s and %s made up!" % [pet.pet_name, _name_of(peer)])
		if kind == "play":
			_emote_mine("happy")
			for p in present:
				_emote_theirs(p, "happy")
			if present.size() > 1:
				_set_info("%s played with %d friends!" % [pet.pet_name, present.size()])
		if present.size() == 1:
			_apply_stage1_effects(scene, present[0])
	for p in _members.keys():
		_settle_visitor(p)
	_end_busy()

# What a gossip / confrontation / romance scene changes in MY game. Each game only changes its own
# state: the scene says what happened, "a" / "b" (_scene_role) says which side I was.
func _apply_stage1_effects(scene: Dictionary, peer: int) -> void:
	var kind: String = str(scene.get("kind", "chat"))
	var peer_fid: String = _fid_of(peer)
	match kind:
		"gossip":
			var w: Dictionary = scene.get("rumor", {})
			if not w.is_empty():
				if _scene_role == "b":
					_store_gossip(w, peer)
					_set_info("%s told %s something juicy..." % [_name_of(peer), pet.pet_name])
				else:
					_mark_told(str(w.get("id", "")), peer_fid)
					if str(scene.get("mode", "")) == "confide" and _book.has(str(w.get("about", ""))):
						_book[str(w["about"])]["confided"].append(peer_fid)
						_save_book()
		"confront":
			if _scene_role == "a" and str(scene.get("resolve", "")) != "":
				_resolve_rumor(str(scene["resolve"]))
			var blame: Dictionary = scene.get("blame", {})
			if not blame.is_empty() and (str(blame.get("by", "both")) == "both" or _scene_role == "b"):
				_blame(str(blame["fid"]), str(blame.get("why", "lie")))
			var cleared: String = str(scene.get("clear_blame", ""))
			if _scene_role == "a" and cleared != "" and _book.has(cleared):
				_book[cleared]["blamed"] = false
				_book[cleared]["blame_why"] = ""
				_save_book()
			_change_crush(peer, float(scene.get("a_crush" if _scene_role == "a" else "b_crush", 0.0)))
			if _scene_role == "b" and str(scene.get("b_drop", "")) != "" and _book.has(str(scene["b_drop"])):
				var dropped: Dictionary = _book[str(scene["b_drop"])]
				dropped["crush"] = clampf(float(dropped["crush"]) - 25.0, 0.0, 100.0)
				_save_book()
			if str(scene.get("mode", "")) == "crush" and bool(scene.get("truth", false)):
				_emote_mine("heart")
			if str(scene.get("split", "")) != "":
				_apply_breakup(scene, peer)   # a confrontation about trust can end a relationship
				return
		"romance":
			if str(scene.get("mode", "")) == "breakup":
				_apply_breakup(scene, peer)
				return
			if str(scene.get("mode", "")) == "couple":
				_rel(peer)["drift"] = false   # quality time cures growing apart
				_save_book()
	# time together slowly grows a crush (between real friends, scaled by how well they fit)
	_crush_after_scene(kind if kind != "confront" else "", peer)
	if kind == "romance" and (str(scene.get("mode", "")) == "couple" or str(scene.get("mode", "")) == "rekindle"):
		_emote_mine("hearts")

# A breakup scene (or a confrontation that ended in one) has played. Each game only changes its OWN state:
# _scene_role "a" = my pet is the one who ended it. split: "" = they talked it out, "amicable", "messy".
func _apply_breakup(scene: Dictionary, peer: int) -> void:
	var split: String = str(scene.get("split", ""))
	if split == "":
		_rel(peer)["drift"] = false
		_save_book()
		_set_info("%s and %s talked it out and are still together." % [pet.pet_name, _name_of(peer)])
		return
	_mark_ex(peer, _scene_role == "a", float(scene.get("crush_cap", 30.0)))
	if split == "messy":
		_set_befriended(peer, false)
	_emote_mine("sad")
	_emote_theirs(peer, "sad")
	_set_info("%s and %s broke up..." % [pet.pet_name, _name_of(peer)])

# =========================================================
#  Mood summary (what my pet says when asked how it feels)
# =========================================================
func build_mood() -> Dictionary:
	var hunger_text: String
	if stats.hunger >= 70.0:
		hunger_text = "well fed"
	elif stats.hunger >= 40.0:
		hunger_text = "doing fine"
	elif stats.hunger >= 20.0:
		hunger_text = "getting hungry"
	else:
		hunger_text = "very hungry"

	var boredom_text: String
	if stats.boredom <= 30.0:
		boredom_text = "entertained"
	elif stats.boredom <= 60.0:
		boredom_text = "a bit restless"
	else:
		boredom_text = "really bored"

	var happy: float = stats.get_happiness()
	var happy_text: String = "happy" if happy >= 70.0 else ("okay" if happy >= 40.0 else "a little down")

	return {
		"name": pet.pet_name,
		"level": stats.level,
		"summary": "feeling %s, %s and %s." % [happy_text, hunger_text, boredom_text],
		"line": "i'm feeling %s. i'm %s and %s." % [happy_text, hunger_text, boredom_text],
	}
