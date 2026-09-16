use lib <lib>;
use Test;
use nqp;
# Milestone 8, the type state: a type's published facts (method cache,
# type-check cache) live in an immutable TypeState with an Assumption. A
# dispatch program or a site that folded a fact must see the change when
# the type republishes -- adding a method republishes the method cache, and
# nqp::settypecache republishes the type-check cache.
#
# TWO STRUCTURAL REQUIREMENTS, both load-bearing and both invisible from a
# casual read (measured 2026-09-16, see the Phase A ledger, Task 4):
#
# 1. ONE site per half. Each half puts its two checks through the body of
#    ONE sub, so the second check re-enters the very site the loop
#    resolved. Two separate `.gist` (or `nqp::istype`) source locations are
#    two sites, and the second resolves afresh against the new facts --
#    proving nothing, and passing no matter what the site does.
# 2. The republish happens at RUNTIME. `augment class Foo { ... }` is a
#    BEGIN-time construct: it runs before this file's mainline, so the loop
#    would fold the augmented method and there would be nothing to see.
#    `.^add_method` + `.^compose` is what augment does, done here at
#    runtime. (EVAL of an augment is not an option: RakuAST rejects an
#    augment of an external declaration.)
#
# The istype half reads its invocant from a closure rather than a
# parameter: settypecache replaces Bar's whole type-check cache, so a
# `$o` parameter (Any) stops binding Bar right after it.
plan 4;

class Foo { }
sub gist-of($o) { $o.gist }
my $f = Foo.new;
my $r;
$r = gist-of($f) for ^200;
is $r, 'Foo.new', 'gist resolves to Mu.gist before the method is added';
Foo.^add_method('gist', method { 'augmented' });
Foo.^compose;
is gist-of($f), 'augmented',
    'a method-call site resolved before the method cache republished sees the added method';

class Bar { }
class Baz { }
my $b = Bar.new;
sub is-baz() { nqp::istype($b, Baz) }
my $t;
$t = is-baz() for ^200;
is $t, 0, 'istype is false before the type-check cache changes';
nqp::settypecache(Bar, nqp::list(Bar, Baz));
is is-baz(), 1, 'an istype site resolved before settypecache sees the new cache';
