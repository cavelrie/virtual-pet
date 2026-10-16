extends RefCounted
## STAGE 2: your pet remembers the friends it met online and talks about them when you're playing alone.
## Pure content + numbers (no nodes, no networking), like pet_chat.gd. social_manager.gd decides WHO is
## missed (it owns the friendship book), companion.gd decides WHEN the pet says it, this file decides
## WHAT is said and how long things take.
##
## "kind" says how my pet feels about a friend that is not in the room:
##   dating : my sweetheart            crush : i have a crush on them
##   best   : best friend              friend: a friend
##   met    : we only met once or twice
##   mad    : we're on bad terms (a fight, or they spread a lie / secret)
##
## Tokens: {name} = the friend's pet name, {ago} = "3 days ago" style text, {lvl} = their last known level.
## Lines are lowercase and in character. The name is made safe for the speech balloon by the caller.

# seconds a friend has to be away before my pet starts missing them
const MIN_AWAY := {"dating": 10800, "crush": 21600, "mad": 21600, "best": 28800, "friend": 43200, "met": 86400}
# seconds before my pet brings up the same friend again
const COOLDOWN := {"dating": 7200, "crush": 10800, "mad": 14400, "best": 14400, "friend": 21600, "met": 43200}
# how likely each kind is to be the one my pet talks about
const WEIGHT := {"dating": 4.0, "crush": 3.0, "best": 3.0, "friend": 2.0, "met": 1.0, "mad": 2.0}
# coming back after at least this long gets a proper reunion
const REUNION_MIN_AWAY: int = 7200

const MISS := {
	"dating": [
		"i miss {name}... it's so quiet without them. can we invite them over?",
		"{name} has been on my mind all day. my sweetheart... can we see them?",
		"i keep checking if {name} is here. they're not. i miss them so much.",
		"it's been {ago} since i saw {name}. that's way too long. let's invite them!",
	],
	"crush": [
		"hey, remember {name} from earlier? i keep thinking about them... i want to see them again.",
		"{name} has been on my mind. is that weird? i kind of want to see them again.",
		"i keep thinking about {name}. my tummy does a flip every time. can we invite them?",
		"...so. {name}. i can't stop thinking about {name}. just so you know.",
	],
	"best": [
		"i miss {name}! my best friend! can we invite them over?",
		"it's too quiet without {name}. i have so much to tell them!",
		"i bet {name} would love it here right now. let's invite them!",
	],
	"friend": [
		"i wonder what {name} is up to. want to invite them over?",
		"i miss {name}. we had so much fun last time!",
		"remember {name}? i'd really like to hang out again.",
	],
	"met": [
		"remember {name}, that pet we met? i wonder how they're doing.",
		"i keep thinking about {name}. maybe we could say hi again?",
		"{name} seemed nice. do you think they'd come back if we asked?",
	],
	"mad": [
		"i hope {name} isn't still mad at me... i don't like fighting. maybe we could make up?",
		"i keep thinking about {name} and the whole mess. i want to say sorry. can we invite them?",
		"things got weird with {name}. i'd rather fix it than stay mad.",
	],
}
const YES := {
	"dating": ["yay!! i'll be so happy to see them!!", "okay okay okay! i'm blushing already."],
	"crush": ["really?! okay! i'll act totally normal. (i won't.)", "yay! please don't tell them i said anything!"],
	"best": ["yesss! the room will be so much better!", "okay! i'll save them the best spot!"],
	"friend": ["yay! i'll tidy up the desktop for them.", "yes! let's do it!"],
	"met": ["ooh, okay! a second chance to make a good impression!", "yes! let's say hi!"],
	"mad": ["thank you. i'll be brave. i'll say sorry first.", "okay... deep breath. let's try."],
}
const LATER: Array = [
	"okay. i'll be here, thinking about it.", "no pressure! i'll just keep missing them quietly.",
	"that's okay. maybe later!", "alright! the offer stands.",
]
const FOLLOW_UP: Array = ["so... want to invite them?", "soooo... shall we invite them?", "so, should we send an invite?"]
const MEMORY_START: Array = [
	"the last time was {ago}. they were level {lvl} then.",
	"{ago}, i think. they were level {lvl}. i remember!",
	"it's been {ago}. last i knew they were level {lvl}.",
]
const MEMORY_EXTRA := {
	"dating": " it felt like forever.", "crush": " i counted. don't make it weird.", "best": " i keep a list of everything to tell them.",
	"friend": "", "met": "", "mad": " we didn't leave things on a good note.",
}
# my pet's face when the friend shows up again after a long time
const REUNION := {
	"dating": ["{name}!!! you're here!! i missed you so much!", "{name}... you came back. i was thinking about you the whole time."],
	"crush": ["{name}! oh! hi! i'm totally calm. hi!", "{name}?! i was just thinking about you!! ...hi."],
	"best": ["{name}!!! finally!! i missed you!!", "you're back, {name}! it was way too quiet!"],
	"friend": ["{name}! you came back! yay!", "hi {name}! i missed you!"],
	"met": ["{name}! hi again! it's so nice to see you.", "oh, {name}! you remembered us!"],
}

static func _pick(options: Array) -> Variant:
	return options[randi() % options.size()]

# "about 5 hours ago" / "3 days ago"
static func ago_text(seconds: int) -> String:
	if seconds < 3600:
		return "a little while ago"
	if seconds < 86400:
		var h: int = maxi(1, seconds / 3600)
		return "about %d hour%s ago" % [h, "" if h == 1 else "s"]
	var d: int = maxi(1, seconds / 86400)
	return "%d day%s ago" % [d, "" if d == 1 else "s"]

static func _fill(text: String, name: String, away: int = 0, level: int = 0) -> String:
	return text.replace("{name}", name).replace("{ago}", ago_text(away)).replace("{lvl}", str(level))

static func miss_line(kind: String, name: String, away: int) -> String:
	return _fill(str(_pick(MISS.get(kind, MISS["friend"]))), name, away)

static func yes_line(kind: String, name: String) -> String:
	return _fill(str(_pick(YES.get(kind, YES["friend"]))), name)

static func later_line() -> String:
	return str(_pick(LATER))

static func follow_up_line() -> String:
	return str(_pick(FOLLOW_UP))

static func memory_line(kind: String, name: String, away: int, level: int) -> String:
	var lv: int = maxi(level, 1)
	return _fill(str(_pick(MEMORY_START)), name, away, lv) + str(MEMORY_EXTRA.get(kind, ""))

# "" for kinds that don't get a reunion line (mad: the normal greeting is awkward on purpose)
static func reunion_line(kind: String, name: String) -> String:
	if not REUNION.has(kind):
		return ""
	return _fill(str(_pick(REUNION[kind])), name)
