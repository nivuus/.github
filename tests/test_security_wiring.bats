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

# A full-history scan would turn CI permanently red on any repository that
# already contains a secret, blocking every merge. The gate detects NEW
# secrets; auditing history is a one-off operation done before rollout.
@test "scopes the secret scan to the change under review" {
    grep -q "log-opts" "$WF"
}

# gitleaks-action v2 requires a paid licence for organization accounts, and
# nivuus is one. The gitleaks CLI is MIT-licensed and needs no licence, so the
# workflow installs the binary instead. Do not "modernise" this back to the
# action.
@test "installs the gitleaks binary rather than the licensed action" {
    run grep -q "gitleaks/gitleaks-action" "$WF"
    [ "$status" -ne 0 ]
    grep -q "releases/download" "$WF"
}

# A push can carry several commits; scanning only the tip misses a secret
# introduced earlier in the same push. github.event.before is the ref
# before the push and covers the whole range.
@test "scans the whole push range, not just the tip commit" {
    grep -q "github.event.before" "$WF"
}

# The socle's own docs quote credential placeholders; without an allowlist the
# secret scan flags its documentation. Allowlist the placeholder, never a path.
@test "allowlists documentation placeholders rather than paths" {
    local root="${BATS_TEST_DIRNAME}/.."
    [ -f "$root/.gitleaks.toml" ]
    grep -q "YOUR_TOKEN" "$root/.gitleaks.toml"
    run grep -qE '^\s*paths\s*=' "$root/.gitleaks.toml"
    [ "$status" -ne 0 ]
}
