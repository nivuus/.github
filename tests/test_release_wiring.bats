#!/usr/bin/env bats

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/release.yml"
    HELPER="${BATS_TEST_DIRNAME}/helpers/extract_run_blocks.awk"
}

# leaked_expressions <helper_awk> <target_yaml>
# Prints any ${{ }} expression the extractor found reaching a run: body.
# Mirrors test_ci_package_wiring.bats's helper: fails LOUDLY (status 2, no
# output) when the extractor is missing or errors, rather than letting a
# broken extractor silently read as "no leak found".
# Exit codes: 0 = leak found, 1 = ran fine and found nothing, 2 = broken.
leaked_expressions() {
    local helper="$1" target="$2" body
    if [ ! -f "$helper" ]; then
        echo "extractor missing: $helper" >&2
        return 2
    fi
    if ! body="$(awk -f "$helper" "$target")"; then
        echo "extractor failed: $helper" >&2
        return 2
    fi
    printf '%s\n' "$body" | grep -F '${{'
}

@test "release workflow exists" {
    [ -f "$WF" ]
}

@test "is callable by other repositories" {
    grep -q "workflow_call:" "$WF"
}

@test "exposes the per-repository knobs" {
    grep -q "package-dir:" "$WF"
    grep -q "version-files:" "$WF"
    grep -q "build-command:" "$WF"
    grep -q "artifact-glob:" "$WF"
}

# Without full history there is no tag to derive from and every release would
# look like the first one.
@test "fetches full history so the last tag is visible" {
    grep -q "fetch-depth: 0" "$WF"
}

@test "derives the version from the shared script" {
    grep -q "derive-version.sh" "$WF"
}

# Override 3: derive-version.sh writes the version on stdout and its
# refusals on stderr, precisely so that `version="$(derive-version.sh)"`
# captures a clean value. Prove the workflow actually captures stdout only -
# a stray 2>&1 would let a diagnostic line become the version string, and
# then the git tag.
@test "captures the version script's stdout only, never merging stderr into it" {
    run grep -nE 'derive-version\.sh.*2>&1|2>&1.*derive-version\.sh' "$WF"
    [ "$status" -ne 0 ]
    grep -qE '="\$\(.*derive-version\.sh[^)]*\)"' "$WF"
}

# Exit 3 means "nothing releasable"; treating it as a failure would paint every
# documentation-only merge red.
@test "treats an empty release as success, not failure" {
    grep -q "eq 3" "$WF"
}

# Override 4: any OTHER non-zero exit (a real error, e.g. outside a git repo
# or an unfetched shallow clone) must still fail the job. The set +e / $? /
# set -e shape must not swallow a genuine failure into the skip path.
@test "still fails the job on a real derive-version.sh error" {
    grep -qE '\[ "\$status" -ne 0 \]' "$WF"
    grep -qE 'exit "\$status"' "$WF"
}

@test "gates publication on the idempotence proof" {
    grep -q "check-idempotence.sh" "$WF"
}

# Override 2: check-idempotence.sh now resolves requires.packages by cloning
# from the nivuus org and accepts an answers file via NIVUUS_ANSWERS_FILE
# (console cannot install without a windows_iso answer). Match
# ci-package.yml's approach rather than inventing a second one.
@test "exposes an overridable answers file" {
    grep -q "answers-file:" "$WF"
}

@test "passes the answers file via NIVUUS_ANSWERS_FILE" {
    grep -q "NIVUUS_ANSWERS_FILE" "$WF"
}

@test "installs what the harness imports" {
    grep -q "pyyaml" "$WF"
}

@test "builds the archive from tracked files only" {
    grep -q "git archive" "$WF"
}

# Override 1: `sha256sum ./* > SHA256SUMS` hashes its own empty self because
# the redirect creates the file before the glob expands. The sums must be
# written to a path excluded from the glob (a temp path, then moved in).
@test "publishes checksums alongside the archive" {
    grep -q "SHA256SUMS" "$WF"
    grep -q "sha256sum" "$WF"
}

@test "does not redirect sha256sum directly into SHA256SUMS in the assets directory" {
    run grep -nE 'sha256sum[^>]*>\s*SHA256SUMS\s*$' "$WF"
    [ "$status" -ne 0 ]
}

@test "attests the build provenance" {
    grep -q "attest-build-provenance" "$WF"
}

@test "asks for the permissions the release needs" {
    grep -q "contents: write" "$WF"
    grep -q "attestations: write" "$WF"
    grep -q "id-token: write" "$WF"
}

# A single-line anchor (^ +run:.*\$\{\{) is blind the moment a run: value
# moves into a `run: |` block. Use the shared multi-line-aware extractor,
# per this repository's own convention (test_ci_package_wiring.bats).
@test "passes github expressions through env, never into run blocks (including multi-line)" {
    [ -f "$HELPER" ]
    run leaked_expressions "$HELPER" "$WF"
    [ "$status" -eq 1 ]
}

# The manifest version travels in the published archive, never in main: the
# branch is protected with enforce_admins, so a bump commit could not land.
# grep -q "0.0.0" alone is not load-bearing: "." is a regex metacharacter, so
# it matches "0-0-0" or "0x0x0" too and would never catch that check going
# missing. Assert the real properties instead: the version is stamped with
# sed into the exported tree, and the workflow never commits a bump to the
# branch (only tags and pushes the tag).
@test "injects the version into the archive rather than committing it" {
    grep -qF "0.0.0" "$WF"
    grep -qF "sed -i" "$WF"
    grep -qF '${VERSION}' "$WF"
    run grep -n "git commit" "$WF"
    [ "$status" -ne 0 ]
}
