#!/usr/bin/env python3
"""Print lists declared in a fluxion profile, so assertions check exactly what the profile installs.

Usage: profile_query.py PROFILE QUERY
  apt-packages   one package per line (every apt-packages step)
  flatpaks       one app id per line (every flatpak-packages step)
  snaps          one snap name per line (tool-packages with backend snap, and `snap install NAME` commands)
  git-repos      "dest<TAB>ref<TAB>url" per git-repo entry (dest with ~ expanded)
  crates         one crate per line (tool-packages with backend cargo-binstall)
  sdkman         one candidate per line (sdkman-packages)
  pipx           one package per line (tool-packages with backend pipx)
  probeless      item keys that run on every --re-probe by design: `assert` steps (a check, not a change)
                 and the pre-install `actions` of package steps without a step-level probeCommand
                 (e.g. apt `update`, shown as action[N]), and tool-packages / sdkman-packages items
                 without a step-level probeCommand (fluxion has no live probe for those kinds)
  asserts        names of the `assert` steps: fluxion re-checks them on every run (never skipped from state)
"""

import os
import re
import sys

import yaml


def steps(doc):
    for phase in doc.get("spec", {}).get("phases", []) or []:
        for step in phase.get("steps", []) or []:
            yield step, step.get("spec") or {}


def names(items, key="name"):
    for item in items or []:
        if isinstance(item, dict):
            item = item.get(key) or item.get("name") or item.get("candidate")
        if item:
            # tool-packages accept name@version
            yield str(item).rsplit("@", 1)[0] if not str(item).startswith("@") else str(item)


def main(path, query):
    with open(path) as fh:
        doc = yaml.safe_load(fh)
    home = os.path.expanduser("~")
    out = []
    for step, spec in steps(doc):
        kind = step.get("kind")
        if query == "apt-packages" and kind == "apt-packages":
            out += names(spec.get("packages"))
        elif query == "flatpaks" and kind == "flatpak-packages":
            out += names(spec.get("apps") or spec.get("appIds"))
        elif query == "snaps":
            if kind == "tool-packages" and spec.get("backend") == "snap":
                out += names(spec.get("packages"))
            if kind == "commands":
                for c in spec.get("commands") or []:
                    run = c.get("run") if isinstance(c, dict) else c
                    m = re.search(r"\bsnap install ([A-Za-z0-9-]+)", run or "") if isinstance(run, str) else None
                    if m:
                        out.append(m.group(1))
        elif query == "git-repos" and kind == "git-repo":
            for r in spec.get("repos") or []:
                dest = r.get("dest") or r.get("destination") or ""
                if dest.startswith("~/"):
                    dest = home + dest[1:]
                dest = dest.replace("${HOME}", home)
                out.append(f"{dest}\t{r.get('ref', '')}\t{r.get('url', '')}")
        elif query == "crates" and kind == "tool-packages" and spec.get("backend") == "cargo-binstall":
            out += names(spec.get("packages"))
        elif query == "pipx" and kind == "tool-packages" and spec.get("backend") == "pipx":
            out += names(spec.get("packages"))
        elif query == "probeless":
            if kind == "assert":
                out.append(step.get("name", ""))
            # A step-level probeCommand gates the actions, so they must be skipped on a re-probe too.
            if not spec.get("probeCommand"):
                for i, _ in enumerate(spec.get("actions") or []):
                    out.append(f"action[{i}]")
                # fluxion 0.3.1 registers no live probe for tool-packages or sdkman-packages items
                # (`fluxion status` calls them "unknown"), so --re-probe runs them again. The tools
                # themselves skip what is present (cargo-binstall, `sdk install`), so nothing changes.
                if kind == "tool-packages":
                    out += names(spec.get("packages"))
                elif kind == "sdkman-packages":
                    out += names(spec.get("packages"), key="candidate")
        elif query == "asserts" and kind == "assert":
            out.append(step.get("name", ""))
        elif query == "sdkman" and kind == "sdkman-packages":
            out += names(spec.get("packages"), key="candidate")
    seen = set()
    for line in out:
        if line not in seen:
            seen.add(line)
            print(line)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1], sys.argv[2])
