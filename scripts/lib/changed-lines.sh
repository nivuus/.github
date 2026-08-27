#!/usr/bin/env bash
# List the line numbers a change adds or modifies in one file.

# Prints one line number per line, on the post-change side of the diff.
added_lines() {
    local base="$1" head="$2" path="$3"
    git diff -U0 "${base}...${head}" -- "$path" \
        | gawk '
            /^@@/ {
                # A hunk header reads: @@ -old,count +new,count @@
                split($3, part, ",")
                start = substr(part[1], 2) + 0
                count = (part[2] == "" ? 1 : part[2] + 0)
                for (i = 0; i < count; i++) print start + i
            }
        '
}
