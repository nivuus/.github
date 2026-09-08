#!/usr/bin/env bats

load helpers/repo

setup() {
    SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"
    make_repo
    FAKE_INSTALLER="$(mktemp -d)"
    mkdir -p "$FAKE_INSTALLER/scripts"
    HARNESS_ARGV_LOG="$(mktemp)"
    export HARNESS_ARGV_LOG

    # A fake harness: it never runs the real idempotence proof, it only
    # records the argv it received (one token per line) so tests can assert
    # on --prereq/--answers wiring, and echoes which package it was called
    # for so the pre-existing tests keep working unchanged.
    cat > "$FAKE_INSTALLER/scripts/idempotence_harness.py" <<'PY'
import os
import sys
with open(os.environ["HARNESS_ARGV_LOG"], "w") as f:
    f.write("\n".join(sys.argv[1:]))
print("harness ran on " + sys.argv[sys.argv.index("--package") + 1])
sys.exit(int(os.environ.get("FAKE_HARNESS_STATUS", "0")))
PY

    # A fake packages.manifest module: check-idempotence.sh always reads
    # requires.packages through the real parser, so the fake installer must
    # provide one - this mirrors the fake harness above, minimal but
    # functionally equivalent to installer/packages/manifest.py for the one
    # thing this script uses (name + requires.packages).
    mkdir -p "$FAKE_INSTALLER/installer/packages"
    touch "$FAKE_INSTALLER/installer/packages/__init__.py"
    cat > "$FAKE_INSTALLER/installer/packages/manifest.py" <<'PY'
import yaml

MANIFEST_NAME = "nivuus-package.yaml"


class Manifest:
    def __init__(self, name, packages):
        self.name = name
        self.packages = tuple(packages)


def load_manifest(path):
    with open(path) as f:
        data = yaml.safe_load(f) or {}
    requires = data.get("requires") or {}
    return Manifest(data.get("name", ""), requires.get("packages") or [])
PY

    # A fake git: "clone" never touches the network. It records every
    # attempted clone (url + target dir) so a test can assert a clone was
    # or was not attempted, and fabricates the target directory from a
    # fixture registered under FIXTURES_DIR/<repo name>, if any.
    FAKE_GIT_LOG="$(mktemp)"
    FIXTURES_DIR="$(mktemp -d)"
    export FAKE_GIT_LOG FIXTURES_DIR
    FAKE_BIN="$(mktemp -d)"
    REAL_GIT="$(command -v git)"
    export REAL_GIT
    cat > "$FAKE_BIN/git" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
if [ "$1" = "clone" ]; then
    shift
    args=("$@")
    n=${#args[@]}
    url="${args[$((n - 2))]}"
    dir="${args[$((n - 1))]}"
    printf '%s %s\n' "$url" "$dir" >> "$FAKE_GIT_LOG"
    mkdir -p "$dir"
    name="$(basename "$url")"
    if [ -d "${FIXTURES_DIR}/${name}" ]; then
        cp -r "${FIXTURES_DIR}/${name}/." "$dir/"
    fi
    exit 0
fi
# Everything else (init, add, commit, config, ...) is real repo setup done
# by the test helpers themselves - only "clone" is intercepted.
exec "$REAL_GIT" "$@"
SH
    chmod +x "$FAKE_BIN/git"
    PATH="$FAKE_BIN:$PATH"
    export PATH
}

teardown() {
    [ -n "${REPO:-}" ] && rm -rf "$REPO"
    [ -n "${FAKE_INSTALLER:-}" ] && rm -rf "$FAKE_INSTALLER"
    [ -n "${HARNESS_ARGV_LOG:-}" ] && rm -f "$HARNESS_ARGV_LOG"
    [ -n "${FAKE_GIT_LOG:-}" ] && rm -f "$FAKE_GIT_LOG"
    [ -n "${FIXTURES_DIR:-}" ] && rm -rf "$FIXTURES_DIR"
}

@test "exits cleanly when the repository is not a package" {
    NIVUUS_INSTALLER_DIR="$FAKE_INSTALLER" run "$SCRIPTS/check-idempotence.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping"* ]]
}

@test "runs the harness when a manifest is present" {
    commit_file "nivuus-package.yaml" "name: demo" "chore: add manifest"
    NIVUUS_INSTALLER_DIR="$FAKE_INSTALLER" run "$SCRIPTS/check-idempotence.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"harness ran on"* ]]
}

