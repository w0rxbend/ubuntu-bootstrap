#!/usr/bin/env bash
# run-tests.sh - end-to-end tests of the bootstrap: the SAME orchestration (bootstrap.sh) on test profiles.
#
# The test profiles (tests/generated/, made by tests/gen-test-profiles.sh from profiles/) are the production
# profiles minus anything that halts a run (logout checkpoint, manual/interrupt steps). bootstrap.sh --test
# runs them with state names test-NAME, so production state is left alone.
#
# Stages (in this order, per selected module set):
#   validate     regenerate + `fluxion validate --strict` + lint every selected test profile, and dry-run them
#   apply        ./bootstrap.sh --test --only MODULES               (real changes, sudo)
#   idempotency  the same again: every module must exit 0 and nothing may run but its `assert` steps (fluxion
#                re-checks those on every run)
#   assert       tests/assertions/MODULE.sh: the real outcome (binaries + versions, repos, links, gsettings,
#                services, docker run, skills, login shell, groups)
#
#   tests/run-tests.sh                         # all default modules, all stages
#   tests/run-tests.sh --only gnome,vicinae    # a subset (optional modules by name too)
#   tests/run-tests.sh --with-optional         # default + optional modules
#   tests/run-tests.sh --stages validate       # read-only: validate + lint + dry-run
#   tests/run-tests.sh --assert-only           # only the post-condition assertions (read-only)
#   tests/run-tests.sh --strict-idempotency    # second run with --re-probe: live probes only, no state
#   tests/run-tests.sh --container             # non-GUI modules inside a throwaway ubuntu:24.04 container
#   tests/run-tests.sh --list                  # modules, their test profiles, and whether they need the GUI
#
# Options: --log-dir DIR (default tests/logs/<timestamp>, git-ignored), --no-color.
# Environment: FLUXION_BIN (default: the patched dev build ~/Projects/Github/fluxion.cr-zorin-fixes/bin/fluxion
# when it exists, else fluxion on PATH / ~/.local/bin/fluxion), ASSERT_NETWORK=0 (skip network checks).
# Exit status: 0 when every stage of every module passed, 1 otherwise, 2 for bad arguments.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_DIR"

# Modules that need the local GNOME session / systemd / snapd / flatpak (not testable in a plain container).
GUI_MODULES=" desktop-apps gnome vicinae docker session gnome-extensions obs zorin-pro-parity post-checks "
# Modules the container mode runs by default (apt, user-level installers, links).
CONTAINER_MODULES="base,apps,toolchains,binaries,shell,dotfiles,wallpapers"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    B=$'\033[1m' G=$'\033[32m' R=$'\033[31m' Y=$'\033[33m' D=$'\033[2m' N=$'\033[0m'
else
    B='' G='' R='' Y='' D='' N=''
fi
say() { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
die() {
    printf '%serror%s %s\n' "$R" "$N" "$*" >&2
    exit 2
}

# ---- module table (read from bootstrap.sh so there is one list) ----------------------------------------------
module_table() {
    # prints "name<TAB>profiles/...<TAB>default|optional"
    awk '
        /^DEFAULT_PROFILES=\(/ { t = "default"; next }
        /^OPTIONAL_PROFILES=\(/ { t = "optional"; next }
        /^\)/ { t = "" }
        t != "" && /^ *"/ {
            line = $0; sub(/^ *"/, "", line); sub(/"$/, "", line)
            split(line, f, ":"); print f[1] "\t" f[2] "\t" t
        }' bootstrap.sh
}
all_names() { module_table | awk -F'\t' -v k="$1" 'k == "" || $3 == k { print $1 }'; }
module_file() { module_table | awk -F'\t' -v n="$1" '$1 == n { print $2 }'; }
needs_gui() { [[ "$GUI_MODULES" == *" $1 "* ]]; }
generated_path() { printf 'tests/generated/%s' "$(module_file "$1" | sed 's|^profiles/||')"; }

# ---- arguments ------------------------------------------------------------------------------------------------
ONLY=''
WITH_OPTIONAL=0
STAGES='validate,apply,idempotency,assert'
STRICT=0
CONTAINER=0
IN_CONTAINER=0
LOG_DIR=''
while [[ $# -gt 0 ]]; do
    case "$1" in
        --only)
            [[ $# -ge 2 ]] || die "--only needs a list"
            ONLY="$2"
            shift
            ;;
        --only=*) ONLY="${1#--only=}" ;;
        --with-optional) WITH_OPTIONAL=1 ;;
        --stages)
            [[ $# -ge 2 ]] || die "--stages needs a list"
            STAGES="$2"
            shift
            ;;
        --stages=*) STAGES="${1#--stages=}" ;;
        --assert-only) STAGES=assert ;;
        --strict-idempotency) STRICT=1 ;;
        --container) CONTAINER=1 ;;
        --in-container) IN_CONTAINER=1 ;;
        --log-dir)
            [[ $# -ge 2 ]] || die "--log-dir needs a directory"
            LOG_DIR="$2"
            shift
            ;;
        --log-dir=*) LOG_DIR="${1#--log-dir=}" ;;
        --no-color) B='' G='' R='' Y='' D='' N='' ;;
        --list)
            printf '%-18s %-9s %-4s %s\n' module kind gui "generated test profile"
            while IFS=$'\t' read -r n f k; do
                printf '%-18s %-9s %-4s %s\n' "$n" "$k" "$(needs_gui "$n" && echo yes || echo no)" \
                    "tests/generated/${f#profiles/}"
            done < <(module_table)
            exit 0
            ;;
        -h | --help)
            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) die "unknown argument: $1 (see --help)" ;;
    esac
    shift
