extends RefCounted
## Blocks offensive pet names (slurs, hate figures, sexual / abusive terms) in MULTIPLAYER.
## Used by pet_network.gd on every name that arrives from another player. Your own pet's name
## is never changed: in singleplayer it can be anything, only what OTHER people would see is filtered.
##
## How it matches (so people can't dodge it with spaces, symbols or numbers):
##   1. lowercase, then undo common "leetspeak" (n1gg3r, h1tl3r, c*m ...)
##   2. SUBSTRING terms are checked against the name with everything except letters removed
##      ("n i g g e r", "n.i.g.g.e.r"). Only use terms here that can't hide inside normal words.
##   3. WORD terms only match as whole words (or word + "s"), so names like "Scunthorpe", "Grape",
##      "Raccoon" or "Cockatiel" are left alone.
##   4. Single letters typed one by one ("c u m") are joined back together before the word check.
## This is a starting list, not a complete one. Add to it whenever something slips through.

const FALLBACK_NAME: String = "Axolotl"

# Checked inside the letters-only version of the name. Keep these long / distinctive.
const SUBSTRING_TERMS: Array = [
	"nigger", "nigga", "faggot", "wetback", "beaner", "kkk", "hitler", "siegheil", "whitepower",
	"whitepride", "cumguzz", "cumslut", "cumdump", "cumsock", "cumrag", "cumbucket", "retarded",
	"goebbels", "himmler", "mengele", "eichmann", "bitchass", "cuntface", "motherfuck",
]

# Matched as whole words only (an optional trailing "s" is allowed).
const WORD_TERMS: Array = [
	# racial / ethnic / religious slurs
	"kike", "spic", "chink", "gook", "coon", "paki", "darkie", "negro", "towelhead", "raghead",
	"gypsy", "wop", "jap", "zipperhead", "redskin", "tranny", "shemale",
	# homophobic / ableist slurs
	"fag", "fags", "dyke", "retard", "spaz", "mong",
	# hate figures and symbols
	"nazi", "neonazi", "nazism", "heil", "gestapo", "fuhrer", "adolf", "hitlers", "swastika", "1488",
	"holocaust", "kukluxklan",
	# sexual / abusive
	"cum", "cumming", "cunt", "twat", "whore", "slut", "bitch", "pussy", "blowjob", "handjob",
	"rape", "raped", "rapist", "rapey", "molest", "molester", "pedo", "paedo", "pedophile", "incest",
	"porn", "hentai", "dildo", "jizz", "cumshot", "orgasm", "fuck", "fucker", "fucking", "shit",
	"asshole", "bastard", "nude", "nudes", "horny", "kys",
]

const LEET := {
	"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b",
	"@": "a", "$": "s", "!": "i", "+": "t", "|": "i", "(": "c", "*": "u",
}

static var _ready_lists: bool = false
static var _words: Dictionary = {}

# Returns the name unchanged, or FALLBACK_NAME if it is not allowed.
static func clean(raw: String, fallback: String = FALLBACK_NAME) -> String:
	if raw.strip_edges().is_empty():
		return fallback
	return fallback if is_bad(raw) else raw

static func is_bad(raw: String) -> bool:
	_prepare()
	var lowered: String = raw.to_lower()
	# raw digits first, before leetspeak turns them into letters ("1488")
	var digits: String = ""
	for ch in lowered:
		if ch >= "0" and ch <= "9":
			digits += ch
	if digits.contains("1488"):
		return true

	var mapped: String = ""
	for ch in lowered:
		mapped += LEET.get(ch, ch)

	# 1. letters only, runs of 3+ identical letters squeezed to 2 ("niggggger" -> "nigger")
	var letters: String = _collapse(_letters_only(mapped))
	for term in SUBSTRING_TERMS:
		if letters.contains(term):
			return true

	# 2. whole words (single letters typed one by one get joined: "c u m" -> "cum")
	for token in _tokens(mapped):
		var t: String = _collapse(token)
		if _words.has(t) or (t.ends_with("s") and _words.has(t.trim_suffix("s"))):
			return true
	return false

static func _prepare() -> void:
	if _ready_lists:
		return
	_ready_lists = true
	for w in WORD_TERMS:
		_words[str(w)] = true

static func _letters_only(s: String) -> String:
	var out: String = ""
	for ch in s:
		if ch >= "a" and ch <= "z":
			out += ch
	return out

# squeeze runs of 3 or more identical letters down to 2
static func _collapse(s: String) -> String:
	var out: String = ""
	var run: int = 0
	var last: String = ""
	for ch in s:
		if ch == last:
			run += 1
		else:
			run = 1
			last = ch
		if run <= 2:
			out += ch
	return out

# Words made of letters. Neighbouring single letters are glued together.
static func _tokens(s: String) -> Array:
	var cleaned: String = ""
	for ch in s:
		cleaned += ch if (ch >= "a" and ch <= "z") else " "
	var out: Array = []
	var glued: String = ""
	for tok in cleaned.split(" ", false):
		if tok.length() == 1:
			glued += tok
		else:
			if glued != "":
				out.append(glued)
				glued = ""
			out.append(tok)
	if glued != "":
		out.append(glued)
	return out
