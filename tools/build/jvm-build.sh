#!/bin/sh
# The JVM rakudo build, the old-fashioned way: every command make would
# have run, written down so no make is needed. Derived from the
# generated Makefile's recipes; regenerate this script when Configure
# or the templates change the build shape.
#
#   sh tools/build/jvm-build.sh gen    # refresh gen/jvm from src (after frontend edits)
#   sh tools/build/jvm-build.sh jars   # rebuild every jar and runner (after an nqp rebuild)
#   sh tools/build/jvm-build.sh        # both
set -e
cd "$(dirname "$0")/../.."

do_gen() {
echo '+++ Generating	gen/jvm/main-version.nqp'
'/usr/bin/perl' -I'/home/longwalker/code/raku/x.core/rakudo/tools/lib' -I'/home/longwalker/code/raku/x.core/rakudo/3rdparty/nqp-configure/lib' '/home/longwalker/code/raku/x.core/rakudo/Configure.pl' --backends=jvm --prefix='/home/longwalker/code/raku/x.core/raku-prefix' --silent-build --expand 'jvm/main-version' --out gen/jvm/main-version.nqp
echo '+++ Generating	gen/jvm/ast.nqp'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' tools/build/raku-ast-compiler.nqp src/Raku/ast/impl.rakumod      src/Raku/ast/resolver.rakumod      src/Raku/ast/origins.rakumod      src/Raku/ast/base.rakumod      src/Raku/ast/checktime.rakumod      src/Raku/ast/sink.rakumod      src/Raku/ast/scoping.rakumod      src/Raku/ast/attaching.rakumod      src/Raku/ast/parsetime.rakumod      src/Raku/ast/begintime.rakumod      src/Raku/ast/traits.rakumod      src/Raku/ast/meta.rakumod      src/Raku/ast/doc-block.rakumod      src/Raku/ast/doc-declarator.rakumod      src/Raku/ast/statements.rakumod      src/Raku/ast/operator-properties.rakumod      src/Raku/ast/expressions.rakumod      src/Raku/ast/pragma.rakumod      src/Raku/ast/pair.rakumod      src/Raku/ast/circumfix.rakumod      src/Raku/ast/call.rakumod      src/Raku/ast/nqp.rakumod      src/Raku/ast/term.rakumod      src/Raku/ast/name.rakumod      src/Raku/ast/type.rakumod      src/Raku/ast/variable-declaration.rakumod      src/Raku/ast/variable-access.rakumod      src/Raku/ast/contextualizer.rakumod      src/Raku/ast/code.rakumod      src/Raku/ast/var-lowering.rakumod      src/Raku/ast/compunit.rakumod      src/Raku/ast/statementprefixes.rakumod      src/Raku/ast/statement-mods.rakumod      src/Raku/ast/signature.rakumod      src/Raku/ast/package.rakumod      src/Raku/ast/literals.rakumod      src/Raku/ast/regex.rakumod > gen/jvm/ast.nqp
echo '+++ Generating	gen/jvm/Actions.nqp'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm src/Perl6/Actions.nqp src/Perl6/PodActions.nqp > gen/jvm/Actions.nqp
echo '+++ Generating	gen/jvm/RakuActions.nqp'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm src/Raku/Actions.nqp > gen/jvm/RakuActions.nqp
echo '+++ Generating	gen/jvm/Compiler.nqp'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm src/Perl6/Compiler.nqp > gen/jvm/Compiler.nqp
echo '+++ Generating	gen/jvm/SysConfig.nqp'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm src/Perl6/SysConfig.nqp > gen/jvm/SysConfig.nqp
echo '+++ Generating	gen/jvm/Grammar.nqp'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm src/Perl6/Grammar.nqp src/Perl6/PodGrammar.nqp > gen/jvm/Grammar.nqp
echo '+++ Generating	gen/jvm/RakuGrammar.nqp'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm src/Raku/Grammar.nqp > gen/jvm/RakuGrammar.nqp
echo '+++ Generating	gen/jvm/Metamodel.nqp'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm src/Perl6/Metamodel/Configuration.nqp      src/Perl6/Metamodel/Archetypes.nqp      src/Perl6/Metamodel/Naming.nqp      src/Perl6/Metamodel/Documenting.nqp      src/Perl6/Metamodel/Explaining.nqp      src/Perl6/Metamodel/Stashing.nqp      src/Perl6/Metamodel/Composing.nqp      src/Perl6/Metamodel/Versioning.nqp      src/Perl6/Metamodel/LanguageRevision.nqp      src/Perl6/Metamodel/Nominalizable.nqp      src/Perl6/Metamodel/TypePretense.nqp      src/Perl6/Metamodel/MethodDelegation.nqp      src/Perl6/Metamodel/BoolificationProtocol.nqp      src/Perl6/Metamodel/ContainerSpecProtocol.nqp      src/Perl6/Metamodel/BUILDALL.nqp      src/Perl6/Metamodel/PackageHOW.nqp      src/Perl6/Metamodel/ModuleHOW.nqp      src/Perl6/Metamodel/GenericHOW.nqp      src/Perl6/Metamodel/AttributeContainer.nqp      src/Perl6/Metamodel/Finalization.nqp      src/Perl6/Metamodel/MethodContainer.nqp      src/Perl6/Metamodel/PrivateMethodContainer.nqp      src/Perl6/Metamodel/MultiMethodContainer.nqp      src/Perl6/Metamodel/MetaMethodContainer.nqp      src/Perl6/Metamodel/RoleContainer.nqp      src/Perl6/Metamodel/MultipleInheritance.nqp      src/Perl6/Metamodel/DefaultParent.nqp      src/Perl6/Metamodel/BaseType.nqp      src/Perl6/Metamodel/C3MRO.nqp      src/Perl6/Metamodel/MROBasedMethodDispatch.nqp      src/Perl6/Metamodel/MROBasedTypeChecking.nqp      src/Perl6/Metamodel/Trusting.nqp      src/Perl6/Metamodel/Mixins.nqp      src/Perl6/Metamodel/BUILDPLAN.nqp      src/Perl6/Metamodel/REPRComposeProtocol.nqp      src/Perl6/Metamodel/InvocationProtocol.nqp      src/Perl6/Metamodel/RolePunning.nqp      src/Perl6/Metamodel/ArrayType.nqp      src/Perl6/Metamodel/RoleToRoleApplier.nqp      src/Perl6/Metamodel/Concretization.nqp      src/Perl6/Metamodel/ConcretizationCache.nqp      src/Perl6/Metamodel/ConcreteRoleHOW.nqp      src/Perl6/Metamodel/CurriedRoleHOW.nqp      src/Perl6/Metamodel/ParametricRoleHOW.nqp      src/Perl6/Metamodel/ParametricRoleGroupHOW.nqp      src/Perl6/Metamodel/RoleToClassApplier.nqp      src/Perl6/Metamodel/ClassHOW.nqp      src/Perl6/Metamodel/GrammarHOW.nqp      src/Perl6/Metamodel/NativeHOW.nqp      src/Perl6/Metamodel/NativeRefHOW.nqp      src/Perl6/Metamodel/SubsetHOW.nqp      src/Perl6/Metamodel/EnumHOW.nqp      src/Perl6/Metamodel/CoercionHOW.nqp      src/Perl6/Metamodel/DefiniteHOW.nqp      src/Perl6/Metamodel/Dispatchers.nqp  						src/vm/jvm/Raku/Metamodel/JavaHOW.nqp > gen/jvm/Metamodel.nqp
echo '+++ Generating	gen/jvm/ModuleLoader.nqp'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm src/vm/jvm/ModuleLoaderVMConfig.nqp src/Perl6/ModuleLoader.nqp src/vm/jvm/Raku/JavaModuleLoader.nqp > gen/jvm/ModuleLoader.nqp
echo '+++ Generating	gen/jvm/Ops.nqp'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm src/vm/jvm/Raku/Ops.nqp > gen/jvm/Ops.nqp
echo '+++ Generating	gen/jvm/Optimizer.nqp'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm src/Perl6/Optimizer.nqp > gen/jvm/Optimizer.nqp
echo '+++ Generating	gen/jvm/Pod.nqp'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm src/Perl6/Pod.nqp > gen/jvm/Pod.nqp
echo '+++ Generating	gen/jvm/World.nqp'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm src/Perl6/World.nqp > gen/jvm/World.nqp
echo '+++ Generating	gen/jvm/rakudo.nqp'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm gen/jvm/main-version.nqp src/main.nqp > gen/jvm/rakudo.nqp
echo '+++ Generating	gen/jvm/rakudo-debug.nqp'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm src/rakudo-debug.nqp gen/jvm/main-version.nqp > gen/jvm/rakudo-debug.nqp
echo '+++ Generating	gen/jvm/BOOTSTRAP/v6c.nqp'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm src/Perl6/bootstrap.c/BOOTSTRAP.nqp src/Perl6/bootstrap.c/EXPORTHOW.nqp > gen/jvm/BOOTSTRAP/v6c.nqp
echo '+++ Generating	gen/jvm/BOOTSTRAP/v6d.nqp'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm src/Perl6/bootstrap.d/BOOTSTRAP.nqp src/Perl6/bootstrap.d/EXPORTHOW.nqp > gen/jvm/BOOTSTRAP/v6d.nqp
echo '+++ Generating	gen/jvm/BOOTSTRAP/v6e.nqp'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm src/Perl6/bootstrap.e/BOOTSTRAP.nqp src/Perl6/bootstrap.e/EXPORTHOW.nqp > gen/jvm/BOOTSTRAP/v6e.nqp
}

