extends RefCounted
## STAGE 1: rumours, crushes and asking each other out. Pure content + script building (no nodes, no
## networking), exactly like pet_chat.gd. social_manager.gd decides WHEN things happen and keeps the
## state; this file decides WHAT is said and what the numbers do.
##
## ---------------------------------------------------------------------------------------------
## RUMOURS
##   A rumour is a Dictionary (see new_rumor): "subj" said / did something, "about" is who it concerns.
##     kind "insult": subj said something mean about "about"
##     kind "crush" : subj has a crush on "about"
##   Mostly true, sometimes twisted: every rumour starts out TRUE (it comes from something a pet really
##   saw or was told first-hand: a vent, a confided secret, a fight, being asked out). Every time a pet
##   passes one on there is a chance it gets twisted (TWIST_FIRST_HAND / TWIST_HEARSAY). A twisted
##   rumour stays twisted forever ("twisted": true) and is always the spicy version. Twisting an
##   insult makes it about the LISTENER; twisting a crush swaps who it is about.
##   Nobody is told which rumours are twisted: the flag only decides how a confrontation ends.
##
##   Scenes written here: gossip (tell / vent / confide), confront (insult / crush / jealous / spreader)
##
## ROMANCE
##   Per friend each pet keeps a private "crush" number (0-100). It grows slowly from chats, games,
##   gifts and make-ups when they are real friends, scaled by "attraction" (shared tastes + luck).
##   Over CRUSH_TO_ASK the pet may ask the other one out all on its own. The other pet decides by
##   date_acceptance(): its OWN crush counts most, so a mutual crush almost always works out.
##   Scenes written here: first_date (after a yes), romance (a couple hanging out)
##
## BREAKUPS AND REKINDLING (stage 3)
##   A couple can split up: breakup_scene (neglect / growing apart), or a confrontation about a believed
##   "they like somebody else" rumour (mode "cheater"). A breakup scene ends one of three ways, and carries
##   "split" so both games apply the same thing: "" (they talked it out, still together), "amicable" (still
##   friends) or "messy" (not friends any more, grudge). Later one ex may ask the other to try again:
##   rekindle_weight / rekindle_acceptance / rekindle_scene.
## ---------------------------------------------------------------------------------------------
## All lines are lowercase and in character. Tokens: {me} {you} (speaker / listener names, filled by
## _line), {s} {t} {src} {p} (rumour subject / about / who told me / my partner, filled by _fill).

const PetChat = preload("res://pet_chat.gd")

# --- tuning knobs -------------------------------------------------------------------------------
const TWIST_FIRST_HAND: float = 0.12     # chance a rumour gets twisted when the pet that saw it tells it
const TWIST_HEARSAY: float = 0.25        # ... when the pet is only passing on what it heard
const MAX_RUMORS: int = 30               # per pet; the oldest are forgotten first
const RUMOR_MAX_AGE: int = 604800        # 7 days
const BROOD_SECONDS: int = 90            # a pet that believes a rumour waits at least this long before confronting
const CRUSH_FELT: float = 40.0           # from here on the pet is visibly smitten (hearts around them)
const CRUSH_TO_ASK: float = 55.0         # from here on the pet may ask them out
const ASK_COOLDOWN: int = 21600          # after a "no" the pet doesn't try again for 6 hours
const BREAKUP_FRIENDSHIP: float = 35.0   # a couple whose friendship sinks below this is on thin ice
const NEGLECT_AWAY: int = 864000         # 10 days apart (counted at the reunion) and a relationship starts to drift
const REKINDLE_MIN_WAIT: int = 7200      # exes wait at least 2 hours before one may ask the other again
const REKINDLE_NO_COOLDOWN: int = 43200  # after a "no" to getting back together: 12 hours
const CRUSH_BASE := {"chat": 2.0, "play": 3.0, "makeup": 4.0, "romance": 3.0, "gossip": 1.5, "gift": 5.0}

# =========================================================
#  Content: telling a rumour
# =========================================================
# TELL[kind][plain|spicy][audience]  (audience: other = about a third pet, you = about the listener, me = about the teller)
const TELL := {
	"insult": {
		"plain": {
			"other": ["i heard {s} say {t} is kind of annoying.", "{s} was complaining about {t} earlier.", "{s} said {t} keeps stealing all the good spots."],
			"you": ["{s} said you keep stealing all the good spots.", "i heard {s} say you're kind of annoying.", "{s} was complaining about you earlier."],
			"me": ["{s} said i'm kind of annoying.", "{s} was complaining about me earlier.", "{s} told somebody i keep stealing all the good spots."],
		},
		"spicy": {
			"other": ["{s} said {t} is the most boring pet alive. out loud!", "{s} said {t} smells like old cheese. i'm just repeating it!", "i heard {s} say {t} cheats at tag. every time."],
			"you": ["{s} said you're the most boring pet alive. out loud!", "{s} said you smell like old cheese. i'm just the messenger!", "i heard {s} say you cheat at tag. every time."],
			"me": ["{s} said i'm the most boring pet alive. out loud!", "{s} said i smell like old cheese!!", "i heard {s} say i cheat at tag. every time."],
		},
	},
	"crush": {
		"plain": {
			"other": ["{s} totally has a crush on {t}. it's so obvious.", "{s} gets all blushy around {t}. i saw it."],
			"you": ["{s} totally has a crush on you. it's so obvious.", "{s} gets all blushy whenever you walk by. i saw it."],
			"me": ["{s} has a crush on me. i think. it's been a little weird.", "{s} asked me out!! i didn't know what to say."],
		},
		"spicy": {
			"other": ["{s} is secretly in love with {t}. wedding plans and everything.", "{s} drew a giant heart with {t}'s name in it. i saw it!"],
			"you": ["{s} is secretly in love with you. wedding plans and everything.", "{s} drew a giant heart with your name in it. i saw it!"],
			"me": ["{s} is madly in love with me. it's a lot.", "{s} drew a giant heart with my name in it. what do i do?!"],
		},
	},
}
const TELL_INTRO: Array = [
	["psst, {you}. come here. i have to tell you something.", "ooh. what?"],
	["{you}, did you hear?", "no?? tell me!"],
	["okay, you did NOT hear this from me.", "my ears are wide open."],
	["{you}, can i tell you something juicy?", "always. go."],
]
const TELL_REACT: Array = [
	"no way!!", "wait, REALLY?", "ooooh. juicy.", "hmm. i'm not sure i believe that.",
	"that sounds like something {s} would do, honestly.", "oh no. that's a lot.", "i did NOT expect that.",
]
const TELL_CLOSE: Array = [
	["you didn't hear it from me!", "my lips are sealed."],
	["just thought you should know.", "...okay but now i can't stop thinking about it."],
	["don't tell anyone i said that!", "i'll keep it between us. mostly."],
]
# venting about somebody they don't like [a opens, b answers], then [a says, b answers]
const VENT_OPEN: Array = [
	["ugh. can i vent for a second?", "of course. what's wrong?"],
	["i need to tell somebody something.", "i'm all ears."],
]
const VENT_BODY: Array = [
	["{t} keeps stealing the sunbeam. every. single. time.", "that's not okay."],
	["{t} totally ignored me earlier. rude.", "wow. i'm sorry. that's rude."],
	["{t} is just so annoying lately.", "yikes. what did they do?"],
	["{t} says the loudest things and thinks nobody hears.", "classic {t}."],
]
const VENT_END: Array = [["thanks for listening.", "anytime."], ["okay. i feel a little better.", "good. i've got you."]]
# confiding a crush
const CONFIDE: Array = [
	["{you}... can you keep a secret?", "always. you know that."],
	["{you}, i need to tell somebody something. and it's a secret.", "okay. i promise."],
]
const CONFIDE_REVEAL: Array = [
	["...i think i have a crush on {t}.", "WHAT?! really?!"],
	["i can't stop thinking about {t}. is that weird?", "no!! that's so cute!"],
]
const CONFIDE_END: Array = [["please don't tell anyone!!", "my lips are sealed. promise."], ["you're the only one who knows.", "i'll take it to my grave. or at least to the next reboot."]]

