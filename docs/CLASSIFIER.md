# Identifying the flower

The app runs two stages. Vision's built-in classifier asks "is this a plant at
all?", which needs no model and ships with the OS. Something then asks "which
one?", and there are three ways to answer that. Identification is a **bonus,
never a gate**: a flower the app cannot name still feeds the colony, at a yield
scaled by confidence. That is what makes a merely-decent identifier worth
having.

## What identification now means

The question is no longer "which species is this?" with a name or nothing as
the answer. It is "how precisely can this honestly be placed?", and family,
genus and species are all real answers.

That works because floral architecture is largely conserved by family. Knowing
a plant is in Boraginaceae tells the game it is a good nectar plant with a
corolla a honey bee can work, even with no idea whether it is borage or viper's
bugloss. Knowing it is in Plantaginaceae tells the game a honey bee will not
reach the nectar at all. So a family-level placement carries most of the useful
information, and being told the rank beats being handed a confident guess at a
species the plant might not be.

Getting it wrong is worse than saying nothing: a patch placed as the wrong
species is given the wrong corolla depth, the wrong nectar and the wrong bloom
season, and tells the player something plainly false about the world.

## The four routes, best first

**1. BioCLIP 2, on the phone. Built, 2026-09-16.**

An open model (Imageomics, MIT licence) trained on two hundred million
photographs of living things to put a picture and the text of its taxonomic
name in the same place. Only the image half ships: a Core ML encoder of about
300 MB, 8-bit, that turns a photograph into 768 numbers. The text half was run
once, at build time, over every flowering plant the model knows — 42,690
species, all 14,061 genera and all 469 families — and ships as a 44 MB matrix.
Identifying a flower is one pass through the encoder and one down the matrix.

`tools/bioclip/build.py` builds all three files into `FlowerPower/Models/`,
which is not checked in. A build without them is a working app that names
less. `TaxonEmbeddingIndex` in the package holds the matrix and does the
arithmetic — a softmax at each rank, the species answer summed up into its
genus and family, the finest rank that clears its threshold wins — and is
tested. `BioCLIPClassifier` in the app runs the encoder.

The species list is every flowering plant that iNaturalist or TreeOfLife has
a photograph of, plus any with an English common name; the rest of the
315,000 are reached through their genus and family rows. The thresholds
(`speciesThreshold` 0.7, `genusThreshold` 0.6, `familyThreshold` 0.4, `familyRowWeight` 0.5) were
set from ten Wikimedia photographs and want tuning on a phone against
photographs taken the way players take them.

