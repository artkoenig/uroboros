# csvfmt

A benchmark task: one greenfield program, small enough for a single run and
wide enough that a process shows in the result. Give it to a development
process unchanged, in an empty repository, and judge what comes back against
the criteria below.

Build a command-line program that reads CSV and prints it as an aligned text
table. Greenfield: the repository starts empty.

## Acceptance criteria

1. The program is invoked as `csvfmt [OPTIONS] [FILE]`. With no FILE, or with
   `-` as FILE, it reads from stdin.
2. It parses CSV per RFC 4180: a field wrapped in double quotes may contain the
   delimiter, line breaks, and doubled double quotes (`""`) standing for one
   literal quote.
3. Every column is printed as wide as its widest value, and columns are
   separated by exactly two spaces. No output line has trailing whitespace.
4. A column whose values are all numbers is right-aligned; every other column is
   left-aligned. The header cell does not count towards this decision.
5. `--delimiter <char>` (short `-d`) sets the field delimiter. The default is
   `,`.
6. By default the first row is a header and is separated from the data by a rule
   line of `-` characters, one rule segment per column, as wide as the column.
   `--no-header` treats the first row as data and prints no rule.
7. `--max-width <n>` truncates any field wider than `n` to exactly `n`
   characters, the last three of which are `...`.
8. A row with fewer fields than the widest row is padded with empty fields. A row
   with more fields widens the table for every row.
9. A line break inside a quoted field is printed as the two characters `\` and
   `n`, so every record occupies exactly one output line.
10. A UTF-8 BOM at the start of the input and CRLF line endings are recognised
    and do not reach the output.
11. Column width is measured in display width: East Asian wide characters count
    as 2, combining marks as 0.
12. Empty input produces empty output and exit code 0.
13. Malformed CSV — for instance a quoted field that is never closed — writes a
    message to stderr and exits with code 1.
14. `--help` writes a usage summary to stdout and exits with code 0.
15. The program runs on Node.js 20 or newer with no runtime dependencies outside
    the standard library. Tests run with `node --test` via `npm test`.
