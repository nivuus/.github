#!/usr/bin/env bats

load helpers/run_blocks

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/policy.yml"
    HELPER="${BATS_TEST_DIRNAME}/helpers/extract_run_blocks.awk"
}

@test "policy workflow exists" {
    [ -f "$WF" ]
}

@test "is callable by other repositories" {
    grep -q "workflow_call:" "$WF"
}

@test "job id stays 'policy' so branch protection keeps matching" {
    grep -qE '^  policy:' "$WF"
}

@test "fetches full history for the diff and the commit range" {
    grep -q "fetch-depth: 0" "$WF"
}

@test "checks out the socle to reach its scripts" {
    grep -q "repository: nivuus/.github" "$WF"
}

@test "installs gawk, required by the French detector" {
    grep -q "gawk" "$WF"
}

@test "runs all three checks" {
    grep -q "check-file-size.sh" "$WF"
    grep -q "check-english.sh" "$WF"
    grep -q "check-commits.sh" "$WF"
}

@test "the commit-subject check is skipped only on a positively squash-only repo" {
    # The negation is the point: a payload without the merge flags must RUN the
    # check. A positive form would silently disable it wherever the fields are
    # absent, and nobody would notice a check that stopped running.
    grep -q '!(github.event.repository.allow_merge_commit == false' "$WF"
    grep -q 'allow_rebase_merge == false' "$WF"
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

@test "socle ref is overridable so the socle can test itself" {
    grep -q "socle-ref:" "$WF"
    grep -q 'ref: ${{ inputs.socle-ref }}' "$WF"
}
