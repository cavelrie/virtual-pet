extends Node
## Autoload this as "PetNetwork"  (Project Settings > Globals > Autoload).
##
## Handles the connection to a ROOM of up to MAX_PLAYERS people (a Steam lobby) and every message that
## goes between the games.
## Each game keeps full authority over its own pet: messages are only ever
## asks / answers / cosmetic info, never "set your stats to X".
##
## Only three kinds of messages exist:
##   profile : who my pet is (name, level, trait, answers, feeling...)   -> sent to everybody
##   act     : one small action {kind, data}: "say", "ask", "answer", "deliver", "status"
##   scene   : a scripted multi-line scene (chat, play, fight, makeup) written by one side
##
## Every message can be aimed at ONE peer (to_peer = that peer's id) or at everybody (to_peer = 0).
## Every signal tells you which peer it came from. That id comes from Godot itself
## (get_remote_sender_id), never from the message contents, so nobody can pretend to be someone else.

const NameFilter = preload("res://name_filter.gd")   # offensive pet names from other players get replaced

const APP_ID: int = 480                       # Spacewar test id. Swap for your real id later.
const LOBBY_TAG_KEY: String = "game"          # lets you filter your lobbies out of the app-480 crowd
const LOBBY_TAG_VALUE: String = "desktop_pet_friends"
const MAX_PLAYERS: int = 8                    # including you. Raise it if you want bigger rooms.
const MAX_LINES: int = 14
const MAX_LINE_LEN: int = 120
const MAX_GROUP_LINES: int = 16
const MAX_ROUNDS: int = 8
# line groups / numbers a tag or hide and seek script may contain (see pet_chat.gd)
const GAME_LINE_GROUPS: Array = ["setup", "count", "taunts", "caught", "count2", "taunts2", "caught2", "search", "decoy", "found", "end"]
const GAME_NUMBER_KEYS: Array = ["max", "max2"]

# What a friend is allowed to send us (everything else is dropped)
const EMOTE_KEYS: Array = ["heart", "hearts", "angry", "sad", "happy", "spark", "think", "laugh", "gift"]
const FX_KEYS: Array = ["hop", "shake", "wiggle"]
const SCENE_KINDS: Array = ["chat", "play", "fight", "makeup", "gossip", "confront", "romance"]
# Stage 1 (pet_gossip.gd): what a gossip / confrontation / romance scene may carry besides its lines
const GOSSIP_MODES: Array = ["tell", "vent", "confide", "insult", "crush", "jealous", "spreader", "first", "couple", "breakup", "rekindle", "cheater"]
const RUMOR_KINDS: Array = ["insult", "crush"]
const FEELINGS: Array = ["happy", "okay", "down", "hungry", "bored"]

signal status_changed(text: String)
signal friend_connected(peer_id: int)
signal friend_disconnected(peer_id: int)
signal profile_received(from_peer: int, profile: Dictionary)
signal act_received(from_peer: int, kind: String, data: Dictionary)
signal scene_received(from_peer: int, scene: Dictionary)

var steam_ok: bool = false
var lobby_id: int = 0
var is_host: bool = false
var peers: Dictionary = {}          # peer id -> true, everybody else in the room
var status: String = "Not connected"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # Steam callbacks must never be paused
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_init_steam()
	_handle_launch_args()

func _process(_delta: float) -> void:
	if steam_ok:
		Steam.run_callbacks()

func _exit_tree() -> void:
	if lobby_id != 0 and steam_ok:
		Steam.leaveLobby(lobby_id)

# --- Steam setup ---
func _init_steam() -> void:
	var result: Dictionary = Steam.steamInitEx(APP_ID)
	print("[PetNetwork] Steam init: ", result)
	steam_ok = int(result.get("status", 1)) == 0
	if not steam_ok:
		_set_status("Steam isn't available. Is the Steam client running?")
		return
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.join_requested.connect(_on_join_requested)
	_set_status("Not connected")

func _handle_launch_args() -> void:
	# Joined through "Join Game" in the Steam friends list while the game was closed
	var args: PackedStringArray = OS.get_cmdline_args()
	var i: int = args.find("+connect_lobby")
	if i != -1 and i + 1 < args.size() and steam_ok:
		var id: int = int(args[i + 1])
		if id > 0:
			join_steam_lobby(id)
			return