do_jars() {
echo '+++ Compiling	blib/Perl6/ModuleLoader.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/ModuleLoader.jar gen/jvm/ModuleLoader.nqp
echo '+++ Compiling	blib/Perl6/Ops.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/Ops.jar gen/jvm/Ops.nqp
echo '+++ Compiling	blib/Perl6/Pod.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/Pod.jar gen/jvm/Pod.nqp
echo '+++ Compiling	blib/Perl6/World.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/World.jar gen/jvm/World.nqp
echo '+++ Compiling	blib/Perl6/Actions.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/Actions.jar gen/jvm/Actions.nqp
echo '+++ Compiling	blib/Perl6/Grammar.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/Grammar.jar gen/jvm/Grammar.nqp
echo '+++ Compiling	blib/Raku/Actions.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Raku/Actions.jar gen/jvm/RakuActions.nqp
echo '+++ Compiling	blib/Raku/Grammar.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Raku/Grammar.jar gen/jvm/RakuGrammar.nqp
echo '+++ Compiling	blib/Perl6/Metamodel.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/Metamodel.jar gen/jvm/Metamodel.nqp
echo '+++ Compiling	blib/Perl6/Optimizer.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/Optimizer.jar gen/jvm/Optimizer.nqp
echo '+++ Compiling	blib/Perl6/Compiler.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/Compiler.jar gen/jvm/Compiler.nqp
echo '+++ Compiling	blib/Perl6/SysConfig.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/SysConfig.jar gen/jvm/SysConfig.nqp
echo '+++ Generating	rakudo-runtime.jar (Gradle)'
( cd rakudo-runtime && ../nqp/gradlew --console=plain jar )
cp -- rakudo-runtime/build/libs/rakudo-runtime.jar rakudo-runtime.jar
echo '+++ Compiling	rakudo.jar'
java -Xmx14G --module-path /home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/truffle --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime --enable-native-access=org.graalvm.truffle --sun-misc-unsafe-memory-access=allow -cp 'blib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-tree-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/fastutil-8.5.19.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/jline-4.3.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/lz4-java-1.8.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/kotlin-stdlib-2.4.10.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/annotations-13.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-runtime.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/lib/nqp.jar:rakudo-runtime.jar:nqp/build/jvm/share/lib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-truffle.jar' nqp --module-path=blib --ll-exception --target=jar --output=rakudo.jar --javaclass=perl6 gen/jvm/rakudo.nqp
echo '+++ Compiling	blib/Perl6/BOOTSTRAP/v6c.jar'
java -Xmx14G --module-path /home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/truffle --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime --enable-native-access=org.graalvm.truffle --sun-misc-unsafe-memory-access=allow -cp 'blib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-tree-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/fastutil-8.5.19.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/jline-4.3.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/lz4-java-1.8.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/kotlin-stdlib-2.4.10.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/annotations-13.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-runtime.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/lib/nqp.jar:rakudo-runtime.jar:nqp/build/jvm/share/lib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-truffle.jar' nqp --module-path=blib --ll-exception --target=jar --output=blib/Perl6/BOOTSTRAP/v6c.jar --javaclass=perl6 gen/jvm/BOOTSTRAP/v6c.nqp
echo '+++ Compiling	blib/CORE.c.setting.jar'
'/usr/bin/perl' -I'/home/longwalker/code/raku/x.core/rakudo/tools/lib' -I'/home/longwalker/code/raku/x.core/rakudo/3rdparty/nqp-configure/lib' '/home/longwalker/code/raku/x.core/rakudo/Configure.pl' --backends=jvm --prefix='/home/longwalker/code/raku/x.core/raku-prefix' --silent-build --expand '/home/longwalker/code/raku/x.core/rakudo/tools/templates/6.c/core_sources' \
		 --out 'gen/jvm/core_sources.c' \
		 --set-var=backend=jvm
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm -p SETTING:: -f 'gen/jvm/core_sources.c' > 'gen/jvm/CORE.c.setting'
echo 'The following step can take a long time, please be patient.'
'/usr/bin/perl' rakudo-j-build --setting=NULL.c --ll-exception --optimize=3 --target=jar --stagestats --output=blib/CORE.c.setting.jar 'gen/jvm/CORE.c.setting'
echo '+++ Compiling	blib/Perl6/BOOTSTRAP/v6d.jar'
java -Xmx14G --module-path /home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/truffle --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime --enable-native-access=org.graalvm.truffle --sun-misc-unsafe-memory-access=allow -cp 'blib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-tree-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/fastutil-8.5.19.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/jline-4.3.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/lz4-java-1.8.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/kotlin-stdlib-2.4.10.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/annotations-13.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-runtime.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/lib/nqp.jar:rakudo-runtime.jar:nqp/build/jvm/share/lib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-truffle.jar' nqp --module-path=blib --ll-exception --target=jar --output=blib/Perl6/BOOTSTRAP/v6d.jar --javaclass=perl6 gen/jvm/BOOTSTRAP/v6d.nqp
echo '+++ Compiling	blib/CORE.d.setting.jar'
'/usr/bin/perl' -I'/home/longwalker/code/raku/x.core/rakudo/tools/lib' -I'/home/longwalker/code/raku/x.core/rakudo/3rdparty/nqp-configure/lib' '/home/longwalker/code/raku/x.core/rakudo/Configure.pl' --backends=jvm --prefix='/home/longwalker/code/raku/x.core/raku-prefix' --silent-build --expand '/home/longwalker/code/raku/x.core/rakudo/tools/templates/6.d/core_sources' \
		 --out 'gen/jvm/core_sources.d' \
		 --set-var=backend=jvm
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm -p SETTING:: -f 'gen/jvm/core_sources.d' > 'gen/jvm/CORE.d.setting'
echo 'The following step can take a long time, please be patient.'
'/usr/bin/perl' rakudo-j-build --setting=NULL.d --ll-exception --optimize=3 --target=jar --stagestats --output=blib/CORE.d.setting.jar 'gen/jvm/CORE.d.setting'
echo '+++ Compiling	blib/Perl6/BOOTSTRAP/v6e.jar'
java -Xmx14G --module-path /home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/truffle --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime --enable-native-access=org.graalvm.truffle --sun-misc-unsafe-memory-access=allow -cp 'blib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-tree-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/fastutil-8.5.19.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/jline-4.3.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/lz4-java-1.8.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/kotlin-stdlib-2.4.10.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/annotations-13.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-runtime.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/lib/nqp.jar:rakudo-runtime.jar:nqp/build/jvm/share/lib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-truffle.jar' nqp --module-path=blib --ll-exception --target=jar --output=blib/Perl6/BOOTSTRAP/v6e.jar --javaclass=perl6 gen/jvm/BOOTSTRAP/v6e.nqp
echo '+++ Compiling	blib/CORE.e.setting.jar'
'/usr/bin/perl' -I'/home/longwalker/code/raku/x.core/rakudo/tools/lib' -I'/home/longwalker/code/raku/x.core/rakudo/3rdparty/nqp-configure/lib' '/home/longwalker/code/raku/x.core/rakudo/Configure.pl' --backends=jvm --prefix='/home/longwalker/code/raku/x.core/raku-prefix' --silent-build --expand '/home/longwalker/code/raku/x.core/rakudo/tools/templates/6.e/core_sources' \
		 --out 'gen/jvm/core_sources.e' \
		 --set-var=backend=jvm
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm -p SETTING:: -f 'gen/jvm/core_sources.e' > 'gen/jvm/CORE.e.setting'
echo 'The following step can take a long time, please be patient.'
'/usr/bin/perl' rakudo-j-build --setting=NULL.e --ll-exception --optimize=3 --target=jar --stagestats --output=blib/CORE.e.setting.jar 'gen/jvm/CORE.e.setting'
echo '+++ Setting up	rakudo-j'
'/usr/bin/perl' -I'/home/longwalker/code/raku/x.core/rakudo/tools/lib' -I'/home/longwalker/code/raku/x.core/rakudo/3rdparty/nqp-configure/lib' '/home/longwalker/code/raku/x.core/rakudo/tools/build/create-jvm-runner.pl' dev '/home/longwalker/code/raku/x.core/rakudo' . . '/home/longwalker/code/raku/x.core/raku-prefix/share/nqp' '/home/longwalker/code/raku/x.core/raku-prefix/share/nqp' '/home/longwalker/code/raku/x.core/raku-prefix/share/perl6' '/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-tree-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/fastutil-8.5.19.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/jline-4.3.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/lz4-java-1.8.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/kotlin-stdlib-2.4.10.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/annotations-13.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-runtime.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/lib/nqp.jar'
echo '+++ Compiling	rakudo-debug.jar'
java -Xmx14G --module-path /home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/truffle --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime --enable-native-access=org.graalvm.truffle --sun-misc-unsafe-memory-access=allow -cp 'blib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-tree-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/fastutil-8.5.19.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/jline-4.3.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/lz4-java-1.8.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/kotlin-stdlib-2.4.10.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/annotations-13.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-runtime.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/lib/nqp.jar:rakudo-runtime.jar:nqp/build/jvm/share/lib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-truffle.jar' nqp --module-path=blib --ll-exception --target=jar --output=rakudo-debug.jar --javaclass=perl6 gen/jvm/rakudo-debug.nqp
echo '+++ Setting up	rakudo-debug-j'
'/usr/bin/perl' -I'/home/longwalker/code/raku/x.core/rakudo/tools/lib' -I'/home/longwalker/code/raku/x.core/rakudo/3rdparty/nqp-configure/lib' '/home/longwalker/code/raku/x.core/rakudo/tools/build/create-jvm-runner.pl' dev-debug '/home/longwalker/code/raku/x.core/rakudo' . . '/home/longwalker/code/raku/x.core/raku-prefix/share/nqp' '/home/longwalker/code/raku/x.core/raku-prefix/share/nqp' '/home/longwalker/code/raku/x.core/raku-prefix/share/perl6' '/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-tree-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/fastutil-8.5.19.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/jline-4.3.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/lz4-java-1.8.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/kotlin-stdlib-2.4.10.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/annotations-13.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-runtime.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/lib/nqp.jar'
mkdir -p -- '/home/longwalker/code/raku/x.core/rakudo/gen/build_rakudo_home/templates'
cp -- src/runner/posix-runner-tmpl '/home/longwalker/code/raku/x.core/rakudo/gen/build_rakudo_home/templates'
echo '+++ Setting up JVM runner'
cp -- rakudo-j rakudo
chmod -- 755 rakudo
}

case "${1:-all}" in
  gen)  do_gen ;;
  jars) do_jars ;;
  all)  do_gen; do_jars ;;
esac
