# Detect French in comments, docstrings and identifiers.
# Usage: gawk -v lang=py -v words=french-words.txt -f english.awk FILE
# Exits 1 when at least one line is flagged.

BEGIN {
    while ((getline word < words) > 0) {
        if (word == "" || word ~ /^#/) continue
        french[tolower(word)] = 1
    }
    close(words)
    accented = "[éèêëàâäîïôöùûüÿçœæÉÈÊËÀÂÄÎÏÔÖÙÛÜŸÇŒÆ]"
    indoc = 0
    found = 0
}

# Replace the contents of string literals with spaces, keeping the
# original length so column positions stay meaningful.
function blank_strings(s,    out, i, c, q, esc, n) {
    out = ""; q = ""; esc = 0
    n = length(s)
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (q != "") {
            if (esc)          { esc = 0; out = out " "; continue }
            if (c == "\\")    { esc = 1; out = out " "; continue }
            if (c == q)       { q = "";  out = out c;   continue }
            out = out " "
        } else {
            if (c == "\"" || c == "'" || c == "`") { q = c; out = out c; continue }
            out = out c
        }
    }
    return out
}

function marker() {
    return (lang == "py" || lang == "sh") ? "#" : "//"
}

function report(n, text) {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", text)
    printf "%d: %s\n", n, text
    found = 1
}

function is_french(text,    spaced, lower, i, nw, parts) {
    if (text ~ accented) return 1
    spaced = gensub(/([a-z0-9])([A-Z])/, "\\1 \\2", "g", text)
    lower = tolower(spaced)
    gsub(/[^a-z0-9]+/, " ", lower)
    nw = split(lower, parts, " ")
    for (i = 1; i <= nw; i++) {
        if (parts[i] in french) return 1
    }
    return 0
}

{
    # Python docstrings are handled before blanking, which would erase them.
    if (lang == "py") {
        copy = $0
        delims = gsub(/"""/, "", copy)
        if (indoc) {
            if (delims % 2 == 1) indoc = 0
            # A docstring is prose a reviewer can read, so the marker is
            # honoured on the raw line, unlike the string-blanked case below.
            if ($0 !~ /policy:[[:space:]]*allow-fr/ && is_french($0)) report(FNR, $0)
            next
        }
        if (delims % 2 == 1) indoc = 1
        if (delims > 0) {
            if ($0 !~ /policy:[[:space:]]*allow-fr/ && is_french($0)) report(FNR, $0)
            next
        }
    }

    blanked = blank_strings($0)

    # The marker only counts outside string literals: a marker sitting in
    # data would silently disable the check for the code beside it.
    if (blanked ~ /policy:[[:space:]]*allow-fr/) next

    idx = index(blanked, marker())

    if (idx > 0) {
        comment = substr($0, idx)
        code = substr(blanked, 1, idx - 1)
    } else {
        comment = ""
        code = blanked
    }

    if (is_french(comment) || is_french(code)) report(FNR, $0)
}

END { exit found }
