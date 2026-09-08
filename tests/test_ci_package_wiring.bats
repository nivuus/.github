#!/usr/bin/env bats

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/ci-package.yml"
    HELPER="${BATS_TEST_DIRNAME}/helpers/extract_run_blocks.awk"
}

# leaked_expressions <helper_awk> <target_yaml>
# Prints any ${{ }} expression the extractor found reaching a run: body.
# Fails LOUDLY (status 2, no output) when the extractor is missing or errors,
# rather than letting a broken extractor silently read as "no leak found":
# without pipefail, a crashing awk feeding an empty stream into `grep -F`
# makes grep exit non-zero for the wrong reason, and the caller could not
# tell "no leak" from "the check never actually ran".
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

@test "ci-package workflow exists" {
    [ -f "$WF" ]
}

@test "is callable by other repositories" {
    grep -q "workflow_call:" "$WF"
}

@test "exposes an overridable package directory" {
    grep -q "package-dir:" "$WF"
}

@test "exposes an overridable answers file" {
    grep -q "answers-file:" "$WF"
}

# Checking these two properties independently lets either drift without the
# other: a step could check the socle out to .nivuus-socle while calling
# check-idempotence.sh from anywhere, or vice versa. Only the joined path
# proves the script that actually runs is the one from the socle checkout.
@test "checks out the socle and invokes its script from that checkout" {
    grep -q "repository: nivuus/.github" "$WF"
    grep -q "path: .nivuus-socle" "$WF"
    grep -qF ".nivuus-socle/scripts/check-idempotence.sh" "$WF"
}

@test "installs what the harness imports" {
    grep -q "pyyaml" "$WF"
}

# The script (task 4) reads the answers file from NIVUUS_ANSWERS_FILE, not
# from a flag - console cannot install without a windows_iso answer.
@test "passes the answers file via NIVUUS_ANSWERS_FILE" {
    grep -q "NIVUUS_ANSWERS_FILE" "$WF"
}

# A single-line anchor (^ +run:.*\$\{\{) is blind the moment a run: value
# moves into a `run: |` block: the expression lands on a following line the
# regex never inspects. extract_run_blocks.awk walks every run: step
# (single-line value or multi-line block, by indentation) and prints its
# full body, so the expression is caught wherever inside a run: it lands.
@test "passes github expressions through env, never into run blocks (including multi-line)" {
    [ -f "$HELPER" ]
    run leaked_expressions "$HELPER" "$WF"
    # 1 = the extractor ran fine and grep found nothing. 0 would mean a
    # leak; 2 would mean the extractor itself is missing or broken - both
    # must fail this test, never read as "clean".
    [ "$status" -eq 1 ]
}

# The guard above is only as good as its extractor. Prove that when the
# extractor is unavailable, the guard reports failure rather than quietly
# agreeing with "no leak found" - the exact regression a pipefail-less
# `awk ... | grep` produced last round.
@test "the multi-line guard fails loudly when its extractor is missing" {
    run leaked_expressions "${BATS_TEST_DIRNAME}/helpers/does-not-exist.awk" "$WF"
    [ "$status" -eq 2 ]
}

# extract_run_blocks.awk must also see a step with no separate name:/uses:
# line, where run: sits inline after the list-item dash ("- run: |") rather
# than on its own indented line.
@test "the multi-line guard also catches a leak in a dash-inline run step" {
    local tmp
    tmp="$(mktemp)"
    {
        printf 'name: Test\n'
        printf 'jobs:\n'
        printf '  x:\n'
        printf '    steps:\n'
        printf '      - run: |\n'
        printf '          echo "%s"\n' '${{ inputs.package-dir }}'
    } > "$tmp"
    run leaked_expressions "$HELPER" "$tmp"
    rm -f "$tmp"
    [ "$status" -eq 0 ]
    [[ "$output" == *'${{ inputs.package-dir }}'* ]]
}

# The dependency clones the script performs need git and network access,
# which a restrictive checkout could interfere with. Guard against that
# regression by never seeing a persist-credentials: false or similar
# submodule/sparse restriction slip in for the caller checkout.
@test "does not restrict the caller checkout in a way that could break cloning dependencies" {
    run grep -nE 'persist-credentials: *false' "$WF"
    [ "$status" -ne 0 ]
}