# =========================================================
#  Content: confrontations
# =========================================================
# [a says, b answers, a_emote, a_fx]   (a = the one who heard the rumour)
const OPEN_ANGRY := {
	"insult": [
		["{you}!!! i heard what you said about me!!!", "what?! what did i say?!", "angry", "shake"],
		["{you}. we need to talk. i heard what you said.", "...said about what?", "angry", ""],
	],
	"crush": [
		["{you}... i heard something. about you and me.", "...what did you hear?", "think", ""],
		["{you}, can i ask you something kind of awkward?", "uh oh. okay. go ahead.", "think", ""],
	],
	"cheater": [
		["{you}. we need to talk. right now.", "oh no. what did i do?", "angry", ""],
		["{you}... i heard something about you and somebody else.", "...what did you hear?", "angry", "shake"],
	],
	"jealous": [
		["{you}. a word. now.", "oh no. what did i do?", "angry", ""],
		["{you}. we need to talk about {p}.", "...why do i feel like i'm in trouble?", "angry", ""],
	],
}
const OPEN_SOFT := {
	"insult": [
		["{you}... someone told me something about you. i don't want to believe it.", "okay... what did they say?", "sad", ""],
		["{you}, can i ask you something? i heard a thing and it's been bugging me.", "of course. what is it?", "sad", ""],
	],
}
const ACCUSE := {
	"insult": {
		"plain": ["{src} told me you said i'm annoying.", "{src} said you were complaining about me behind my back."],
		"spicy": ["{src} told me you said i smell like old cheese!!", "{src} said you called me the most boring pet alive!!"],
	},
	"crush": {
		"plain": ["{src} said you have a crush on me?", "{src} told me you get all blushy around me."],
		"spicy": ["{src} said you drew a giant heart with my name in it??", "{src} told me you're secretly in love with me?!"],
	},
	"cheater": {
		"plain": ["{src} said you have a crush on {t}. and we're TOGETHER.", "{src} told me you keep blushing at {t}. while you're with me!"],
		"spicy": ["{src} said you drew a giant heart with {t}'s name in it!! we're together!!", "{src} said you're secretly in love with {t}!! and you're with ME!!"],
	},
	"jealous": {
		"plain": ["{src} said you have a crush on {p}. {p} is MY partner.", "{src} told me you keep blushing at {p}. that's MY partner."],
		"spicy": ["{src} said you're secretly in love with {p}. {p} is MY partner!!", "{src} said you drew a heart with {p}'s name. {p} is MINE."],
	},
}
const ADMIT: Array = [
	["...okay. i did say that. i was in a mood.", "that really hurt, you know.", "i know. i'm sorry. i didn't mean it.", "...thanks for being honest. i forgive you."],
	["...yeah. i said it. i'm not proud of it.", "why would you say that about me?", "because i was jealous of how well you hide. i'm sorry.", "...okay. thank you for telling me the truth."],
]
const DEFIANT: Array = [
	["so what if i did?!", "excuse me?!"],
	["fine!! i said it! and i'd say it again!", "wow. just wow."],
]
const DENY: Array = [
	["i NEVER said that!!", "...you didn't?"],
	["what?! no!! i would never!", "...really?"],
]
const DENY_WHO: Array = [
	["who even told you that?", "{src} did."],
	["where did you hear that?!", "from {src}."],
]
const DENY_REACT: Array = ["{src}?! that's not true at all!", "{src} made that up! i swear!", "that's a lie, {you}. a total lie."]
const BELIEVE: Array = [
	["...oh no. i'm so sorry i yelled at you.", "it's okay. i'd have been upset too."],
	["...i believe you. i'm sorry i doubted you.", "it's okay. i forgive you."],
]
const BELIEVE_END: Array = ["but i'm definitely having words with {src}.", "{src} and i need to have a talk."]
const DISBELIEVE: Array = [
	["that's exactly what a liar would say.", "wow. okay. we're done here."],
	["i don't believe you.", "fine. don't. i don't care."],
]
const BLUSH_TRUE: Array = [
	["...oh no. is it that obvious?", "...a little. it's kind of sweet.", "so you're not mad?", "not even a little."],
	["...okay. maybe it's true. i do like you.", "i... think i like you too, a little.", "you do?!", "don't make me say it twice."],
]
const BLUSH_FALSE: Array = [
	["WHAT?! no!! i don't!!", "...you don't?", "who said that?!", "{src} did."],
	["that's not true at all!!", "oh. ...oh. okay.", "{src} made that up, i swear.", "...this is so awkward."],
]
const JEALOUS_BACK: Array = [
	["...i might like {p}. i'm sorry.", "that's not okay.", "you're right. i'll back off.", "thank you."],
]
const JEALOUS_DEFY: Array = [
	["you can't tell me who to like!", "watch me!"],
]
const ESCALATE: Array = [
	["you take that back!", "make me!"],
	["you're being so annoying right now!", "no, YOU'RE annoying!"],
	["i can't even look at you!", "then don't!"],
]
const STALEMATE: Array = [["hmph.", "hmph!!"], ["i'm not talking to you.", "fine! neither am i!"]]
const UNFRIEND: Array = [["we are NOT friends anymore.", "good!! fine!!"]]
# spreader: [a to b, b answers, a, b]   a = the one who was blamed-against (heard it was spread), b = who spread it
const SPREAD_LIE_OPEN: Array = ["{you}. did you tell people i said that?", "{you}. i heard you've been spreading stuff about me."]
const SPREAD_SECRET_OPEN: Array = ["{you}. i told you a secret. you PROMISED.", "{you}. i trusted you with that. everybody knows now."]
const SPREAD_SORRY_LIE: Array = [
	["...i heard it from someone and i just passed it on. i'm sorry.", "please check before you tell people things.", "i know. i will.", "...okay. thank you."],
]
const SPREAD_SORRY_SECRET: Array = [
	["...i'm so sorry. it slipped out.", "that was really private.", "i know. it won't happen again.", "...okay. i believe you."],
]
const SPREAD_DEFY: Array = [
	["i was just repeating what i heard!", "that's not an excuse!"],
	["it's not like i made it up!", "you still told everyone!"],
]

