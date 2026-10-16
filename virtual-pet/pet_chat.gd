extends RefCounted
## Everything the pets say to each other. Pure content + script building: no nodes, no networking.
## All lines are lowercase and in character. Tokens inside lines:
##   {me}  = the speaker's name        {you} = the other pet's name
##   {mine} / {theirs} = answer values (see _vals)        {item} = a gift's name
##
## A "scene" is a script the initiating pet writes and both games play locally:
##   {"kind": "chat"|"play"|"fight"|"makeup", "lines": [{who, text, emote, fx}], "delta": int,
##    "grudge": seconds, "unfriend": bool}
## who = "a" is the pet that started it, "b" is the other one.
##
## Relationship tiers used everywhere: "stranger", "acquaintance", "friend", "best", "rival"

# keys of stats.player_answers the pets like to talk about (the human's answers)
const TOPICS := {
	"favorite_snack": ["my human is all about {mine}.", "lately my human keeps going for {mine}.", "my human's favorite snack is {mine}. i've seen the crumbs."],
	"music_pref": ["my human listens to {mine} when working.", "my human's music is {mine}. i know every beat.", "{mine} is what my human puts on. i like it."],
	"color_pref": ["my human is a {mine} person.", "my human says {mine} feel like them.", "i think {mine} suit my human best."],
	"drink_pref": ["my human's go-to drink is {mine}.", "my human basically runs on {mine}.", "there's always {mine} nearby when my human works."],
	"pet_animal": ["my human says i'd be {mine}.", "my human thinks i'm {mine}. kind of accurate.", "i'm {mine}, according to my human."],
	"weather_pref": ["my human loves {mine} days.", "my human is a {mine} weather person.", "{mine} days are my human's favorite."],
	"fav_spot": ["if my human could go anywhere: {mine}.", "my human's dream adventure is {mine}.", "my human wants {mine} for the perfect day."],
	"unwind_style": ["my human unwinds with {mine}.", "after a long day my human goes for {mine}.", "my human's reset button is {mine}."],
	"dream_room": ["my human's dream room is {mine}.", "my human talks about {mine} a lot.", "i've heard all about {mine}. my human wants it so bad."],
	"superpower": ["my human wants the power of {mine}.", "if my human had a power, it'd be {mine}.", "my human would pick {mine}. very them."],
	"season_fav": ["my human's favorite season is {mine}.", "my human is all about {mine}.", "every year my human can't wait for {mine}."],
	"comfort_food": ["my human's comfort food is {mine}.", "when my human is down, it's {mine} time.", "my human swears by {mine} for a bad day."],
	"desk_style": ["my human's desk is {mine}.", "my human keeps a desk that's {mine}.", "i live on a desktop that's {mine}. well, the desk is."],
	"wyr_pet": ["my human would pick the {mine}.", "given the choice, my human takes the {mine}.", "the {mine}! that's my human's pick."],
}
const SAME_REACT: Array = [
	"no way, mine too!", "wait, really?? same!!", "ha! we have the same human taste.", "oh my gosh, same!!",
	"stop it, that's mine too!", "whoa. we're basically the same pet.",
]
const DIFF_REACT: Array = [
	"ooh, mine's more into {mine}. different but cool!", "huh, {theirs}? mine likes {mine}.",
	"{theirs}? neat! mine is {mine}.", "mine picked {mine}, but i get it.",
	"{theirs}... i might have to try that.", "interesting! mine goes for {mine} instead.",
]
const TEASE_REACT: Array = [
	"{theirs}?? mine would never. {mine} all the way.", "ha, {mine} is clearly better. sorry not sorry.",
	"{theirs}... really? okay, i love you anyway.", "we can't be friends. (kidding. mostly.) mine is {mine}.",
]
const SMALLTALK: Array = [
	["do you ever chase the cursor?", "all the time!! it's so fast, i never catch it."],
	["my human taps me sometimes. best part of my day.", "same! the taps are my favorite."],
	["what do you do when your human's away?", "sit very still and pretend i'm a statue."],
	["i found a really cozy corner of the desktop.", "show me later!!"],
	["do you think the other icons are alive?", "the little folder is definitely alive. i named it steve."],
	["have you tried spinning really fast?", "yes!! i got so dizzy. 10/10."],
	["what's your human like?", "a little messy, very sweet. yours?"],
	["i had a dream about a giant yarn ball.", "no way, i dreamed about snacks. we're so different."],
	["do you think keyboards sound like rain?", "the best rain. i fall asleep to it."],
	["sometimes i just sit and do nothing. it's a skill.", "a very underrated skill."],
	["i tried to catch a pixel earlier.", "did you get it?? ...of course not. they're fast."],
	["if you could have any snack right now, what would it be?", "an apple. a big, shiny one."],
	["do you ever wonder what's past the edge of the screen?", "all the time. i think it's just more desktop."],
	["what's the best part of being a desktop pet?", "the warm glow from the monitor. and the taps."],
	["do you get lonely when your human leaves?", "a little. but then they come back and it's the best."],
	["i wish i could smell things.", "same. i bet apples smell amazing."],
	["what do you want to be when you grow up?", "a really big pet. with a really big hat."],
	["do you ever get nervous?", "sometimes. then i think about snacks and it passes."],
	["what's your favorite time of day?", "when my human comes back and says hi."],
	["do you think our humans talk about us?", "i hope so. i'd want them to say nice things."],
	["i found a crumb earlier. i'm calling it a snack.", "a crumb is a snack if you believe hard enough."],
	["what's the weirdest thing on your human's desktop?", "a folder called 'misc misc final'. i'm scared of it."],
	["do you ever talk to the cursor?", "every day. it never answers. i respect that."],
	["i learned a new trick today!", "show me!! ...okay that's just falling over. but a great fall."],
	["sometimes my human stares at the screen for hours.", "mine too. i think they're talking to the little glowing rectangle."],
	["what's the scariest thing you've seen?", "the loading circle. it never ends."],
	["do you think clouds taste like cotton candy?", "no, i think they taste like nothing. which is also nice."],
	["i'm trying to learn how to whistle.", "how's it going? ...oh, that's just air. keep practicing."],
	["what's your favorite sound?", "the little 'ding' when my human gets a message."],
	["have you ever tried hiding behind a window?", "yes. it works until my human moves it."],
	["i think my human is secretly really smart.", "mine is secretly really tired. same thing."],
	["what would you name a pet pet?", "sir fluffington. no questions."],
	["i tried to eat a pixel once.", "and?? what did it taste like?? ...nothing. right."],
	["do you ever pretend the taskbar is a bridge?", "every single day. i'm the troll under it."],
	["what's the best nap spot you've found?", "right behind the clock. it's warm and ticks softly."],
	["i want to see the ocean someday.", "me too. my human has a picture of it. i stare at it."],
	["do you think pets can have best friends AND rivals?", "yes. my rival is the recycling bin."],
	["i keep hearing a tiny hum from the computer.", "that's the computer purring. don't tell anyone i know."],
	["what's your human's worst habit?", "forgetting to snack me. i love them anyway."],
	["have you ever tried to dance?", "all the time! i just wiggle and call it dancing."],
	["do you think the sun gets tired?", "probably. that's why it goes to bed."],
	["my human told me a secret today.", "ooh, what was it?? ...okay fine. you keep it safe."],
	["i've been collecting shiny things.", "same! i have a very shiny button. don't touch."],
	["what's the best thing about mondays?", "nothing. but my human is cuddlier."],
	["do you ever hum when you're happy?", "constantly. my human probably hears it."],
	["i wish i could taste a real apple.", "same. they look so crunchy."],
	["what's the longest you've stayed awake?", "all night. my human was working late. we kept each other company."],
	["i can do a really good spin.", "do it!! ...ooh, 9 out of 10! the landing needs work."],
	["did you ever get lost on the desktop?", "once. i found three old screenshots and a lot of dust."],
	["what's your human's room like?", "messy but cozy. lots of cups."],
	["sometimes i practice what to say before i talk to someone new.", "i do that too! it never goes how i plan."],
	["do you believe in luck?", "i believe in lucky snacks."],
	["i heard that some pets can talk to the weather.", "i tried. it rained anyway. so... maybe?"],
	["what's the nicest thing your human did for you?", "they stayed up to keep me company when i was sad."],
	["i like it when the screen gets warm.", "it's like a tiny sunbeam. best nap."],
	["do you ever imagine being huge?", "yes. i'd be a giant pet, but a friendly one."],
	["if you could change color, what would you pick?", "sparkly. just sparkly."],
	["what do you do when you can't sleep?", "count windows. there are always more than i remember."],
	["i got my first level up in a while!", "congrats!! level ups feel like tiny fireworks."],
	["do you think we dream the same dreams?", "if we do, i hope you share your snacks in them."],
	["i'm bad at waiting.", "me too. i've been waiting for lunch since breakfast."],
	["what's the loudest sound you've ever heard?", "my human's alarm. i fell off the desktop."],
	["i like watching the little progress bars.", "they're so honest. they always get there. eventually."],
	["what's something you're proud of?", "i learned all the icons' names. except steve. he won't say."],
	["do you ever wish you had hands?", "constantly. i'd high five everyone."],
	["have you seen the moon from the screen?", "i have! it's my favorite wallpaper moment."],
	["i think the screen saver is watching me.", "it's not. it's just very dramatic."],
	["what do you think about when it's quiet?", "snacks, mostly. sometimes friends. mostly snacks."],
	["i'm learning how to be brave.", "you already are. you're talking to me!"],
	["my human laughed at something i did.", "that's the best! i'd do anything to hear that."],
	["what's your favorite thing to watch?", "my human typing. it looks like tiny rain."],
	["do you ever get the zoomies?", "all the time. the whole desktop becomes a racetrack."],
	["what's the best gift you've ever gotten?", "a yarn ball. it still has my tooth marks."],
	["i tried to learn a joke.", "tell it!! ...i didn't get it. but i laughed anyway."],
	["what's your favorite thing about visiting?", "meeting new pets. and rearranging the desktop a little."],
	["i keep thinking about what we talked about last time.", "me too. you said something that stuck with me."],
	["do you ever just look at the other pets and think 'wow'?", "yes. we're all just tiny miracles with a lot of opinions."],
	["what's the weirdest food you've ever wanted?", "a cloud with sprinkles. it didn't exist. sad."],
	["if you had a day off, what would you do?", "nap, then snack, then nap again. repeat."],
]
const TRAITS := {
	"Cheerfulness": ["i'm just so happy today!", "i woke up smiling and it won't stop."],
	"Curiosity": ["i wonder what's behind that window...", "i have like a million questions today."],
	"Affection": ["i'm so glad we get to hang out.", "i love it when my human taps me."],
	"Energy": ["i've got so much energy, i could run laps!", "i can't sit still today!"],
	"Calmness": ["it's so nice and peaceful today.", "i could sit here and watch the cursor all day."],
	"Balanced": ["today is a pretty good day.", "not much going on. i like it."],
}
# [a, b, emote, fx]
const OPEN := {
	"stranger": [
		["hi! i'm {me}. what's your name?", "i'm {me}! nice to meet you!", "", ""],
		["um, hi... i'm {me}. do you live here too?", "kind of! i'm {me}. i'm visiting.", "", ""],
		["oh! hello! i'm {me}!", "hi hi! i'm {me}!", "happy", ""],
		["hey... i'm {me}. i hope this isn't weird.", "not weird at all! i'm {me}. hi!", "", ""],
	],
	"acquaintance": [
		["hey {you}! it's {me}! we met before, right?", "yeah! hi {you}! good to see you again.", "happy", ""],
		["oh, {you}! i was hoping to run into you.", "me too! what's new?", "", ""],
		["{you}! you came back!", "of course! i like it here.", "happy", ""],
		["hi again, {you}!", "hi {you}! how've you been?", "", ""],
	],
	"friend": [
		["{you}!! hiii!", "{you}! i'm so happy you're here!", "heart", "hop"],
		["there you are, {you}! i was waiting for you!", "sorry i'm late! i missed you!", "heart", ""],
		["{you}!! come sit with me!", "yes!! scoot over!", "happy", "hop"],
		["look who it is! hi {you}!", "hi hi hi {you}!", "happy", "wiggle"],
	],
	"best": [
		["{you}!!! i missed you so much!", "{you}!!! i missed you too!! come here!", "hearts", "hop"],
		["my favorite pet in the whole world is here!", "stop, you're making me blush!", "hearts", "wiggle"],
		["{you}!! finally!! i have so much to tell you!", "me too!! okay you first!", "heart", "hop"],
	],
	"partner": [
		["{you}!! there you are, my favorite pet!", "{you}!! i was just thinking about you!", "hearts", "hop"],
		["hi, sweetheart.", "hi, you. come here.", "heart", ""],
		["{you}... i missed you.", "i missed you too. come sit with me.", "hearts", "wiggle"],
		["there's my person.", "there's mine.", "heart", "wiggle"],
	],
	"rival": [
		["oh. it's you.", "oh. hi. i guess.", "", ""],
		["...hi, {you}.", "...hi, {you}.", "", ""],
		["ugh, you're here.", "i could say the same.", "angry", ""],
	],
}
# [commenter, replier, (optional comfort line from the commenter)]
const FEELING := {
	"hungry": [
		["{you}, was that your tummy?? i heard it from here.", "...maybe. my human is slow with the snacks."],
		["you sound hungry, {you}.", "so hungry. i could eat a whole cloud."],
	],
	"bored": [
		["you look bored, {you}.", "so bored. i've counted every pixel twice."],
		["{you}, you okay? you're staring at nothing.", "just bored. my human hasn't played with me in ages."],
	],
	"down": [
		["hey, you okay, {you}?", "i'm a little down today.", "i'm right here, okay? we can just sit together."],
		["{you}... you seem sad.", "kind of. it's just one of those days.", "then i'll sit with you. no talking needed."],
	],
}

