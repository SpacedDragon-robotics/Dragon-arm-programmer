// SyntaxHighlight.js
//
// Minimal C/C++ tokeniser for the generated sketch. Produces one HTML string
// per source line, which the code view renders as rich text. Block comments
// carry state across lines, so the big header comment highlights correctly.

.pragma library

var KEYWORDS = [
    "alignas", "auto", "break", "case", "class", "const", "constexpr", "continue",
    "default", "delete", "do", "else", "enum", "extern", "false", "for", "goto",
    "if", "inline", "namespace", "new", "nullptr", "operator", "private", "public",
    "register", "return", "signed", "sizeof", "static", "struct", "switch",
    "template", "this", "true", "typedef", "typename", "union", "unsigned",
    "using", "virtual", "volatile", "while"
]

var TYPES = [
    "bool", "char", "double", "float", "int", "long", "short", "size_t", "void",
    "int8_t", "int16_t", "int32_t", "int64_t",
    "uint8_t", "uint16_t", "uint32_t", "uint64_t",
    "String", "byte", "word"
]

function escapeHtml(text) {
    return text.replace(/&/g, "&amp;")
               .replace(/</g, "&lt;")
               .replace(/>/g, "&gt;")
               .replace(/ /g, "&nbsp;")
}

function span(color, text) {
    return "<span style=\"color:" + color + "\">" + escapeHtml(text) + "</span>"
}

function isIdentStart(c) {
    return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c === "_"
}

function isIdentChar(c) {
    return isIdentStart(c) || (c >= "0" && c <= "9")
}

function isDigit(c) {
    return c >= "0" && c <= "9"
}

function classifyWord(word, nextChar, colors) {
    if (KEYWORDS.indexOf(word) !== -1)
        return colors.keyword
    if (TYPES.indexOf(word) !== -1)
        return colors.type
    // SCREAMING_CASE is a constant in the generated sketch.
    if (word === word.toUpperCase() && word.length > 1 && /[A-Z]/.test(word))
        return colors.constant
    if (nextChar === "(")
        return colors.func
    return colors.text
}

// Returns { html, inBlockComment }
function highlightLine(line, inBlockComment, colors) {
    var html = ""
    var i = 0
    var sawPreprocessor = false

    if (inBlockComment) {
        var close = line.indexOf("*/")
        if (close === -1)
            return { html: span(colors.comment, line), inBlockComment: true }
        html += span(colors.comment, line.substring(0, close + 2))
        i = close + 2
        inBlockComment = false
    }

    while (i < line.length) {
        var c = line.charAt(i)
        var c2 = line.charAt(i + 1)

        // Line comment
        if (c === "/" && c2 === "/") {
            html += span(colors.comment, line.substring(i))
            break
        }

        // Block comment
        if (c === "/" && c2 === "*") {
            var end = line.indexOf("*/", i + 2)
            if (end === -1) {
                html += span(colors.comment, line.substring(i))
                return { html: html, inBlockComment: true }
            }
            html += span(colors.comment, line.substring(i, end + 2))
            i = end + 2
            continue
        }

        // Preprocessor directive
        if (c === "#" && html.replace(/<[^>]*>/g, "").trim().length === 0) {
            var j = i + 1
            while (j < line.length && isIdentChar(line.charAt(j)))
                j++
            html += span(colors.preprocessor, line.substring(i, j))
            sawPreprocessor = true
            i = j
            continue
        }

        // Include path <...>
        if (sawPreprocessor && c === "<") {
            var gt = line.indexOf(">", i)
            if (gt !== -1) {
                html += span(colors.string, line.substring(i, gt + 1))
                i = gt + 1
                continue
            }
        }

        // String / character literal
        if (c === "\"" || c === "'") {
            var quote = c
            var k = i + 1
            while (k < line.length) {
                if (line.charAt(k) === "\\") {
                    k += 2
                    continue
                }
                if (line.charAt(k) === quote) {
                    k++
                    break
                }
                k++
            }
            html += span(colors.string, line.substring(i, k))
            i = k
            continue
        }

        // Number, including 0x.., trailing f / U / L
        if (isDigit(c) || (c === "." && isDigit(c2))) {
            var n = i
            while (n < line.length && /[0-9a-fA-FxXuUlLfF.]/.test(line.charAt(n)))
                n++
            html += span(colors.number, line.substring(i, n))
            i = n
            continue
        }

        // Identifier
        if (isIdentStart(c)) {
            var m = i
            while (m < line.length && isIdentChar(line.charAt(m)))
                m++
            var word = line.substring(i, m)
            var next = line.charAt(m)
            html += span(classifyWord(word, next, colors), word)
            i = m
            continue
        }

        // Punctuation and whitespace
        var p = i
        while (p < line.length) {
            var pc = line.charAt(p)
            if (isIdentStart(pc) || isDigit(pc) || pc === "\"" || pc === "'" || pc === "#")
                break
            if (pc === "/" && (line.charAt(p + 1) === "/" || line.charAt(p + 1) === "*"))
                break
            if (sawPreprocessor && pc === "<")
                break
            p++
        }
        if (p === i)
            p = i + 1
        html += span(colors.punctuation, line.substring(i, p))
        i = p
    }

    return { html: html, inBlockComment: inBlockComment }
}

function highlightDocument(text, colors) {
    var lines = text.split("\n")
    var out = []
    var inBlockComment = false
    for (var i = 0; i < lines.length; ++i) {
        var r = highlightLine(lines[i], inBlockComment, colors)
        out.push(r.html)
        inBlockComment = r.inBlockComment
    }
    return out
}