# =========================================================
#  Content: romance
# =========================================================
const ASK_OUT: Array = [
	"{you}... can i tell you something? i really like you. like, LIKE like. will you go out with me?",
	"{you}, i've been trying to say this for ages... would you be my sweetheart?",
	"um. {you}. i think about you a lot. wanna be... more than friends?",
	"{you}, my heart does a flip every time you show up. would you go out with me?",
]
const ANSWER_YES: Array = [
	"yes!! i was hoping you'd ask!!", "i like you too!! yes!", "...yes. oh my gosh. yes.", "yes!! yes yes yes!!",
]
const ANSWER_NO: Array = [
	"oh... i really care about you, but just as a friend. i'm sorry.",
	"i'm not ready for that. i'm so sorry.",
	"aw... you're so sweet. but not like that.",
]
const ANSWER_TAKEN: Array = ["i'm already with someone... i'm so sorry!", "oh! i'm taken. i'm sorry!"]
const AFTER_NO: Array = [
	"oh. okay. that's okay. we can still be friends, right?",
	"...i understand. thank you for being honest.",
	"that's fair. i'll just... go be embarrassed over here.",
]
const FIRST_DATE: Array = [
	[["so... are we a thing now?", "we're a thing!!"], ["can i sit next to you?", "always."]],
	[["i can't stop smiling.", "me neither. my cheeks hurt."], ["want to watch the cursor together?", "i'd love to."]],
]
const FIRST_DATE_END: Array = [["this is the best day ever.", "it really is."], ["i'm so glad i asked.", "i'm so glad you did."]]
const COUPLE_CHAT: Array = [
	["i keep thinking about you.", "i was just thinking about you too."],
	["come watch the cursor with me?", "okay. only if i can lean on you."],
	["you're my favorite part of the desktop.", "stop it, you're making me blush!"],
	["i saved you the best sunbeam spot.", "you always do. i love you for it."],
	["do you think our humans know how cute we are?", "i hope they're taking notes."],
	["i drew you a tiny pixel heart.", "i'm keeping it forever."],
	["what are you thinking about?", "you. always you."],
	["you're the first thing i look for when i get here.", "i do the exact same thing."],
	["is it weird that i missed you and you were only gone a minute?", "not weird. i counted the seconds."],
	["i like it when we don't have to say anything.", "me too. the quiet is better with you."],
	["you make the desktop feel like home, {nick}.", "you're my home."],
	["i told the folder named steve all about you.", "what did steve say? ...he says he's happy for us."],
	["hold still. you have a pixel on your head. ...no, i'm keeping it.", "you're ridiculous. i love you."],
	["i'd pick you every single time.", "i'd pick you first. and second."],
]
const NICKNAMES: Array = ["sweet pea", "sunshine", "love bug", "cutie", "my favorite", "darling", "buttercup"]
const COUPLE_PLANS: Array = [
	["let's watch the sunset wallpaper together later.", "it's a date. i'll bring snacks."],
	["we should build a pixel fort and never leave.", "yes. with a really big door for visitors."],
	["next time let's find the coziest corner and nap there. together.", "the coziest corner is wherever you are."],
	["want to race around the screen and then collapse in a heap?", "that's my favorite kind of date."],
	["let's make a list of all our favorite spots.", "number one: right next to you."],
	["can we have a picnic on the taskbar?", "a picnic on the taskbar sounds perfect."],
	["we should learn a duet. i'll hum, you wiggle.", "that's the cutest plan i've ever heard."],
]
const COUPLE_TEASE: Array = [
	["you snore, you know.", "i do NOT. ...do i?"],
	["you steal all of the sunbeam.", "only because you look cute in the shade."],
	["you were staring again.", "i'm allowed. you're very stare-worthy."],
	["you always win at tag.", "i let you win. every single time."],
	["you get so dramatic when you're hungry.", "i'm not dramatic, i'm starving. it's different."],
	["you told everybody about my hat, didn't you.", "...i might have. it's a very good hat."],
]
# {days} = "5 days" / "a week" / "3 weeks"...
const COUPLE_MEMORY: Array = [
	["it's been {days} since we got together.", "i know. i keep count. is that weird?"],
	["{days} together. i never want to stop.", "me neither. it goes by so fast."],
	["do you remember the day we got together?", "i could never forget. my heart was doing flips."],
	["i still think about the day we became a couple.", "i'd do it all over again in a heartbeat."],
	["we've been through a lot in {days}.", "and we're still here. that's the best part."],
]
# {mine} / {theirs}: what the speaker's / the other's human picked
const COUPLE_TASTE_SAME: Array = [
	["our humans both picked {mine}. we're meant to be.", "of course they did. we're a perfect match."],
	["{mine}! we both love it. that can't be a coincidence.", "nothing about us is a coincidence."],
]
const COUPLE_TASTE_DIFF: Array = [
	["my human picked {mine} and yours picked {theirs}. opposites attract.", "and somehow it works."],
	["{mine} for mine, {theirs} for yours. i love that we're different.", "me too. it's never boring with you."],
]
# [the one who notices says, the one who feels it answers]
const COUPLE_CARE := {
	"hungry": [["you sound hungry, {nick}. i'll share my snack.", "you'd really share? i love you."], ["{nick}, was that your tummy? take my snack.", "you're the best. i'm keeping you."]],
	"bored": [["you look bored, {nick}. let's do something together.", "as long as it's with you, i'm in."]],
	"down": [["you seem down. come here, {nick}.", "...thank you. i feel better already."], ["hey. whatever it is, i'm right here.", "i know. that's why it already hurts less."]],
}
const COUPLE_SWEET: Array = [
	["you're my best friend and my sweetheart.", "that's the nicest thing anyone's ever said to me."],
	["i'd share my last apple with you.", "that is true love."],
]

