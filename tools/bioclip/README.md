# The flower identifier

`build.py` turns [BioCLIP 2](https://huggingface.co/imageomics/bioclip-2)
into the three files the app identifies flowers with. They land in
`FlowerPower/Models/` and are not checked in; see the docstring at the top of
the script for what each one is and why.

    uv venv --python 3.12 .venv
    uv pip install --python .venv/bin/python torch torchvision open_clip_torch coremltools numpy pandas pyarrow safetensors huggingface_hub pillow
    .venv/bin/python build.py all

The first run downloads about 4.5 GB (the model, and the official text
embeddings for every taxon it knows) into the Hugging Face cache. To try it
on photographs before building the app:

    .venv/bin/python build.py check --coreml ~/Pictures/tulip.jpg

BioCLIP 2 is MIT licensed. The taxon list is derived from TreeOfLife-200M
(CC0) and TreeOfLife-10M metadata.