@test "fails when the harness refuses the package" {
    commit_file "nivuus-package.yaml" "name: demo" "chore: add manifest"
    FAKE_HARNESS_STATUS=1 NIVUUS_INSTALLER_DIR="$FAKE_INSTALLER" \
        run "$SCRIPTS/check-idempotence.sh"
    [ "$status" -ne 0 ]
}

@test "fails loudly when the harness is missing rather than passing" {
    commit_file "nivuus-package.yaml" "name: demo" "chore: add manifest"
    rm "$FAKE_INSTALLER/scripts/idempotence_harness.py"
    NIVUUS_INSTALLER_DIR="$FAKE_INSTALLER" run "$SCRIPTS/check-idempotence.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"harness"* ]]
}

@test "passes a requires.packages dependency to the harness as --prereq" {
    mkdir -p "${FAKE_INSTALLER}/console"
    cat > "${FAKE_INSTALLER}/console/nivuus-package.yaml" <<'YAML'
name: console
YAML
    commit_file "nivuus-package.yaml" \
        $'name: demo\nrequires:\n  packages: [console]' \
        "chore: add manifest with a dependency"

    NIVUUS_INSTALLER_DIR="$FAKE_INSTALLER" run "$SCRIPTS/check-idempotence.sh"

    [ "$status" -eq 0 ]
    grep -qx -- "--prereq" "$HARNESS_ARGV_LOG"
    grep -qx -- "${FAKE_INSTALLER}/console" "$HARNESS_ARGV_LOG"
}

@test "a console dependency resolves to the installer checkout's console/ directory, never a clone" {
    mkdir -p "${FAKE_INSTALLER}/console"
    cat > "${FAKE_INSTALLER}/console/nivuus-package.yaml" <<'YAML'
name: console
YAML
    commit_file "nivuus-package.yaml" \
        $'name: demo\nrequires:\n  packages: [console]' \
        "chore: add manifest with a console dependency"

    NIVUUS_INSTALLER_DIR="$FAKE_INSTALLER" run "$SCRIPTS/check-idempotence.sh"

    [ "$status" -eq 0 ]
    ! grep -q "console" "$FAKE_GIT_LOG"
}

@test "a non-console dependency is cloned from the nivuus org and passed as --prereq" {
    mkdir -p "${FIXTURES_DIR}/home-manager"
    cat > "${FIXTURES_DIR}/home-manager/nivuus-package.yaml" <<'YAML'
name: home-manager
YAML
    commit_file "nivuus-package.yaml" \
        $'name: demo\nrequires:\n  packages: [home-manager]' \
        "chore: add manifest with a real dependency"

    NIVUUS_INSTALLER_DIR="$FAKE_INSTALLER" run "$SCRIPTS/check-idempotence.sh"

    [ "$status" -eq 0 ]
    grep -q "https://github.com/nivuus/home-manager" "$FAKE_GIT_LOG"
    grep -qx -- "--prereq" "$HARNESS_ARGV_LOG"
}

@test "a dependency cycle does not hang the script" {
    mkdir -p "${FIXTURES_DIR}/pkg-a" "${FIXTURES_DIR}/pkg-b"
    cat > "${FIXTURES_DIR}/pkg-a/nivuus-package.yaml" <<'YAML'
name: pkg-a
requires:
  packages: [pkg-b]
YAML
    cat > "${FIXTURES_DIR}/pkg-b/nivuus-package.yaml" <<'YAML'
name: pkg-b
requires:
  packages: [pkg-a]
YAML
    commit_file "nivuus-package.yaml" \
        $'name: demo\nrequires:\n  packages: [pkg-a]' \
        "chore: add manifest with a dependency cycle"

    NIVUUS_INSTALLER_DIR="$FAKE_INSTALLER" run timeout 10 \
        "$SCRIPTS/check-idempotence.sh"

    [ "$status" -eq 0 ]
}

@test "forwards an answers file to the harness as --answers" {
    commit_file "nivuus-package.yaml" "name: demo" "chore: add manifest"
    ANSWERS_FILE="$(mktemp)"
    printf '{}' > "$ANSWERS_FILE"

    NIVUUS_INSTALLER_DIR="$FAKE_INSTALLER" NIVUUS_ANSWERS_FILE="$ANSWERS_FILE" \
        run "$SCRIPTS/check-idempotence.sh"

    [ "$status" -eq 0 ]
    grep -qx -- "--answers" "$HARNESS_ARGV_LOG"
    grep -qx -- "$ANSWERS_FILE" "$HARNESS_ARGV_LOG"
    rm -f "$ANSWERS_FILE"
}
