#!/usr/bin/env python3
"""Write every inline shell snippet of the given fluxion profiles to OUT_DIR, one file each, for bash -n/shellcheck.

Covers shell-scripts `content`, commands `run`/string items, `unless`, `probeCommand` and assert `command`.
Usage: extract_inline_scripts.py OUT_DIR PROFILE...   (prints the written file names)
"""

import os
import re
import sys

import yaml


def snippets(doc):
    for phase in doc.get("spec", {}).get("phases", []) or []:
        for step in phase.get("steps", []) or []:
            spec = step.get("spec") or {}
            name = step.get("name", "step")
            shell = spec.get("shell", "bash")
            if isinstance(spec.get("probeCommand"), str):
                yield f"{name}.probe", "bash", spec["probeCommand"]
            if step.get("kind") == "assert" and isinstance(spec.get("command"), str):
                yield f"{name}.assert", "bash", spec["command"]
            for i, item in enumerate(spec.get("scripts") or []):
                if isinstance(item, dict):
                    iname = item.get("name", str(i))
                    if isinstance(item.get("content"), str):
                        yield f"{name}.{iname}", item.get("shell", shell), item["content"]
                    if isinstance(item.get("unless"), str):
                        yield f"{name}.{iname}.unless", "bash", item["unless"]
            for i, item in enumerate(spec.get("commands") or []):
                if isinstance(item, str):
                    yield f"{name}.cmd{i}", "bash", item
                elif isinstance(item, dict):
                    iname = item.get("name", str(i))
                    run = item.get("run") or item.get("shellCommand")
                    if isinstance(run, str):
                        yield f"{name}.{iname}", "bash", run
                    if isinstance(item.get("unless"), str):
                        yield f"{name}.{iname}.unless", "bash", item["unless"]


def main(out_dir, profiles):
    os.makedirs(out_dir, exist_ok=True)
    for path in profiles:
        with open(path) as fh:
            doc = yaml.safe_load(fh)
        base = os.path.splitext(os.path.basename(path))[0]
        for label, shell, text in snippets(doc):
            safe = re.sub(r"[^A-Za-z0-9._-]", "_", f"{base}.{label}")
            dest = os.path.join(out_dir, safe + ".sh")
            with open(dest, "w") as fh:
                fh.write(f"# shellcheck shell={'sh' if shell == 'sh' else 'bash'}\n")
                fh.write(f"# from {path}: {label}\n")
                fh.write(text if text.endswith("\n") else text + "\n")
            print(dest)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1], sys.argv[2:])
