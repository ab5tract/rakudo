multi f(Int $x) { "int:$x" }
multi f(Any $x) { "any:$x" }
multi g(Int $x where * > 10) { "big" }
multi g(Int $x) { "small" }
class A { method m($x) { "A:$x" } }
class B is A { method m($x) { "B:" ~ callsame() } }
class C is A { method m($x) { "C:" ~ nextsame() } }
class D is A { method m($x) { "D:" ~ callwith($x + 1) } }
multi h(Int $x) { "h-int:" ~ (nextsame() // "none") }
multi h(Any $x) { "h-any" }
sub w($x) { $x * 2 }
&w.wrap(-> $x { "wrapped:" ~ callsame() });
say f(1), " ", f("s");
say g(20), " ", g(5);
say B.new.m(1), " ", C.new.m(2), " ", D.new.m(3);
say h(7), " ", h("q");
say w(21);
my &ff = &f;
my $err = try { ff(); CATCH { default { .^name } } };
say $err // $!.^name;
sub t(Int $x) { $x }
my &tt = &t;
say (try tt("nope")) // $!.message.lines[0];
say "loop:", (1..2000).map({ f($_) ~ g($_) ~ B.new.m($_) ~ h($_) }).elems;