# --- Public API: connecting ---
func host_steam() -> void:
	if not steam_ok:
		_set_status("Steam isn't available. Is the Steam client running?")
		return
	leave()
	_set_status("Creating room...")
	Steam.createLobby(Steam.LobbyType.LOBBY_TYPE_FRIENDS_ONLY, MAX_PLAYERS)

# Opens Steam's own invite window. Only works when the game was started THROUGH Steam (the overlay has to
# attach to it); from the editor or a double-clicked exe it silently does nothing. See invite_steam_friend().
func invite_friend() -> void:
	if steam_ok and lobby_id != 0:
		Steam.activateGameOverlayInviteDialog(lobby_id)

# --- Inviting without the overlay: our own friend picker -------------------------------------------
const FRIEND_FLAG_IMMEDIATE: int = 4   # Steam's "real friends" filter (k_EFriendFlagImmediate)

# Your Steam friends: [{"id": steam id, "name": persona name, "online": bool}], online ones first, then A-Z
func get_steam_friends() -> Array:
	var out: Array = []
	if not steam_ok:
		return out
	for i in Steam.getFriendCount(FRIEND_FLAG_IMMEDIATE):
		var id: int = Steam.getFriendByIndex(i, FRIEND_FLAG_IMMEDIATE)
		out.append({
			"id": id,
			"name": Steam.getFriendPersonaName(id),
			"online": int(Steam.getFriendPersonaState(id)) != 0,   # 0 = offline
		})
	out.sort_custom(_friend_before)
	return out

func _friend_before(a: Dictionary, b: Dictionary) -> bool:
	if bool(a["online"]) != bool(b["online"]):
		return bool(a["online"])
	return str(a["name"]).to_lower() < str(b["name"]).to_lower()

# Sends a normal Steam invite for the room I'm in. They get the same notification as when you invite them
# from the Steam friends list. Returns false if there is no room yet or Steam refused.
func invite_steam_friend(steam_id: int) -> bool:
	if not steam_ok or lobby_id == 0 or steam_id <= 0:
		return false
	return bool(Steam.inviteUserToLobby(lobby_id, steam_id))

func join_steam_lobby(id: int) -> void:
	if not steam_ok or id <= 0 or id == lobby_id:
		return
	leave()
	_set_status("Joining room...")
	Steam.joinLobby(id)

func leave() -> void:
	var had: Array = peers.keys()
	if lobby_id != 0 and steam_ok:
		Steam.leaveLobby(lobby_id)
	lobby_id = 0
	is_host = false
	peers.clear()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_set_status("Not connected")
	for id in had:
		friend_disconnected.emit(int(id))

# True when at least one other pet is in the room
func is_connected_to_friend() -> bool:
	return not peers.is_empty()

# My own peer id (the same number everybody else sees me as). 0 while not connected.
func my_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 0

func _set_status(text: String) -> void:
	status = text
	status_changed.emit(text)

func _update_status() -> void:
	if peers.is_empty():
		if is_host:
			_set_status("Room ready! Press Invite to bring friends.")
		return
	_set_status("Connected! %d other pet%s here." % [peers.size(), "" if peers.size() == 1 else "s"])

# --- Steam callbacks ---
func _on_lobby_created(result, id) -> void:
	if int(result) != Steam.Result.RESULT_OK:
		_set_status("Couldn't create a room (Steam error %s)." % str(result))
		return
	lobby_id = int(id)
	is_host = true
	Steam.setLobbyData(lobby_id, LOBBY_TAG_KEY, LOBBY_TAG_VALUE)
	Steam.setLobbyData(lobby_id, "lobby_name", "%s's pet room" % Steam.getPersonaName())

	var peer := SteamMultiplayerPeer.new()
	var err: int = peer.host_with_lobby(lobby_id)
	if err != OK:
		_set_status("Couldn't start hosting (error %d)." % err)
		leave()
		return
	multiplayer.multiplayer_peer = peer
	_set_status("Room ready! Press Invite to bring friends.")

func _on_lobby_joined(id, _permissions, _locked, response) -> void:
	# Steam also fires this for the host joining their own lobby: ignore that one
	if is_host or Steam.getLobbyOwner(int(id)) == Steam.getSteamID():
		return
	if int(response) != Steam.ChatRoomEnterResponse.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		_set_status("Couldn't join that room (it may be full or closed).")
		return
	lobby_id = int(id)
	var peer := SteamMultiplayerPeer.new()
	var err: int = peer.connect_to_lobby(lobby_id)
	if err != OK:
		_set_status("Couldn't connect to the room (error %d)." % err)
		leave()
		return
	multiplayer.multiplayer_peer = peer
	_set_status("Connecting to the room...")

