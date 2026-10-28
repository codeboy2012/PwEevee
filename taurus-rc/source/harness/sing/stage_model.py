#!/usr/bin/env python3
"""Stage the pinned Vitrine ANE model as a local fixture for model_test.py; uploads nothing."""
import argparse
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import sys

here = Path(__file__).resolve().parent
code = here.parent.parent / "tweak/Sources/Shared/Sing/SGSingModel.m"

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("model", type=Path, help="the compiled separator-ane.mlmodelc from Vitrine's model mirror")
parser.add_argument("output", type=Path, help="a new local repository fixture folder")
args = parser.parse_args()
source, output = args.model.resolve(), args.output.resolve()
if source.suffix != ".mlmodelc" or not source.is_dir():
    parser.error("need a compiled .mlmodelc")
if output.exists():
    parser.error(f"{output} already exists")

files = []
for path in source.rglob("*"):
    if path.is_symlink():
        parser.error(f"{path} is a link; the model's files must be regular files")
    if path.is_file():
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        files.append((path.relative_to(source).as_posix(), path.stat().st_size, digest))

pinned = {(name, int(size), digest) for name, size, digest in re.findall(
    r'\{"([^"]+)", (\d+), "([0-9a-f]{64})"\}', code.read_text())}
if set(files) != pinned:
    parser.error("this bundle does not match the Vitrine model manifest pinned by the app")

output.mkdir(parents=True)
try:
    for name, _, _ in files:
        target = output / "separator-ane.mlmodelc" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if sys.platform == "darwin":
            subprocess.run(["cp", "-c", str(source / name), str(target)], check=True)
        else:
            shutil.copyfile(source / name, target)
except BaseException:
    shutil.rmtree(output)
    raise

print(f"Staged the verified Vitrine ANE model as a local fixture in {output}")
print(f"Model: {sum(size for _, size, _ in files)} bytes; no model files were uploaded.")