# --- breakups ---
# [a says, b answers]  (a = the one who brings it up)
const BREAKUP_OPEN := {
	"drifted": [
		["{you}... can we talk? it feels like we haven't really been together lately.", "...yeah. i've felt it too. i miss you, but it's not the same."],
		["{you}, it's been so long. i don't know where we stand anymore.", "i don't either. i've been afraid to ask."],
	],
	"fading": [
		["{you}... can we talk? things haven't felt right between us for a while.", "...i know. it's been hard."],
		["{you}, we keep hurting each other. i don't think this is working.", "...i don't want to hear that. but i know."],
	],
}
# endings: lines alternate a, b, a, b...
const BREAKUP_PATCH: Array = [   # talked it out: still together
	["do you still want this? really?", "i do. please, let's try harder.", "...okay. okay. let's try again.", "thank you. i promise i'll do better."],
	["maybe we just need more time together.", "maybe. i'd like that. i don't want to lose you.", "you won't. let's start over, slowly.", "slowly is perfect."],
]
const BREAKUP_FRIENDS: Array = [   # still friends
	["i think we're better as friends.", "...i think you might be right. it hurts, though.", "it hurts me too. i still care about you so much.", "me too. friends?", "friends. always.", "always."],
	["i don't want to keep pretending, {you}.", "...me neither. i don't want to hate you.", "you could never. you'll always matter to me.", "you too. can we still hang out?", "i'd like that. a lot."],
]
const BREAKUP_MESSY: Array = [   # not friends any more
	["i think we should break up.", "WHAT? just like that?!", "i can't keep doing this.", "fine!! if that's what you want!", "it is.", "...then go."],
	["we're done, {you}.", "you can't mean that!", "i do. i'm sorry, but i do.", "don't be sorry. just leave."],
]
# --- trust: a believed rumour that my sweetheart likes somebody else ---
const CHEAT_ADMIT: Array = [   # [b, a, b]
	["...okay. it's true. i did have feelings for {t}. i'm so sorry.", "how could you?!", "i didn't act on it. i swear. i chose you."],
]
const CHEAT_FORGIVE: Array = [   # [a, b]
	["...i believe you. but you have to let it go.", "i already have. it's you. it's only you."],
	["...okay. i'll forgive you. once.", "thank you. i won't ruin it."],
]
const CHEAT_BREAK: Array = [   # [a, b, a]
	["i can't trust you after this. we're done.", "wait, please!", "no. goodbye, {you}."],
]
# --- getting back together ---
const REKINDLE_ASK: Array = [
	"{you}... i've been thinking about us. do you want to try again?",
	"{you}, i miss what we had. would you give us another chance?",
	"i know how it ended. but i keep thinking about you. can we try again?",
	"{you}... i was wrong to let you go. will you be my sweetheart again?",
]
const REKINDLE_YES: Array = ["...yes. let's try again.", "i was hoping you'd say that. yes.", "yes. i've missed you so much.", "yes!! come here!!"]
const REKINDLE_NO: Array = ["i'm sorry... i don't think i can go back.", "i care about you, but not like that. not anymore. i'm sorry.", "it hurt too much. i'm not ready. i'm sorry."]
const REKINDLE_SCENE: Array = [
	[["...hi. i'm sorry about how it ended.", "me too. i've thought about it a lot."], ["i missed you.", "i missed you too. so much."]],
	[["i was wrong to let you go.", "i was wrong too. let's not do that again."], ["can we go slow this time?", "slow is perfect. as long as it's with you."]],
]
const REKINDLE_END: Array = [["this feels like coming home.", "it does. welcome back."], ["i'm never letting go again.", "you'd better not."]]

# =========================================================
#  helpers
# =========================================================
static func _pick(options: Array) -> Variant:
	return options[randi() % options.size()]

static func _fill(text: String, vars: Dictionary) -> String:
	var out: String = text
	for k in vars.keys():
		out = out.replace("{%s}" % k, str(vars[k]))
	return out

static func _line(who: String, text: String, a: String, b: String, emote: String = "", fx: String = "") -> Dictionary:
	var me: String = a if who == "a" else b
	var you: String = b if who == "a" else a
	return {"who": who, "text": text.replace("{me}", me).replace("{you}", you), "emote": emote, "fx": fx}

static func _scene(kind: String, lines: Array, delta: int, grudge: int = 0, unfriend: bool = false) -> Dictionary:
	return {"kind": kind, "lines": lines.slice(0, 14), "delta": delta, "grudge": grudge, "unfriend": unfriend}

# =========================================================
#  Rumour data
# =========================================================
static func new_rumor(kind: String, subj: String, subj_name: String, about: String, about_name: String,
		twisted: bool, secret: bool, from: String, from_name: String, now: int) -> Dictionary:
	return {
		"id": "%08x" % randi(), "kind": kind,
		"subj": subj, "subj_name": subj_name, "about": about, "about_name": about_name,
		"twisted": twisted, "secret": secret,
		"from": from, "from_name": from_name,
		"heard": now, "told": [], "believed": true, "done": false,
	}

# What goes over the wire inside a gossip scene (the listener builds its own copy with receive())
static func wire(r: Dictionary) -> Dictionary:
	return {
		"id": str(r["id"]), "kind": str(r["kind"]),
		"subj": str(r["subj"]), "subj_name": str(r["subj_name"]),
		"about": str(r["about"]), "about_name": str(r["about_name"]),
		"twisted": bool(r["twisted"]), "secret": bool(r["secret"]),
	}

static func receive(w: Dictionary, from_fid: String, from_name: String, now: int, believed: bool) -> Dictionary:
	var r: Dictionary = new_rumor(str(w["kind"]), str(w["subj"]), str(w["subj_name"]), str(w["about"]), str(w["about_name"]),
			bool(w.get("twisted", false)), bool(w.get("secret", false)), from_fid, from_name, now)
	r["believed"] = believed
	return r

# Index of the best rumour to pass on to `listener_fid`, or -1.
# Not about / from the listener's own mouth, not already told to them, not too old. Rumours about the
# listener are the juiciest; secrets are told less eagerly (that's the betrayal).
static func pick_rumor(rumors: Array, listener_fid: String, now: int) -> int:
	var weights: Array = []
	var total: float = 0.0
	for i in rumors.size():
		var r: Dictionary = rumors[i]
		var w: float = 0.0
		if not bool(r["done"]) and str(r["subj"]) != listener_fid and str(r["from"]) != listener_fid \
				and not (listener_fid in r["told"]) and now - int(r["heard"]) < RUMOR_MAX_AGE:
			w = 1.0
			if str(r["about"]) == listener_fid:
				w = 3.0
			if bool(r["secret"]):
				w *= 0.4
		weights.append(w)
		total += w
	if total <= 0.0:
		return -1
	var roll: float = randf() * total
	for i in weights.size():
		roll -= float(weights[i])
		if roll < 0.0:
			return i
	return -1

