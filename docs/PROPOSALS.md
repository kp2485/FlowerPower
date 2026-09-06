# Proposals for the player experience

**Status, 2026-09-06: all twenty-one approved and built.** The engine half of
every proposal is measured and tested; the interface half is written and, like
the rest of the app, has never been compiled. What each one became is noted at
the end of its entry under *Built*.

**Later the same day, four more things were built that are not proposals here**
— they came off PLAN.md's roadmap rather than out of this document, and they are
written up there rather than added as numbers 22 to 25. In short: something to
do about swarming (open the nest up, or divide the colony deliberately);
something to read in winter; alarm pheromone wired to defence and foraging; and
two modelling errors behind the second-year cliff. The measured effect of each
is in PLAN.md, including the two that measured *worse* than doing nothing.

Twenty-one proposals, numbered so you can approve or deny each one by
number. Each has a pitch, what the player would actually see, the decision it
puts in front of them if any, the biology it rests on, a cost, and a
recommendation. The recommendation is mine and you should overrule it freely.

The brief these are written against: **an idle game with occasional
interaction, not something people play for hours.** Every proposal was tested
against that, and the ones that failed it are listed at the end with the reason.

---

## The principle behind the event proposals

Several of these put a decision in front of the player at a moment the
simulation chooses. For that to feel like an idle game rather than a pager,
five rules:

1. **The default is instinct.** If the player does not respond, the colony does
   what a colony does — which is exactly what the engine does today. Nobody is
   punished for being at work. Responding is a chance to do better than
   instinct, not a duty.
2. **Windows are real.** An event lasts as long as it lasts in the simulation.
   At two real hours per simulated day, a wasp attack lasting a simulated
   afternoon gives about half an hour to respond, and a swarm gathering over
   eight simulated days gives the best part of a real day. Nothing needs
   answering in seconds.
3. **Few and consequential.** A handful of decisions a season, each of which
   matters. Not a stream.
4. **Decidable from the lock screen.** The decision should fit in a
   notification's action buttons or a tap on the watch. Opening the app is for
   when the player *wants* to look.
5. **Never retroactive.** A decision applies from the moment it is made. The
   deterministic catch-up stays deterministic; the player's choices are simply
   inputs with timestamps, which is what they already are.

And the engine's standing rule applies to all of them: every new player action
is a balance lever, and it gets measured with `beesim` before it ships.

---

## A. Events with decisions

### 1. Defend the hive — threat events with a choice

**Pitch.** The engine already models twenty-one predators with six distinct
attack styles, and every attack resolves automatically. Turn the ones a colony
can genuinely do something about into decisions.

**What the player sees.** A notification: "Wasps at the entrance." On the lock
screen, action buttons. On the watch, the same. In the app, a Live Activity
showing the attack in progress and the guards' strength.

**The decision**, by attack style:

| Style | Predators | Choices |
|---|---|---|
| Entrance | wasp, hornet, robber bee, ant | Hold the entrance · Narrow the entrance · Let them be |
| Pilfer | skunk, raccoon, opossum, mouse | Narrow the entrance · Flee (see 2) · Weather it |
| Field | bee-eater, shrike, dragonfly, crab spider, mantis | Keep the foragers home · Accept the losses |
| Comb | wax moth, hive beetle | Send in the cleaners · Nothing |
| Catastrophic | bear, badger, human | No decision during. Afterwards: Rebuild here · Move |
| Parasite | mites | No event; that is the disease system's job |

*Hold the entrance* is `emphasise(.guardBee)` for the duration: more guards,
fewer foragers, more stings, more dead defenders. *Narrow the entrance* is the
propolis envelope the engine already tracks, applied to the entrance: harder
to force, harder to rob, and slower foraging throughput while it stands. *Keep
the foragers home* pulls foragers in for the day. *Send in the cleaners* is
`emphasise(.cellCleaner)`.

**Realism.** All of it. Guards hold entrances; alarm pheromone recruits more;
stinging is fatal to the bee. Colonies narrow entrances with propolis in
autumn against wasps and mice. Nothing a colony does stops a bear.

