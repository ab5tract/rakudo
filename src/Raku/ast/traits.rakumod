# Done by everything that can have traits applied to it.
class RakuAST::TraitTarget {
    has Mu $!traits;

    # Set the list of traits on this declaration.
    method set-traits(List $traits) {
        my @traits;
        if $traits {
            for self.IMPL-UNWRAP-LIST($traits) {
                unless nqp::istype($_, RakuAST::Trait) {
                    nqp::die('The traits list can only contain RakuAST::Trait objects');
                }
                nqp::push(@traits, $_);
            }
        }
        nqp::bindattr(self, RakuAST::TraitTarget, '$!traits', @traits);
        Nil
    }

    # Add a trait to this declaration.
    method add-trait(RakuAST::Trait $trait) {
        my $traits := $!traits;
        unless nqp::islist($traits) {
            $traits := [];
            nqp::bindattr(self, RakuAST::TraitTarget, '$!traits', $traits);
        }
        nqp::push($traits, $trait);
        Nil
    }

    # Get the list of traits on this declaration.
    method traits() {
        my $traits := $!traits;
        self.IMPL-WRAP-LIST(nqp::islist($traits) ?? $traits !! [])
    }

    # Apply all traits (and already applied will not be applied again).
    method apply-traits(RakuAST::Resolver $resolver, RakuAST::IMPL::QASTContext $context, RakuAST::TraitTarget $target, *%named) {
        if $!traits {
            for $!traits {
                $_.apply($resolver, $context, $target, |%named) unless $_.applied;
            }
        }
        Nil
    }

    # Apply the visitor to each trait on this declaration.
    method visit-traits(Code $visitor) {
        if $!traits {
            for $!traits {
                $visitor($_);
            }
        }
    }
}

# The base of all traits.
class RakuAST::Trait
  is RakuAST::ImplicitLookups
{
    has int $!applied;

    method IMPL-TRAIT-NAME() {
        nqp::die(self.HOW.name(self) ~ ' does not implement IMPL-TRAIT-NAME')
    }

    method PRODUCE-IMPLICIT-LOOKUPS() {
        self.IMPL-WRAP-LIST([
            RakuAST::Var::Lexical::Constant.new('&trait_mod:<' ~ self.IMPL-TRAIT-NAME() ~ '>')
        ])
    }

    # Checks if this trait has been applied already.
    method applied() {
        $!applied ?? True !! False
    }

    # Marks the trait as having been applied. Typically used when the trait is
    # specially handled by a construct rather than actually being dispatched
    # to a trait handler (for example, `is repr` on packages).
    method mark-applied() {
        nqp::bindattr_i(self, RakuAST::Trait, '$!applied', 1);
        Nil
    }

    # Apply the trait to the specified target. Checks if it has been applied,
    # and then applies it.
    method apply(RakuAST::Resolver $resolver, RakuAST::IMPL::QASTContext $context, RakuAST::TraitTarget $target, *%named) {
        unless self.applied {
            self.IMPL-CHECK($resolver, $context, False);
            my $decl-target := RakuAST::Declaration::ResolvedConstant.new:
                compile-time-value => $target.compile-time-value;
            my $args := self.IMPL-TRAIT-ARGS($resolver, $decl-target);
            for %named {
                nqp::push(
                    self.IMPL-UNWRAP-LIST($args.args),
                    RakuAST::ColonPair::Value.new(:key(nqp::iterkey_s($_)), :value(nqp::iterval($_)))
                );
            }
            $args.IMPL-CHECK($resolver, $context, False);
            $target.IMPL-BEGIN-TIME-CALL(
              self.get-implicit-lookups.AT-POS(0),
              $args,
              $resolver,
              $context
            );
            self.mark-applied;
        }
    }
}