done

for s in ${STAGES//,/ }; do
    case "$s" in validate | apply | idempotency | assert) ;; *) die "unknown stage '$s'" ;; esac
done
has_stage() { [[ ",$STAGES," == *",$1,"* ]]; }

if [[ $CONTAINER -eq 1 && -z "$ONLY" ]]; then ONLY="$CONTAINER_MODULES"; fi
MODULES=()
if [[ -n "$ONLY" ]]; then
    IFS=',' read -r -a wanted <<<"$ONLY"
    for w in "${wanted[@]}"; do
        w="${w// /}"
        [[ -n "$w" ]] || continue
        [[ -n "$(module_file "$w")" ]] || die "unknown module '$w' (see --list)"
    done
    # table order, like bootstrap.sh
    while read -r n; do
        for w in "${wanted[@]}"; do [[ "${w// /}" == "$n" ]] && MODULES+=("$n"); done
    done < <(all_names "")
else
    mapfile -t MODULES < <(all_names default)
    if [[ $WITH_OPTIONAL -eq 1 ]]; then mapfile -t -O "${#MODULES[@]}" MODULES < <(all_names optional); fi
fi
[[ ${#MODULES[@]} -gt 0 ]] || die "no modules selected"
ONLY_CSV="$(
    IFS=,
    echo "${MODULES[*]}"
)"

# ---- fluxion binary -------------------------------------------------------------------------------------------
if [[ -z "${FLUXION_BIN:-}" ]]; then
    for cand in "$HOME/Projects/Github/fluxion.cr-zorin-fixes/bin/fluxion" "$(command -v fluxion || true)" "$HOME/.local/bin/fluxion"; do
        if [[ -n "$cand" && -x "$cand" ]]; then
            FLUXION_BIN="$cand"
            break
        fi
    done
fi
[[ -n "${FLUXION_BIN:-}" && -x "$FLUXION_BIN" ]] || die "no fluxion found; set FLUXION_BIN"
export FLUXION_BIN

LOG_DIR="${LOG_DIR:-$REPO_DIR/tests/logs/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$LOG_DIR"
LOG_DIR="$(cd "$LOG_DIR" && pwd -P)"

# ---- container mode: re-run this script inside a throwaway ubuntu:24.04 ---------------------------------------
if [[ $CONTAINER -eq 1 ]]; then
    for m in "${MODULES[@]}"; do
        needs_gui "$m" && die "module '$m' needs the GNOME session/systemd; it cannot run in container mode"
    done
    if docker info >/dev/null 2>&1; then
        DOCKER=(docker)
    elif sudo -n docker info >/dev/null 2>&1; then
        DOCKER=(sudo -n docker)
    else
        die "docker is not usable (install it with ./bootstrap.sh --only docker; run sudo -v first)"
    fi
    image="zorin-bootstrap-test:noble"
    say "building $image (tests/container/Dockerfile: ubuntu:24.04 + tests/container/zorin-baseline.txt)"
    "${DOCKER[@]}" build -q -t "$image" \
        --build-arg "USER_NAME=$USER" --build-arg "USER_UID=$(id -u)" --build-arg "USER_GID=$(id -g)" \
        -f tests/container/Dockerfile tests/container >/dev/null
    # A fresh machine gets the repo by `git clone`, so the container does too: only COMMITTED content is tested.
    if [[ -n "$(git -C "$REPO_DIR" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
        printf '%swarn%s uncommitted changes in %s are NOT part of the container test (it clones HEAD %s)\n' \
            "$Y" "$N" "$REPO_DIR" "$(git -C "$REPO_DIR" rev-parse --short HEAD)" >&2
    fi
    cname="zorin-bootstrap-test-$(date +%Y%m%d-%H%M%S)"
    say "running ${MODULES[*]} in container $cname (stages: $STAGES); logs: $LOG_DIR"
    # Same user, uid and home path as on the host, so ${HOME}-based profile paths are valid inside. The host repo
    # is mounted read-only at /src/zorin-bootstrap and cloned to ~/.zorin-bootstrap (the path the profiles
    # hard-code); logs go to /logs = $LOG_DIR. The fluxion binary is mounted read-only (a dynamically linked dev
    # build finds its libraries in the image: they ship with Zorin, see zorin-baseline.txt).
    inner=(--in-container --only "$ONLY_CSV" --stages "$STAGES" --log-dir /logs)
    [[ $STRICT -eq 1 ]] && inner+=(--strict-idempotency)
    set +e
    "${DOCKER[@]}" run --rm --name "$cname" \
        -v "$REPO_DIR:/src/zorin-bootstrap:ro" \
        -v "$LOG_DIR:/logs" \
        -v "$FLUXION_BIN:/usr/local/bin/fluxion:ro" \
        -e FLUXION_BIN=/usr/local/bin/fluxion -e ASSERT_CONTEXT=container -e TEST_CONTEXT=container \
        -e "ASSERT_NETWORK=${ASSERT_NETWORK:-1}" -e NO_COLOR=1 "$image" \
        bash -c 'set -e; git clone -q /src/zorin-bootstrap "$HOME/.zorin-bootstrap"
                 echo "==> cloned $(git -C "$HOME/.zorin-bootstrap" log -1 --format="%h %s") to ~/.zorin-bootstrap"
                 exec "$HOME/.zorin-bootstrap/tests/run-tests.sh" "$@"' _ "${inner[@]}"
    rc=$?
    set -e
    exit $rc
fi
if [[ $IN_CONTAINER -eq 1 ]]; then
    # TEST_CONTEXT=container makes gen-test-profiles.sh (also when bootstrap.sh --test calls it) drop the steps
    # that need systemd/snapd; they are listed in tests/generated/container-skips.tsv and reported below.
    export ASSERT_CONTEXT=container TEST_CONTEXT=container
fi

# ---- run ------------------------------------------------------------------------------------------------------
declare -A RESULT=()
FAILURES=0
mark() {
    # mark MODULE STAGE ok|FAIL|skip [note]
    RESULT["$1/$2"]="$3${4:+ ($4)}"
    [[ "$3" == FAIL ]] && FAILURES=$((FAILURES + 1))
    return 0
}

say "fluxion: $("$FLUXION_BIN" --version 2>/dev/null) ($FLUXION_BIN)"
say "modules: ${MODULES[*]}"
say "stages:  $STAGES$([[ $STRICT -eq 1 ]] && echo ' (strict idempotency: --re-probe)')"
say "logs:    $LOG_DIR"

tests/gen-test-profiles.sh --quiet
tests/gen-test-profiles.sh --check --quiet >/dev/null || die "generated profiles out of date after regeneration"

# Container mode: the steps the container cannot run are dropped from the test profiles. Say so, per module, and
# keep the list with the logs, so a skipped step is never mistaken for a tested one.
CONTAINER_SKIPS=()
if [[ "${TEST_CONTEXT:-}" == container ]]; then
    : >"$LOG_DIR/container-skips.tsv"
    for m in "${MODULES[@]}"; do
        while IFS=$'\t' read -r _ phase step kind reason; do
            printf '%s\t%s\t%s\t%s\t%s\n' "$m" "$phase" "$step" "$kind" "$reason" >>"$LOG_DIR/container-skips.tsv"
            CONTAINER_SKIPS+=("$m: step $step ($kind, phase $phase): $reason")
        done < <(awk -F'\t' -v f="$(module_file "$m")" '$1 == f' tests/generated/container-skips.tsv)
    done
    if [[ ${#CONTAINER_SKIPS[@]} -gt 0 ]]; then
        say "container mode: ${#CONTAINER_SKIPS[@]} step(s) removed from the test profiles (NOT tested here):"
        printf '    %sSKIP%s %s\n' "$Y" "$N" "${CONTAINER_SKIPS[@]}"
    fi
fi

if has_stage validate; then
    say "stage validate"
    for m in "${MODULES[@]}"; do
        f="$(generated_path "$m")"
        if ! "$FLUXION_BIN" validate -c "$f" --strict --no-tui >"$LOG_DIR/validate-$m.log" 2>&1; then
            mark "$m" validate FAIL "fluxion validate --strict"
            continue
        fi
        "$FLUXION_BIN" lint -c "$f" --no-tui >>"$LOG_DIR/validate-$m.log" 2>&1 || true
        # dry-run through the orchestrator; fluxion's rc must be 0 (75 = a checkpoint stopped it, which the
        # test profiles must never contain)
        : >"$LOG_DIR/dryrun-$m.tsv"
        ./bootstrap.sh --test --dry-run --only "$m" --no-tui --report "$LOG_DIR/dryrun-$m.tsv" \
            >"$LOG_DIR/dryrun-$m.log" 2>&1 || true
        rc="$(awk -F'\t' -v n="$m" '$1 == n { print $2 }' "$LOG_DIR/dryrun-$m.tsv" | tail -n1)"
        case "$rc" in
            0) mark "$m" validate ok ;;
            75) mark "$m" validate FAIL "dry-run stopped at a checkpoint" ;;
            *) mark "$m" validate FAIL "dry-run rc=${rc:-none}" ;;
        esac
    done
fi

# Items of module $1 that ran ("✔ ok") in bootstrap log $2, minus those that run again by design. $3 selects
# them (see tests/lib/profile_query.py): `asserts` for a plain second run (fluxion re-checks every assert and
# never skips a phase that holds one), `probeless` for a --re-probe run (asserts + package pre-install actions
# without a step-level probeCommand). One key per line.
ran_items() {
    local m="$1" log="$2" query="$3" exempt
    exempt="$(python3 tests/lib/profile_query.py "$(module_file "$m")" "$query")"
    sed 's/\x1b\[[0-9;]*m//g' "$log" |
        awk -v n="$m" '/^━━━ / { on = ($2 == n); next } on && /▸ .* \.\.\. ✔ ok/ { sub(/^ *▸ /, ""); sub(/ \.\.\. ✔ ok.*$/, ""); print }' |
        grep -vxF -f <(printf '%s\n' "$exempt") || true
}

# Evaluate a bootstrap --report file. $1 = stage, $2 = report, $3 = 1 when nothing may have run,
# $4 = the bootstrap log, $5 = which items may run again anyway (`asserts`, or `probeless` for --re-probe)
evaluate_report() {
    local stage="$1" report="$2" strict_zero="$3" log="${4:-}" exempt="${5:-asserts}" m line rc note ok failed ran
    for m in "${MODULES[@]}"; do
        line="$(awk -F'\t' -v n="$m" '$1 == n' "$report" 2>/dev/null | tail -n1)"
        if [[ -z "$line" ]]; then
            mark "$m" "$stage" FAIL "not run"
            continue
        fi
        IFS=$'\t' read -r _ rc note _ ok failed _ _ <<<"$line"
        if [[ "$strict_zero" == 1 && -n "$log" ]]; then
            ran="$(ran_items "$m" "$log" "$exempt" | wc -l)"
            [[ "$ran" -eq 0 ]] || ran_items "$m" "$log" "$exempt" >"$LOG_DIR/ran-again-$m.txt"
        else
            ran="$ok"
        fi
        if [[ "$rc" != 0 ]]; then
            mark "$m" "$stage" FAIL "rc=$rc $note, $failed failed"
        elif [[ "$strict_zero" == 1 && "$ran" != 0 ]]; then
            mark "$m" "$stage" FAIL "$ran item(s) ran again"
        else
            mark "$m" "$stage" ok "$ok ok, $failed failed"
        fi
    done
}

if has_stage apply || has_stage idempotency; then
    if ! sudo -n true 2>/dev/null; then
        say "sudo will ask for your password once (bootstrap.sh keeps the ticket warm)"
    fi
fi

if has_stage apply; then
    say "stage apply: ./bootstrap.sh --test --only $ONLY_CSV"
    : >"$LOG_DIR/apply.tsv"
    ./bootstrap.sh --test --only "$ONLY_CSV" --no-tui --report "$LOG_DIR/apply.tsv" 2>&1 | tee "$LOG_DIR/apply.log" || true
    evaluate_report apply "$LOG_DIR/apply.tsv" 0
fi

if has_stage idempotency; then
    extra=()
    [[ $STRICT -eq 1 ]] && extra=(--re-probe)
    say "stage idempotency: ./bootstrap.sh --test --only $ONLY_CSV ${extra[*]}"
    : >"$LOG_DIR/idempotency.tsv"
    ./bootstrap.sh --test --only "$ONLY_CSV" --no-tui "${extra[@]}" --report "$LOG_DIR/idempotency.tsv" 2>&1 |
        tee "$LOG_DIR/idempotency.log" || true
    if [[ $STRICT -eq 1 ]]; then
        evaluate_report idempotency "$LOG_DIR/idempotency.tsv" 1 "$LOG_DIR/idempotency.log" probeless
    else
        evaluate_report idempotency "$LOG_DIR/idempotency.tsv" 1 "$LOG_DIR/idempotency.log" asserts
    fi
fi

if has_stage assert; then
    say "stage assert"
    for m in "${MODULES[@]}"; do
        file="tests/assertions/$m.sh"
        if [[ ! -f "$file" ]]; then
            mark "$m" assert skip "no assertions"
            continue
        fi
        # Each module in its own bash so a helper's state cannot leak into the next module.
        if bash -c 'source "$1"; fn="assert_${2//-/_}"; "$fn"; assert_summary' _ "$file" "$m" 2>&1 |
            tee "$LOG_DIR/assert-$m.log"; then
            mark "$m" assert ok "$(tail -n1 "$LOG_DIR/assert-$m.log" | sed 's/\x1b\[[0-9;]*m//g; s/^\[[^]]*\] //')"
        else
            mark "$m" assert FAIL "$(tail -n1 "$LOG_DIR/assert-$m.log" | sed 's/\x1b\[[0-9;]*m//g; s/^\[[^]]*\] //')"
        fi
    done
fi

# ---- summary --------------------------------------------------------------------------------------------------
printf '\n%sTest summary%s  (%s)\n' "$B" "$N" "$LOG_DIR"
printf '  %-18s' module
for s in ${STAGES//,/ }; do printf ' %-30s' "$s"; done
printf '\n'
for m in "${MODULES[@]}"; do
    printf '  %-18s' "$m"
    for s in ${STAGES//,/ }; do
        r="${RESULT["$m/$s"]:-"-"}"
        c="$D"
        [[ "$r" == ok* ]] && c="$G"
        [[ "$r" == FAIL* ]] && c="$R"
        [[ "$r" == skip* ]] && c="$Y"
        printf ' %s%-30s%s' "$c" "${r:0:30}" "$N"
    done
    printf '\n'
done
{
    for m in "${MODULES[@]}"; do
        for s in ${STAGES//,/ }; do printf '%s\t%s\t%s\n' "$m" "$s" "${RESULT["$m/$s"]:-"-"}"; done
    done
} >"$LOG_DIR/summary.tsv"

if [[ ${#CONTAINER_SKIPS[@]} -gt 0 ]]; then
    printf '\n%sNot tested in the container%s (steps removed from the test profiles; %s):\n' "$Y" "$N" \
        "$LOG_DIR/container-skips.tsv"
    printf '  %s\n' "${CONTAINER_SKIPS[@]}"
fi

if [[ $FAILURES -gt 0 ]]; then
    printf '\n%s%d check(s) failed.%s Logs: %s\n' "$R" "$FAILURES" "$N" "$LOG_DIR"
    exit 1
fi
printf '\n%sAll stages passed.%s\n' "$G" "$N"