**Names, and finishing a coarse placement (2026-11-07).** `build.py` gives
common names to species only, about half of them, so a genus or family
placement used to be titled in Latin ("Tulipa sp."), and on a phone that read
as the identifier stopping part of the way. `TaxonEmbeddingIndex.naming`
now names each genus at load from the last word most of its species share
("rose", "clover", "dandelion"), a one-species genus from that species, and
anything else by its Latin genus, which is what a gardener calls a hibiscus
anyway. A family without notes is named for its type genus ("Gesneria
Family"). Non-ASCII species names (Swedish, Korean) are dropped rather than
shown. A genus or family placement also carries `narrower`: the likeliest
members one rank down, offered on the card as "Which one is it?", so a
player who knows the plant finishes the identification with one tap.

On the iOS 27 simulator the encoder must run on the CPU: with `.all` the
request succeeds and returns zeros. An embedding that is not unit length is
now refused and logged as "the model did not run".

**2. Vision's own labels. Built, 2026-09-16.**

The classifier that ships with iOS has thirteen hundred labels, and a couple
of dozen of them are flowers: rose, tulip, lily, orchid, daisy, dahlia,
carnation, daffodil, chrysanthemum, marigold, petunia, begonia, snapdragon,
cornflower, clover, sunflower, dandelion, rosemary, cactus. The app always ran
this request as the "is this a plant?" gate and threw the rest away.
`VisionLabelTaxa` in the package maps each label to the finest rank it
honestly supports — a genus for tulip, a family for daisy, the catalogue entry
for sunflower — and the gate's answer is read a second time.

**3. The on-device language model, through `TaxonomicClassifier`. Built.**

Foundation Models gained image attachments in iOS 27, so the system model can
be handed a photograph. What makes it the right tool rather than merely an
available one is guided generation: `@Generable` constrains the answer to a
schema, so the question is a form with a family, a genus, an epithet and a
confidence, any of which may be left blank. The prompt argues against the
model's instinct to name a species, because that instinct is exactly wrong for
this problem.

Until 2026-09-16 the family was chosen from a closed list of the eighteen the
game models, which is why a tulip, an orchid or a hydrangea came back as "a
flower, but we cannot name it": there was no legal answer. Any family is
allowed now, checked for shape (a Latin name ending in -aceae) rather than
membership.

Answers are refused unless coherent - an epithet with no genus, a family with
no plant, a confidence that is not a number. A genus the catalogue knows
sitting in the wrong family corrects the family rather than discarding the
answer, because the genus is the more specific claim.

Needs Apple Intelligence, so it cannot be the only path. Availability is
reported with a reason, since "your device cannot" and "turn Apple Intelligence
on" want different things said to the player.

**4. Vision feature prints, nearest neighbour. Built.**

`GenerateImageFeaturePrintRequest` returns a vector describing an image, from a
network Apple already trained. Reference photographs plus a nearest-neighbour
lookup is a working classifier with no training step and no model to ship, on
every device. The arithmetic is `FeaturePrintLibrary` in the package and is
tested; the Vision call is `FeaturePrints` in the app.

No references are bundled. The library fills from flowers the player names and
flowers people share, so it improves with use.

**A trained Core ML classifier of the thirty catalogue species is no longer
planned.** BioCLIP 2 covers them and everything else; the brief below is kept
for the record of why Oxford 102 would have been the wrong dataset for it.

**Visual Look Up is still not available.** No public API for third-party apps,
checked again in September 2026.

## What the game does with a plant it does not model

`Taxon.family` is a `BotanicalFamily` — any family by name — rather than the
`PlantFamily` enum, which is the eighteen the collection counts. A placement in
Orchidaceae or Paeoniaceae is a real placement: it is shown on the capture
card, listed on the collection screen under "Beyond the catalogue", and the
colony is given the family's typical forage. `WorldFamilies` holds notes and
traits for some fifty families a player is likely to meet (peonies are all
pollen; orchids are no use to a honey bee; eucalyptus is a flow), and a family
in neither table gets middling traits and a plain sentence. Saves are
unchanged: the family was always stored as its lower-cased Latin name.

"Name It Yourself" offers the catalogue first and then, when the taxon matrix
is on the phone, every flowering plant there is.

---

## 1. Oxford 102 is the wrong dataset

`SETUP.md` used to say the Oxford 102 Flowers dataset was "the usual starting
point". For flower classification in general, it is. For *this* catalogue it is
close to useless, and that is worth knowing before spending an afternoon on it.

`FlowerCatalogue` is thirty species of British and northern European **bee
forage**: white clover, goat willow, hawthorn, oilseed rape, bramble, lime,
ling heather, ivy, Himalayan balsam, viper's bugloss, meadowsweet. These are
the plants a colony actually lives on, which is why they are the ones in the
game.

Oxford 102 is a set of **ornamental and glasshouse flowers** photographed in the
UK: bird of paradise, frangipani, anthurium, canna lily, cattleya, king protea,
hippeastrum. Beautiful, and almost entirely not what a bee eats.

Overlapping usefully: roughly **six of thirty**.

| Catalogue species | Oxford 102 class |
|---|---|
| `sunflower` | sunflower |
| `foxglove` | foxglove |
| `poppy` | corn poppy |
| `dandelion` | common dandelion |
| `echinacea` | purple coneflower |
| `crocus` | spring crocus |
| `thistle` | spear thistle / globe thistle (a different species of the same genus) |

Everything else — the clover, the willow, the blossom, both heathers, the ivy,
the rape, the lime, the bramble — has no class in it at all. A model trained on
Oxford 102 would be confidently wrong about most of what this game asks a player
to photograph, and confidently wrong is worse than unidentified, because
unidentified is honest and still pays out.

### What to use instead

Sources that actually cover wild European flora, in rough order of how well
they fit:

- **iNaturalist** research-grade observations, filtered to the thirty species by
  taxon and to Europe by place. Photographs taken on phones, of plants growing
  where they grow, by people standing where the player will be standing. This is
  the closest match to the app's real input distribution, which usually matters
  more than raw dataset size.
- **PlantNet-300K**, which is built from Pl@ntNet submissions and is
  specifically a hard, long-tailed, real-world plant dataset.
- **GBIF** occurrence media, as a way of topping up whichever species come out
  thin.

Whatever the source, hold out a test set of photographs **taken the way players
will take them**: a phone, one hand, imperfect light, the flower filling maybe a
third of the frame. Accuracy on curated dataset images will flatter a model that
then disappoints in a field.

---

## 2. Labels do not need to match

They will not match, and they do not have to.
`FlowerPowerCore/Content/ClassifierLabels.swift` holds a table of botanical
synonyms per species, and `FlowerCatalogue.match(label:)` resolves a model's
class name through it. So a model may emit `Papaver rhoeas`, `corn poppy`,
`common poppy` or `field poppy` and all four land on `poppy`.

Two things it deliberately will not do:

- **Match on a bare word inside a longer label.** The catalogue contains `Ivy`,
  and an earlier substring fallback meant every label containing those three
  letters — "poison ivy", "Boston ivy", "ivy-leaved toadflax" — resolved to
  *Hedera helix*, which is a keystone autumn nectar source and none of those
  things. Matching is on whole words, and a phrase needs at least two of them.
- **Match a near relative.** Canterbury bells is not a bluebell; blackberry lily
  is not a bramble. Sharing a common name is not sharing a species.

If a new dataset uses a name the table does not know, add it to the table rather
than loosening the matcher. `ClassifierLabelTests` covers all of this, including
a round trip asserting every alias resolves back to the species that declared
it, so a new entry is checked the moment it is added.

---

## 3. Training

1. Assemble the set, one folder per species, named with the catalogue
   identifier (`white_clover`, `vipers_bugloss`, …). Using our identifiers
   directly skips the alias table entirely.
2. **Create ML ▸ Image Classification.** Turn on the standard augmentations —
   crop, rotate, blur, expose — since every one of them is something a player's
   photo will actually be.
3. Export as `FlowerClassifier.mlmodel` and drop it into the app target.
   `FlowerClassifier.bundled()` finds it by name with no other change.
4. Check `FlowerClassifier.speciesThreshold`, currently 0.25. Below it the app
   returns "a flower, but we cannot name it", which is the safe answer.

### Species that will be hard

Worth expecting rather than being surprised by:

- **The two heathers.** *Calluna vulgaris* and *Erica carnea* look similar and
  bloom in opposite halves of the year, so confusing them is not cosmetic — the
  game treats one as an autumn keystone and the other as a winter one.
- **The blossom.** Apple, cherry and hawthorn at a distance are white blossom on
  a branch. Close up they are separable; a photograph from across a garden is
  not.
- **The umbellifers and daisies.** Meadowsweet against cow parsley, Michaelmas
  daisy against every other aster.

Where a model cannot separate two species, the honest option is to leave the
harder one out and let it come back unidentified. A patch identified as the
wrong species gets the wrong nectar richness and the wrong bloom season, and a
player who is told their October ivy is April willow has been told something
plainly false about the world.

---

## 4. Meanwhile

The player can name the flower themselves — `SpeciesPickerView`, reachable from
the capture result. That was added because with no model the classifier cannot
name *anything*, so the entire catalogue was invisible and every patch yielded
60% for ever. It now does double duty: every name a player supplies becomes a
reference photograph for the feature-print library, so the classifier they are
compensating for gets better because they compensated for it.

A self-chosen name is recorded at 0.8 confidence rather than 1.0. Confidence
scales yield, and perfect confidence would make naming a flower by hand strictly
better than photographing one well, which is the wrong incentive in a game about
going outside and taking photographs.

The same screen is how a player corrects a wrong answer once there *is* a model.
The classifier already computed runner-up guesses and showed them as a sentence;
they are now buttons.

---

## 5. Visual Look Up is not available

The plant identification in Photos is not exposed to third-party apps through
any public API. It cannot be used here, and this is why a model is needed at
all.
