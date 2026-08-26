#!/usr/bin/env bash
# Shared path predicates for the Nivuus policy checks.

# Test files are exempt from the size limit and from the English check.
is_test_path() {
    local path="$1"
    [[ "$path" =~ (^|/)tests?/ ]] && return 0
    [[ "$path" =~ (^|/)test_[^/]*$ ]] && return 0
    [[ "$path" =~ _test\.[^/]+$ ]] && return 0
    [[ "$path" =~ \.test\.[^/]+$ ]] && return 0
    [[ "$path" =~ \.spec\.[^/]+$ ]] && return 0
    return 1
}

# Generated files are never authored by hand.
is_generated_path() {
    local path="$1"
    [[ "$path" =~ (^|/)generated/ ]] && return 0
    [[ "$path" =~ (^|/)(package-lock\.json|Cargo\.lock)$ ]] && return 0
    [[ "$path" =~ \.pb\.rs$ ]] && return 0
    return 1
}

# Print the dialect of a source file, or fail for anything else.
dialect_of() {
    case "$1" in
        *.py)       printf 'py' ;;
        *.sh|*.zsh) printf 'sh' ;;
        *.rs)       printf 'rs' ;;
        *.ts|*.tsx) printf 'ts' ;;
        *.js)       printf 'js' ;;
        *)          return 1 ;;
    esac
}