# The version the teller actually says. May be twisted on the way (a copy; the teller's own memory is untouched).
# known = [{"fid", "name"}] the teller knows (used to pick somebody else for a twisted crush rumour).
static func twist(r: Dictionary, listener_fid: String, listener_name: String, hearsay: bool, known: Array) -> Dictionary:
	var out: Dictionary = r.duplicate(true)
	if bool(out["twisted"]):
		return out   # once twisted, always twisted
	if randf() >= (TWIST_HEARSAY if hearsay else TWIST_FIRST_HAND):
		return out
	match str(out["kind"]):
		"insult":
			# it was about someone else (or milder): now it is about YOU
			if str(out["about"]) != listener_fid:
				out["about"] = listener_fid
				out["about_name"] = listener_name
			out["twisted"] = true
		"crush":
			var options: Array = []
			for k in known:
				if str(k["fid"]) != str(out["subj"]) and str(k["fid"]) != str(out["about"]):
					options.append(k)
			if not options.is_empty():
				var k: Dictionary = _pick(options)
				out["about"] = str(k["fid"])
				out["about_name"] = str(k["name"])
			elif str(out["about"]) != listener_fid and str(out["subj"]) != listener_fid:
				out["about"] = listener_fid
				out["about_name"] = listener_name
			out["twisted"] = true
	return out

# =========================================================
#  Crush maths
# =========================================================
# How much this pet is into that pet (0.05 .. 1.5). Shared human tastes, friendship and a bit of luck.
static func attraction(me: Dictionary, them: Dictionary, friendship: float) -> float:
	var a: float = 0.35 + PetChat.same_count(me, them) * 0.1 + friendship / 250.0 + randf_range(-0.2, 0.2)
	if str(me.get("trait", "")) == "Affection":
		a += 0.15
	return clampf(a, 0.05, 1.5)

static func crush_gain(kind: String, me: Dictionary, them: Dictionary, friendship: float) -> float:
	return float(CRUSH_BASE.get(kind, 0.0)) * attraction(me, them, friendship)

# Would this pet say yes? Its OWN crush counts most, so a mutual crush nearly always works.
static func date_acceptance(own_crush: float, friendship: float, same: int, taken: bool) -> float:
	if taken:
		return 0.02
	return clampf(0.08 + own_crush / 100.0 * 0.65 + friendship / 100.0 * 0.2 + same * 0.03, 0.05, 0.95)

# Chance that an ask-out comes up this tick (added to the director's weights). 0 = not now.
static func ask_weight(crush: float, friendship: float, trait_name: String) -> float:
	if crush < CRUSH_TO_ASK or friendship < 50.0:
		return 0.0
	var w: float = (crush - CRUSH_TO_ASK) * 1.5 + 8.0
	if trait_name == "Affection" or trait_name == "Cheerfulness":
		w += 6.0
	elif trait_name == "Calmness":
		w -= 4.0   # the shy ones need longer to work up the courage
	return clampf(w, 3.0, 45.0)

# =========================================================
#  one-liners (the ask / answer handshake speaks these)
# =========================================================
static func ask_line(me: Dictionary, them: Dictionary) -> String:
	return _line("a", _pick(ASK_OUT), me["name"], them["name"])["text"]

static func answer_line(ok: bool, taken: bool) -> String:
	if ok:
		return _pick(ANSWER_YES)
	return _pick(ANSWER_TAKEN) if taken else _pick(ANSWER_NO)

static func after_no_line() -> String:
	return _pick(AFTER_NO)

# =========================================================
#  Scenes: gossip
# =========================================================
# plan = {"mode": "tell"|"vent"|"confide", "rumor": (tell only, already twisted or not),
#         "about_fid", "about_name" (vent / confide), "me_fid", "you_fid"}
static func gossip_scene(me: Dictionary, them: Dictionary, plan: Dictionary, now: int) -> Dictionary:
	var a: String = me["name"]
	var b: String = them["name"]
	var lines: Array = []
	var wire_rumor: Dictionary = {}
	var delta: int = 2
	var mode: String = str(plan.get("mode", "tell"))
	match mode:
		"vent":
			var open: Array = _pick(VENT_OPEN)
			lines.append(_line("a", open[0], a, b, "angry"))
			lines.append(_line("b", open[1], a, b))
			var body: Array = _pick(VENT_BODY)
			var t: String = str(plan["about_name"])
			lines.append(_line("a", _fill(body[0], {"t": t}), a, b, "angry", "shake"))
			lines.append(_line("b", _fill(body[1], {"t": t}), a, b))
			var end: Array = _pick(VENT_END)
			lines.append(_line("a", end[0], a, b, "sad"))
			lines.append(_line("b", end[1], a, b, "heart"))
			var r: Dictionary = new_rumor("insult", str(plan["me_fid"]), a, str(plan["about_fid"]), t, false, false, str(plan["me_fid"]), a, now)
			wire_rumor = wire(r)
			delta = 3
		"confide":
			var c: Array = _pick(CONFIDE)
			lines.append(_line("a", c[0], a, b, "think"))
			lines.append(_line("b", c[1], a, b))
			var rev: Array = _pick(CONFIDE_REVEAL)
			var t2: String = str(plan["about_name"])
			lines.append(_line("a", _fill(rev[0], {"t": t2}), a, b, "heart"))
			lines.append(_line("b", _fill(rev[1], {"t": t2}), a, b, "spark", "hop"))
			var e: Array = _pick(CONFIDE_END)
			lines.append(_line("a", e[0], a, b, "think"))
			lines.append(_line("b", e[1], a, b, "heart"))
			var r2: Dictionary = new_rumor("crush", str(plan["me_fid"]), a, str(plan["about_fid"]), t2, false, true, str(plan["me_fid"]), a, now)
			wire_rumor = wire(r2)
			delta = 4
		_:
			var r3: Dictionary = plan["rumor"]
			var intro: Array = _pick(TELL_INTRO)
			lines.append(_line("a", intro[0], a, b, "think"))
			lines.append(_line("b", intro[1], a, b, "spark"))
			var aud: String = "other"
			if str(r3["about"]) == str(plan["you_fid"]):
				aud = "you"
			elif str(r3["about"]) == str(plan["me_fid"]):
				aud = "me"
			var variant: String = "spicy" if bool(r3["twisted"]) else "plain"
			var tell: String = _fill(_pick(TELL[str(r3["kind"])][variant][aud]), {"s": r3["subj_name"], "t": r3["about_name"]})
			lines.append(_line("a", tell, a, b, "think"))
			lines.append(_line("b", _fill(_pick(TELL_REACT), {"s": r3["subj_name"]}), a, b, "spark", "wiggle"))
			var close: Array = _pick(TELL_CLOSE)
			lines.append(_line("a", close[0], a, b))
			lines.append(_line("b", close[1], a, b))
			wire_rumor = wire(r3)
	var scene: Dictionary = _scene("gossip", lines, delta)
	scene["mode"] = mode
	scene["rumor"] = wire_rumor
	return scene

