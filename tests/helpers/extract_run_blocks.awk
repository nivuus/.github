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

    if (match(line, /^[[:space:]]*run:/)) {
        indent = cur_indent
        print line
        if (line ~ /run:[[:space:]]*[|>]/) { in_run = 1 }
        next
    }
}
