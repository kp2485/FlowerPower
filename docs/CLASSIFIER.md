# Identifying the flower

The app runs two stages. Vision's built-in classifier asks "is this a plant at
all?", which needs no model and ships with the OS. Something then asks "which
one?", and there are three ways to answer that. Identification is a **bonus,
never a gate**: a flower the app cannot name still feeds the colony, at a yield
scaled by confidence. That is what makes a merely-decent identifier worth
having.

## The three routes, and which is in use

**1. Vision feature prints, nearest neighbour. Built, and working today.**

`VNGenerateImageFeaturePrintRequest` returns a vector describing what is in an
image, from a network Apple already trained. Photographs of the same flower
land near each other in that space. So a set of labelled reference photographs
plus a nearest-neighbour lookup is a working classifier with no training step,
no dataset pipeline and no model to ship — and it runs on every device the app
supports, back to iOS 13.

The arithmetic is `FeaturePrintLibrary` in the package, and it is tested. The
Vision call is `FeaturePrints` in the app.

It is less accurate than a trained model. Two things make that affordable:
identification is a bonus, and the library **grows as the game is played**. A
player who names a flower themselves has just labelled a photograph; a flower
somebody shares arrives with a label and a picture attached. Both are recorded
as references, tagged with where the label came from.

No reference photographs are bundled yet, which is the honest state of things.
Until some are, the library starts empty and fills from what the player names —
so identification works from the first flower they name by hand rather than not
at all. Curating a starter set means photographing the thirty catalogue species
or embedding research-grade observations; that is the cheapest real win
available here.

**2. A trained Core ML model. The upgrade.**

Most accurate, and the most work. The rest of this document is the brief.
`FlowerClassifier` prefers a bundled model over the reference library
automatically, so adding one needs no other change.

**3. Apple Intelligence, with image input. Not usable as the base.**

The Foundation Models framework gained image attachments in **iOS 27**,
announced at WWDC26. You can hand `LanguageModelSession` a `UIImage` alongside
text and ask what is in it, entirely on device.

It is genuinely attractive as an *enhancement*: guided generation can constrain
the answer to the thirty catalogue species, which is exactly the shape of this
problem. But it cannot be the only path. It requires iOS 27 against a
deployment target of iOS 17, and it runs only on Apple Intelligence hardware,
so most devices would get nothing. Its accuracy on fine-grained British
wildflower species is also unmeasured — a general model asked to distinguish
*Calluna vulgaris* from *Erica carnea* is a different proposition from one
asked to spot a dog.

Worth revisiting as a fourth stage on capable devices, behind an availability
check, once routes 1 and 2 exist.

**Visual Look Up is still not available.** The plant identification in Photos
has no public API for third-party apps, checked again in September 2026. That
is why any of this is necessary.

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