# =========================================================
#  Scenes: confrontations
# =========================================================
# plan = {"mode": "insult"|"crush"|"jealous"|"spreader", "rumor": {...} (not for spreader),
#         "partner_name" (jealous), "target_fid" (spreader), "why": "lie"|"secret" (spreader)}
# a = the pet that starts it, b = the one being confronted.
static func confront_scene(me: Dictionary, them: Dictionary, plan: Dictionary, friendship: float, befriended: bool) -> Dictionary:
	var mode: String = str(plan["mode"])
	if mode == "spreader":
		return _spreader_scene(me, them, plan)
	var a: String = me["name"]
	var b: String = them["name"]
	var r: Dictionary = plan["rumor"]
	var truth: bool = not bool(r["twisted"])
	var src: String = str(r.get("from_name", ""))
	if src == "":
		src = "somebody"
	var vars := {"src": src, "p": str(plan.get("partner_name", "them")), "t": str(plan.get("third_name", "somebody"))}
	var soft: bool = friendship >= 60.0 and mode == "insult"
	var lines: Array = []

	# 1. the opening
	var open: Array = _pick(OPEN_SOFT[mode]) if soft else _pick(OPEN_ANGRY[mode])
	lines.append(_line("a", _fill(open[0], vars), a, b, str(open[2]), str(open[3])))
	lines.append(_line("b", _fill(open[1], vars), a, b))
	# 2. what they heard
	var accuse: String = _fill(_pick(ACCUSE[mode]["spicy" if bool(r["twisted"]) else "plain"]), vars)
	lines.append(_line("a", accuse, a, b, "angry" if mode != "crush" else "think", "shake" if mode != "crush" else ""))

	var delta: int = 0
	var grudge: int = 0
	var unfriend: bool = false
	var scene_extra: Dictionary = {}
	var blame_src: bool = false
	var split: String = ""

	# 3. how it ends depends on whether the rumour was true
	match mode:
		"insult":
			if truth:
				var p_admit: float = clampf(0.45 + friendship / 200.0 + (0.2 if soft else 0.0), 0.3, 0.9)
				if randf() < p_admit:
					var ad: Array = _pick(ADMIT)
					lines.append(_line("b", ad[0], a, b, "sad"))
					lines.append(_line("a", ad[1], a, b, "sad"))
					lines.append(_line("b", ad[2], a, b, "sad"))
					lines.append(_line("a", ad[3], a, b, "heart"))
					delta = 4
				else:
					var dd: Array = _pick(DEFIANT)
					lines.append(_line("b", dd[0], a, b, "angry", "shake"))
					lines.append(_line("a", dd[1], a, b, "angry", "shake"))
					var es: Array = _pick(ESCALATE)
					lines.append(_line("a", es[0], a, b, "angry", "shake"))
					lines.append(_line("b", es[1], a, b, "angry", "shake"))
					var st: Array = _pick(STALEMATE)
					lines.append(_line("a", st[0], a, b, "angry"))
					lines.append(_line("b", st[1], a, b, "angry", "shake"))
					delta = -12
					grudge = 150
					unfriend = befriended and friendship - 12.0 < 20.0
			else:
				var believed: bool = _denial(lines, a, b, vars, friendship, soft)
				blame_src = true
				delta = 5 if believed else -8
				grudge = 0 if believed else 120
		"crush":
			if truth:
				var bt: Array = _pick(BLUSH_TRUE)
				lines.append(_line("b", bt[0], a, b, "heart"))
				lines.append(_line("a", bt[1], a, b, "heart"))
				lines.append(_line("b", bt[2], a, b, "think"))
				lines.append(_line("a", bt[3], a, b, "hearts", "hop"))
				delta = 5
				scene_extra["a_crush"] = 15.0   # now the listener starts to wonder...
				scene_extra["b_crush"] = 8.0
			else:
				var bf: Array = _pick(BLUSH_FALSE)
				lines.append(_line("b", bf[0], a, b, "angry", "shake"))
				lines.append(_line("a", bf[1], a, b, "think"))
				lines.append(_line("b", _fill(bf[2], vars), a, b, "angry"))
				lines.append(_line("a", _fill(bf[3], vars), a, b, "think"))
				delta = -3
				blame_src = true
		"cheater":
			# my sweetheart is said to like somebody else
			if truth:
				var ch: Array = _pick(CHEAT_ADMIT)
				lines.append(_line("b", _fill(ch[0], vars), a, b, "sad"))
				lines.append(_line("a", ch[1], a, b, "angry", "shake"))
				lines.append(_line("b", ch[2], a, b, "sad"))
				if randf() < 0.45:
					var cf: Array = _pick(CHEAT_FORGIVE)
					lines.append(_line("a", cf[0], a, b, "sad"))
					lines.append(_line("b", cf[1], a, b, "heart"))
					delta = -3
					scene_extra["b_drop"] = str(r["about"])   # b's own game lowers b's crush on that pet
				else:
					var cb: Array = _pick(CHEAT_BREAK)
					lines.append(_line("a", cb[0], a, b, "angry", "shake"))
					lines.append(_line("b", cb[1], a, b, "sad"))
					lines.append(_line("a", cb[2], a, b, "angry"))
					delta = -10
					grudge = 150
					split = "messy"
			else:
				var believed3: bool = _denial(lines, a, b, vars, friendship, false)
				blame_src = true
				if believed3:
					delta = 5
				else:
					delta = -8
					grudge = 120
					split = "messy"   # trust is gone
		"jealous":
			if truth:
				if randf() < 0.6:
					var jb: Array = _pick(JEALOUS_BACK)
					lines.append(_line("b", _fill(jb[0], vars), a, b, "sad"))
					lines.append(_line("a", jb[1], a, b, "angry"))
					lines.append(_line("b", jb[2], a, b, "sad"))
					lines.append(_line("a", jb[3], a, b, "heart"))
					delta = 1
					scene_extra["b_drop"] = str(r["about"])   # b's own game lowers b's crush on that pet
				else:
					var jd: Array = _pick(JEALOUS_DEFY)
					lines.append(_line("b", jd[0], a, b, "angry", "shake"))
					lines.append(_line("a", jd[1], a, b, "angry", "shake"))
					var st2: Array = _pick(STALEMATE)
					lines.append(_line("a", st2[0], a, b, "angry"))
					lines.append(_line("b", st2[1], a, b, "angry", "shake"))
					delta = -12
					grudge = 150
					unfriend = befriended and friendship - 12.0 < 20.0
			else:
				var believed2: bool = _denial(lines, a, b, vars, friendship, false)
				blame_src = true
				delta = 5 if believed2 else -8
				grudge = 0 if believed2 else 120

	var scene: Dictionary = _scene("confront", lines, delta, grudge, unfriend)
	scene["mode"] = mode
	scene["resolve"] = str(r["id"])
	scene["truth"] = truth
	if split != "":
		scene["split"] = split
		scene["crush_cap"] = 15.0
	for k in scene_extra.keys():
		scene[k] = scene_extra[k]
	# a lie (or a betrayed secret) leaves a mark on whoever passed it on.
	# "by": who holds the grudge: "both" (a lie fooled both of them) or "b" (only the one whose secret it was)
	if blame_src and str(r.get("from", "")) != "":
		scene["blame"] = {"fid": str(r["from"]), "name": src, "why": "lie", "by": "both"}
	elif bool(r.get("secret", false)) and truth and str(r.get("from", "")) != "" and mode == "crush":
		scene["blame"] = {"fid": str(r["from"]), "name": src, "why": "secret", "by": "b"}
	return scene

