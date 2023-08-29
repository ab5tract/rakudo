class RakuAST::Package
  is RakuAST::PackageInstaller
  is RakuAST::StubbyMeta
  is RakuAST::Term
  is RakuAST::IMPL::ImmediateBlockUser
  is RakuAST::Declaration
  is RakuAST::AttachTarget
  is RakuAST::BeginTime
  is RakuAST::TraitTarget
  is RakuAST::ImplicitBlockSemanticsProvider
  is RakuAST::LexicalScope
  is RakuAST::Lookup
  is RakuAST::Doc::DeclaratorTarget
{
    has Str           $.declarator;
    has RakuAST::Name $.name;
    has RakuAST::Code $.body;
    has Mu            $.attribute-type;
    has Mu            $.how;
    has Str           $.repr;

    has Mu   $!role-group;
    has Mu   $!block-semantics-applied;
    has Bool $.is-stub;

    # Methods and attributes are not directly added, but rather through the
    # RakuAST::Attaching mechanism. Attribute usages are also attached for
    # checking after compose time.
    has Mu $!attached-methods;
    has Mu $!attached-attributes;
    has Mu $!attached-attribute-usages;

    method new(          str :$scope,
                         Str :$declarator!,
               RakuAST::Name :$name,
          RakuAST::Signature :$parameterization,
                        List :$traits,
               RakuAST::Code :$body,
                          Mu :$attribute-type,
                          Mu :$how,
                         Str :$repr,
    RakuAST::Doc::Declarator :$WHY
    ) {
        my $obj := nqp::create(self);
        nqp::bindattr_s($obj, RakuAST::Declaration, '$!scope', $scope);
        nqp::bindattr($obj, RakuAST::Package, '$!declarator', $declarator);
        nqp::bindattr($obj, RakuAST::Package, '$!name', $name // RakuAST::Name);
        nqp::bindattr($obj, RakuAST::Package, '$!attribute-type',
          nqp::eqaddr($attribute-type, NQPMu) ?? Attribute !! $attribute-type);
        nqp::bindattr($obj, RakuAST::Package, '$!how',
          nqp::eqaddr($how,NQPMu) ?? $obj.default-how !! $how);
        nqp::bindattr($obj, RakuAST::Package, '$!repr', $repr // Str);

        $obj.set-traits($traits) if $traits;
        $obj.replace-body($body, $parameterization);
        $obj.set-WHY($WHY);

        # Set up internal defaults
        nqp::bindattr($obj, RakuAST::Package, '$!attached-methods', []);
        nqp::bindattr($obj, RakuAST::Package, '$!attached-attributes', []);
        nqp::bindattr($obj, RakuAST::Package, '$!attached-attribute-usages',[]);
        nqp::bindattr($obj, RakuAST::Package, '$!role-group', Mu);
        nqp::bindattr($obj, RakuAST::Package, '$!is-stub', False);

        $obj
    }

    method replace-body(RakuAST::Code $body, RakuAST::Signature $signature?) {
        $body := RakuAST::Block.new unless $body;

        # The body of a role is internally a Sub that has the parameterization
        # of the role as the signature.  This allows a role to be selected
        # using ordinary dispatch semantics.  The statement list gets a return
        # value added, so that the role's meta-object and lexpad are returned.
        if $!declarator eq 'role' {
            $signature := RakuAST::Signature.new unless $signature;
            $signature.set-is-on-role-body(1);

            $body := $body.body;
            $body.statement-list.add-statement(
              RakuAST::Statement::Expression.new(
                expression => RakuAST::Nqp.new('list',
                  RakuAST::Declaration::ResolvedConstant.new(
                    compile-time-value => self.stubbed-meta-object
                  ),
                  RakuAST::Nqp.new('curlexpad')
                )
              )
            );
            $body := RakuAST::Sub.new(:name($!name), :$signature, :$body);
        }

        nqp::bindattr(self, RakuAST::Package, '$!body', $body);
        Nil
    }

    method set-repr(Str $repr) {
        nqp::bindattr(self, RakuAST::Package, '$!repr', $repr);
    }

    method set-is-stub(Bool $is-stub) {
        nqp::bindattr(self, RakuAST::Package, '$!is-stub', $is-stub ?? True !! False);
    }

    method resolve-with(RakuAST::Resolver $resolver) {
        if $!name {
            my $resolved := $resolver.resolve-name-constant($!name);
            if $resolved {
                my $meta-object := $resolved.compile-time-value;
                if $meta-object.HOW.HOW.name($meta-object.HOW) ne 'Perl6::Metamodel::PackageHOW'
                    && nqp::can($meta-object.HOW, 'is_composed')
                    && !$meta-object.HOW.is_composed($meta-object)
                {
                    self.set-resolution($resolved);
                }
            }
        }
        Nil
    }

    method default-scope() { 'our' }

    method default-how() {
        my constant HOWS := nqp::hash(
          'class',   Metamodel::ClassHOW,
          'grammar', Metamodel::GrammarHOW,
          'knowhow', Metamodel::KnowHOW,
          'module',  Metamodel::ModuleHOW,
          'native',  Metamodel::NativeHOW,
          'package', Metamodel::PackageHOW,
          'role',    Metamodel::ParametricRoleHOW
        );
        nqp::ifnull(nqp::atkey(HOWS,$!declarator),Metamodel::PackageHOW)
    }

    method dba() { 'package' }

    method parameterization() {
        $!declarator eq 'role' ?? $!body.signature !! Mu
    }

    # While a package may be declared `my`, its installation semantics are
    # more complex, and thus handled as a BEGIN-time effect. (For example,
    # `my Foo::Bar { }` should not create a lexical symbol Foo::Bar.)
    method is-simple-lexical-declaration() {
        False
    }

    method attach-target-names() { self.IMPL-WRAP-LIST(['package', 'also']) }

    method clear-attachments() {
        # Attributes and methods only attach once as a BEGIN effect, thus we
        # don't have to deal with duplicates on them.
        Nil
    }

    method ATTACH-METHOD(RakuAST::Method $method) {
        nqp::push($!attached-methods, $method);
        Nil
    }

    # TODO also list-y declarations
    method ATTACH-ATTRIBUTE(RakuAST::VarDeclaration::Simple $attribute) {
        nqp::push($!attached-attributes, $attribute);
        Nil
    }

    method ATTACH-ATTRIBUTE-USAGE(RakuAST::Var::Attribute $attribute) {
        nqp::push($!attached-attribute-usages, $attribute);
        Nil
    }

    # We install the name before parsing the class body.
    method is-begin-performed-before-children() { True }

    method IMPL-GENERATE-LEXICAL-DECLARATION(RakuAST::Name $name, Mu $type-object) {
        RakuAST::Declaration::LexicalPackage.new:
            :lexical-name($name),
            :compile-time-value($type-object),
            :package(self);
    }

    method PERFORM-BEGIN(RakuAST::Resolver $resolver, RakuAST::IMPL::QASTContext $context) {
         # Note that this early return is actually not effective as the begin handler will
         # already be run when the parser enters the package and we only know that it's a
         # stub when we are done parsing the body.
         return Nil if $!is-stub;

        # Install the symbol.
        my str $scope := self.scope;
        $scope := 'our' if $scope eq 'unit';
        my $name := $!name;
        if $name && !$name.is-empty {
            my $type-object := self.stubbed-meta-object;
            my $current-package := $resolver.current-package;
            my $full-name := $current-package =:= $resolver.get-global
                ?? $name
                !! $name.qualified-with(
                    RakuAST::Name.from-identifier-parts(
                        |nqp::split('::', $current-package.HOW.name($current-package))
                    )
                );
            $type-object.HOW.set_name(
                $type-object,
                $full-name.canonicalize(:colonpairs(0))
            ) if !nqp::eqaddr($current-package, $resolver.get-global);
            # Update the Stash's name, too.
            nqp::bindattr_s($type-object.WHO, Stash, '$!longname', $type-object.HOW.name($type-object));

            if ($scope eq 'my' || $scope eq 'our') && $!declarator ne 'role' {
                # Need to install the package somewhere.
                self.IMPL-INSTALL-PACKAGE($resolver, $scope, $name, $type-object, $resolver.current-package);
            }

            elsif $!declarator eq 'role' {
                # Find an appropriate existing role group
                my $group-name := $full-name.canonicalize(:colonpairs(0));
                my $group := $resolver.resolve-lexical-constant($group-name);
                if $group {
                    $group := $group.compile-time-value;
                }
                else {
                    # No existing one found - create a role group
                    $group := Perl6::Metamodel::ParametricRoleGroupHOW.new_type(
                        :name($group-name),
                        :repr($!repr)
                    );
                    my $outer := $resolver.find-attach-target('block') // $resolver.find-attach-target('compunit');
                    $outer.add-generated-lexical-declaration(
                        RakuAST::VarDeclaration::Implicit::Constant.new(
                            :name($name.canonicalize(:colonpairs(0))),
                            :value($group)
                        )
                    );
                    if $scope eq 'our' {
                        self.IMPL-INSTALL-PACKAGE($resolver, $scope, $name, $group, $resolver.current-package, :no-lexical);
                    }
                }
                # Add ourselves to the role group
                $type-object.HOW.set_group($type-object, $group);
                nqp::bindattr(self, RakuAST::Package, '$!role-group', $group);
            }
        }

        # TODO split off the above into a pre-begin handler, so the enter-scope
        # and declarations can go back into RakuAST::Actions
        if nqp::istype($resolver, RakuAST::Resolver::Compile) {
            $resolver.enter-scope(self);

            if $!declarator eq 'role' {
                $resolver.declare-lexical(
                    RakuAST::VarDeclaration::Implicit::Constant.new(
                        name => '$?ROLE', value => self.stubbed-meta-object
                    )
                );
                $resolver.declare-lexical(
                    RakuAST::VarDeclaration::Implicit::Constant.new(
                        name => '::?ROLE', value => self.stubbed-meta-object
                    )
                );
                $resolver.declare-lexical(
                    RakuAST::Type::Capture.new(RakuAST::Name.from-identifier('$?CLASS'))
                );
                $resolver.declare-lexical(
                    RakuAST::Type::Capture.new(RakuAST::Name.from-identifier('::?CLASS'))
                );
            }
            elsif $!declarator eq 'module' {
                $resolver.declare-lexical(
                    RakuAST::VarDeclaration::Implicit::Constant.new(
                        name => '$?MODULE', value => self.stubbed-meta-object
                    )
                );
                $resolver.declare-lexical(
                    RakuAST::VarDeclaration::Implicit::Constant.new(
                        name => '::?MODULE', value => self.stubbed-meta-object
                    )
                );
            }
            elsif $!declarator ne 'package' {
                $resolver.declare-lexical(
                    RakuAST::VarDeclaration::Implicit::Constant.new(
                        name => '$?CLASS', value => self.stubbed-meta-object
                    )
                );
                $resolver.declare-lexical(
                    RakuAST::VarDeclaration::Implicit::Constant.new(
                        name => '::?CLASS', value => self.stubbed-meta-object
                    )
                );
            }
        }

        # Apply traits.
        self.apply-traits($resolver, $context, self);
    }

    method PRODUCE-STUBBED-META-OBJECT() {
        if self.is-resolved {
            self.resolution.compile-time-value;
        }
        else {
            # Create the type object and return it; this stubs the type.
            my %options;
            %options<name> := $!name.canonicalize if $!name;
            %options<repr> := $!repr if $!repr;
            if $!name {
                for $!name.colonpairs {
                    %options{$_.key} := $_.simple-compile-time-quote-value;
                }
            }
            $!how.new_type(|%options)
        }
    }

    method PRODUCE-META-OBJECT() {
        # Obtain the stubbed meta-object, which is the type object.
        my $type := self.stubbed-meta-object();

        # Add methods and attributes.
        for $!attached-methods {
            my $name := $_.name.canonicalize;
            my $meta-object := $_.meta-object;
            if nqp::istype($_, RakuAST::Method) && $_.private {
                $type.HOW.add_private_method($type, $name, $meta-object);
            }
            elsif nqp::istype($_, RakuAST::Method) && $_.meta {
                $type.HOW.add_meta_method($type, $name, $meta-object);
            }
            elsif $_.multiness eq 'multi' {
                $type.HOW.add_multi_method($type, $name, $meta-object);
            }
            else {
                $type.HOW.add_method($type, $name, $meta-object);
            }
        }
        for $!attached-attributes {
            # TODO: create method BUILDALL here
            $type.HOW.add_attribute($type, $_.meta-object);
        }

        if $!declarator eq 'role' {
            $type.HOW.set_body_block($type, $!body.meta-object);

            # The role needs to be composed before we add the possibility to the group
            $type.HOW.compose($type);

            my $group := $!role-group;
            $group.HOW.add_possibility($group, $type) unless $group =:= Mu;
        } else {
            # Compose the meta-object
            $type.HOW.compose($type);
        }
        # Return the meta-object
        $type
    }

    method apply-implicit-block-semantics() {
        if $!block-semantics-applied {
            return;
        }
        nqp::bindattr(self, RakuAST::Package, '$!block-semantics-applied', 1);
        $!body.add-generated-lexical-declaration(
            RakuAST::VarDeclaration::Implicit::Constant.new(
                name => '$?PACKAGE', value => self.stubbed-meta-object
            )
        );
        if $!declarator eq 'role' {
            $!body.add-generated-lexical-declaration(
                RakuAST::VarDeclaration::Implicit::Constant.new(
                    name => '$?ROLE', value => self.stubbed-meta-object
                )
            );
            $!body.add-generated-lexical-declaration(
                RakuAST::VarDeclaration::Implicit::Constant.new(
                    name => '::?ROLE', value => self.stubbed-meta-object
                )
            );
        }
        elsif $!declarator eq 'module' {
            $!body.add-generated-lexical-declaration(
                RakuAST::VarDeclaration::Implicit::Constant.new(
                    name => '$?MODULE', value => self.stubbed-meta-object
                )
            );
            $!body.add-generated-lexical-declaration(
                RakuAST::VarDeclaration::Implicit::Constant.new(
                    name => '::?MODULE', value => self.stubbed-meta-object
                )
            );
        }
        elsif $!declarator ne 'package' {
            $!body.add-generated-lexical-declaration(
                RakuAST::VarDeclaration::Implicit::Constant.new(
                    name => '$?CLASS', value => self.stubbed-meta-object
                )
            );
            $!body.add-generated-lexical-declaration(
                RakuAST::VarDeclaration::Implicit::Constant.new(
                    name => '::?CLASS', value => self.stubbed-meta-object
                )
            );
        }
    }

    method IMPL-EXPR-QAST(RakuAST::IMPL::QASTContext $context) {
        my $type-object := self.meta-object;
        $context.ensure-sc($type-object);
        my $body := $!body.IMPL-QAST-BLOCK($context, :blocktype<immediate>);
        my $result := QAST::Stmts.new(
            $body,
            QAST::WVal.new( :value($type-object) )
        );
        $result
    }

    method IMPL-CAN-INTERPRET() {
        True
    }

    method IMPL-INTERPRET(RakuAST::IMPL::InterpContext $ctx) {
        self.compile-time-value
    }

    method IMPL-COMPOSE() {
        if $!declarator eq 'class' {
            # create BUILDALL method if there's something to create,
            # otherwise put in a generic fallback BUILDALL that doesn't
            # do anything
        }
        self.meta-object; # Ensure it's composed
    }

    method visit-children(Code $visitor) {
        $visitor($!name) if $!name;
        self.visit-traits($visitor);
        $visitor($!body);
        $visitor(self.WHY) if self.WHY;
    }

    method needs-sink-call() { False }
}

class RakuAST::Package::Augmented
    is RakuAST::Package
{
    method resolve-with(RakuAST::Resolver $resolver) {
        my $resolved := $resolver.resolve-name(self.name);
        if $resolved {
            self.set-resolution($resolved);
        }
        Nil
    }

    method PRODUCE-STUBBED-META-OBJECT() {
        self.resolution.compile-time-value
    }
}