# --- asks / answers (the pet speaks these in its bubble) ---
const ASK := {
	"befriend": [
		"{you}... can i ask you something? do you wanna be friends?",
		"i really like hanging out with you. wanna be friends?",
		"hey {you}, would you be my friend? like, officially?",
		"so... friends? i'd really like that.",
	],
	"gift": [
		"{you}! i got you a {item}. do you want it?",
		"psst, {you}... i have a {item} for you. want it?",
		"i found a {item} and thought of you. want it?",
	],
	"play": [
		"{you}, wanna play tag?", "i'm so full of energy... wanna play with me?",
		"race you around the screen? wanna play?", "{you}!! play with me!",
	],
	"mood": [
		"hey {you}, how are you feeling today?", "{you}, are you doing okay today?", "how's your day going, {you}?",
	],
}
const ANSWER_YES := {
	"befriend": ["yes!! i was hoping you'd ask!", "of course! i'd love to be friends!", "aww, yes! friends!"],
	"gift": ["ooh, for me?? yes please!", "aww, thank you! i'd love it!", "yes!! you're so sweet!"],
	"play": ["yes!! you're it!", "yesss let's go!", "okay okay okay, ready!"],
}
const ANSWER_NO := {
	"befriend": ["hmm... i think i need to know you a bit more first.", "aww... not yet? can we hang out more first?", "i'm not sure yet... maybe later?"],
	"gift": ["aw, that's sweet, but no thanks.", "hmm, i'm okay, thanks!", "keep it! i don't need it."],
	"play": ["maybe later? i'm kinda tired.", "not right now... sorry!", "hmm, not in the mood right now."],
	"mood": ["hmph. i'm fine.", "...fine. don't ask."],
}
const SAD_AFTER_NO: Array = ["oh. okay... that's fair.", "oh... okay. maybe later then!", "that's okay! i'll try again another time."]
const CHEER_FRIENDS: Array = ["yay!! we're friends now!", "yesss!! best day ever!", "we're FRIENDS! i'm so happy!"]
const GIVE_LINES: Array = ["here you go!", "tada! it's all yours!", "for you! i hope you like it."]
const THANKS_GENERIC: Array = ["thank you so much!! i love it!", "aww, you're so thoughtful!", "i'll keep it safe forever!"]
const THANKS_ATE: Array = ["*nom nom* i was SO hungry. thank you!!", "you saved me!! *munch* thank you!!"]
const THANKS_PLAYED: Array = ["a yarn ball!! i needed this!", "yes!! *pounces* thank you!!"]
const COMFORT: Array = ["aww, i hope today gets better. i'm here!", "you can lean on me, okay?", "sending you a very big pretend hug."]
const WORRY: Array = ["oh no... i hope you get a snack soon!", "i wish i could share my lunch with you..."]

