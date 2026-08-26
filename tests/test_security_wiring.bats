#!/usr/bin/env bats

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/security.yml"
}

@test "security workflow exists" {
    [ -f "$WF" ]
}

@test "is callable by other repositories" {
    grep -q "workflow_call:" "$WF"
}

@test "job id stays 'security' so branch protection keeps matching" {
    grep -qE '^  security:' "$WF"
}

@test "scans for secrets with gitleaks" {
    grep -q "gitleaks" "$WF"
}

@test "audits dependencies for all three ecosystems" {
    grep -q "pip-audit" "$WF"
    grep -q "cargo audit" "$WF"
    grep -q "npm audit" "$WF"
}

@test "guards each audit behind a manifest check" {
    grep -q "requirements.txt\|pyproject.toml" "$WF"
    grep -q "Cargo.lock" "$WF"
    grep -q "package-lock.json" "$WF"
}