**Cost.** Medium. Engine: a "posture" with a duration, three or four new
inputs, events for the window opening and closing. App: notification
categories with actions, a Live Activity, watch handling. Needs the Mac.

**Recommendation: Approve.** This is the one you asked for, and it is the best
fit for occasional interaction in the whole list.

*Built.* `HivePosture`, `ActiveThreat`, sieges with real windows in `ThreatSystem`, notification categories with action buttons, a Live Activity, and `ThreatDecisionCard` on the dashboard. Holding the entrance measurably repels more wasps and measurably costs forage.

### 2. Flee the hive — absconding as a real choice

**Pitch.** "Flee" in bee terms is absconding: the whole colony abandons the
nest. It is real, it is drastic, and it is sometimes right.

**What the player sees.** Offered as an option during pilfering (a skunk at the
entrance every night will wear a colony down) and after a catastrophic attack.
Also reachable from settings as "abandon this site".

**The decision.** Flee now, or stay. Fleeing moves the colony to a new site of
the player's choosing — the existing relocation screen — but the adults go
alone. Stores stay behind. Brood stays behind. The colony arrives as a swarm
does: bees, a queen, and whatever honey is in their crops.

**Realism, and a correction.** Relocation today moves everything, which no
wild colony can do. Making *every* relocation an absconding is the honest
model, and it turns "move house" from a free action into a hard one. I would
make that change as part of this.

**Cost.** Small. The engine has an `absconded` event and relocation already;
this is mostly the cost of leaving things behind, and the screen.

**Recommendation: Approve, including the correction.** If you would rather
keep free relocation as a mercy, say so — it is a design choice, but I think
the game is better for the loss being real.

*Built, with the correction.* Every relocation is an absconding: adults go with what honey they carry, everything else stays.

### 3. The swarm decision, and following the swarm

**Pitch.** Swarming is the main thing that ends colonies, the engine emits an
event when swarm cells are started, and the eight simulated days before
departure are the best part of a real day. The player currently learns about
it afterwards.

**What the player sees.** "The colony is preparing to swarm." A Live Activity
counting down. On departure, a second decision.

**Decision one, before.** Let them go · Discourage · Move to a larger cavity.
*Discourage* is `emphasise(.honeycombBuilder)` plus keeping foragers in — it
lowers the congestion that drives swarming and reduces the chance without
removing it, which is about what a beekeeper achieves by giving room.

