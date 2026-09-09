# Shared guard against a ${{ }} expression reaching a run: body.
#
# Eight wiring suites needed this check and each one used to spell it as a
# single-line anchor, `grep -nE '^ +run:.*\$\{\{'`. That anchor is blind the
# moment the value moves into a `run: |` block, which is where nearly every
# real run: body in this repository lives: the expression lands on a line the
# regex never inspects, and the test passes because it looked at the wrong
# line, not because the workflow is clean.

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
