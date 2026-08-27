# Test helpers: build throwaway git repositories.

make_repo() {
    REPO="$(mktemp -d)"
    cd "$REPO" || return 1
    git init -q -b main .
    git config user.email "test@nivuus.local"
    git config user.name "Test"
    git commit -q --allow-empty -m "chore: initial commit"
}

commit_file() {
    local path="$1" content="$2" message="${3:-chore: add file}"
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
    git add "$path"
    git commit -q -m "$message"
}

teardown() {
    [ -n "${REPO:-}" ] && rm -rf "$REPO"
}
