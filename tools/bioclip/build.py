#!/usr/bin/env python3
"""
Builds the on-device flower identifier from BioCLIP 2.

BioCLIP 2 (Imageomics, MIT licence) is a CLIP-style model trained on
TreeOfLife-200M: an image encoder and a text encoder that map into the same
space, so that a photograph of a plant lands near the text of its taxonomic
name. That property is what makes it usable as a classifier with no training
step: embed the photograph, compare it with the embeddings of every name we
care about, and the nearest names are the answer.

Only the image encoder goes on the phone. The text side is done here, once,
and shipped as a matrix of vectors — one per taxon — that the app compares a
photograph against. The text vectors are the official ones published with the
model (TreeOfLife-200M `embeddings/txt_emb_bioclip-2.npy`), which were built
with the same 80-template ensemble the authors evaluate with; reproducing them
locally would give a slightly different, slightly worse matrix.

Three outputs, all into `FlowerPower/Models/`:

    BioCLIP2.mlpackage   the image encoder, Core ML, 8-bit weights
    BioCLIPTaxa.bin      the taxon matrix, int8 rows with a float scale each
    BioCLIPTaxa.json     one entry per row: rank, family, genus, epithet, common name

Run `python build.py all`, or the steps one at a time: `vocabulary`,
`embeddings`, `convert`, `check`. Everything downloaded is cached under
`~/.cache/huggingface`, so a second run does no network work.

The outputs are not checked in: they are large and are built from this file.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
MODELS = REPO / "FlowerPower" / "Models"
WORK = HERE / "work"

MODEL_ID = "imageomics/bioclip-2"
DATASET_ID = "imageomics/TreeOfLife-200M"
TOL10M_ID = "imageomics/TreeOfLife-10M"

MAGIC = b"BCTX"
FORMAT_VERSION = 1

# Flowering plants only. GBIF's backbone, which the names follow, files every
# angiosperm under one of these two classes.
FLOWERING_CLASSES = {"Magnoliopsida", "Liliopsida"}


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


# MARK: - Downloads


def fetch(repo_id: str, filename: str, repo_type: str = "dataset") -> Path:
    from huggingface_hub import hf_hub_download

    return Path(hf_hub_download(repo_id, filename, repo_type=repo_type))


# MARK: - Vocabulary


def build_vocabulary(cap: int) -> list[dict]:
    """
    Which names the phone will know.

    The full list is 315,000 flowering-plant species, which is more than a
    phone needs to carry and more than the model can tell apart anyway. What
    is kept is every species somebody has actually photographed — the
    iNaturalist 2021 plants and everything in TreeOfLife-10M — plus every
    species that has an English common name, which is a fair proxy for "a
    plant people notice". That comes to about 42,000. Every genus and every
    family is kept regardless, so a photograph of a species the list lacks
    still lands on the right genus.
    """
    names_path = fetch(DATASET_ID, "embeddings/txt_emb_bioclip-2.json")
    inat_path = fetch(TOL10M_ID, "metadata/naming/inat21_name_lookup.json")
    chains_path = fetch(TOL10M_ID, "metadata/species_level_taxonomy_chains.csv")

    log("reading names")
    names = json.loads(names_path.read_text())

    inat = json.loads(inat_path.read_text())
    inat_species = {
        (v[0][5], v[0][6]) for v in inat.values() if v[0][0] == "Plantae"
    }

    import csv

    tol10 = set()
    with chains_path.open(newline="") as handle:
        for row in csv.DictReader(handle):
            if row["Kingdom"] != "Plantae":
                continue
            binomial = row["Species"] or ""
            if " " in binomial:
                genus, epithet = binomial.split(" ", 1)
                tol10.add((genus, epithet))

    species: list[dict] = []
    for row, (chain, common) in enumerate(names):
        if len(chain) != 7 or chain[0] != "Plantae" or chain[2] not in FLOWERING_CLASSES:
            continue
        family, genus, epithet = chain[4], chain[5], chain[6]
        if not family or not genus or not epithet:
            continue
        key = (genus, epithet)
        # Priority, lowest first: photographed on iNaturalist, photographed
        # anywhere, merely named. The cap trims from the bottom.
        priority = 0 if key in inat_species else 1 if key in tol10 else 2 if common else 3
        if priority == 3:
            continue
        species.append({
            "rank": "species",
            "family": family,
            "genus": genus,
            "epithet": epithet,
            "common": common or "",
            "row": row,
            "priority": priority,
        })

    species.sort(key=lambda s: (s["priority"], s["family"], s["genus"], s["epithet"]))
    if cap and len(species) > cap:
        log(f"capping species from {len(species)} to {cap}")
        species = species[:cap]

    # Genera and families come from the whole flowering-plant list, not just
    # the kept species, so a rare genus with no kept species is still a
    # possible answer.
    genera: dict[tuple[str, str], list[int]] = {}
    families: dict[str, list[int]] = {}
    for row, (chain, _) in enumerate(names):
        if len(chain) != 7 or chain[0] != "Plantae" or chain[2] not in FLOWERING_CLASSES:
            continue
        family, genus = chain[4], chain[5]
        if not family or not genus:
            continue
        genera.setdefault((family, genus), []).append(row)
        families.setdefault(family, []).append(row)

    vocabulary = list(species)
    for (family, genus), rows in sorted(genera.items()):
        vocabulary.append({
            "rank": "genus", "family": family, "genus": genus, "epithet": "",
            "common": "", "rows": rows,
        })
    for family, rows in sorted(families.items()):
        vocabulary.append({
            "rank": "family", "family": family, "genus": "", "epithet": "",
            "common": "", "rows": rows,
        })

    log(f"vocabulary: {len(species)} species, {len(genera)} genera, {len(families)} families")
    return vocabulary


# MARK: - Embeddings


def build_embeddings(vocabulary: list[dict], logit_scale: float) -> None:
    """
    Turns the vocabulary into the matrix the phone searches.

    Species rows are copied straight from the official embeddings. A genus or
    family has no official embedding — the published file is species only — so
    it gets the normalised mean of its members' vectors, which is the usual
    way to make a class prototype out of a CLIP space and works well as a
    fallback rank.

    Stored as int8 with one float scale per row: the vectors are unit length
    and the rounding error is far below the model's own noise, and it halves
    the file against fp16. About 44 MB for 57,000 rows.
    """
    import numpy as np

    npy_path = fetch(DATASET_ID, "embeddings/txt_emb_bioclip-2.npy")
    log("opening official embeddings")
    # Published as (dims, taxa): one column per taxon.
    official = np.load(npy_path, mmap_mode="r")
    dims = official.shape[0]

    matrix = np.zeros((len(vocabulary), dims), dtype=np.float32)
    for index, entry in enumerate(vocabulary):
        if entry["rank"] == "species":
            vector = np.asarray(official[:, entry["row"]], dtype=np.float32)
        else:
            rows = entry["rows"]
            # Cap the members averaged for a huge genus; the mean has settled
            # long before then, and reading 20,000 scattered columns of a
            # memory-mapped file is slow.
            if len(rows) > 512:
                rows = rows[:: max(1, len(rows) // 512)][:512]
            vector = np.asarray(official[:, rows], dtype=np.float32).mean(axis=1)
        norm = np.linalg.norm(vector)
        matrix[index] = vector / norm if norm > 0 else vector
        if index % 10000 == 0:
            log(f"  {index}/{len(vocabulary)}")

    scales = np.abs(matrix).max(axis=1) / 127.0
    scales[scales == 0] = 1.0
    quantised = np.round(matrix / scales[:, None]).astype(np.int8)

    MODELS.mkdir(parents=True, exist_ok=True)

    with (MODELS / "BioCLIPTaxa.bin").open("wb") as out:
        out.write(MAGIC)
        out.write(struct.pack("<III", FORMAT_VERSION, len(vocabulary), dims))
        out.write(struct.pack("<f", logit_scale))
        out.write(quantised.tobytes(order="C"))
        out.write(scales.astype(np.float32).tobytes())

    with (MODELS / "BioCLIPTaxa.json").open("w") as out:
        json.dump(
            [
                [e["rank"][0], e["family"], e["genus"], e["epithet"], e["common"]]
                for e in vocabulary
            ],
            out,
            ensure_ascii=False,
            separators=(",", ":"),
        )

    log(f"wrote {MODELS / 'BioCLIPTaxa.bin'} ({(MODELS / 'BioCLIPTaxa.bin').stat().st_size / 1e6:.1f} MB)")


# MARK: - The image encoder


def load_model():
    import open_clip

    log("loading BioCLIP 2")
    model, _, preprocess = open_clip.create_model_and_transforms(f"hf-hub:{MODEL_ID}")
    model.eval()
    return model, preprocess


def logit_scale_of(model) -> float:
    import torch

    with torch.no_grad():
        return float(model.logit_scale.exp().item())


def convert(model) -> None:
    """
    The image tower, as a Core ML program.

    Normalisation is folded into the model so the app can hand Vision a
    plain image: the input is RGB in 0...255 and the output is a unit-length
    embedding. Weights are quantised to 8 bits per channel, which takes the
    ViT-L/14 tower from about 600 MB to about 300 MB with no measurable loss on
    this task.
    """
    import coremltools as ct
    import coremltools.optimize.coreml as cto
    import torch
    from torch import nn

    class ImageTower(nn.Module):
        def __init__(self, clip):
            super().__init__()
            self.clip = clip
            mean = torch.tensor([0.48145466, 0.4578275, 0.40821073]).view(1, 3, 1, 1)
            std = torch.tensor([0.26862954, 0.26130258, 0.27577711]).view(1, 3, 1, 1)
            self.register_buffer("mean", mean)
            self.register_buffer("std", std)

        def forward(self, image):
            x = (image / 255.0 - self.mean) / self.std
            features = self.clip.encode_image(x)
            return features / features.norm(dim=-1, keepdim=True)

    tower = ImageTower(model).eval()
    example = torch.rand(1, 3, 224, 224) * 255

    # torch.export rather than torch.jit.trace: the traced graph of this
    # transformer contains a shape cast the converter cannot handle, and the
    # exported one, once decomposed to core ATen ops, converts cleanly.
    log("exporting")
    with torch.no_grad():
        exported = torch.export.export(tower, (example,))
        exported = exported.run_decompositions({})

    log("converting")
    mlmodel = ct.convert(
        exported,
        inputs=[ct.ImageType(
            name="image", shape=(1, 3, 224, 224),
            color_layout=ct.colorlayout.RGB, scale=1.0,
        )],
        outputs=[ct.TensorType(name="embedding")],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS18,
        compute_precision=ct.precision.FLOAT16,
    )

    log("quantising to 8-bit")
    config = cto.OptimizationConfig(
        global_config=cto.OpLinearQuantizerConfig(mode="linear_symmetric", granularity="per_channel")
    )
    mlmodel = cto.linear_quantize_weights(mlmodel, config=config)

    mlmodel.author = "Imageomics Institute (BioCLIP 2), converted for FlowerPower"
    mlmodel.license = "MIT"
    mlmodel.short_description = "BioCLIP 2 image encoder. Maps a photograph to a 768-d embedding in the model's shared image-text space."
    mlmodel.version = "2.0"

    MODELS.mkdir(parents=True, exist_ok=True)
    target = MODELS / "BioCLIP2.mlpackage"
    mlmodel.save(str(target))
    size = sum(p.stat().st_size for p in target.rglob("*") if p.is_file())
    log(f"wrote {target} ({size / 1e6:.1f} MB)")


# MARK: - Checking


def read_index() -> tuple:
    import numpy as np

    raw = (MODELS / "BioCLIPTaxa.bin").read_bytes()
    assert raw[:4] == MAGIC
    version, rows, dims = struct.unpack_from("<III", raw, 4)
    (logit_scale,) = struct.unpack_from("<f", raw, 16)
    offset = 20
    quantised = np.frombuffer(raw, dtype=np.int8, count=rows * dims, offset=offset).reshape(rows, dims)
    offset += rows * dims
    scales = np.frombuffer(raw, dtype=np.float32, count=rows, offset=offset)
    matrix = quantised.astype(np.float32) * scales[:, None]
    names = json.loads((MODELS / "BioCLIPTaxa.json").read_text())
    return matrix, names, logit_scale


def check(images: list[Path], use_coreml: bool) -> None:
    """
    Runs photographs through the identifier the way the phone will.

    With `--coreml` the Core ML package is used for the image side, which is
    the real test; otherwise PyTorch, which is the reference the package
    should agree with.
    """
    import numpy as np
    from PIL import Image

    matrix, names, logit_scale = read_index()
    ranks = np.array([n[0] for n in names])

    if use_coreml:
        import coremltools as ct

        mlmodel = ct.models.MLModel(str(MODELS / "BioCLIP2.mlpackage"))

        def embed(image: Image.Image) -> np.ndarray:
            # Centre crop and resize to 224, as Vision's centerCrop does.
            width, height = image.size
            side = min(width, height)
            left, top = (width - side) // 2, (height - side) // 2
            square = image.crop((left, top, left + side, top + side)).resize((224, 224), Image.BICUBIC)
            out = mlmodel.predict({"image": square})
            return np.asarray(out["embedding"], dtype=np.float32).reshape(-1)
    else:
        import torch

        model, preprocess = load_model()

        def embed(image: Image.Image) -> np.ndarray:
            with torch.no_grad():
                features = model.encode_image(preprocess(image).unsqueeze(0))
                features = features / features.norm(dim=-1, keepdim=True)
            return features[0].numpy()

    # The same rule as `TaxonEmbeddingIndex.place`, so what prints here is
    # what the phone will say. Keep the two in step.
    thresholds = {"s": 0.7, "g": 0.6, "f": 0.4}
    family_row_weight = 0.5

    def label_of(i):
        _, family, genus, epithet, _ = names[i]
        return " ".join(x for x in (genus, epithet) if x) or family

    for path in images:
        image = Image.open(path).convert("RGB")
        vector = embed(image)
        logits = matrix @ vector * logit_scale
        print(f"\n{path.name}")

        probabilities = np.zeros_like(logits)
        for rank in ("s", "g", "f"):
            mask = ranks == rank
            scores = logits[mask]
            p = np.exp(scores - scores.max())
            probabilities[mask] = p / p.sum()

        genus_mass: dict = {}
        family_mass: dict = {}
        for i in np.flatnonzero(ranks == "s"):
            _, family, genus, _, _ = names[i]
            genus_mass[(family, genus)] = genus_mass.get((family, genus), 0) + probabilities[i]
            family_mass[family] = family_mass.get(family, 0) + probabilities[i]

        scored = np.zeros_like(logits)
        for i, (rank, family, genus, _, _) in enumerate(names):
            if rank == "s":
                scored[i] = probabilities[i]
            elif rank == "g":
                scored[i] = max(probabilities[i], genus_mass.get((family, genus), 0))
            else:
                scored[i] = max(probabilities[i] * family_row_weight, family_mass.get(family, 0))

        placed = None
        for rank in ("s", "g", "f"):
            mask = ranks == rank
            indices = np.flatnonzero(mask)
            order = indices[np.argsort(-scored[mask])[:3]]
            for i in order:
                _, family, _, _, common = names[i]
                print(f"  {rank}  {scored[i]:5.1%}  {label_of(i):32} {family:20} {common}")
            if placed is None and scored[order[0]] >= thresholds[rank]:
                placed = order[0]
        if placed is None:
            print("  -> not placed")
        else:
            print(f"  -> {label_of(placed)}  ({names[placed][4] or 'no common name'}, {scored[placed]:.0%})")


# MARK: - Main


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("step", choices=["all", "vocabulary", "embeddings", "convert", "check"])
    parser.add_argument("--cap", type=int, default=0, help="most species to keep (0 = no cap)")
    parser.add_argument("--coreml", action="store_true", help="check: use the Core ML package rather than PyTorch")
    parser.add_argument("images", nargs="*", type=Path, help="check: photographs to identify")
    args = parser.parse_args()

    WORK.mkdir(parents=True, exist_ok=True)
    vocabulary_path = WORK / "vocabulary.json"

    if args.step in ("all", "vocabulary"):
        vocabulary = build_vocabulary(args.cap)
        vocabulary_path.write_text(json.dumps(vocabulary))

    if args.step in ("all", "embeddings", "convert"):
        model, _ = load_model()
        scale = logit_scale_of(model)
        log(f"logit scale {scale:.2f}")

    if args.step in ("all", "embeddings"):
        vocabulary = json.loads(vocabulary_path.read_text())
        build_embeddings(vocabulary, scale)

    if args.step in ("all", "convert"):
        convert(model)

    if args.step == "check":
        if not args.images:
            parser.error("check needs at least one image")
        check(args.images, args.coreml)


if __name__ == "__main__":
    main()