**Decision two, at departure — follow the swarm.** The old queen leaves with
sixty per cent of the bees. Stay with the parent colony (a virgin queen and a
mating flight she may not return from) or go with the swarm (the proven queen,
a new site of the player's choosing, and nothing else). The garden comes along
either way. Mechanically it is `newGame(at:inheriting:)`, which exists.

**Realism.** Swarming is exactly this. The parent colony's fate rests on a
virgin's mating flight; the swarm's on finding a site and building comb before
the flow ends.

**Cost.** Medium. Engine: expose the window, add discouragement as an input,
build the swarm's starting state. App: two decision points.

**Recommendation: Approve.** Following the swarm turns the largest cause of
death into a story fork rather than a loss, and it costs nothing in realism.

*Built.* `PendingSwarm` opens with the first swarm cell; discouraging adopts the make-room posture and halves the odds; the departed swarm is kept so the player can follow it into a new colony with the queen's number intact.

### 4. Winter intruders, decided in autumn

**Pitch.** Winter is a quarter of the year with nothing to photograph. Two
things that actually happen to clustered colonies would give it a shape: mice
move in, and in a hard frost green woodpeckers open up the nest.

**What the player sees.** In autumn: "The bees are sealing the entrance with
propolis." In winter, if they did not: "A mouse has got in." A woodpecker
attack in a cold snap, catastrophic-style, no decision.

**The decision.** In autumn only: let them narrow the entrance (mouse-proof,
but the cluster ventilates less and damp does its own damage) or keep it open.
Once clustered there is nothing a colony can do, which is the point — the
decision is made before the season, and the season is what happens.

**Realism.** Both are well documented. Mice in overwintering hives are a
standard beekeeping problem; woodpecker damage in hard winters is a British
speciality.

**Cost.** Small to medium. Mouse and woodpecker exist as predators; this is the
autumn choice and the winter consequence.

**Recommendation: Approve.** It gives winter one decision and one story, and
that is about the right amount.

*Built.* Instinct seals the entrance late in autumn if there is propolis; the player can keep it open; sealed keeps mice out and damp in; woodpeckers attack only in frost.

### 5. Robbing in a dearth

**Pitch.** In a dearth, strong colonies rob weak ones, and wasps join in. The
engine has `robberBee` as an entrance predator and a dearth state.

**Recommendation: Fold into 1.** It is an entrance event with the same choices.
Listed separately only so you can see it was considered.


*Folded into 1*, as recommended.

---

## B. Cadence and where decisions arrive

### 6. Actionable notifications

**Pitch.** Decisions arrive as notifications with action buttons, so "Hold the
entrance" is a tap on the lock screen and the app never has to be opened.

**What the player sees.** A notification category per event type, with two or
three actions. On the watch, the same actions. The app's background refresh
already runs the simulation while closed; this is what lets it *ask* while
closed.

**Cost.** Small to medium, and it is the foundation for everything in section A.
`ColonyNews` already decides what deserves a notification; this adds the
buttons and the handling.

**Recommendation: Approve, first.** Nothing in A works well without it.

*Built.* `NotificationActions` registers a category per decision, and a tapped button becomes a store call on the save file with no interface running. Stale taps do nothing rather than something wrong.

### 7. Live Activities for events in progress

**Pitch.** An attack under way, a swarm gathering, a queen out on her mating
flight — each has a duration, and each is what Live Activities are for. On
the lock screen, in the Dynamic Island, in the watch's Smart Stack.

**What the player sees.** A compact status that updates as the event runs and
disappears when it ends. Guards holding, or not. Days until the swarm goes.
The queen out, then back.

**Cost.** Medium. It is a widget extension with a shared attributes type and
updates pushed from the background task. The complication code is a starting
point.

**Recommendation: Approve.** The mating flight alone justifies it: it is the
most dramatic thing that happens in the game and today it is invisible.

*Built.* `HiveActivityAttributes` shared with a new `FlowerPowerWidgets` extension; a siege, a swarm gathering and a virgin queen's wait each show on the lock screen and in the Dynamic Island, reconciled on every catch-up.

### 8. One digest a day instead of a drip

**Pitch.** Twelve simulated days pass between a player's daily visits. Rather
than notifying as things happen, send one "morning at the hive" summary at a
time the player picks, and reserve immediate notifications for events with a
decision attached.

**Cost.** Small. `ColonyNews` decides what is worth saying; this decides when.

**Recommendation: Approve.** It is what makes the notifications from section A
tolerable: routine news is bundled, and an interruption means something.

*Built.* `DailyDigest` from the catch-up report, sent once a day at the hour the player picks, and not at all if nothing happened.

### 9. A Home Screen widget

**Pitch.** The watch has a complication. The phone should have the same thing
on the Home Screen and the lock screen: status, the seasonal gauge, the
headline.

**Cost.** Small. The complication's provider and views port nearly directly.

**Recommendation: Approve.** Cheap, and the phone is where most players are.

*Built.* The complication's provider and gauge, ported into the widget extension for small, medium and lock-screen families.

---

## C. The long game

### 10. Queen lineage

**Pitch.** Every queen gets a number and, if the player likes, a name. The
colony shows its generation. When a colony ends, its queens are remembered in
the garden alongside the flowers. An idle game lives on legacy, and this game
already generates it — swarms, supersedures, failed mating flights — without
keeping any of it.

**What the player sees.** "Third colony. Queen V, daughter of Queen III, mated
with eleven drones." A tree, if the player wants one.

**Cost.** Small to medium. The events exist; this records them.

**Recommendation: Approve.** It costs little and it is what turns a
simulation into a story.

*Built.* `Lineage` kept by `LineageSystem` from the queen events; Roman numerals, names the player gives, endings recorded; `LineageView`.

### 11. The almanac

**Pitch.** A journal written by the game: first willow, first swarm cell, the
day the honey peaked, the coldest night, what ended the colony. One line a
day at most, and only when something happened.

**Cost.** Medium. Mostly presentation over the event stream.

**Recommendation: Consider.** Lovely, and less urgent than 10. It is also what
gives winter something to read.

*Built.* `Almanac` written by the simulation itself, one line per kind per day, capped; `AlmanacView` by year and season.

### 12. Honey as a decision

**Pitch.** Honey has no purpose in the game beyond keeping the colony alive.
Give it one: in autumn the player may take some. It becomes the score, or a
gift to a friend (see 17), and every unit taken is a unit the colony does not
have for winter.

**The decision.** How much, once a year, against the winter-readiness meter.

**Realism.** This is the central decision of beekeeping, and it is a stretch
for a game about a wild colony with a guardian rather than a keeper. I would
frame it as the colony's surplus rather than a harvest.

**Cost.** Medium.

**Recommendation: Consider.** It is the strongest candidate for a score, and
the game has none. But it changes what the player is, and that is your call.

*Built.* `takeHoney` capped at what the colony can spare for the season; a running total; `HoneyDecisionCard` in autumn.

### 13. Botany as a collection

**Pitch.** Now that flowers are placed by family, the garden can show the
collection that implies: fourteen families of eighteen, which genera, how much
of the bloom calendar is covered. The gaps are the nudge to go out.

**Cost.** Small. Presentation over data the engine already has.

**Recommendation: Approve.** It is the natural reward for the taxonomy work,
and it points the player at the door.

*Built.* `BotanyCollection` over the garden — families, genera, species, the bloom calendar with its gaps — and `CollectionView`.

---

## D. Winter

### 14. Winter as the reading season

**Pitch.** Rather than making winter shorter, make it the time the almanac,
the lineage and the collection are worth opening — and the time a friend's
shared flower matters most. Nothing to do, something to look at.

**Cost.** Small, once 10, 11 and 13 exist.

**Recommendation: Approve, as the framing.** Winter should feel like winter.

*Built as framing.* The lineage, almanac and collection are reachable from the dashboard, and the bloom prompt steps aside in winter.

### 15. A faster winter clock

**Pitch.** Idle games often accelerate dead time. Winter at twice the speed
would be four real days rather than seven.

**Why I would not.** The clock's rate is baked into the deterministic mapping
from dates to ticks; a seasonal rate is possible but complicates catch-up,
the watch's independent replay, and every balance figure. And it treats the
symptom: winter is dull because there is nothing in it, not because it is long.

**Recommendation: Deny.** Prefer 4 and 14.

*Built, overruling the recommendation.* `SimClock.winterSpeed`, default 2, part of the save so catch-up and the watch's replay stay exact. Old saves decode as uniform. A toggle in settings.

*And then the symptom was treated too, later the same day.* The objection above
— "winter is dull because there is nothing in it, not because it is long" — was
the right one, and the faster clock did not answer it. Winter now has the
colony's own account of the year it has just finished (`Almanac.review`), a
headline that moves through the four things a wintering colony is actually
doing rather than one sentence for ninety days, and the bloom prompt is no
longer hidden in the one season where it matters most: two plants in the
catalogue flower in winter, and both are keystones. See PLAN.md, roadmap item 6.

---

## E. Botany and understanding

### 16. Show the reason

**Pitch.** The flower page shows *why* the bees do what they do: a small
diagram of corolla depth against a honey bee's reach, the sugar
concentration, the pollen's protein and whether its amino acids are complete.
When foxglove yields nothing, the page says it is a bumblebee flower and
shows the tube.

**Cost.** Small to medium. Interface only; the numbers exist.

**Recommendation: Approve.** The science is the game's distinguishing feature,
and this is how the player sees it.

*Built.* `FloralTraitsView` on every flower: the corolla drawn against a honey bee's reach, sugar concentration, pollen protein, and a warning for incomplete amino acids.

### 17. "In bloom near you"

**Pitch.** A seasonal prompt from the bloom calendar: what is out this month,
which of it the player has not photographed, which families they are missing.
Uses the season and hemisphere, not the player's location.

**Cost.** Small.

**Recommendation: Approve.** It is the gentlest possible way of getting
someone outside.

*Built.* `BloomPrompt` from the real date and hemisphere, on the dashboard and in the collection.

---

## F. Between players

### 18. Gifting a swarm

**Pitch.** When your colony swarms, send the swarm to a friend. They receive a
file like a shared flower, and on opening it may start a new colony from it —
your old queen, sixty per cent of your bees, at a site they choose.

**Realism.** Catching a swarm is how most beekeepers get their second colony.

**Cost.** Medium. The share file format extends naturally; the new-colony path
exists.

**Recommendation: Consider.** Charming, and it pairs with 3. Lower priority
than the events.

*Built.* `SwarmShare` as a `.swarm` file; the recipient founds a colony from it at a site they choose.

### 19. Asking for a flower

**Pitch.** A colony short of forage can send a request — a small file that,
opened by a friend, shows what is needed and offers to share.

**Cost.** Medium, and the value is unproven.

**Recommendation: Deny for now.** Sharing already works; asking adds a step
without a clear win.

*Built, overruling the recommendation.* A `FlowerShare` of kind `request` carrying the families the colony is short of; the recipient sees which of their flowers would help.

---

## G. Ambience

### 20. The hum

**Pitch.** A soft hive sound when the app is open, changing with the colony:
foraging, clustered, the sharp note of an alarm. Off by default on the watch.

**Cost.** Small. A few loops and a state mapping.

**Recommendation: Consider.** It is the cheapest way to make the colony feel
alive, and the easiest to overdo.

*Built.* Synthesised rather than recorded — two detuned oscillators and a slow tremolo — changing with foraging, clustering and alarm. Off by default.

### 21. Haptics on the watch

**Pitch.** A distinct tap for a decision arriving, a different one for good
news. The watch's whole job is to be glanced at; haptics are how it earns the
glance.

**Cost.** Small.

**Recommendation: Approve with 6.**

*Built.* A distinct tap for a critical alert arriving, another for any alert.

---

## Not proposed, and why

These were considered and cut against the brief.

- **Energy, timers, speed-ups, anything purchasable.** All of them exist to
  make people play longer or pay to play less. You asked for neither.
- **Streaks with punishment.** A colony already suffers if the player stops
  photographing; that is enough, and it is honest. A streak counter on top
  would be manipulation.
- **A real-time defence minigame.** Tapping wasps. It is the tower-defence
  game from 2023 that stalled the project, and it demands attention by the
  minute.
- **A "watch the bees" live mode.** Anything that rewards keeping the app
  open works against the brief. The live refresh every twenty seconds is for
  someone who opened the app to look, and that is all it should be.
- **Real weather from WeatherKit.** Tempting for realism, but it breaks the
  deterministic catch-up the whole design rests on — the watch could no
  longer replay the same colony the phone did. Worth revisiting only as a
  once-fetched, stored input, which is a different and larger design.

---

## If you approve the recommended set

The coherent first batch, in the order I would build it:

1. **6** actionable notifications and **21** watch haptics — the plumbing.
2. **1** threat events with **2** absconding — the mechanic you asked for.
3. **3** the swarm decision and following the swarm.
4. **8** the daily digest, so the above stays occasional.
5. **10** queen lineage and **13** the botany collection — the long game.
6. **7** Live Activities, **9** the Home Screen widget, **16** show the reason,
   **17** in bloom near you, **4** winter intruders, **14** winter as the
   reading season.

Everything in 1 through 4 can be engine-first and measured with `beesim`
before any of the interface exists. The interface still needs the Mac.
