#!/usr/bin/env bash
# Prove that this repository's install hook can be replayed, by handing it to
# the engine's own harness.
#
# The harness lives in nivuus/installer, next to the runner.py it drives,
# rather than being copied here: two copies of the engine would drift, and
# this repository's sibling projects already validate against the real
# parser through NIVUUS_INSTALLER_DIR for exactly that reason.
#
# Four of the six packages this gates cannot install alone: home-desk and
# home-stock declare `requires.packages: [home-manager]`, desk declares
# `requires.packages: [console]`, and console itself needs a wizard answer.
# Without resolving and installing those prerequisites first, wiring this
# into CI would paint every one of those repositories red for a reason that
# has nothing to do with idempotence - the mirror image of the failure this
# whole effort exists to prevent. That resolution is why this script exists
# rather than a one-line call to the harness.
#
# Usage: check-idempotence.sh [<package directory>]
# Exit 0: nothing to prove, or the proof passed.
# NIVUUS_INSTALLER_DIR: an existing installer checkout; skips the clone.
# NIVUUS_ANSWERS_FILE: a JSON file of wizard answers, forwarded to the
#   harness as --answers (console cannot install without one).
set -uo pipefail

readonly MANIFEST="nivuus-package.yaml"
readonly INSTALLER_URL="https://github.com/nivuus/installer"
readonly ORG_URL="https://github.com/nivuus"

# Directories this script creates itself (an installer clone, prerequisite
# clones) and must remove on exit, whichever way the script returns.
TEMP_DIRS=()

cleanup() {
    local dir
    for dir in "${TEMP_DIRS[@]:-}"; do
        [ -n "$dir" ] && rm -rf "$dir"
    done
}

# Print the names in <manifest_path>'s requires.packages, one per line.
# Goes through the engine's own packages.manifest.load_manifest, never a
# hand-rolled YAML grep - the manifest format is the engine's contract, not
# ours to reimplement.
manifest_packages() {
    local manifest_path="$1" installer="$2"
    python3 -c "
import sys
sys.path.insert(0, sys.argv[1] + '/installer')
from packages.manifest import load_manifest
for name in load_manifest(sys.argv[2]).packages:
    print(name)
" "$installer" "$manifest_path"
}

# Populate the global PREREQ_DIRS array with one directory per transitive
# requires.packages dependency of <package>. A worklist with a `seen` guard
# so a dependency cycle cannot loop forever. Order is discovery order, not a
# topological sort - the harness's own install_order() does that real sort,
# so --prereq flags may arrive in any order.
PREREQ_DIRS=()

resolve_prereqs() {
    local package="$1" installer="$2"
    local -A seen=()
    local -a queue
    local names name dep_dir sub_names

    names="$(manifest_packages "${package}/${MANIFEST}" "$installer")" || {
        printf 'Could not read requires.packages from %s\n' "${package}/${MANIFEST}"
        return 1
    }
    # Intentional word-splitting: one dependency name per line.
    # shellcheck disable=SC2206
    queue=($names)

    local idx=0
    while [ "$idx" -lt "${#queue[@]}" ]; do
        name="${queue[$idx]}"
        idx=$((idx + 1))
        [ -n "$name" ] || continue
        [ -n "${seen[$name]:-}" ] && continue
        seen["$name"]=1

        if [ "$name" = "console" ]; then
            # console has no repository of its own, unlike every other
            # package name: it lives inside nivuus/installer, right next to
            # the harness this script already cloned to obtain. Cloning
            # "nivuus/console" would fail outright - no such repository
            # exists - so this name is special-cased to the checkout we
            # already have.
            dep_dir="${installer}/console"
        else
            dep_dir="$(mktemp -d)"
            TEMP_DIRS+=("$dep_dir")
            if ! git clone -q --depth 1 "${ORG_URL}/${name}" "$dep_dir"; then
                printf 'Could not clone %s/%s to resolve the "%s" prerequisite.\n' \
                    "$ORG_URL" "$name" "$name"
                return 1
            fi
        fi

        if [ ! -f "${dep_dir}/${MANIFEST}" ]; then
            printf 'Prerequisite "%s" has no %s at %s\n' "$name" "$MANIFEST" "$dep_dir"
            return 1
        fi

        PREREQ_DIRS+=("$dep_dir")

        sub_names="$(manifest_packages "${dep_dir}/${MANIFEST}" "$installer")" || {
            printf 'Could not read requires.packages from %s\n' "${dep_dir}/${MANIFEST}"
            return 1
        }
        # shellcheck disable=SC2206
        queue+=($sub_names)
    done

    return 0
}

main() {
    local package="${1:-.}"

    if [ ! -f "${package}/${MANIFEST}" ]; then
        printf 'No %s in %s, skipping the idempotence proof.\n' \
            "$MANIFEST" "$package"
        return 0
    fi

    trap cleanup EXIT

    local installer="${NIVUUS_INSTALLER_DIR:-}"
    if [ -z "$installer" ]; then
        installer="$(mktemp -d)"
        TEMP_DIRS+=("$installer")
        git clone -q --depth 1 "$INSTALLER_URL" "$installer" || {
            printf 'Could not clone %s to obtain the harness.\n' "$INSTALLER_URL"
            return 1
        }
    fi

    local harness="${installer}/scripts/idempotence_harness.py"
    # A missing harness must FAIL, never skip: a proof that quietly does not
    # run is worse than no proof, because the release goes out believing it ran.
    if [ ! -f "$harness" ]; then
        printf 'The idempotence harness is missing at %s\n' "$harness"
        return 1
    fi

    resolve_prereqs "$package" "$installer" || return 1

    local -a cmd=(python3 "$harness" --package "$package")
    local dir
    for dir in "${PREREQ_DIRS[@]:-}"; do
        [ -n "$dir" ] && cmd+=(--prereq "$dir")
    done
    if [ -n "${NIVUUS_ANSWERS_FILE:-}" ]; then
        cmd+=(--answers "$NIVUUS_ANSWERS_FILE")
    fi

    "${cmd[@]}"
}

main "$@"
