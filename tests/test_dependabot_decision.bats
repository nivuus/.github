#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../scripts/dependabot-decision.sh"
}

# dep <name> <update-type> <previous-version>: one updated-dependencies-json item.
dep() {
    printf '{"dependencyName":"%s","updateType":"%s","prevVersion":"%s"}' "$1" "$2" "$3"
}

decide() {
    local IFS=,
    run "$SCRIPT" <<< "[$*]"
}

@test "a patch on a stable version merges" {
    decide "$(dep serde version-update:semver-patch 1.0.200)"
    [ "$status" -eq 0 ]
}

@test "a minor on a stable version merges" {
    decide "$(dep tokio version-update:semver-minor 1.38.0)"
    [ "$status" -eq 0 ]
}

@test "a major waits for review" {
    decide "$(dep actions/checkout version-update:semver-major 4)"
    [ "$status" -eq 3 ]
    [[ "$output" == *"actions/checkout"* ]]
}

@test "a minor on a 0.x version waits for review" {
    decide "$(dep str0m version-update:semver-minor 0.21.0)"
    [ "$status" -eq 3 ]
    [[ "$output" == *"0.x"* ]]
}

@test "a patch on a 0.x version merges, with or without a v prefix" {
    decide "$(dep a version-update:semver-patch 0.21.0)" "$(dep b version-update:semver-patch v0.3.1)"
    [ "$status" -eq 0 ]
}

@test "a version merely starting with 0 is not 0.x" {
    decide "$(dep a version-update:semver-minor 10.2.0)"
    [ "$status" -eq 0 ]
}

@test "in a group, the strictest dependency decides" {
    decide "$(dep a version-update:semver-patch 1.0.0)" \
        "$(dep b version-update:semver-minor 2.1.0)" \
        "$(dep str0m version-update:semver-minor 0.21.0)"
    [ "$status" -eq 3 ]
    [[ "$output" == *"merge   a"* ]]
    [[ "$output" == *"review  str0m"* ]]
}

@test "the order of a group does not matter" {
    decide "$(dep big version-update:semver-major 1.0.0)" "$(dep a version-update:semver-patch 1.0.0)"
    [ "$status" -eq 3 ]
}

@test "an unknown update type waits for review" {
    decide "$(dep a "" 1.0.0)"
    [ "$status" -eq 3 ]
    [[ "$output" == *"unknown update type"* ]]
}

@test "an unknown previous version waits for review" {
    decide "$(dep a version-update:semver-patch "")"
    [ "$status" -eq 3 ]
    [[ "$output" == *"unknown previous version"* ]]
}

@test "the allowed types can be narrowed to patches" {
    ALLOWED_UPDATE_TYPES=semver-patch decide "$(dep tokio version-update:semver-minor 1.38.0)"
    [ "$status" -eq 3 ]
}

@test "majors can be opted into, comma-separated" {
    ALLOWED_UPDATE_TYPES="semver-patch,semver-minor,semver-major" \
        decide "$(dep actions/checkout version-update:semver-major 4)"
    [ "$status" -eq 0 ]
}

@test "opting into majors never lifts the 0.x patch-only rule" {
    ALLOWED_UPDATE_TYPES="semver-patch semver-minor semver-major" \
        decide "$(dep str0m version-update:semver-major 0.21.0)"
    [ "$status" -eq 3 ]
}

@test "an unknown allowed type is an error, not a silent refusal" {
    ALLOWED_UPDATE_TYPES="patch" decide "$(dep a version-update:semver-patch 1.0.0)"
    [ "$status" -eq 1 ]
}

@test "input that is not the json array is an error" {
    run "$SCRIPT" <<< "not json"
    [ "$status" -eq 1 ]
    run "$SCRIPT" <<< '{"dependencyName":"a"}'
    [ "$status" -eq 1 ]
}

@test "an empty dependency list is an error, not a merge" {
    run "$SCRIPT" <<< "[]"
    [ "$status" -eq 1 ]
}
