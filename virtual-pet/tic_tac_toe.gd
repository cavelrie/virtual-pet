class_name TicTacToe
extends Node
## Tic tac toe: you are X, the pet is O.
## Fills a GridContainer with 9 buttons (same idea as the shop grid).
## Emits `commentary(event)` so the companion can react. Events:
##   start, next_you, next_pet, player_move, player_block,
##   pet_move, pet_block, pet_slip, player_win, pet_win, draw

signal commentary(event: String)

const PLAYER: String = "X"
const PET: String = "O"
const LINES: Array = [
	[0, 1, 2], [3, 4, 5], [6, 7, 8],  # rows
	[0, 3, 6], [1, 4, 7], [2, 5, 8],  # columns
	[0, 4, 8], [2, 4, 6],             # diagonals
]
const CELL_SIZE: Vector2 = Vector2(64, 64)
const PET_MISTAKE_CHANCE: float = 0.25  # how often the pet plays a random move (keeps it beatable)
const WIN_COINS: int = 10
const DRAW_COINS: int = 3

var grid: GridContainer
var status_label: Label
var pet_score_label: Label
var you_score_label: Label
var stats: petstats
var pet_name: String = "Companion"

var board: Array[String] = []
var cells: Array[Button] = []
var player_turn: bool = true
var game_over: bool = false
var player_starts: bool = true
var player_score: int = 0
var pet_score: int = 0
var rounds_played: int = 0  # finished rounds in the current match (dialogue can read this)

var _round_id: int = 0  # bumped on every reset so stale timers do nothing
var _pet_move_kind: String = "move"


func setup(p_grid: GridContainer, p_status: Label, p_pet_score: Label, p_you_score: Label, p_stats: petstats) -> void:
	grid = p_grid
	status_label = p_status
	pet_score_label = p_pet_score
	you_score_label = p_you_score
	stats = p_stats
	_build_cells()


func _build_cells() -> void:
	grid.columns = 3
	for c in grid.get_children():
		c.queue_free()
	cells.clear()

	for i in 9:
		var btn := Button.new()
		btn.custom_minimum_size = CELL_SIZE
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 28)
		btn.pressed.connect(_on_cell_pressed.bind(i))
		grid.add_child(btn)
		cells.append(btn)


# --- Round flow ---
func start_new_match(p_pet_name: String) -> void:
	pet_name = p_pet_name
	player_score = 0
	pet_score = 0
	rounds_played = 0
	player_starts = true
	_update_scores()
	start_round()
	commentary.emit("start")


func start_round() -> void:
	_round_id += 1
	game_over = false
	board.clear()
	for i in 9:
		board.append("")
		cells[i].text = ""
		cells[i].disabled = false
		cells[i].modulate = Color.WHITE

	player_turn = player_starts
	player_starts = not player_starts  # alternate who opens next round

	if player_turn:
		_set_status("your turn!")
		if rounds_played > 0:
			commentary.emit("next_you")
	else:
		_set_status("%s goes first..." % pet_name)
		if rounds_played > 0:
			commentary.emit("next_pet")
		_pet_turn_delayed()


func stop() -> void:
	_round_id += 1  # cancels any pending timers


func _on_cell_pressed(i: int) -> void:
	if game_over or not player_turn or board[i] != "":
		return

	var blocks_pet: bool = _find_line_move(PET) == i
	_place(i, PLAYER)
	if _check_end():
		return
	commentary.emit("player_block" if blocks_pet else "player_move")

	player_turn = false
	_set_status("%s is thinking..." % pet_name)
	_pet_turn_delayed()


func _pet_turn_delayed() -> void:
	var id := _round_id
	await get_tree().create_timer(0.6).timeout
	if id != _round_id or game_over:
		return

	_place(_choose_pet_move(), PET)
	if _check_end():
		return

	match _pet_move_kind:
		"block":
			commentary.emit("pet_block")
		"slip":
			commentary.emit("pet_slip")
		_:
			commentary.emit("pet_move")

	player_turn = true
	_set_status("your turn!")


func _place(i: int, mark: String) -> void:
	board[i] = mark
	cells[i].text = mark


# --- Win / draw handling ---
func _check_end() -> bool:
	var line := _winning_line()
	if not line.is_empty():
		game_over = true
		rounds_played += 1
		var winner: String = board[line[0]]
		for i in line:
			cells[i].modulate = Color(1.0, 0.9, 0.4)
		if winner == PLAYER:
			player_score += 1
			_set_status("you win! +%d coins" % WIN_COINS)
			if stats:
				stats.complete_game(1.0)
				stats.add_coins(WIN_COINS)
			_update_scores()
			commentary.emit("player_win")
		else:
			pet_score += 1
			_set_status("%s wins this one!" % pet_name)
			if stats:
				stats.complete_game(0.25)
			_update_scores()
			commentary.emit("pet_win")
		_finish_round()
		return true

	if not board.has(""):
		game_over = true
		rounds_played += 1
		_set_status("it's a draw! +%d coins" % DRAW_COINS)
		if stats:
			stats.complete_game(0.5)
			stats.add_coins(DRAW_COINS)
		_update_scores()
		commentary.emit("draw")
		_finish_round()
		return true

	return false


func _finish_round() -> void:
	for b in cells:
		b.disabled = true
	var id := _round_id
	await get_tree().create_timer(3.5).timeout  # long enough to read the pet's reaction
	if id == _round_id:
		start_round()


func _winning_line() -> Array:
	for line in LINES:
		var m: String = board[line[0]]
		if m != "" and m == board[line[1]] and m == board[line[2]]:
			return line
	return []


# --- Pet "AI": win > block > center > corner > anything (with a few random slips) ---
func _choose_pet_move() -> int:
	var empties: Array[int] = []
	for i in 9:
		if board[i] == "":
			empties.append(i)

	var win_move := _find_line_move(PET)
	var block_move := _find_line_move(PLAYER)

	if randf() < PET_MISTAKE_CHANCE:
		# only counts as a "slip" if it skipped a win or a block it could have made
		_pet_move_kind = "slip" if (win_move != -1 or block_move != -1) else "move"
		return empties.pick_random()

	if win_move != -1:
		_pet_move_kind = "win"
		return win_move
	if block_move != -1:
		_pet_move_kind = "block"
		return block_move

	_pet_move_kind = "move"
	if board[4] == "":
		return 4

	var corners: Array[int] = []
	for c in [0, 2, 6, 8]:
		if board[c] == "":
			corners.append(c)
	if not corners.is_empty():
		return corners.pick_random()
	return empties.pick_random()


func _find_line_move(mark: String) -> int:
	for line in LINES:
		var count := 0
		var empty_idx := -1
		for i in line:
			if board[i] == mark:
				count += 1
			elif board[i] == "":
				empty_idx = i
		if count == 2 and empty_idx != -1:
			return empty_idx
	return -1


# --- UI helpers ---
func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text


func _update_scores() -> void:
	if you_score_label:
		you_score_label.text = "You: %d" % player_score
	if pet_score_label:
		pet_score_label.text = "%s: %d" % [pet_name, pet_score]
