# Milestone 5 (RakuObject layout) — ledger

Running record for the plan
`docs/superpowers/plans/2026-09-11-jvm-milestone-5-rakuobject-layout.md`.

## Task 1 — baseline numbers, pinning tests, attribute bench

All numbers below were taken on the untouched milestone 4 build in the
worktree `.claude/worktrees/jesp-direct-lazy-records` (rakudo
`worktree-jesp-direct-lazy-records`, nqp `jesp-direct-lazy-records`), Oracle
GraalVM, one run each, before any milestone 5 change.

### plusquick before

`RAKUDO_RAKUAST=1 NQP_DISPATCH_STATS=1 ./rakudo-j docs/bench/jesp/plusquick.raku`

| road | before (ns/op) |
| --- | --- |
| `$a + $b` (plusquick) | 82.625 |

Dispatch stats from the same run: `hits=90247539 misses=11614 slowEvals=364
invokes=13845 directs=13826 noTarget=19 badExpectation=0 notCodeRef=0`,
`byKind[value,syscall,mapped,invoke,resumable]=[0, 95661, 45117402, 13446,
45021030]`.

### attrquick before

`RAKUDO_RAKUAST=1 ./rakudo-j docs/bench/jesp/attrquick.raku`

| road | before (ns/op) |
| --- | --- |
| getattr | 68.75 |
| bindattr | 57.05 |
| getattr_i | 107.3 |
| decont | 78.35 |
| bigint+ | 172.4 |
| create | 573.25 |

No road is above 1000 ns/op, so all six are fair regression targets.
`create` is the slowest by a wide margin and is the one the storage-class
family is meant to move.

### Adjustments made to the brief's code (milestone 4 is the truth)

1. **`docs/bench/jesp/attrquick.raku`** — the brief's `my $p = P.new(...)` /
   `my $n = N.new(...)` made the bench die at line 1 with

   ```
   No such attribute '$!a' for this object (looked in P; has [null: $!value,$!descriptor])
   ```

   because `=` puts the object in a `Scalar` and `nqp::getattr` then looks at
   the container. Both are bound with `:=` instead; the `$scalar` used by the
   `decont` road stays assigned, since that road wants the container.

2. **`nqp/t/jvm/17-object-layout.t`, the multiple-inheritance type** — NQP's
   `class` declaration accepts only one `is`, so `class MAB is MA is MB`
   fails to parse (`Malformed package declaration`). The two-parent type is
   built through the HOW (`NQPClassHOW.new_type` + two `add_parent` calls +
   `compose`), the way `t/nqp/058-attrs.t` builds its types. The assertion is
   unchanged: attributes of both parents and of the child resolve by name.

3. **`nqp/t/jvm/17-object-layout.t`, the type-object error text** — the brief
   expected `does not support attributes`; milestone 4 says
   `Cannot look up attributes in a type object`. Expectation changed to the
   runtime's wording.

4. **`nqp/t/jvm/17-object-layout.t`, the unbound `$` attribute** — the brief
   expected `nqp::isnull(nqp::getattr($av, AV, '$!s'))`. Milestone 4 hands
   back the `NQPMu` type object, not a null. Probed behaviour:

   | probe | milestone 4 |
   | --- | --- |
   | `attrinited($av, AV, '$!s')` before any read | 0 |
   | `attrinited($av, AV, '@!a')` before any read | 1 (auto-vivified at creation) |
   | `getattr($av, AV, '$!s')` | `NQPMu`, `isconcrete` 0, `isnull` 0 |
   | `attrinited($av, AV, '$!s')` after that read | 1 (the read initializes the slot) |

   The one line became two: `attrinited` is 0 until the slot is read or
   bound, and the read hands back `NQPMu`. `plan()` therefore went from the
   brief's 46 to **47**.

Everything else in the brief's three test files ran green on milestone 4 as
written — including the four error texts (`No such attribute '$!nope'`,
`Cannot access a reference attribute as a native attribute` twice,
`Incompatible MROs`), the sized-native truncation (int8/uint8 both 44 from
300), hints (`attrhintfor` is the slot number, parents first, `-1` unknown),
clone of inline plus both overflow arrays, and the delegates.

### Test files and their pinned counts (milestone 4, all green)

| file | plan | result |
| --- | --- | --- |
| `nqp/t/jvm/17-object-layout.t` | 47 | 47/47 |
| `nqp/t/jvm/18-rebless-layout.t` | 14 | 14/14 (no adjustment needed) |
| `t/02-rakudo/mixin-identity.t` | 8 | 8/8 (no adjustment needed) |

`t/02-rakudo/mixin-identity.t` needed no drop: on the JVM `does` keeps both
identity and `WHICH`, and `but` leaves the original's `WHICH` and type alone.

Commands:

```
RAKUDO_RAKUAST=1 NQP_DISPATCH_STATS=1 ./rakudo-j docs/bench/jesp/plusquick.raku
RAKUDO_RAKUAST=1 ./rakudo-j docs/bench/jesp/attrquick.raku
cd nqp && ./nqp-j-gradle t/jvm/17-object-layout.t
cd nqp && ./nqp-j-gradle t/jvm/18-rebless-layout.t
RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/mixin-identity.t
```