# The is trait.
class RakuAST::Trait::Is
  is RakuAST::Trait
  is RakuAST::BeginTime
{
    has RakuAST::Name $.name;
    has RakuAST::Circumfix $.argument;
    has RakuAST::Term::Name $.resolved-name;

    method new(RakuAST::Name :$name!, RakuAST::Circumfix :$argument) {
        my $obj := nqp::create(self);
        nqp::bindattr($obj, RakuAST::Trait::Is, '$!name', $name);
        nqp::bindattr($obj, RakuAST::Trait::Is, '$!argument',
            $argument // RakuAST::Circumfix);
        $obj
    }

    method PERFORM-BEGIN(RakuAST::Resolver $resolver, RakuAST::IMPL::QASTContext $context) {
        # See if the name resolves as a type and commit to that.
        my $resolution := $resolver.resolve-name-constant($!name);
        if nqp::istype($resolution, RakuAST::CompileTimeValue) &&
                !nqp::isconcrete($resolution.compile-time-value) {
            my $resolved-name := RakuAST::Type::Simple.new($!name);
            $resolved-name.set-resolution($resolution);
            nqp::bindattr(self, RakuAST::Trait::Is, '$!resolved-name',
                $resolved-name);
        }
        Nil
    }

    method IMPL-TRAIT-NAME() { 'is' }

    method IMPL-TRAIT-ARGS(RakuAST::Resolver $resolver, RakuAST::Node $target) {
        my @args := [$target];
        if $!resolved-name {
            @args.push($!resolved-name);
        }
        else {
            my $key := $!name.canonicalize;
            @args.push(
                $!argument
                ?? RakuAST::ColonPair::Value.new(:$key, :value($!argument))
                !! RakuAST::ColonPair::True.new($key)
            );
        }
        RakuAST::ArgList.new(|@args)
    }

    method visit-children(Code $visitor) {
        $visitor($!name);
        $visitor($!argument) if $!argument;
    }
}

class RakuAST::Trait::Type
  is RakuAST::Trait
{
    has RakuAST::Type $.type;

    method new(RakuAST::Type $type) {
        my $obj := nqp::create(self);
        nqp::bindattr($obj, RakuAST::Trait::Type, '$!type', $type);
        $obj
    }

    method IMPL-TRAIT-ARGS(RakuAST::Resolver $resolver, RakuAST::Node $target) {
        RakuAST::ArgList.new($target, $!type)
    }

    method visit-children(Code $visitor) {
        $visitor($!type);
    }
}

# The hides trait.
class RakuAST::Trait::Hides
  is RakuAST::Trait::Type
{
    method IMPL-TRAIT-NAME() { 'hides' }
}

# The does trait.
class RakuAST::Trait::Does
  is RakuAST::Trait::Type
{
    method IMPL-TRAIT-NAME() { 'does' }
}

# The of trait.
class RakuAST::Trait::Of
  is RakuAST::Trait::Type
{
    method IMPL-TRAIT-NAME() { 'of' }
}

# The returns trait.
class RakuAST::Trait::Returns
  is RakuAST::Trait::Type
{
    method IMPL-TRAIT-NAME() { 'returns' }
}

# The will trait.
class RakuAST::Trait::Will
  is RakuAST::Trait
{
    has str $.type;
    has RakuAST::Expression $.expr;

    method new(str $type, RakuAST::Expression $expr) {
        my $obj := nqp::create(self);
        nqp::bindattr_s($obj, RakuAST::Trait::Will, '$!type', $type);
        nqp::bindattr($obj, RakuAST::Trait::Will, '$!expr', $expr);
        $obj
    }

    method IMPL-TRAIT-NAME() { 'will' }

    method IMPL-TRAIT-ARGS(RakuAST::Resolver $resolver, RakuAST::Node $target) {
        RakuAST::ArgList.new($target, RakuAST::ColonPair::Value.new(:key($!type), :value($!expr)))
    }

    method visit-children(Code $visitor) {
        $visitor($!expr);
    }
}

class RakuAST::Trait::Handles
  is RakuAST::Trait
{
    has RakuAST::Term $.term;

    method new(RakuAST::Term $term) {
        my $obj := nqp::create(self);
        nqp::bindattr($obj, RakuAST::Trait::Handles, '$!term', $term);
        $obj
    }

    method IMPL-TRAIT-NAME() { 'handles' }

    method IMPL-TRAIT-ARGS(RakuAST::Resolver $resolver, RakuAST::Node $target) {
        my $block := RakuAST::Block.new:
                        body => RakuAST::Blockoid.new:
                            RakuAST::StatementList.new:
                                RakuAST::Statement::Expression.new:
                                    expression => $!term;
        RakuAST::ArgList.new($target, $block);
    }

    method visit-children(Code $visitor) {
        $visitor($!term);
    }
}