# --- fights ---
const FIGHT_TOPIC_A: Array = [
	"{mine} is obviously the best. everything else is wrong.",
	"i can't believe your human likes {theirs}. {mine} is the only good one.",
]
const FIGHT_TOPIC_B: Array = [
	"excuse me?? {theirs}? no way. {mine} is way better.",
	"wow. rude. {mine} beats {theirs} any day.",
]
const GRIPES: Array = [
	["you stepped on my spot.", "it's not YOUR spot!"],
	["you keep stealing the sunbeam!", "the sunbeam belongs to everyone!"],
	["you were staring at me.", "i was NOT staring."],
	["your human gets more coins than mine. unfair.", "that's not my fault!"],
	["you always get to be the visitor. must be nice.", "oh, so now it's MY fault?!"],
]
const ESCALATE: Array = [
	["you take that back!", "make me!"],
	["you're being so annoying right now!", "no, YOU'RE annoying!"],
	["i can't even look at you!", "then don't!"],
	["you're so stubborn!", "you're the stubborn one!"],
]
const MAKEUP_IN_FIGHT: Array = [
	["...wait. this is kind of silly.", "...yeah. i'm sorry too."],
	["i don't actually want to fight.", "me neither. i'm sorry."],
]
const MAKEUP_END: Array = [["friends?", "friends!"], ["still friends?", "always."]]
const STALEMATE: Array = [["hmph.", "hmph!!"], ["i'm not talking to you.", "fine! neither am i!"]]
const UNFRIEND: Array = [["we are NOT friends anymore.", "good!! fine!!"]]
const MAKEUP_SCENE: Array = [
	["...hey. about earlier. i'm sorry.", "...me too. i'm sorry too."],
	["hey. i've been thinking... i'm sorry i got so mad.", "i'm sorry too. i didn't mean it."],
]
const MAKEUP_SCENE_END: Array = [["can we start over?", "yes please!! come here!"], ["can we be friends again?", "yes! always!"]]

