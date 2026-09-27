#!/usr/bin/env python3
"""Generate the test profiles in tests/generated/ from the production profiles in profiles/.

A test profile is the production profile, 1:1, except for what would stop or pause an unattended run:

  * phase restartPolicy prompt-logout / requires-new-shell  -> removed (the phase runs, the run goes on)
  * steps of kind interrupt, manual, shell-reload          -> removed
  * `confirm:` on commands / shell-scripts items            -> removed (nothing waits for --yes)
  * phases left without steps                                -> removed, and dropped from every dependsOn
  * relative `config:` / `configPath:` / `script:` paths   -> made absolute (the file moves directories)

Everything else (names, vars, probes, scripts, ordering) is copied unchanged, so the tests exercise exactly what
production runs. Usage: gen_test_profiles.py REPO_DIR OUT_DIR [--check] [--quiet]
"""

import difflib
import io
import os
import sys

import yaml

HALTING_KINDS = {"interrupt", "manual", "shell-reload"}
HALTING_RESTART = {"prompt-logout", "requires-new-shell"}
PATH_KEYS = {"config", "configPath", "script"}


class StrictLoader(yaml.SafeLoader):
    """SafeLoader that refuses YAML 1.1 scalars whose meaning a round trip could change.

    PyYAML reads `0755` as the int 493 and `yes`/`on` as booleans, while fluxion's parser may read them
    differently; failing loudly beats generating a subtly different profile.
    """


def _int(loader, node):
    text = loader.construct_scalar(node)
    digits = text.lstrip("+-")
    if len(digits) > 1 and digits.startswith("0"):
        raise yaml.constructor.ConstructorError(
            None, None, f"ambiguous octal-looking number {text!r}: quote it in the profile", node.start_mark)
    return yaml.SafeLoader.construct_yaml_int(loader, node)


def _bool(loader, node):
    text = loader.construct_scalar(node)
    if text.lower() not in ("true", "false"):
        raise yaml.constructor.ConstructorError(
            None, None, f"ambiguous YAML 1.1 boolean {text!r}: use true/false or quote it", node.start_mark)
    return yaml.SafeLoader.construct_yaml_bool(loader, node)


StrictLoader.add_constructor("tag:yaml.org,2002:int", _int)
StrictLoader.add_constructor("tag:yaml.org,2002:bool", _bool)


class Dumper(yaml.SafeDumper):
    """Block style everywhere, multi-line strings as literal blocks, no key sorting, no aliases."""

    def ignore_aliases(self, data):
        return True


def _str(dumper, value):
    if "\n" in value:
        return dumper.represent_scalar("tag:yaml.org,2002:str", value, style="|")
    return dumper.represent_scalar("tag:yaml.org,2002:str", value)


Dumper.add_representer(str, _str)


def transform(doc, src_dir, notes):
    phases = doc.get("spec", {}).get("phases", [])
    removed_phases = set()
    kept = []
    for phase in phases:
        rp = phase.get("restartPolicy")
        if isinstance(rp, dict) and rp.get("type") in HALTING_RESTART:
            notes.append(f"phase {phase['name']}: removed restartPolicy {rp['type']}")
            del phase["restartPolicy"]
        steps = []
        for step in phase.get("steps") or []:
            if step.get("kind") in HALTING_KINDS:
                notes.append(f"phase {phase['name']}: removed {step['kind']} step {step['name']}")
                continue
            spec = step.get("spec")
            if isinstance(spec, dict):
                for key in PATH_KEYS & set(spec):
                    spec[key] = absolute(spec[key], src_dir, notes, step["name"])
                items = spec.get("commands") or spec.get("scripts") or []
                if isinstance(items, list):
                    for i, item in enumerate(items):
                        if isinstance(item, dict):
                            if "confirm" in item:
                                notes.append(f"step {step['name']}: removed confirm from item {item.get('name', i)}")
                                del item["confirm"]
                            if "script" in item:
                                item["script"] = absolute(item["script"], src_dir, notes, step["name"])
                        elif isinstance(item, str) and spec.get("scripts") is items:
                            items[i] = absolute(item, src_dir, notes, step["name"])  # bare local script path
                if "confirm" in spec:
                    notes.append(f"step {step['name']}: removed confirm")
                    del spec["confirm"]
            steps.append(step)
        if not steps:
            notes.append(f"phase {phase['name']}: removed (no steps left)")
            removed_phases.add(phase["name"])
            continue
        phase["steps"] = steps
        kept.append(phase)
    for phase in kept:
        deps = phase.get("dependsOn")
        if deps:
            left = [d for d in deps if d not in removed_phases]
            if left != deps:
                notes.append(f"phase {phase['name']}: dependsOn no longer lists {sorted(set(deps) - set(left))}")
                if left:
                    phase["dependsOn"] = left
                else:
                    del phase["dependsOn"]
    doc["spec"]["phases"] = kept
    labels = doc.setdefault("metadata", {}).setdefault("labels", {})
    labels["generated-by"] = "tests-gen-test-profiles"
    return doc