# Fired when you accept an invite (or "Join Game") while the game is already running
func _on_join_requested(id, _friend_id) -> void:
	join_steam_lobby(int(id))

# --- Multiplayer callbacks ---
# NOTE: with server_relay on (Godot's default) every client also gets peer_connected for every OTHER
# client, so everybody ends up knowing everybody. That is what makes pet-to-pet messages work.
func _on_peer_connected(id: int) -> void:
	if peers.size() >= MAX_PLAYERS - 1:
		multiplayer.multiplayer_peer.disconnect_peer(id)   # room is full
		return
	peers[id] = true
	_update_status()
	# Give the other side a moment to finish setting up before we start sending
	await get_tree().create_timer(0.5).timeout
	if peers.has(id):
		friend_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	if not peers.has(id):
		return
	peers.erase(id)
	friend_disconnected.emit(id)
	if not is_host and id == 1:
		leave()           # a guest lost the host (peer id 1 is always the server): the room is gone
		return
	if peers.is_empty() and is_host:
		_set_status("Everyone left. The room is still open.")
	else:
		_update_status()

func _on_connection_failed() -> void:
	leave()
	_set_status("Couldn't connect to the room.")

func _on_server_disconnected() -> void:
	leave()
	_set_status("The room was closed.")

# --- Public API: messages ---
func _targets(to_peer: int) -> Array:
	if to_peer != 0:
		return [to_peer] if peers.has(to_peer) else []
	return peers.keys()

func send_profile(profile: Dictionary, to_peer: int = 0) -> void:
	for id in _targets(to_peer):
		_rpc_profile.rpc_id(int(id), profile)

func send_act(kind: String, data: Dictionary = {}, to_peer: int = 0) -> void:
	for id in _targets(to_peer):
		_rpc_act.rpc_id(int(id), kind, data)

# My pet says something; it shows up in the other game as a bubble over my visitor pet
func send_say(text: String, emote: String = "", fx: String = "", to_peer: int = 0) -> void:
	send_act("say", {"text": text, "emote": emote, "fx": fx}, to_peer)

# A scene goes ONLY to the pets that take part in it
func send_scene(scene: Dictionary, to_peers: Array) -> void:
	for id in to_peers:
		if peers.has(int(id)):
			_rpc_scene.rpc_id(int(id), scene)

# --- RPC receivers (everything is validated: the other games are friends, not trusted servers) ---
# Returns who sent this, or 0 if it isn't somebody in our room
func _sender() -> int:
	var id: int = multiplayer.get_remote_sender_id()
	return id if peers.has(id) else 0

@rpc("any_peer", "call_remote", "reliable")
func _rpc_profile(profile: Dictionary) -> void:
	var from: int = _sender()
	if from != 0:
		profile_received.emit(from, _clean_profile(profile))

@rpc("any_peer", "call_remote", "reliable")
func _rpc_act(kind: String, data: Dictionary) -> void:
	var from: int = _sender()
	if from != 0:
		act_received.emit(from, _s(kind, 24), _clean_act(data))

@rpc("any_peer", "call_remote", "reliable")
func _rpc_scene(scene: Dictionary) -> void:
	var from: int = _sender()
	if from != 0:
		var clean: Dictionary = _clean_scene(scene)
		if not clean["lines"].is_empty():
			scene_received.emit(from, clean)

# --- Sanitising incoming data ---
func _s(value: Variant, max_len: int) -> String:
	return str(value).strip_edges().substr(0, max_len)

# A pet name that arrived over the network: offensive ones are replaced (empty stays empty)
func _clean_name(name: String, fallback: String = NameFilter.FALLBACK_NAME) -> String:
	if name.is_empty():
		return name
	return NameFilter.clean(name, fallback)