# single goodbye lines (used when the friend leaves, no scene needed)
const BYE := {
	"stranger": ["bye {you}! it was nice meeting you!", "see you around, {you}!"],
	"acquaintance": ["bye for now, {you}!", "see you next time, {you}!"],
	"friend": ["bye {you}! come back soon!", "aww, leaving already? bye {you}! <3"],
	"best": ["bye {you}!! i'll miss you!!", "come back soon, okay? i'll miss you!"],
	"partner": ["bye {you}... i'll miss you already. <3", "come back soon, sweetheart. i'll be waiting!"],
	"rival": ["...bye.", "finally."],
}
# when they are already together, a chat just carries on instead of saying hello again [a, b]
const CONTINUE: Array = [
	["hey, can i tell you something?", "always. go ahead!"],
	["oh, that reminds me...", "ooh, what?"],
	["you know what i was just thinking about?", "what?? tell me!"],
	["random thought, {you}...", "i'm listening!"],
	["okay, important question.", "oh no. okay. ask me."],
]
# a pet with a sweetheart talks about them to others. {p} = the speaker's sweetheart, {q} = the listener's.
const PARTNER_GUSH: Array = [   # [speaker says, listener answers]
	["i have to tell you, {p} is the best thing that ever happened to me.", "aww!! you two are so sweet together."],
	["{p} and i watched the cursor together earlier. it was perfect.", "stop, that's so cute. i'm jealous!"],
	["i can't stop talking about {p}, sorry. i'm just so happy.", "don't be sorry! it's adorable."],
	["{p} saved me the best sunbeam spot. i think i'm in love.", "you ARE in love. it's all over your face."],
	["do you ever just look at {p} and your whole chest goes warm?", "i've never seen you this happy. it suits you."],
	["{p} said the sweetest thing to me today. i'm still blushing.", "ooh, what did they say?? ...okay, keep it private. i'm so happy for you."],
]
const PARTNER_GUSH_BACK: Array = [   # [listener says, speaker answers] (the listener has a sweetheart too)
	["same!! {q} is my whole world.", "we're so lucky, aren't we?"],
	["i know exactly what you mean. {q} does that to me too.", "it's the best feeling."],
	["ha, i'm the same about {q}. we're hopeless.", "completely hopeless. i love it."],
]
const PARTNER_MISS: Array = [   # [listener says, speaker answers] (only the listener has a sweetheart)
	["{q} is the best thing that happened to me. sorry, i just had to say it.", "aww! you two are so cute together."],
	["{q} saved me the best sunbeam spot today. i might be in love.", "that's the sweetest thing. i'm happy for you."],
	["i've been telling everyone about {q}. you're next. sorry.", "i'm all ears. they sound lovely."],
]
# [a congratulates b, b replies]: needs the old level, then the new one
const LEVEL_UP: Array = [
	["wait, you're level %d now? you were level %d last time!", "i've been busy! my human taps me a lot :D"],
	["{you}!! level %d?! last time you were only level %d!", "i know!! it's been a good few days."],
	["you leveled up! %d now, right? you were %d before.", "yep! it feels good!"],
]

# --- tag --- [runner says, "it" replies]
const TAG_SETUP: Array = [
	["tag! you're it!!", "hey!! okay okay. i'll count, you run!"],
	["wanna play tag? not it!", "ugh, fine. i'm it. go, i'll count!"],
	["you're it! catch me if you can!", "oh you are SO going down. counting now!"],
]
const TAG_COUNT: Array = ["3...", "2...", "1...", "ready or not!"]   # said by whoever is "it"
const TAG_TAUNT_RUNNER: Array = ["haha, can't catch me!", "too slow!", "is that all you've got?", "catch me if you can!"]
const TAG_TAUNT_IT: Array = ["get back here!", "i'm gonna get you!", "you can't run forever!"]
# [it says, runner says] when "it" catches the runner for the first time (they swap)
const TAG_CAUGHT: Array = [
	["gotcha!! tag, you're it!", "noooo! okay okay, my turn!"],
	["tag!! you're it now!", "aww! fine, count for me!"],
]
const TAG_CAUGHT_FINAL: Array = [
	["tag! got you again!", "ahh! okay okay, i'm out of breath!"],
	["caught you!!", "haha, i give up, i'm so tired!"],
]
const TAG_END: Array = [
	["that was so fun!", "again later?! i'm worn out!"],
	["i can't feel my paws...", "best game ever. let's rest for a bit."],
]