def absolute(value, src_dir, notes, step):
    if not isinstance(value, str) or value.startswith(("/", "~", "$", "http://", "https://")):
        return value
    new = os.path.normpath(os.path.join(src_dir, value))
    notes.append(f"step {step}: path {value} -> {new}")
    return new


def render(src, repo):
    with open(src) as fh:
        doc = yaml.load(fh, Loader=StrictLoader)
    notes = []
    doc = transform(doc, os.path.dirname(src), notes)
    rel = os.path.relpath(src, repo)
    out = io.StringIO()
    out.write(f"# GENERATED from {rel} by tests/gen-test-profiles.sh. Do not edit; edit {rel} and regenerate.\n")
    out.write("# Test variant: identical to production except for these changes (nothing may halt the run):\n")
    for n in notes or ["(none: the production profile has no halting steps)"]:
        out.write(f"#   - {n}\n")
    yaml.dump(doc, out, Dumper=Dumper, sort_keys=False, default_flow_style=False, width=4096, allow_unicode=True)
    # Round-trip sanity check: the output parses back to exactly the transformed document.
    if yaml.load(out.getvalue(), Loader=StrictLoader) != doc:
        raise SystemExit(f"round trip changed {rel}")
    return out.getvalue(), notes


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    repo, outdir = os.path.abspath(argv[1]), os.path.abspath(argv[2])
    check = "--check" in argv
    quiet = "--quiet" in argv
    prod = os.path.join(repo, "profiles")
    sources = []
    for root, _dirs, files in os.walk(prod):
        sources += [os.path.join(root, f) for f in files if f.endswith(".yaml")]
    sources.sort()
    drift = 0
    manifest = []
    wanted = set()
    for src in sources:
        rel = os.path.relpath(src, prod)
        dest = os.path.join(outdir, rel)
        wanted.add(dest)
        text, notes = render(src, repo)
        manifest.append((rel, len(notes)))
        old = open(dest).read() if os.path.exists(dest) else None
        if check:
            if old != text:
                drift += 1
                sys.stdout.writelines(difflib.unified_diff(
                    (old or "").splitlines(True), text.splitlines(True), f"a/{rel}", f"b/{rel}"))
            continue
        if old != text:
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest + ".tmp", "w") as fh:
                fh.write(text)
            os.replace(dest + ".tmp", dest)
        if not quiet:
            print(f"{'changed' if old != text else 'same   '}  {os.path.relpath(dest, repo)}  ({len(notes)} change(s))")
    # Stale generated files whose production profile is gone.
    if os.path.isdir(outdir):
        for root, _dirs, files in os.walk(outdir):
            for f in files:
                path = os.path.join(root, f)
                if f.endswith(".yaml") and path not in wanted:
                    if check:
                        drift += 1
                        print(f"stale: {os.path.relpath(path, repo)}")
                    else:
                        os.remove(path)
                        if not quiet:
                            print(f"removed  {os.path.relpath(path, repo)} (no production profile)")
    if check:
        if drift:
            print(f"{drift} generated profile(s) out of date: run tests/gen-test-profiles.sh", file=sys.stderr)
            return 1
        if not quiet:
            print(f"all {len(sources)} generated profiles are up to date")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
