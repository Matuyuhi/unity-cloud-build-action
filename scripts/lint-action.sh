#!/usr/bin/env bash
# Validate action.yml: it must parse as YAML, declare consistent step IDs for the
# outputs it exposes, and every embedded `run:` script must pass shellcheck.
#
# Usage: ./scripts/lint-action.sh [path/to/action.yml]
set -euo pipefail

ACTION_FILE="${1:-$(dirname "$0")/../action.yml}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "==> Validating $ACTION_FILE"

python3 - "$ACTION_FILE" "$WORKDIR" <<'PY'
import sys, os, re

try:
    import yaml
except ModuleNotFoundError:
    sys.stderr.write(
        "error: PyYAML is required to lint action.yml but is not installed.\n"
        "  Debian/Ubuntu: sudo apt-get install -y python3-yaml\n"
        "  macOS/other:   python3 -m pip install pyyaml\n"
    )
    sys.exit(1)

action_file, workdir = sys.argv[1], sys.argv[2]

with open(action_file) as fh:
    action = yaml.safe_load(fh)

errors = []

for key in ("name", "description", "runs"):
    if key not in action:
        errors.append(f"missing top-level key: {key}")

steps = action.get("runs", {}).get("steps", [])
step_ids = {s["id"] for s in steps if "id" in s}

# Every ${{ steps.X.outputs.Y }} referenced by an output must point at a real step.
for name, spec in (action.get("outputs") or {}).items():
    for ref in re.findall(r"steps\.([A-Za-z0-9_-]+)\.outputs", spec.get("value", "")):
        if ref not in step_ids:
            errors.append(f"output '{name}' references unknown step id '{ref}'")

declared = set(action.get("inputs") or {})

for i, step in enumerate(steps):
    run = step.get("run")
    if run is None:
        continue
    if step.get("shell") != "bash":
        errors.append(f"step {i} ({step.get('name')!r}) has run: but shell is not bash")
    # Interpolating inputs straight into a run: block is a script-injection vector;
    # they must be passed through env: instead.
    for expr in re.findall(r"\$\{\{\s*(inputs\.[A-Za-z0-9_-]+)\s*\}\}", run):
        errors.append(
            f"step {i} ({step.get('name')!r}) interpolates {expr} into the script; pass it via env: instead"
        )
    with open(os.path.join(workdir, f"step{i}.sh"), "w") as fh:
        fh.write("#!/usr/bin/env bash\n" + run)

# Inputs referenced in env: blocks should actually exist.
for i, step in enumerate(steps):
    for value in (step.get("env") or {}).values():
        for ref in re.findall(r"inputs\.([A-Za-z0-9_-]+)", str(value)):
            if ref not in declared:
                errors.append(f"step {i} references undeclared input '{ref}'")

if errors:
    print("action.yml validation failed:")
    for e in errors:
        print(f"  - {e}")
    sys.exit(1)

print(f"    inputs:  {', '.join(sorted(declared))}")
print(f"    outputs: {', '.join(sorted(action.get('outputs') or {}))}")
print(f"    extracted {len(os.listdir(workdir))} shell script(s)")
PY

echo "==> bash -n"
for script in "$WORKDIR"/*.sh; do
  bash -n "$script"
done
echo "    syntax OK"

echo "==> shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck --shell=bash --severity=style "$WORKDIR"/*.sh
  echo "    shellcheck clean"
else
  echo "    shellcheck not installed; skipping"
fi

echo "==> OK"
