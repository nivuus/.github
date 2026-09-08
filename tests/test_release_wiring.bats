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

# run_bodies <target_yaml>
# Prints the full body of every run: step in the workflow, via the shared
# multi-line-aware extractor. A prose match against the whole file (an input
# description, a comment) is not proof that a command actually runs -
# several of this suite's own assertions used to pass on that false comfort
# (round-1 review, 2026-09-08). Anchoring to run: bodies excludes anything
# that lives only in inputs:/description: text.
run_bodies() {
    awk -f "$HELPER" "$1"
}

# functional_run_lines <target_yaml>
# run_bodies with full-line shell comments stripped, so a `#` line that
# documents an anti-pattern (e.g. "# Never `sha256sum * > SHA256SUMS`") can
# never be mistaken for the real command it warns against.
functional_run_lines() {
    run_bodies "$1" | grep -vE '^[[:space:]]*#'
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

# Anchored to the real invocation (an assignment capturing the exact script
# path), not a bare substring: a bare "derive-version.sh" also matches this
# step's own diagnostic `echo "derive-version.sh failed..."` line, so
# pointing the actual call at a wrong script used to pass (round-1 review).
@test "derives the version from the shared script" {
    grep -qE '="\$\(\.nivuus-socle/scripts/derive-version\.sh\)"' "$WF"
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

# Anchored to the actual run: invocation, not a bare substring: the
# answers-file input's own description prose mentions
# "check-idempotence.sh", so `run: true` used to pass this check (round-1
# review) - the worst of the five, since it could silently disable the gate
# that stops a broken install hook reaching a public release.
@test "gates publication on the idempotence proof" {
    run_bodies "$WF" | grep -qF ".nivuus-socle/scripts/check-idempotence.sh"
}

# Override 2: check-idempotence.sh now resolves requires.packages by cloning
# from the nivuus org and accepts an answers file via NIVUUS_ANSWERS_FILE
# (console cannot install without a windows_iso answer). Match
# ci-package.yml's approach rather than inventing a second one.
@test "exposes an overridable answers file" {
    grep -q "answers-file:" "$WF"
}

# Anchored to the real env: mapping line (key, colon, the exact expression),
# not a bare substring: the answers-file input's own description prose also
# names NIVUUS_ANSWERS_FILE, so deleting the actual env: line used to pass
# this check (round-1 review).
@test "passes the answers file via NIVUUS_ANSWERS_FILE" {
    grep -qE 'NIVUUS_ANSWERS_FILE:[[:space:]]*\$\{\{[[:space:]]*inputs\.answers-file[[:space:]]*\}\}' "$WF"
}

@test "installs what the harness imports" {
    grep -q "pyyaml" "$WF"
}

# Anchored to run: bodies with comments stripped: the comment documenting
# why the working tree must not be used ("git archive exports TRACKED files
# only...") also contains the words "git archive", so a bare substring match
# used to pass even after the real call was replaced with `tar -cf - .`
# (which WOULD ship .env files and logs into a public release - round-1
# review, the one the reviewer found).
@test "builds the archive from tracked files only" {
    functional_run_lines "$WF" | grep -qF "git archive HEAD"
}

# Override 1: `sha256sum ./* > SHA256SUMS` hashes its own empty self because
# the redirect creates the file before the glob expands. The sums must be
# written to a path excluded from the glob (a temp path, then moved in).
# Anchored to run: bodies with comments stripped, and to the real "sha256sum
# -- *" invocation specifically: the anti-pattern comment above it also
# contains the bare word "sha256sum" and the string "SHA256SUMS", so a bare
# substring match used to pass even after the real generating line was
# deleted (round-1 review).
@test "publishes checksums alongside the archive" {
    functional_run_lines "$WF" | grep -qF "SHA256SUMS"
    functional_run_lines "$WF" | grep -qE 'sha256sum[[:space:]]+--[[:space:]]+\*'
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
# No "0.0.0" conjunct here: that string appears only in a comment
# (round-1 review), so checking for it adds fragility (a documentation
# reword would redden CI) without adding coverage. The three conjuncts below
# already cover the real mechanism.
@test "injects the version into the archive rather than committing it" {
    grep -qF "sed -i" "$WF"
    grep -qF '${VERSION}' "$WF"
    run grep -n "git commit" "$WF"
    [ "$status" -ne 0 ]
}

# Round-1 review, point 2/3: a separate `git tag -a` needs a committer
# identity this workflow never configures (a hard failure on a fresh
# runner), and a tag-then-push-then-create-release sequence is not atomic -
# a failure between the push and the release create leaves a public tag
# with no release, unrecoverable by re-running on a protected main.
# `gh release create --target` creates the tag itself in the same call that
# creates the release, closing both gaps at once.
@test "creates the tag via gh release create rather than a separate git tag and push" {
    run functional_run_lines "$WF"
    [ "$status" -eq 0 ]
    [[ "$output" != *"git tag -a"* ]]
    [[ "$output" != *"git push origin"* ]]
    [[ "$output" == *"gh release create"* ]]
    [[ "$output" == *"--target"* ]]
}

# Round-1 review, point 4a: an explicitly named version-files entry that is
# not in the exported tree is an operator error (a typo, a renamed file)
# worth stopping the release for - not something to pass over in silence the
# way an auto-detected candidate's absence is.
@test "fails loudly when an explicitly requested version-files entry is missing from the export" {
    functional_run_lines "$WF" | grep -qF "is not in the exported tree"
}

# Round-1 review, point 4b: the stamping step used to echo "Stamped $VERSION
# into $file" unconditionally after the case, even when the sed pattern
# found nothing to replace. A before/after comparison makes the log
# describe what actually happened.
@test "logs a stamp only when the file's content actually changed" {
    functional_run_lines "$WF" | grep -qE 'before="\$\(sha256sum'
    functional_run_lines "$WF" | grep -qE 'after="\$\(sha256sum'
    functional_run_lines "$WF" | grep -qE 'if \[ "\$before" != "\$after" \]'
}

# CRITICAL 2: desk's release stub passes no `with:`, so the shared workflow
# ran the idempotence gate with no answers file and no way to opt out. An
# explicit, visible opt-out (default on) is right; a silently-skipped gate
# is not.
@test "exposes an explicit opt-out for the idempotence gate, defaulting to on" {
    grep -qF "prove-package:" "$WF"
    grep -qE 'default:[[:space:]]*true' "$WF"
}

@test "the idempotence gate step is conditional on prove-package" {
    run grep -n "Prove the install hook is idempotent" "$WF"
    [ "$status" -eq 0 ]
    local line
    line="$(cut -d: -f1 <<< "$output" | head -1)"
    sed -n "${line},+3p" "$WF" | grep -qF "inputs.prove-package"
}

# CRITICAL 3: retro/pyproject.toml declares `dynamic = ["version"]` in
# [project] and its only column-0 `version = ` line sits under
# [tool.setuptools.dynamic] (defining HOW to compute the version, not a
# value to overwrite). A table-blind sed rewrote that line, breaking the
# published wheel: `tool.setuptools.dynamic.version must be valid exactly by
# one definition`. Stamping must track the current table and only ever
# touch a version line while inside [project], and must skip a file whose
# [project] table itself declares the version dynamic.
@test "TOML stamping tracks the current table, never touching version blindly" {
    functional_run_lines "$WF" | grep -qF 'tbl=$0'
    functional_run_lines "$WF" | grep -qF 'tbl == "[project]"'
}

@test "TOML stamping skips the file when [project].dynamic already declares version" {
    functional_run_lines "$WF" | grep -qF 'dynamic[[:space:]]*=.*"version"'
    functional_run_lines "$WF" | grep -qF 'Skipping TOML stamp'
}

@test "TOML stamping no longer rewrites the first column-0 version line blindly" {
    run functional_run_lines "$WF"
    [ "$status" -eq 0 ]
    [[ "$output" != *'sed -i "s/^version = .*/version = \"${VERSION}\"/" "$path"'* ]]
}

# IMPORTANT 7: the build step used to run before the export-and-stamp step,
# so a .deb or wheel it produced carried the checked-in (dev) version while
# the archive published beside it carried the real one. A build command
# cannot honour VERSION if it is never handed to it.
@test "exports VERSION into the build step's environment" {
    run grep -n "name: Build the native artifact" "$WF"
    [ "$status" -eq 0 ]
    local line
    line="$(cut -d: -f1 <<< "$output" | head -1)"
    sed -n "${line},+9p" "$WF" | grep -qE 'VERSION:[[:space:]]*\$\{\{[[:space:]]*steps\.version\.outputs\.version[[:space:]]*\}\}'
}

@test "the build step still runs before the export-and-stamp step" {
    run grep -n "name: Build the native artifact\|name: Export the tracked tree" "$WF"
    [ "$status" -eq 0 ]
    local build_line export_line
    build_line="$(sed -n '1p' <<< "$output" | cut -d: -f1)"
    export_line="$(sed -n '2p' <<< "$output" | cut -d: -f1)"
    [ "$build_line" -lt "$export_line" ]
}

# IMPORTANT 10: two merges to main inside one run's duration derive the same
# version; the second `gh release create` fails on the tag the first run
# already published. Serialise per repository rather than race.
@test "serialises releases per repository so concurrent merges cannot race" {
    grep -qE '^concurrency:' "$WF"
    grep -qF 'group: release-${{ github.repository }}' "$WF"
    grep -qF 'cancel-in-progress: false' "$WF"
}
