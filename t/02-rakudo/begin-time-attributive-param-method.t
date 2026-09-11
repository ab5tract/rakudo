use Test;

plan 6;

# A `method` with an attributive parameter, built inside a BEGIN block in a
# class body, must not force the enclosing class to compose. Composing it
# mid-body would finalize the class before its remaining members are added,
# so any method declared after the BEGIN block would go missing.
{
    my class C {
        has $!x;
        BEGIN my $m = method ($!x) { $!x };
        method later { 'installed' }
    }
    is C.new.later, 'installed',
        'a method after a BEGIN-built attributive-param method is still installed';
}

# The attribute the parameter binds into must still work at runtime.
{
    my class C {
        has $.v;
        BEGIN my $store = method ($!v) { $!v };
        method run { $store(self, 42) }
    }
    is C.new.run, 42,
        'a BEGIN-built attributive-param method binds its attribute';
}

# The shape from PDF::Content::Ops: a table of anonymous methods built in a
# BEGIN block, whose signatures carry a slurpy attributive parameter and a
# `where` clause that calls a private method declared later in the class.
{
    my class C {
        has @!colors;
        my Method %store;
        BEGIN %store = (
            fill => method (*@!colors where self!ok($_)) { @!colors.join(',') },
        );
        method run { %store<fill>(self, 1, 2, 3) }
        method !ok(@c) { True }
    }
    is C.new.run, '1,2,3',
        'a BEGIN-built method with a where-clause private call composes and runs';
}

# The normal (non-BEGIN) path is unchanged.
{
    my class C {
        has @!colors;
        my $m = method (*@!colors) { @!colors.elems };
        method run { $m(self, 1, 2) }
    }
    is C.new.run, 2,
        'the non-BEGIN attributive-param method path still works';
}

# The other half of the same fix: a parameter DEFAULT holding a code
# object. The default is a nested block reached from the signature
# prologue, so it records a deferred code-ref slot exactly as a `where`
# clause does; losing that slot left the placeholder qbid 0 -- the unit's
# mainline -- in the CODEREF cell, and calling the default ran the whole
# compilation unit instead of the block.
{
    is BEGIN { sub g($x = { 42 }) { $x() }; g() }, 42,
        'a BEGIN-time parameter default holding a code object calls that code';
}

# An attributive parameter naming an attribute the class does not have must
# still be a compile error, not a silent pass.
{
    throws-like
        'class C { has $!x; BEGIN my $m = method ($!nope) { } }',
        X::Attribute::Undeclared,
        'an undeclared attribute in a BEGIN-built method is still rejected';
}