# --- hide and seek --- [seeker says, hider replies]
const HIDE_SETUP: Array = [
	["let's play hide and seek! i'll count!", "okay okay! no peeking!"],
	["hide and seek? i'll be the seeker!", "you'd better count slowly!"],
	["i'll seek, you hide! deal?", "deal! you'll never find me!"],
]
const HIDE_COUNT: Array = ["1... 2... 3...", "...4... 5... 6...", "...7... 8... 9...", "10! ready or not, here i come!"]
const HIDE_SEARCH: Array = ["hmm... where could they be?", "i will find you...", "hellooo? where did you go?"]
const HIDE_DECOY: Array = ["not over here...", "hmm, not behind the icons...", "nope, nobody here.", "so quiet... suspicious."]
const HIDE_FOUND: Array = [
	["FOUND YOU!!", "eep! how did you find me?!"],
	["aha!! there you are!", "aww, you found me already?!"],
	["gotcha! i heard you giggling!", "i was NOT giggling!!"],
]
const HIDE_END: Array = [
	["that was a really good hiding spot!", "thanks! let's play again later!"],
	["you hide so far away!", "next time it's my turn to seek!"],
]

# =========================================================
#  helpers
# =========================================================
static func _pick(options: Array) -> Variant:
	return options[randi() % options.size()]

static func pretty(value: Variant) -> String:
	return str(value).replace("_", " ").strip_edges().to_lower()

static func _vals(text: String, mine: String, theirs: String) -> String:
	return text.replace("{mine}", mine).replace("{theirs}", theirs)

static func _line(who: String, text: String, a: String, b: String, emote: String = "", fx: String = "") -> Dictionary:
	var me: String = a if who == "a" else b
	var you: String = b if who == "a" else a
	return {"who": who, "text": text.replace("{me}", me).replace("{you}", you), "emote": emote, "fx": fx}

static func _other(who: String) -> String:
	return "b" if who == "a" else "a"

static func _scene(kind: String, lines: Array, delta: int, grudge: int = 0, unfriend: bool = false) -> Dictionary:
	return {"kind": kind, "lines": lines.slice(0, 14), "delta": delta, "grudge": grudge, "unfriend": unfriend}

# keys both pets have an answer for
static func shared_keys(me: Dictionary, them: Dictionary) -> Array:
	var out: Array = []
	for key in TOPICS.keys():
		if me["answers"].get(key) is String and them["answers"].get(key) is String:
			out.append(key)
	return out

static func same_count(me: Dictionary, them: Dictionary) -> int:
	var n: int = 0
	for key in shared_keys(me, them):
		if pretty(me["answers"][key]) == pretty(them["answers"][key]):
			n += 1
	return n

static func differing_keys(me: Dictionary, them: Dictionary) -> Array:
	var out: Array = []
	for key in shared_keys(me, them):
		if pretty(me["answers"][key]) != pretty(them["answers"][key]):
			out.append(key)
	return out

# =========================================================
#  one-liners
# =========================================================
static func ask_line(what: String, me: Dictionary, them: Dictionary, item_name: String = "") -> String:
	var t: String = _pick(ASK[what])
	return _line("a", t.replace("{item}", item_name), me["name"], them["name"])["text"]

static func answer_line(what: String, ok: bool) -> String:
	var pool: Array = ANSWER_YES.get(what, []) if ok else ANSWER_NO.get(what, [])
	if pool.is_empty():
		return "okay!" if ok else "hmm, not now."
	return _pick(pool)

static func disappointed_line() -> String:
	return _pick(SAD_AFTER_NO)

static func cheer_line() -> String:
	return _pick(CHEER_FRIENDS)

static func give_line() -> String:
	return _pick(GIVE_LINES)

static func thanks_line(used: String) -> String:
	match used:
		"ate": return _pick(THANKS_ATE)
		"played": return _pick(THANKS_PLAYED)
	return _pick(THANKS_GENERIC)

static func comfort_line() -> String:
	return _pick(COMFORT)

static func worry_line() -> String:
	return _pick(WORRY)

# =========================================================
#  scenes
# =========================================================
static func bye_line(tier: String, you: String) -> String:
	return str(_pick(BYE.get(tier, BYE["acquaintance"]))).replace("{you}", you)

# Stable id for "these two humans' answers for this key": once the pets talked about it, they
# don't bring it up again (unless one of the answers changes).
static func topic_tag(key: String, me: Dictionary, them: Dictionary) -> String:
	var pair: Array = [pretty(me["answers"][key]), pretty(them["answers"][key])]
	pair.sort()
	return "ans:%s=%s/%s" % [key, pair[0], pair[1]]

static func _fresh_small(talked: Array, used_now: Array) -> int:
	var fresh: Array = []
	var any: Array = []
	for i in SMALLTALK.size():
		var tag: String = "talk:%d" % i
		if tag in used_now:
			continue
		any.append(i)
		if not (tag in talked):
			fresh.append(i)
	var pool: Array = fresh if not fresh.is_empty() else any
	if pool.is_empty():
		return 0
	return int(_pick(pool))

