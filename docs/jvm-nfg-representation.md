# NFG on the JVM — representation decision

Status: **decision draft, 2026-09-06.** The one-page artifact the plan calls
for before any op is written (see the `nfg-truffle-direction` /
`full-suite-run-2026-09` memories). Sibling of `docs/jvm-eval-server.md`,
`docs/jvm-newdisp-port.md`.

## Why this exists

Raku's string model is **NFG** — Normal Form Grapheme. A string is a sequence
of *graphemes* (extended grapheme clusters), each addressed by a single
integer index, `.chars` counts graphemes, `substr`/`index`/regex positions are
all grapheme-indexed, and a grapheme built from more than one codepoint (base +
combining marks, or a fused `\r\n`) is represented by a single **synthetic
codepoint** — a negative id allocated from a process-wide table that maps the id
back to its codepoint sequence. MoarVM implements this natively and passes all
of roast's S15/S32 Unicode suite; this backend does not, which is the entire
NFG/Unicode/collation/encoding failure cluster in
`docs/jvm-full-suite-run-2026-09-05.md`.

## Where the backend is today (verified 2026-09-06)

Strings are bare `java.lang.String`, **UTF-16-indexed**, everywhere:

- Carrier: `P6strInstance.value: String`, `SixModelObject.get_str/set_str:
  String`, `ThreadContext.nativeS: String`, `P6str` inlines a `Ljava/lang/String;`
  field. The wire/native-string type is Java `String` from top to bottom.
- Ops (`nqp/.../runtime/Ops.kt`) operate on UTF-16 code units:
  `chars()` = `val.length`; `substr3` = `val.substring(i, j)`;
  `ordat(str, off)` = `codePointAt(off)` with a UTF-16 `off`. So an astral char
  is two "chars", a combining sequence is N "chars", and a slice can bisect a
  surrogate pair or a mark. `java.text.Normalizer` is used ad hoc in `codes`,
  `ordbaseat`, `strtocodes`, `encoderep` — there is **no** grapheme
  segmentation, **no** synthetic table, **no** `BreakIterator`, **no** ICU jar.

There is **no** grapheme layer to retrofit — this is a from-scratch build. The
one asset already in place: **`TruffleString` is on the classpath today**
(ships inside `truffle-api-25.2.4.jar`, already a `nqp-truffle` dependency,
synced into all three runtime dirs). No new dependency is needed.

## The fork this resolves

The memory left one architectural question open: *int[] grapheme buffers + a
shared synthetic table* vs *TruffleString-backed views*. The deciding fact:

> **TruffleString has no grapheme notion at all.** It stores codepoints/bytes
> under a fixed encoding and indexes by them. A synthetic grapheme — the fusion
> of several codepoints into one addressable unit — has no representation inside
> a TruffleString. Grapheme identity must live in a layer *above* one either way.

So "TruffleString-backed views" still needs the full grapheme index **and** the
synthetic table bolted on the side, and buys only storage + encoding + equality.
Whereas a grapheme-indexed buffer gets O(1) grapheme addressing for free — which
is what almost every string op needs. The buffer must be primary.

## Decision

**Primary carrier: a grapheme-indexed value, `NFGString`, holding
`int[] graphemes` where each element is a real codepoint (`>= 0`) or a synthetic
id (`< 0`). TruffleString is used at the two boundaries where it actually
earns its place — the ASCII/BMP fast path and encode/decode — not as the
grapheme carrier.** Kotlin, in `nqp-runtime` (the value type) with the synthetic
table reachable from both `nqp-runtime` and `nqp-truffle`.

This is MoarVM's model (`MVMString`: grapheme blob + global synthetic table),
transliterated, which is the point — roast was written against exactly these
semantics.

### The value type

