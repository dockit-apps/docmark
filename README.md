# DocMark

A small native Markdown editor and viewer for macOS. It opens a Markdown file showing the rendered
result, you edit in place, and syntax appears only around the caret. The file stays plain Markdown.

It also edits other UTF-8 text files, colouring code in the languages listed below, and shows PDFs
read-only.

Typing `/` on an empty line lists blocks to insert, such as headings, tables and code. In a table's
source, Tab moves between cells and adds a row after the last one.

Code blocks are coloured for C, C++, Java, JavaScript, TypeScript, Swift, Python, Go, Rust, shell, SQL,
JSON and YAML when the opening fence names the language, and in files with those extensions.

Command-P prints through the system panel, which also saves PDFs. Text prints rendered, in a light
palette for paper, and File > Export as PDF… goes straight to a file.

## Build and install

```bash
scripts/build-app.sh release --install
```

Then in Finder: Get Info on a `.md` file → Open With → DocMark → Change All.

Installing also adds the `dm` command, as a link at `~/.local/bin/dm`:

```bash
dm notes.md
```

It opens the text and PDF files it is given and creates missing ones that have an extension. Without
arguments it opens DocMark, which lists recent files if it wasn't running.

## Test

Swift Testing's macros are outside the default search path with Command Line Tools only:

```bash
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

## Layout

- `Sources/DocMarkCore`: parsing Markdown into styled ranges and hideable syntax, Enter rules, file bytes
- `Sources/DocMark`: AppKit document, text view, rendering and menus