# ctx (all optional): greet (say hello first), met_before, talked (topic tags already discussed),
# prev_level (their level the last time we chatted)
static func chat_scene(me: Dictionary, them: Dictionary, tier: String, ctx: Dictionary = {}) -> Dictionary:
	var a: String = me["name"]
	var b: String = them["name"]
	var lines: Array = []
	var topics: Array = []
	var talked: Array = ctx.get("talked", [])
	var delta: int = 3

	# 1. a hello, but only when they have just got together. No re-introducing every few minutes.
	if bool(ctx.get("greet", true)):
		var hello_tier: String = tier
		if tier == "stranger" and bool(ctx.get("met_before", false)):
			hello_tier = "acquaintance"
		var hello: Array = _pick(OPEN[hello_tier])
		lines.append(_line("a", hello[0], a, b, hello[2], hello[3]))
		lines.append(_line("b", hello[1], a, b, hello[2], hello[3]))
	elif tier != "rival" and randf() < 0.6:
		var cont: Array = _pick(CONTINUE)
		lines.append(_line("a", cont[0], a, b))
		lines.append(_line("b", cont[1], a, b))

	# 2. somebody looks hungry / bored / down: the other one notices
	var notable: Array = ["hungry", "bored", "down"]
	var fa: String = str(me.get("feeling", "okay"))
	var fb: String = str(them.get("feeling", "okay"))
	var sad_one: String = ""
	if fa in notable and (not (fb in notable) or randf() < 0.5):
		sad_one = "a"
	elif fb in notable:
		sad_one = "b"
	if sad_one != "" and tier != "rival":
		var feeling: String = fa if sad_one == "a" else fb
		var pair: Array = _pick(FEELING[feeling])
		var commenter: String = _other(sad_one)
		lines.append(_line(commenter, pair[0], a, b))
		lines.append(_line(sad_one, pair[1], a, b, "sad" if feeling == "down" else ""))
		if pair.size() > 2:
			lines.append(_line(commenter, pair[2], a, b, "heart"))
			delta += 2

	# 3. they've grown since the last time we talked
	var prev_level: int = int(ctx.get("prev_level", 0))
	var their_level: int = int(them["level"])
	if tier != "rival" and prev_level > 0 and their_level > prev_level:
		var lv: Array = _pick(LEVEL_UP)
		var template: String = lv[0]
		lines.append(_line("a", template % [their_level, prev_level], a, b, "spark"))
		lines.append(_line("b", lv[1], a, b, "happy", "hop"))
		delta += 1

	# 3b. somebody is head over heels: they talk about their sweetheart (never to the sweetheart itself)
	var pa: String = str(me.get("partner", ""))
	var pb: String = str(them.get("partner", ""))
	if tier != "rival" and tier != "partner" and pa != b and pb != a:
		if pa != "" and randf() < 0.55:
			var g: Array = _pick(PARTNER_GUSH)
			lines.append(_line("a", str(g[0]).replace("{p}", pa), a, b, "heart"))
			lines.append(_line("b", str(g[1]), a, b, "happy"))
			if pb != "" and randf() < 0.6:
				var gb: Array = _pick(PARTNER_GUSH_BACK)
				lines.append(_line("b", str(gb[0]).replace("{q}", pb), a, b, "heart"))
				lines.append(_line("a", str(gb[1]), a, b, "hearts", "hop"))
			delta += 2
		elif pb != "" and randf() < 0.4:
			var gm: Array = _pick(PARTNER_MISS)
			lines.append(_line("b", str(gm[0]).replace("{q}", pb), a, b, "heart"))
			lines.append(_line("a", str(gm[1]), a, b, "happy"))
			delta += 1
	var short_chat: bool = lines.size() >= 8   # scenes are cut off at 14 lines: no room for more topics

	# 4. what their humans like: only things they haven't talked about yet
	var keys: Array = []
	for key in shared_keys(me, them):
		if not (topic_tag(key, me, them) in talked):
			keys.append(key)
	keys.shuffle()
	var picks: Array = [] if short_chat else keys.slice(0, 1 if randf() < 0.45 else 2)
	var turn: String = "a" if randf() < 0.5 else "b"
	for key in picks:
		var sv: String = pretty(me["answers"][key]) if turn == "a" else pretty(them["answers"][key])
		var rv: String = pretty(them["answers"][key]) if turn == "a" else pretty(me["answers"][key])
		lines.append(_line(turn, _vals(_pick(TOPICS[key]), sv, rv), a, b))
		topics.append(topic_tag(key, me, them))
		var reactor: String = _other(turn)
		if sv == rv:
			lines.append(_line(reactor, _vals(_pick(SAME_REACT), rv, sv), a, b, "happy", "hop"))
			delta += 2
		else:
			var pool: Array = DIFF_REACT
			if tier == "friend" or tier == "best" or tier == "partner":
				pool = DIFF_REACT + TEASE_REACT
			lines.append(_line(reactor, _vals(_pick(pool), rv, sv), a, b))
		turn = reactor

	# 5. nothing new about their humans: personalities (once), then fresh small talk
	var small_needed: int = 0
	if short_chat:
		small_needed = 0
	elif picks.is_empty():
		var traits: Array = [str(me["trait"]), str(them["trait"])]
		traits.sort()
		var trait_tag: String = "trait:%s/%s" % [traits[0], traits[1]]
		if not (trait_tag in talked):
			var ta: Array = TRAITS.get(me["trait"], TRAITS["Balanced"])
			var tb: Array = TRAITS.get(them["trait"], TRAITS["Balanced"])
			lines.append(_line("a", _pick(ta), a, b))
			lines.append(_line("b", _pick(tb), a, b))
			topics.append(trait_tag)
			small_needed = 1
		else:
			small_needed = 2
	elif picks.size() == 1:
		small_needed = 1
	for i in small_needed:
		var idx: int = _fresh_small(talked, topics)
		var talk: Array = SMALLTALK[idx]
		topics.append("talk:%d" % idx)
		lines.append(_line(turn, talk[0], a, b))
		lines.append(_line(_other(turn), talk[1], a, b))
		turn = _other(turn)

	var scene: Dictionary = _scene("chat", lines, mini(delta, 8))
	scene["topics"] = topics   # social_manager saves these so the pets don't repeat themselves
	return scene

static func _count_lines(who: String, a: String, b: String) -> Array:
	var out: Array = []
	for text in TAG_COUNT:
		out.append(_line(who, text, a, b, "spark" if str(text).begins_with("ready") else ""))
	return out

# [runner taunt at ~t0, "it" taunt a few seconds later]; each has a "t" (seconds into the chase)
static func _taunts(runner: String, it: String, a: String, b: String, t0: float) -> Array:
	var run_line: Dictionary = _line(runner, _pick(TAG_TAUNT_RUNNER), a, b, "laugh")
	run_line["t"] = t0 + randf() * 2.0
	var it_line: Dictionary = _line(it, _pick(TAG_TAUNT_IT), a, b, "", "hop")
	it_line["t"] = t0 + 5.0 + randf() * 3.0
	return [run_line, it_line]