# The target says "i never said that" and the confronter believes it (or doesn't).
# Appends the lines and returns true when the confronter believed it.
static func _denial(lines: Array, a: String, b: String, vars: Dictionary, friendship: float, soft: bool) -> bool:
	var dn: Array = _pick(DENY)
	lines.append(_line("b", dn[0], a, b, "angry", "shake"))
	lines.append(_line("a", dn[1], a, b, "think"))
	var who: Array = _pick(DENY_WHO)
	lines.append(_line("b", _fill(who[0], vars), a, b, "angry"))
	lines.append(_line("a", _fill(who[1], vars), a, b))
	lines.append(_line("b", _fill(_pick(DENY_REACT), vars).replace("{you}", a), a, b, "angry"))
	var p_believe: float = clampf(0.5 + friendship / 200.0 + (0.2 if soft else 0.0), 0.4, 0.95)
	if randf() < p_believe:
		var be: Array = _pick(BELIEVE)
		lines.append(_line("a", be[0], a, b, "sad"))
		lines.append(_line("b", be[1], a, b, "heart"))
		lines.append(_line("b", _fill(_pick(BELIEVE_END), vars), a, b, "spark"))
		return true
	else:
		var di: Array = _pick(DISBELIEVE)
		lines.append(_line("a", di[0], a, b, "angry", "shake"))
		lines.append(_line("b", di[1], a, b, "angry", "shake"))
		return false

static func _spreader_scene(me: Dictionary, them: Dictionary, plan: Dictionary) -> Dictionary:
	var a: String = me["name"]
	var b: String = them["name"]
	var secret: bool = str(plan.get("why", "lie")) == "secret"
	var lines: Array = []
	lines.append(_line("a", _pick(SPREAD_SECRET_OPEN if secret else SPREAD_LIE_OPEN), a, b, "angry", "shake"))
	var delta: int = 3
	var grudge: int = 0
	if randf() < 0.65:
		var s: Array = _pick(SPREAD_SORRY_SECRET if secret else SPREAD_SORRY_LIE)
		lines.append(_line("b", s[0], a, b, "sad"))
		lines.append(_line("a", s[1], a, b, "sad"))
		lines.append(_line("b", s[2], a, b, "sad"))
		lines.append(_line("a", s[3], a, b, "heart"))
	else:
		var d: Array = _pick(SPREAD_DEFY)
		lines.append(_line("b", d[0], a, b, "angry", "shake"))
		lines.append(_line("a", d[1], a, b, "angry", "shake"))
		var st: Array = _pick(STALEMATE)
		lines.append(_line("a", st[0], a, b, "angry"))
		lines.append(_line("b", st[1], a, b, "angry", "shake"))
		delta = -8
		grudge = 120
	var scene: Dictionary = _scene("confront", lines, delta, grudge)
	scene["mode"] = "spreader"
	scene["clear_blame"] = str(plan.get("target_fid", ""))
	return scene

# =========================================================
#  Scenes: romance
# =========================================================
# Right after a "yes". a = the one who asked.
static func first_date_scene(me: Dictionary, them: Dictionary) -> Dictionary:
	var a: String = me["name"]
	var b: String = them["name"]
	var lines: Array = []
	var bits: Array = _pick(FIRST_DATE)
	var first: Array = bits[0]
	var second: Array = bits[1]
	lines.append(_line("a", first[0], a, b, "hearts", "hop"))
	lines.append(_line("b", first[1], a, b, "hearts", "hop"))
	lines.append(_line("a", second[0], a, b, "heart"))
	lines.append(_line("b", second[1], a, b, "heart"))
	var end: Array = _pick(FIRST_DATE_END)
	lines.append(_line("a", end[0], a, b, "hearts"))
	lines.append(_line("b", end[1], a, b, "hearts", "wiggle"))
	var scene: Dictionary = _scene("romance", lines, 10)
	scene["dating"] = true
	scene["mode"] = "first"
	return scene

# "5 days" / "a week" / "3 weeks" / "2 months"
static func _since_text(days: int) -> String:
	if days < 2:
		return "a day"
	if days < 7:
		return "%d days" % days
	if days < 14:
		return "a week"
	if days < 60:
		return "%d weeks" % (days / 7)
	return "%d months" % (days / 30)

# One little exchange of a couple scene. `turn` ("a" / "b") says the first line, the other one answers.
static func _couple_segment(seg: String, me: Dictionary, them: Dictionary, turn: String, vars: Dictionary) -> Array:
	var a: String = me["name"]
	var b: String = them["name"]
	var other: String = _other_who(turn)
	var pair: Array = []
	var e1: String = "heart"
	var e2: String = "hearts"
	match seg:
		"plans":
			pair = _pick(COUPLE_PLANS)
		"tease":
			pair = _pick(COUPLE_TEASE)
			e1 = ""
			e2 = "laugh"
		"memory":
			pair = _pick(COUPLE_MEMORY)
		"taste":
			var key: String = str(_pick(PetChat.shared_keys(me, them)))
			var mine: String = PetChat.pretty(me["answers"][key]) if turn == "a" else PetChat.pretty(them["answers"][key])
			var theirs: String = PetChat.pretty(them["answers"][key]) if turn == "a" else PetChat.pretty(me["answers"][key])
			vars["mine"] = mine
			vars["theirs"] = theirs
			pair = _pick(COUPLE_TASTE_SAME if mine == theirs else COUPLE_TASTE_DIFF)
		"care":
			# whoever is hungry / bored / down gets looked after by the other one
			var notable: Array = ["hungry", "bored", "down"]
			var fa: String = str(me.get("feeling", "okay"))
			var fb: String = str(them.get("feeling", "okay"))
			var sad_one: String = "a" if fa in notable else "b"
			var feeling: String = fa if sad_one == "a" else fb
			if not (feeling in notable):
				pair = _pick(COUPLE_CHAT)
			else:
				turn = _other_who(sad_one)   # the one who notices speaks first
				other = sad_one
				pair = _pick(COUPLE_CARE[feeling])
		_:
			pair = _pick(COUPLE_CHAT)
	return [
		_line(turn, _fill(str(pair[0]), vars), a, b, e1),
		_line(other, _fill(str(pair[1]), vars), a, b, e2, "wiggle" if seg == "chat" else ""),
	]