```
NFGString                         // immutable
  ├─ flat fast path:  a TruffleString (or char[]) + FLAT flag
  │     when every grapheme is one codepoint and there are no synthetics
  │     (ASCII, Latin-1, BMP-without-combining — the overwhelming majority:
  │      source, identifiers, most test data). grapheme index == codepoint
  │      index; .chars is O(1) from the TruffleString's codepoint length;
  │      NO int[] materialized. This is moar's blob_ascii/blob_32 fast path.
  └─ general form:  int[] graphemes  (+ optional strand rope for cheap concat)
        materialized only when a combining sequence or synthetic appears.
        graphemes[i] >= 0  → that Unicode codepoint IS the grapheme
        graphemes[i] <  0  → synthetic id; table lookup gives the codepoint run
```

`.chars` = number of graphemes (buffer length, or codepoint length when flat).
`substr`/`index`/`ordat`/regex `.from`/`.to` all index `graphemes` directly —
O(1), and correct by construction.

### The synthetic table (the shared mutable state to get right)

- Process-wide, append-only: `synthId (< 0) → int[] codepoints` (the fused
  sequence, e.g. base+combiners, or `[0x0D, 0x0A]` for CRLF), plus the reverse
  map `codepoint-sequence → synthId` for interning so equal graphemes share an
  id (equality/hashing stay integer compares).
- **Must survive across eval-server runs but never be reset per run.** Unlike
  the resolution caches that leaked (`evalserver-leak-hunting`:
  `NqpGrammarEngine.STATES`, `WvalSite`, etc.), the synth table holds no
  run-owned objects — only immutable `int[]` codepoint sequences and boxed ids.
  It is legitimately process-global and monotonic (bounded by the distinct
  synthetics the workload actually forms), so it does **not** register with
  `DispatchBootstrap.registerResettable`. Document this explicitly so a future
  leak hunt doesn't "fix" it by clearing it — clearing it would invalidate every
  live synthetic id.
- Concurrency: a `ConcurrentHashMap` + atomic id counter; ids never reused.

### Normalization & segmentation

- Normalization: `java.text.Normalizer` (NFC/NFD/NFKC/NFKD) over codepoint runs —
  already the tool in use, no new dep. NFG itself = NFC + then fuse each
  extended grapheme cluster spanning >1 codepoint into a synthetic.
- Segmentation (cluster boundaries): the target roast files include
  `GraphemeBreakTest-0..3`, so we implement the **UAX#29 extended grapheme
  cluster** algorithm directly against the UCD tables (the property data is the
  same UCD the `t/09-moar` `General_Category`/`NAME` tests already need).
  `java.text.BreakIterator.getCharacterInstance` is a fallback/cross-check but
  its cluster rules lag the UCD version, so the hand table is authoritative.
- **Pin the UCD version to MoarVM's snapshot** — collation, GraphemeBreak, and
  the property tests are all version-sensitive; a mismatch shows up as a handful
  of off-by-one property failures, not a crash.

### Encodings ride on the same layer

`utf8`, `utf8-c8`, `utf16`, `utf32`, and the legacy CJK encodings (S32-str
`gb18030`/`gb2312`/`shiftjis`) are decode(bytes)→NFGString and
NFGString→encode(bytes). TruffleString's `SwitchEncoding`/`GetCodeRange` machinery
is the right engine for the Unicode encodings on the *codepoint* stream feeding
the grapheme builder. `utf8-c8` (round-trips invalid bytes via synthetics in the
`0x10FFFF+` private plane) rides the synthetic table directly.

## Migration shape (the op surface is the cost, not the value type)

The value type is a week; the surface is the project. Every `String`-typed op
signature and the three `String` carriers (`get_str/set_str`, `nativeS`,
`P6str` inline field) become `NFGString`-typed. Phasing to keep the gate green
(`t/01-sanity` 25/25) throughout, validated cheaply on one warm eval server over
`t/spec/S15-*` + `t/spec/S32-str` (`nqp-runtime:jar syncRuntimeJars` ~10s,
restart server):

1. **`NFGString` + synthetic table + flat fast path**, with a `String` interop
   in/out so nothing else changes yet. Prove: `chars`/`substr`/`ordat` on
   astral + combining inputs, GraphemeBreakTest-0.