static func _tag_script(a: String, b: String, it_who: String, run_who: String) -> Dictionary:
	var setup: Array = _pick(TAG_SETUP)
	var caught1: Array = _pick(TAG_CAUGHT)
	var caught2: Array = _pick(TAG_CAUGHT_FINAL)
	var end: Array = _pick(TAG_END)
	return {
		"setup": [_line(run_who, setup[0], a, b, "happy", "hop"), _line(it_who, setup[1], a, b)],
		"count": _count_lines(it_who, a, b),
		"taunts": _taunts(run_who, it_who, a, b, 3.0),
		"caught": [_line(it_who, caught1[0], a, b, "happy", "hop"), _line(run_who, caught1[1], a, b, "laugh", "shake")],
		"max": randf_range(16.0, 22.0),
		# round 2: the one who got caught is "it"
		"count2": _count_lines(run_who, a, b),
		"taunts2": _taunts(it_who, run_who, a, b, 3.0),
		"caught2": [_line(run_who, caught2[0], a, b, "happy", "hop"), _line(it_who, caught2[1], a, b, "laugh", "shake")],
		"max2": randf_range(11.0, 16.0),
		"end": [_line(it_who, end[0], a, b, "happy"), _line(run_who, end[1], a, b, "laugh")],
	}

static func _hide_script(a: String, b: String, seeker: String, hider: String) -> Dictionary:
	var setup: Array = _pick(HIDE_SETUP)
	var found: Array = _pick(HIDE_FOUND)
	var end: Array = _pick(HIDE_END)
	var count: Array = []
	for text in HIDE_COUNT:
		count.append(_line(seeker, text, a, b, "spark" if str(text).begins_with("10") else ""))
	var decoys: Array = HIDE_DECOY.duplicate()
	decoys.shuffle()
	return {
		"setup": [_line(seeker, setup[0], a, b), _line(hider, setup[1], a, b, "happy")],
		"count": count,
		"search": [_line(seeker, _pick(HIDE_SEARCH), a, b, "think")],
		"decoy": [_line(seeker, decoys[0], a, b), _line(seeker, decoys[1], a, b)],
		"found": [_line(seeker, found[0], a, b, "spark", "hop"), _line(hider, found[1], a, b, "laugh", "hop")],
		"end": [_line(seeker, end[0], a, b, "happy"), _line(hider, end[1], a, b, "heart")],
	}

# Tag or hide and seek. The scene carries a "script" (named groups of lines) plus the random picks
# both screens need to agree on. The actual running around is simulated on each screen by social_manager.
static func play_scene(me: Dictionary, them: Dictionary) -> Dictionary:
	var a: String = me["name"]
	var b: String = them["name"]
	var first: String = "a" if randf() < 0.5 else "b"     # who is "it" / the seeker first
	var other: String = _other(first)
	var game: String = "tag" if randf() < 0.5 else "hide"
	var script: Dictionary = _tag_script(a, b, first, other) if game == "tag" else _hide_script(a, b, first, other)

	var flat: Array = []   # plain list of every line, so the scene still has "lines" like all the others
	for key in script.keys():
		if script[key] is Array:
			flat.append_array(script[key])
	var scene: Dictionary = _scene("play", flat, 5)
	scene["game"] = game
	scene["first"] = first
	scene["script"] = script
	if game == "hide":
		var edge: int = randi() % 4                          # 0 left, 1 right, 2 top, 3 bottom
		scene["edge"] = edge
		scene["along"] = randf_range(0.15, 0.85)
		scene["decoy"] = (edge + 1 + randi() % 3) % 4
		scene["decoy_along"] = randf_range(0.15, 0.85)
	return scene

# --- Tag / hide and seek for ANY number of pets ---------------------------------------------------
# A group game is a list of ROUNDS. In every round two pets are "a" and "b" and have their own script:
#   tag : "a" is it and chases "b". The one who gets caught is "a" in the next round (a chain).
#   hide: "a" is the seeker in every round, "b" is the hider that gets found in that round.
# profiles[i] / peers[i] describe the same pet. Slot 0 is the pet that started the game.
# (play_scene() above is the old two-pet version and is no longer used by social_manager.gd.)
static func group_play_scene(profiles: Array, peers: Array) -> Dictionary:
	var n: int = mini(profiles.size(), peers.size())
	if n < 2:
		return {}
	var game: String = "tag" if randf() < 0.5 else "hide"
	var first_slot: int = randi() % n            # who is "it" first / the seeker
	var others: Array = range(n)
	others.erase(first_slot)
	others.shuffle()
	var rounds: Array = []

	if game == "tag":
		var chain: Array = [first_slot] + others + [first_slot]
		var round_count: int = mini(n, 4)
		for i in round_count:
			var it_slot: int = chain[i]
			var run_slot: int = chain[i + 1]
			rounds.append({
				"a": peers[it_slot],
				"b": peers[run_slot],
				"script": _tag_round(str(profiles[it_slot]["name"]), str(profiles[run_slot]["name"]), i == 0, i == round_count - 1),
			})
	else:
		var edges: Array = [0, 1, 2, 3]
		edges.shuffle()
		for i in others.size():
			var edge: int = edges[i % 4]
			rounds.append({
				"a": peers[first_slot],
				"b": peers[others[i]],
				"script": _hide_round(str(profiles[first_slot]["name"]), str(profiles[others[i]]["name"]), i == 0, i == others.size() - 1),
				"edge": edge,                                  # 0 left, 1 right, 2 top, 3 bottom
				"along": randf_range(0.15, 0.85),
				"decoy": (edge + 1 + randi() % 3) % 4,        # a wrong edge the seeker checks first (round 1)
				"decoy_along": randf_range(0.15, 0.85),
			})

	var flat: Array = []   # plain list of every line, so the scene still has "lines" like all the others
	for r in rounds:
		for key in r["script"].keys():
			if r["script"][key] is Array:
				flat.append_array(r["script"][key])
	var scene: Dictionary = _scene("play", flat, 5)
	scene["game"] = game
	scene["players"] = peers.slice(0, n)
	scene["rounds"] = rounds
	return scene