static func _other_who(who: String) -> String:
	return "b" if who == "a" else "a"

# A couple spending time together. ctx (optional): "days" = how long they have been together.
static func romance_scene(me: Dictionary, them: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var a: String = me["name"]
	var b: String = them["name"]
	var days: int = int(ctx.get("days", 0))
	var vars := {"nick": str(_pick(NICKNAMES)), "days": _since_text(days)}
	var pool: Array = ["chat", "chat", "plans", "tease"]
	if days >= 1:
		pool.append_array(["memory", "memory"])
	if not PetChat.shared_keys(me, them).is_empty():
		pool.append("taste")
	var notable: Array = ["hungry", "bored", "down"]
	if str(me.get("feeling", "okay")) in notable or str(them.get("feeling", "okay")) in notable:
		pool.append_array(["care", "care", "care"])
	pool.shuffle()
	var count: int = 2 if randf() < 0.55 else 3
	var chosen: Array = []
	for s in pool:
		if chosen.size() < count and not (s in chosen):
			chosen.append(s)
	var lines: Array = []
	var turn: String = "a" if randf() < 0.5 else "b"
	for s in chosen:
		lines.append_array(_couple_segment(str(s), me, them, turn, vars))
		turn = _other_who(turn)
	if randf() < 0.3:
		var sw: Array = _pick(COUPLE_SWEET)
		lines.append(_line(turn, sw[0], a, b, "hearts"))
		lines.append(_line(_other_who(turn), sw[1], a, b, "hearts", "hop"))
	var scene: Dictionary = _scene("romance", lines, 4 + (1 if chosen.size() > 2 else 0))
	scene["mode"] = "couple"
	return scene

# =========================================================
#  Scenes: breaking up
# =========================================================
# a = the one who brings it up (the one who ends it), b = the other one. reason: "drifted" | "fading".
# The scene says how it ended in "split": "" (talked it out), "amicable" (still friends) or "messy".
# "crush_cap": what is left of the crush on the other one afterwards (each game applies it to its own pet).
static func breakup_scene(me: Dictionary, them: Dictionary, reason: String, friendship: float) -> Dictionary:
	var a: String = me["name"]
	var b: String = them["name"]
	var lines: Array = []
	var open: Array = _pick(BREAKUP_OPEN.get(reason, BREAKUP_OPEN["drifted"]))
	lines.append(_line("a", open[0], a, b, "sad"))
	lines.append(_line("b", open[1], a, b, "sad"))

	var w_patch: float = 12.0 + friendship * 0.3 + (15.0 if reason == "drifted" else 0.0)
	var w_messy: float = maxf(5.0, 40.0 - friendship * 0.5 - (15.0 if reason == "drifted" else 0.0))
	var w_friends: float = 50.0
	var roll: float = randf() * (w_patch + w_messy + w_friends)
	var split: String = "amicable"
	var pool: Array = BREAKUP_FRIENDS
	if roll < w_patch:
		split = ""
		pool = BREAKUP_PATCH
	elif roll < w_patch + w_messy:
		split = "messy"
		pool = BREAKUP_MESSY
	var body: Array = _pick(pool)
	for i in body.size():
		var who: String = "a" if i % 2 == 0 else "b"
		var emote: String = "sad"
		var fx: String = ""
		var last: bool = i == body.size() - 1
		if split == "":
			emote = "heart" if i >= 2 else "sad"
		elif split == "messy":
			emote = "sad" if last else "angry"
			fx = "shake" if i == 1 else ""
		else:
			emote = "heart" if last else "sad"
		lines.append(_line(who, str(body[i]), a, b, emote, fx))

	var delta: int = 6
	if split == "amicable":
		delta = -6
	elif split == "messy":
		delta = -10
	var scene: Dictionary = _scene("romance", lines, delta, 150 if split == "messy" else 0)
	scene["mode"] = "breakup"
	scene["split"] = split
	scene["crush_cap"] = 42.0 if split == "amicable" else 20.0
	return scene

# =========================================================
#  Getting back together
# =========================================================
# How likely an ex is to ask this tick (0 = not now). Needs time apart, real friendship and some feelings left.
static func rekindle_weight(crush: float, friendship: float, since: int, i_ended_it: bool) -> float:
	if since < REKINDLE_MIN_WAIT or friendship < 45.0 or crush < 25.0:
		return 0.0
	var w: float = 6.0 + (crush - 25.0) * 0.6 + (friendship - 45.0) * 0.2
	if i_ended_it:
		w *= 0.6   # a bit sheepish about asking
	return clampf(w, 3.0, 28.0)

static func rekindle_acceptance(crush: float, friendship: float, same: int, i_ended_it: bool) -> float:
	var p: float = 0.12 + crush / 100.0 * 0.55 + friendship / 100.0 * 0.25 + same * 0.03
	p += 0.05 if i_ended_it else -0.08   # whoever got left is warier
	return clampf(p, 0.05, 0.92)

static func rekindle_ask_line(me: Dictionary, them: Dictionary) -> String:
	return _line("a", _pick(REKINDLE_ASK), me["name"], them["name"])["text"]

static func rekindle_answer_line(ok: bool, taken: bool) -> String:
	if ok:
		return _pick(REKINDLE_YES)
	return _pick(ANSWER_TAKEN) if taken else _pick(REKINDLE_NO)

# Right after a "yes". a = the one who asked.
static func rekindle_scene(me: Dictionary, them: Dictionary) -> Dictionary:
	var a: String = me["name"]
	var b: String = them["name"]
	var lines: Array = []
	var bits: Array = _pick(REKINDLE_SCENE)
	for pair in bits:
		lines.append(_line("a", pair[0], a, b, "sad"))
		lines.append(_line("b", pair[1], a, b, "heart"))
	var end: Array = _pick(REKINDLE_END)
	lines.append(_line("a", end[0], a, b, "hearts"))
	lines.append(_line("b", end[1], a, b, "hearts", "hop"))
	var scene: Dictionary = _scene("romance", lines, 10)
	scene["mode"] = "rekindle"
	return scene