func _clean_profile(p: Dictionary) -> Dictionary:
	var answers: Dictionary = {}
	var raw = p.get("answers", {})
	if raw is Dictionary:
		for k in raw.keys():
			if answers.size() >= 24:
				break
			if raw[k] is String:
				answers[_s(k, 32)] = _s(raw[k], 40)
	var feeling: String = _s(p.get("feeling", "okay"), 12)
	# the axolotl's colour as a hex string like "ff99cc" ("" = the friend didn't pick one)
	var color: String = _s(p.get("color", ""), 8)
	if color != "" and not color.is_valid_html_color():
		color = ""
	return {
		"color": color,
		"id": _s(p.get("id", ""), 40),
		"name": NameFilter.clean(_s(p.get("name", "Friend"), 24)),
		"level": clampi(int(p.get("level", 1)), 1, 9999),
		"trait": _s(p.get("trait", "Balanced"), 20),
		"partner": _clean_name(_s(p.get("partner", ""), 24), ""),   # the name of their sweetheart ("" = single)
		"feeling": feeling if feeling in FEELINGS else "okay",
		"fights": bool(p.get("fights", true)),
		"answers": answers,
	}

# Acts only carry short strings, bools and small numbers
func _clean_act(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d.keys():
		if out.size() >= 8:
			break
		var v = d[k]
		if v is String:
			out[_s(k, 16)] = _s(v, MAX_LINE_LEN)
		elif v is bool:
			out[_s(k, 16)] = v
		elif v is int or v is float:
			out[_s(k, 16)] = clampf(float(v), -1000.0, 1000.0)
	return out

func _clean_line(entry: Variant) -> Dictionary:
	if not (entry is Dictionary) or not (entry.get("who", "") in ["a", "b"]):
		return {}
	var text: String = _s(entry.get("text", ""), MAX_LINE_LEN)
	if text.is_empty():
		return {}
	var emote: String = _s(entry.get("emote", ""), 10)
	var fx: String = _s(entry.get("fx", ""), 10)
	var out: Dictionary = {
		"who": entry["who"],
		"text": text,
		"emote": emote if emote in EMOTE_KEYS else "",
		"fx": fx if fx in FX_KEYS else "",
	}
	if entry.has("t"):   # taunts: seconds into the chase when the line is said
		out["t"] = clampf(float(entry["t"]), 0.0, 120.0)
	return out

# The script of a tag / hide and seek round: named groups of lines plus a few numbers ("max", "max2").
# Only the group names the game actually uses are let through.
func _clean_script(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	for key in GAME_LINE_GROUPS:
		var group = raw.get(key, [])
		if group is Array:
			var lines: Array = []
			for entry in group:
				if lines.size() >= MAX_GROUP_LINES:
					break
				var line: Dictionary = _clean_line(entry)
				if not line.is_empty():
					lines.append(line)
			out[key] = lines
	for key in GAME_NUMBER_KEYS:
		if raw.has(key):
			out[key] = clampf(float(raw[key]), 1.0, 60.0)
	return out

# A group game (tag / hide and seek, any number of pets) is a list of ROUNDS. Each round has two
# pets, "a" and "b" (peer ids), and its own script whose lines say "a" or "b".
func _clean_rounds(raw: Variant, players: Array) -> Array:
	var rounds: Array = []
	if not (raw is Array):
		return rounds
	for r in raw:
		if rounds.size() >= MAX_ROUNDS:
			break
		if not (r is Dictionary):
			continue
		var a: int = int(r.get("a", 0))
		var b: int = int(r.get("b", 0))
		if a == b or not (a in players) or not (b in players):
			continue
		var script: Dictionary = _clean_script(r.get("script", {}))
		if script.is_empty():
			continue
		rounds.append({
			"a": a,
			"b": b,
			"script": script,
			"edge": clampi(int(r.get("edge", 0)), 0, 3),
			"along": clampf(float(r.get("along", 0.5)), 0.0, 1.0),
			"decoy": clampi(int(r.get("decoy", 1)), 0, 3),
			"decoy_along": clampf(float(r.get("decoy_along", 0.5)), 0.0, 1.0),
		})
	return rounds

# A rumour inside a gossip scene: short strings and two flags, nothing else gets through ({} = invalid)
func _clean_rumor(raw: Variant) -> Dictionary:
	if not (raw is Dictionary) or not (str(raw.get("kind", "")) in RUMOR_KINDS):
		return {}
	var out: Dictionary = {
		"id": _s(raw.get("id", ""), 16), "kind": str(raw["kind"]),
		"subj": _s(raw.get("subj", ""), 40), "subj_name": _clean_name(_s(raw.get("subj_name", ""), 24)),
		"about": _s(raw.get("about", ""), 40), "about_name": _clean_name(_s(raw.get("about_name", ""), 24)),
		"twisted": bool(raw.get("twisted", false)), "secret": bool(raw.get("secret", false)),
	}
	if out["subj"] == "" or out["about"] == "" or out["subj_name"] == "" or out["about_name"] == "":
		return {}
	return out

# Everything Stage 1 adds to a scene (kept apart so the original validation above stays readable)
func _clean_gossip_extras(scene: Dictionary, kind: String, out: Dictionary) -> void:
	if not (kind in ["gossip", "confront", "romance"]):
		return
	var mode: String = _s(scene.get("mode", ""), 10)
	if mode in GOSSIP_MODES:
		out["mode"] = mode
	if kind == "gossip":
		out["rumor"] = _clean_rumor(scene.get("rumor", {}))
	out["resolve"] = _s(scene.get("resolve", ""), 16)
	out["truth"] = bool(scene.get("truth", true))
	out["dating"] = bool(scene.get("dating", false)) and kind == "romance"
	out["a_crush"] = clampf(float(scene.get("a_crush", 0.0)), 0.0, 20.0)
	out["b_crush"] = clampf(float(scene.get("b_crush", 0.0)), 0.0, 20.0)
	out["b_drop"] = _s(scene.get("b_drop", ""), 40)
	# breakups: how it ended ("" = they talked it out) and what is left of the crush afterwards
	var split: String = _s(scene.get("split", ""), 10)
	out["split"] = split if (split in ["amicable", "messy"] and (kind == "romance" or kind == "confront")) else ""
	out["crush_cap"] = clampf(float(scene.get("crush_cap", 100.0)), 0.0, 100.0)
	out["clear_blame"] = _s(scene.get("clear_blame", ""), 40)
	var raw_blame = scene.get("blame", null)
	if raw_blame is Dictionary and _s(raw_blame.get("fid", ""), 40) != "":
		var why: String = _s(raw_blame.get("why", "lie"), 8)
		var by: String = _s(raw_blame.get("by", "both"), 8)
		out["blame"] = {
			"fid": _s(raw_blame["fid"], 40), "name": _clean_name(_s(raw_blame.get("name", "somebody"), 24)),
			"why": why if why in ["lie", "secret"] else "lie",
			"by": by if by in ["both", "b"] else "both",
		}

func _clean_scene(scene: Dictionary) -> Dictionary:
	var kind: String = _s(scene.get("kind", "chat"), 12)
	if not kind in SCENE_KINDS:
		kind = "chat"
	var out_lines: Array = []
	var raw = scene.get("lines", [])
	if raw is Array:
		for entry in raw:
			if out_lines.size() >= MAX_LINES:
				break
			var line: Dictionary = _clean_line(entry)
			if not line.is_empty():
				out_lines.append(line)
	var out: Dictionary = {
		"kind": kind,
		"lines": out_lines,
		"delta": clampi(int(scene.get("delta", 0)), -20, 20),
		"grudge": clampi(int(scene.get("grudge", 0)), 0, 300),
		"unfriend": bool(scene.get("unfriend", false)) and (kind == "fight" or kind == "confront"),
	}
	_clean_gossip_extras(scene, kind, out)
	# Tag / hide and seek: every pet that takes part gets the same list of players and rounds, so all
	# screens agree on who is "it", who hides where, and which lines are said.
	if kind == "play" and scene.has("rounds"):
		var players: Array = []
		var raw_players = scene.get("players", [])
		if raw_players is Array:
			for p in raw_players:
				var pid: int = int(p)
				if players.size() < MAX_PLAYERS and pid != 0 and not (pid in players):
					players.append(pid)
		var rounds: Array = _clean_rounds(scene["rounds"], players)
		if players.size() >= 2 and not rounds.is_empty():
			var game: String = _s(scene.get("game", "tag"), 8)
			out["game"] = game if game in ["tag", "hide"] else "tag"
			out["players"] = players
			out["rounds"] = rounds
	# topics are only used by the pet that wrote the scene, but harmless short strings
	var topics: Array = []
	var raw_topics = scene.get("topics", [])
	if raw_topics is Array:
		for t in raw_topics:
			if topics.size() >= 8:
				break
			topics.append(_s(t, 40))
	out["topics"] = topics
	return out