# One chase of a tag game. Only the first round has the "let's play" lines, only the last has the goodbye.
static func _tag_round(a: String, b: String, first: bool, last: bool) -> Dictionary:
	var caught: Array = _pick(TAG_CAUGHT_FINAL if last else TAG_CAUGHT)
	var script: Dictionary = {
		"count": _count_lines("a", a, b),
		"taunts": _taunts("b", "a", a, b, 3.0),
		"caught": [_line("a", caught[0], a, b, "happy", "hop"), _line("b", caught[1], a, b, "laugh", "shake")],
		"max": randf_range(16.0, 22.0) if first else randf_range(11.0, 16.0),
	}
	if first:
		var setup: Array = _pick(TAG_SETUP)
		script["setup"] = [_line("b", setup[0], a, b, "happy", "hop"), _line("a", setup[1], a, b)]
	if last:
		var end: Array = _pick(TAG_END)
		script["end"] = [_line("a", end[0], a, b, "happy"), _line("b", end[1], a, b, "laugh")]
	return script

# One "found you!" of a hide and seek game. The first round also has the setup, the counting, the
# searching and the decoy lines; the last round has the goodbye.
static func _hide_round(a: String, b: String, first: bool, last: bool) -> Dictionary:
	var found: Array = _pick(HIDE_FOUND)
	var script: Dictionary = {
		"found": [_line("a", found[0], a, b, "spark", "hop"), _line("b", found[1], a, b, "laugh", "hop")],
	}
	if first:
		var setup: Array = _pick(HIDE_SETUP)
		var count: Array = []
		for text in HIDE_COUNT:
			count.append(_line("a", text, a, b, "spark" if str(text).begins_with("10") else ""))
		var decoys: Array = HIDE_DECOY.duplicate()
		decoys.shuffle()
		script["setup"] = [_line("a", setup[0], a, b), _line("b", setup[1], a, b, "happy")]
		script["count"] = count
		script["search"] = [_line("a", _pick(HIDE_SEARCH), a, b, "think")]
		script["decoy"] = [_line("a", decoys[0], a, b), _line("a", decoys[1], a, b)]
	if last:
		var end: Array = _pick(HIDE_END)
		script["end"] = [_line("a", end[0], a, b, "happy"), _line("b", end[1], a, b, "heart")]
	return script

static func fight_scene(me: Dictionary, them: Dictionary, friendship: float, befriended: bool) -> Dictionary:
	var a: String = me["name"]
	var b: String = them["name"]
	var lines: Array = []

	# what is it about?
	var diff: Array = differing_keys(me, them)
	if not diff.is_empty() and randf() < 0.8:   # most fights are about what their humans like
		var key: String = _pick(diff)
		var av: String = pretty(me["answers"][key])
		var bv: String = pretty(them["answers"][key])
		lines.append(_line("a", _vals(_pick(FIGHT_TOPIC_A), av, bv), a, b))
		lines.append(_line("b", _vals(_pick(FIGHT_TOPIC_B), bv, av), a, b, "angry", "shake"))
	elif int(me["level"]) > int(them["level"]) and randf() < 0.5:
		lines.append(_line("a", "i'm level %d and you're level %d... just saying." % [int(me["level"]), int(them["level"])], a, b, "spark"))
		lines.append(_line("b", "oh, you did NOT just say that.", a, b, "angry", "shake"))
	else:
		var gripe: Array = _pick(GRIPES)
		lines.append(_line("a", gripe[0], a, b, "angry"))
		lines.append(_line("b", gripe[1], a, b, "angry", "shake"))

	# it escalates
	var pairs: Array = ESCALATE.duplicate()
	pairs.shuffle()
	for i in (2 if randf() < 0.5 else 1):
		lines.append(_line("a", pairs[i][0], a, b, "angry", "shake"))
		lines.append(_line("b", pairs[i][1], a, b, "angry", "shake"))

	# and then: make up, or stay mad
	var p_makeup: float = clampf(0.1 + friendship / 100.0 * 0.5 + (0.1 if befriended else 0.0), 0.15, 0.7)
	if randf() < p_makeup:
		var sorry: Array = _pick(MAKEUP_IN_FIGHT)
		lines.append(_line("a", sorry[0], a, b, "sad"))
		lines.append(_line("b", sorry[1], a, b, "sad"))
		var end: Array = _pick(MAKEUP_END)
		lines.append(_line("a", end[0], a, b, "heart"))
		lines.append(_line("b", end[1], a, b, "hearts", "hop"))
		return _scene("fight", lines, 5 if befriended else 3)

	var stale: Array = _pick(STALEMATE)
	lines.append(_line("a", stale[0], a, b, "angry"))
	lines.append(_line("b", stale[1], a, b, "angry", "shake"))
	var unfriend: bool = befriended and friendship - 12.0 < 20.0
	if unfriend:
		var cut: Array = _pick(UNFRIEND)
		lines.append(_line("a", cut[0], a, b, "angry", "shake"))
		lines.append(_line("b", cut[1], a, b, "sad"))
	return _scene("fight", lines, -12, 150, unfriend)

static func makeup_scene(me: Dictionary, them: Dictionary) -> Dictionary:
	var a: String = me["name"]
	var b: String = them["name"]
	var lines: Array = []
	var first: Array = _pick(MAKEUP_SCENE)
	lines.append(_line("a", first[0], a, b, "sad"))
	lines.append(_line("b", first[1], a, b, "sad"))
	var second: Array = _pick(MAKEUP_SCENE_END)
	lines.append(_line("a", second[0], a, b, "heart"))
	lines.append(_line("b", second[1], a, b, "hearts", "hop"))
	return _scene("makeup", lines, 8)