2. **Repoint the carriers** (`P6strInstance`, `nativeS`, `get_str/set_str`,
   `P6str` inline) to `NFGString`; bridge at the JVM-`String` FFI edges
   (source read, `say`, NativeCall, serialization) with explicit decode/encode.
3. **Grapheme-ize the ops** in dependency order: `chars`/`codes` → `substr`/
   `index`/`substr-eq` → `ord`/`chr`/`ordbaseat` → case/fold/`comb`/`val` →
   normalization ops → encodings. Each op differentially checked against its
   moar answer (roast is the oracle; moar passes all of these).
4. **Regex engine** grapheme positions: retire the CRLF pseudo-codepoint
   emulation (`RxProgram.CRLF`, `nfg-truffle-direction`) once real synthetics
   carry `\r\n`; un-skip `t/02-rakudo/regex-crlf-grapheme.t` test 3 (grapheme
   `.from`/`.to`).
5. **Serialization**: strings serialize as their grapheme/synthetic form so a
   precompiled setting round-trips synthetics (see the jar-sidecar precomp,
   `phase4-progress`).

Target checklist = the ~40 files in `nfg-truffle-direction` (S15-nfg 21,
S15-normalization 5, S15-unicode-information 3, S32-str Collation+encodings+
fc/comb/val/numeric, t/09-moar UCD-data). Diff against
`docs/jvm-full-suite-run-2026-09-05.md` after each phase.

## Discovered constraint (2026-09-06): the regex engine gates the indexing ops

An attempt to grapheme-ize the value-level ops *first* (rewrite `Ops.chars`/
`substr`/`index`/`ordat`/`eqat` bodies, signatures unchanged, so both codegen
paths pick them up via the classlib registry) **broke the compiler build**. The
regex/grammar engine — `Cursor.nqp` plus the Truffle `RxCursor`/`RxDescriptor`
and the bytecode regex path — tracks target positions in **UTF-16 units**
(`RxDescriptorCheck.eos() = target.length()`, `RxCursor.OfString` indexes by
`charAt`) and extracts captures / matches literals with the *same* `nqp::substr`
/ `nqp::eqat` / `nqp::index` ops that Raku values use. Grapheme-indexing those
ops desyncs the two spaces at any astral character in **source**: an astral char
(`👍`, 2 UTF-16 units / 1 grapheme) in a comment in `src/Raku/Grammar.nqp` made
the tokenizer grab a trailing space into the next identifier (`$*IN-DECL ` →
"undeclared variable"). There is no separable op to split "engine UTF-16 substr"
from "Raku grapheme substr" — it is one op.

**Consequence for sequencing:** the regex engine's position model must move to
grapheme indices *before* (or together with) the value-level indexing ops —
phase 4 gates phase 3 for anything position-based. What is safe to do without the
engine port, and was kept: the **non-indexing** NFG semantics — canonical
(NFC) string equality/ordering (`iseq_s`/`cmp_s`/…) and the normalization-form
methods (`.NFC`/`.NFD`/`.NFKC`/`.NFKD`/`.ords` via `nqp::strtocodes`). Those move
the S15-normalization and equality tests without touching positions. The
grapheme-indexed `chars`/`substr`/`index` await the engine port.

## Open questions for sign-off

1. **Flat fast-path backing — TruffleString vs `char[]`/`String`.** TruffleString
   gives interning + free encoding conversions + PE-friendliness (the "Truffle
   goodness" goal) at the cost of construction overhead on every flat string;
   `char[]` is cheaper to build but hands nothing to the encode path. Leaning
   TruffleString for the goal's sake, measured on the CORE.c parse (strings are
   hot there). **This is the main thing to confirm before phase 1.**
2. **Strand ropes for concat now or later** — moar has them; we can ship the
   flat/int[] forms first and add strands only if concat shows up hot.
3. **UCD version** — pin to whatever MoarVM's current snapshot ships; confirm
   the exact version so GraphemeBreak/collation/property tests line up.
