#!/usr/bin/env bash
# List files added or modified between two refs.

changed_files() {
    local base="${1:-origin/main}"
    local head="${2:-HEAD}"
    git diff --name-only --diff-filter=ACMR "${base}...${head}"
}
