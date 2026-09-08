# Print the full body of every `run:` step in a workflow YAML file, whether
# it is a single-line value or a `run: |` / `run: >` multi-line block, so
# callers can grep the result for a leaked ${{ }} wherever it lands.
{
    line = $0
    ws = line
    sub(/[^ ].*/, "", ws)
    cur_indent = length(ws)

    if (in_run) {
        if (line ~ /^[[:space:]]*$/) { print line; next }
        if (cur_indent <= indent) { in_run = 0 }
        else { print line; next }
    }

    # A step's run: key normally starts the line after its own indentation,
    # but a step with no separate name:/uses: line writes it inline after
    # the list-item dash ("- run: |"), at the same column as the dash. The
    # block-scalar body (and any sibling key, like a same-step "if:") is
    # indented relative to run: itself, not to the dash, so the recorded
    # indent must be the column where "run:" starts, not cur_indent - the
    # two coincide in the non-dash form but differ by the width of the
    # "- " prefix (which can be more than two characters) in the dash form.
    if (match(line, /^[[:space:]]*(- +)?run:/)) {
        indent = RLENGTH - length("run:")
        print line
        if (line ~ /run:[[:space:]]*[|>]/) { in_run = 1 }
        next
    }
}
