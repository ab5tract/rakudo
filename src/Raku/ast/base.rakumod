# The base of all RakuAST nodes.
class RakuAST::Node {
    # What type does evaluating this node produce, if known?
    method type() { Mu }

    # Is evaluating this pure (that is, if its evaluation is elided due to
    # not being used, then the program will behave the same)?
    method pure() { False }

    # Visits all child nodes of this one, applying the selected block.
    # This is a non-recursive operation.
    method visit-children($visitor) {
        # Default is that we have no children to visit.
        Nil
    }

    # Resolves all nodes beneath this one, recursively, using the specified
    # resolver.
    method resolve-all(RakuAST::Resolver $resolver) {
        if nqp::istype(self, RakuAST::Lookup) && !self.is-resolved {
            self.resolve-with($resolver);
        }
        if nqp::istype(self, RakuAST::ImplicitLookups) {
            self.resolve-implicit-lookups-with($resolver);
        }
        my int $is-scope := nqp::istype(self, RakuAST::LexicalScope);
        $resolver.push-scope(self) if $is-scope;
        self.visit-children(-> $child { $child.resolve-all($resolver) });
        $resolver.pop-scope() if $is-scope;
        Nil
    }

    # Recursively walks the tree finding nodes of the specified type that are
    # beneath this one. A node that matches the stopper type will be returned
    # if it satisfies the specified type, but it's children shall not be
    # visited. The search is strict - that is to say, it starts at the children
    # of the current node, but doesn't consider the current one.
    method find-nodes(Mu $type, Mu :$stopper) {
        # Walk the tree searching for matching nodes.
        my int $have-stopper := !nqp::eqaddr($stopper, Mu);
        my @visit-queue := [self];
        my @result;
        my $collector := sub collector($node) {
            if nqp::istype($node, $type) {
                nqp::push(@result, $node);
            }
            unless $have-stopper && nqp::istype($node, $stopper) {
                nqp::push(@visit-queue, $node);
            }
        }
        while @visit-queue {
            nqp::shift(@visit-queue).visit-children($collector);
        }
        self.IMPL-WRAP-LIST(@result)
    }

    method IMPL-WRAP-LIST(Mu $vm-array) {
        my $result := nqp::create(List);
        nqp::bindattr($result, List, '$!reified', $vm-array);
        $result
    }

    method IMPL-UNWRAP-LIST(Mu $list) {
        if nqp::islist($list) {
            # Wasn't wrapped anyway
            $list
        }
        else {
            my $reified := nqp::getattr($list, List, '$!reified');
            nqp::isconcrete($reified)
                ?? $reified
                !! $list.FLATTENABLE_LIST
        }
    }
}

# Anything with a known compile time value does RakuAST::CompileTimeValue.
class RakuAST::CompileTimeValue is RakuAST::Node {
    method compile-time-value() {
        nqp::die('compile-time-value not implemented for ' ~ self.HOW.name(self))
    }
}
