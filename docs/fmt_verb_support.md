# Gada.Std.Fmt — supported verb set (v1)

Go's `fmt` verbs and flags, as ported in `runtime/src/gada-std-fmt.*`.
Anything not listed here is a documented v1 limitation
(see `docs/imperfections.md`).

## Arguments

Go's variadic `...any` is `Fmt.Arg_Array` — an array of the variant
record `Fmt.Arg`, built with the `A` constructor overloads:

| Go value            | Ada constructor          | `Arg.K`     |
|---------------------|--------------------------|-------------|
| `int`               | `A (42)`                 | `Int_Arg`   |
| `float64`           | `A (3.14)`               | `Float_Arg` |
| `string`            | `A ("hi")`               | `Str_Arg`   |
| `bool`              | `A (true)`               | `Bool_Arg`  |
| `byte`/`rune`       | `A ('x')`                | `Char_Arg`  |
| pointer             | `A (X'Address)`          | `Ptr_Arg`   |
| `error`             | `A (Err)`                | `Err_Arg`   |

## Verbs

| Verb | Meaning | Notes |
|------|---------|-------|
| `%v` | default format | int→decimal, float→`%g` shortest, string→itself, bool→`true`/`false`, error→its message, ptr→`%p` |
| `%s` | string | `Str_Arg`, `Err_Arg` |
| `%q` | double-quoted Go string literal | via `strconv.Quote` |
| `%d` | decimal integer | `Int_Arg` |
| `%b` `%o` `%x` `%X` | binary / octal / hex | `Int_Arg`; `#` adds `0b`/`0o`/`0x`/`0X` |
| `%c` | character | `Int_Arg` (code point) or `Char_Arg` |
| `%t` | boolean | `true` / `false` |
| `%f` `%F` | fixed float | default precision 6 |
| `%e` `%E` | scientific | default precision 6 |
| `%g` `%G` | shortest of e/f | default precision −1 (round-trip) |
| `%p` | pointer | `0x` + hex address |
| `%w` | wrap error | `Errorf` only: the error becomes the cause (`errors.Is`/`Unwrap` see it) |
| `%%` | literal `%` | |

## Flags and width

- Flags: `-` (left-justify), `+` (always sign), ` ` (space for positive
  sign), `#` (alternate base prefix), `0` (zero-pad, after sign/prefix).
  Integers and floats both honour `+`/` `/`0`; float `±Inf`/`NaN` are
  only ever space-padded, `Inf` always carries its sign and `NaN` shows
  one only under `+`/` ` (Go's `fmtFloat`).
- Width: decimal digits, e.g. `%5d`. Precision: `%.2f`, `%.3s`
  (truncates strings).
- `*` (width from argument) is **not** supported in v1.

## Print family

`Print`/`Sprint` put a space between two operands only when neither is
a string (`Sprint("a", "b") = "ab"`, `Sprint(1, 2) = "1 2"`);
`Println`/`Sprintln` always separate operands and end with a newline.

## Errors

- A verb that does not apply to the argument kind renders Go-style
  `%!z(BADVERB)`.
- More verbs than arguments renders `%!(NOVERB)`.

## Scanf (v1)

`Sscanf (S, Format, Args, N, Err)` parses whitespace-separated tokens
from `S` into a pre-sized `Arg_Array` whose kinds the caller fixes:
`%d`→`Int_Arg`, `%f`/`%g`/`%e`/`%v`→`Float_Arg`, `%s`→`Str_Arg`,
`%t`→`Bool_Arg`, `%c`→`Char_Arg`. `N` is the number of items parsed;
`Err` reports a bad token, a kind mismatch, or premature EOF.
Newline handling, `%x` scanning, and scanning into structs are not
supported in v1.
