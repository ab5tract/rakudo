#!/bin/sh
# Resumable driver over jvm-build.sh steps: a step whose output file
# already exists is skipped, and a step whose process is killed from
# outside is retried (three times) before giving up. Outputs are the
# step labels themselves where they name a file.
cd "$(dirname "$0")/../.."
# --- step 0: blib/Perl6/ModuleLoader.jar
step_0() {
echo '+++ Compiling	blib/Perl6/ModuleLoader.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/ModuleLoader.jar gen/jvm/ModuleLoader.nqp
}
if [ ! -s "blib/Perl6/ModuleLoader.jar" ]; then
  for try in 1 2 3; do step_0 && break; echo "retry blib/Perl6/ModuleLoader.jar ($try)"; sleep 3; done
  [ -s "blib/Perl6/ModuleLoader.jar" ] || { echo "FAILED blib/Perl6/ModuleLoader.jar"; exit 1; }
else
  echo "skip blib/Perl6/ModuleLoader.jar (exists)"
fi
# --- step 1: blib/Perl6/Ops.jar
step_1() {
echo '+++ Compiling	blib/Perl6/Ops.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/Ops.jar gen/jvm/Ops.nqp
}
if [ ! -s "blib/Perl6/Ops.jar" ]; then
  for try in 1 2 3; do step_1 && break; echo "retry blib/Perl6/Ops.jar ($try)"; sleep 3; done
  [ -s "blib/Perl6/Ops.jar" ] || { echo "FAILED blib/Perl6/Ops.jar"; exit 1; }
else
  echo "skip blib/Perl6/Ops.jar (exists)"
fi
# --- step 2: blib/Perl6/Pod.jar
step_2() {
echo '+++ Compiling	blib/Perl6/Pod.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/Pod.jar gen/jvm/Pod.nqp
}
if [ ! -s "blib/Perl6/Pod.jar" ]; then
  for try in 1 2 3; do step_2 && break; echo "retry blib/Perl6/Pod.jar ($try)"; sleep 3; done
  [ -s "blib/Perl6/Pod.jar" ] || { echo "FAILED blib/Perl6/Pod.jar"; exit 1; }
else
  echo "skip blib/Perl6/Pod.jar (exists)"
fi
# --- step 3: blib/Perl6/World.jar
step_3() {
echo '+++ Compiling	blib/Perl6/World.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/World.jar gen/jvm/World.nqp
}
if [ ! -s "blib/Perl6/World.jar" ]; then
  for try in 1 2 3; do step_3 && break; echo "retry blib/Perl6/World.jar ($try)"; sleep 3; done
  [ -s "blib/Perl6/World.jar" ] || { echo "FAILED blib/Perl6/World.jar"; exit 1; }
else
  echo "skip blib/Perl6/World.jar (exists)"
fi
# --- step 4: blib/Perl6/Actions.jar
step_4() {
echo '+++ Compiling	blib/Perl6/Actions.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/Actions.jar gen/jvm/Actions.nqp
}
if [ ! -s "blib/Perl6/Actions.jar" ]; then
  for try in 1 2 3; do step_4 && break; echo "retry blib/Perl6/Actions.jar ($try)"; sleep 3; done
  [ -s "blib/Perl6/Actions.jar" ] || { echo "FAILED blib/Perl6/Actions.jar"; exit 1; }
else
  echo "skip blib/Perl6/Actions.jar (exists)"
fi
# --- step 5: blib/Perl6/Grammar.jar
step_5() {
echo '+++ Compiling	blib/Perl6/Grammar.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/Grammar.jar gen/jvm/Grammar.nqp
}
if [ ! -s "blib/Perl6/Grammar.jar" ]; then
  for try in 1 2 3; do step_5 && break; echo "retry blib/Perl6/Grammar.jar ($try)"; sleep 3; done
  [ -s "blib/Perl6/Grammar.jar" ] || { echo "FAILED blib/Perl6/Grammar.jar"; exit 1; }
else
  echo "skip blib/Perl6/Grammar.jar (exists)"
fi
# --- step 6: blib/Raku/Actions.jar
step_6() {
echo '+++ Compiling	blib/Raku/Actions.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Raku/Actions.jar gen/jvm/RakuActions.nqp
}
if [ ! -s "blib/Raku/Actions.jar" ]; then
  for try in 1 2 3; do step_6 && break; echo "retry blib/Raku/Actions.jar ($try)"; sleep 3; done
  [ -s "blib/Raku/Actions.jar" ] || { echo "FAILED blib/Raku/Actions.jar"; exit 1; }
else
  echo "skip blib/Raku/Actions.jar (exists)"
fi
# --- step 7: blib/Raku/Grammar.jar
step_7() {
echo '+++ Compiling	blib/Raku/Grammar.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Raku/Grammar.jar gen/jvm/RakuGrammar.nqp
}
if [ ! -s "blib/Raku/Grammar.jar" ]; then
  for try in 1 2 3; do step_7 && break; echo "retry blib/Raku/Grammar.jar ($try)"; sleep 3; done
  [ -s "blib/Raku/Grammar.jar" ] || { echo "FAILED blib/Raku/Grammar.jar"; exit 1; }
else
  echo "skip blib/Raku/Grammar.jar (exists)"
fi
# --- step 8: blib/Perl6/Metamodel.jar
step_8() {
echo '+++ Compiling	blib/Perl6/Metamodel.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/Metamodel.jar gen/jvm/Metamodel.nqp
}
if [ ! -s "blib/Perl6/Metamodel.jar" ]; then
  for try in 1 2 3; do step_8 && break; echo "retry blib/Perl6/Metamodel.jar ($try)"; sleep 3; done
  [ -s "blib/Perl6/Metamodel.jar" ] || { echo "FAILED blib/Perl6/Metamodel.jar"; exit 1; }
else
  echo "skip blib/Perl6/Metamodel.jar (exists)"
fi
# --- step 9: blib/Perl6/Optimizer.jar
step_9() {
echo '+++ Compiling	blib/Perl6/Optimizer.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/Optimizer.jar gen/jvm/Optimizer.nqp
}
if [ ! -s "blib/Perl6/Optimizer.jar" ]; then
  for try in 1 2 3; do step_9 && break; echo "retry blib/Perl6/Optimizer.jar ($try)"; sleep 3; done
  [ -s "blib/Perl6/Optimizer.jar" ] || { echo "FAILED blib/Perl6/Optimizer.jar"; exit 1; }
else
  echo "skip blib/Perl6/Optimizer.jar (exists)"
fi
# --- step 10: blib/Perl6/Compiler.jar
step_10() {
echo '+++ Compiling	blib/Perl6/Compiler.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/Compiler.jar gen/jvm/Compiler.nqp
}
if [ ! -s "blib/Perl6/Compiler.jar" ]; then
  for try in 1 2 3; do step_10 && break; echo "retry blib/Perl6/Compiler.jar ($try)"; sleep 3; done
  [ -s "blib/Perl6/Compiler.jar" ] || { echo "FAILED blib/Perl6/Compiler.jar"; exit 1; }
else
  echo "skip blib/Perl6/Compiler.jar (exists)"
fi
# --- step 11: blib/Perl6/SysConfig.jar
step_11() {
echo '+++ Compiling	blib/Perl6/SysConfig.jar'
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' --module-path=blib --ll-exception --target=jar --output=blib/Perl6/SysConfig.jar gen/jvm/SysConfig.nqp
}
if [ ! -s "blib/Perl6/SysConfig.jar" ]; then
  for try in 1 2 3; do step_11 && break; echo "retry blib/Perl6/SysConfig.jar ($try)"; sleep 3; done
  [ -s "blib/Perl6/SysConfig.jar" ] || { echo "FAILED blib/Perl6/SysConfig.jar"; exit 1; }
else
  echo "skip blib/Perl6/SysConfig.jar (exists)"
fi
# --- step 12: rakudo-runtime.jar (Gradle)
step_12() {
echo '+++ Generating	rakudo-runtime.jar (Gradle)'
( cd rakudo-runtime && ../nqp/gradlew --console=plain jar )
cp -- rakudo-runtime/build/libs/rakudo-runtime.jar rakudo-runtime.jar
}
step_12
# --- step 13: rakudo.jar
step_13() {
echo '+++ Compiling	rakudo.jar'
java -Xmx14G --module-path /home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/truffle --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime --enable-native-access=org.graalvm.truffle --sun-misc-unsafe-memory-access=allow -cp 'blib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-tree-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/fastutil-8.5.19.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/jline-4.3.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/lz4-java-1.8.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/kotlin-stdlib-2.4.10.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/annotations-13.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-runtime.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/lib/nqp.jar:rakudo-runtime.jar:nqp/build/jvm/share/lib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-truffle.jar' nqp --module-path=blib --ll-exception --target=jar --output=rakudo.jar --javaclass=perl6 gen/jvm/rakudo.nqp
}
if [ ! -s "rakudo.jar" ]; then
  for try in 1 2 3; do step_13 && break; echo "retry rakudo.jar ($try)"; sleep 3; done
  [ -s "rakudo.jar" ] || { echo "FAILED rakudo.jar"; exit 1; }
else
  echo "skip rakudo.jar (exists)"
fi
# --- step 14: blib/Perl6/BOOTSTRAP/v6c.jar
step_14() {
echo '+++ Compiling	blib/Perl6/BOOTSTRAP/v6c.jar'
java -Xmx14G --module-path /home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/truffle --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime --enable-native-access=org.graalvm.truffle --sun-misc-unsafe-memory-access=allow -cp 'blib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-tree-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/fastutil-8.5.19.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/jline-4.3.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/lz4-java-1.8.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/kotlin-stdlib-2.4.10.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/annotations-13.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-runtime.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/lib/nqp.jar:rakudo-runtime.jar:nqp/build/jvm/share/lib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-truffle.jar' nqp --module-path=blib --ll-exception --target=jar --output=blib/Perl6/BOOTSTRAP/v6c.jar --javaclass=perl6 gen/jvm/BOOTSTRAP/v6c.nqp
}
if [ ! -s "blib/Perl6/BOOTSTRAP/v6c.jar" ]; then
  for try in 1 2 3; do step_14 && break; echo "retry blib/Perl6/BOOTSTRAP/v6c.jar ($try)"; sleep 3; done
  [ -s "blib/Perl6/BOOTSTRAP/v6c.jar" ] || { echo "FAILED blib/Perl6/BOOTSTRAP/v6c.jar"; exit 1; }
else
  echo "skip blib/Perl6/BOOTSTRAP/v6c.jar (exists)"
fi
# --- step 15: blib/CORE.c.setting.jar
step_15() {
echo '+++ Compiling	blib/CORE.c.setting.jar'
'/usr/bin/perl' -I'/home/longwalker/code/raku/x.core/rakudo/tools/lib' -I'/home/longwalker/code/raku/x.core/rakudo/3rdparty/nqp-configure/lib' '/home/longwalker/code/raku/x.core/rakudo/Configure.pl' --backends=jvm --prefix='/home/longwalker/code/raku/x.core/raku-prefix' --silent-build --expand '/home/longwalker/code/raku/x.core/rakudo/tools/templates/6.c/core_sources' \
		 --out 'gen/jvm/core_sources.c' \
		 --set-var=backend=jvm
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm -p SETTING:: -f 'gen/jvm/core_sources.c' > 'gen/jvm/CORE.c.setting'
echo 'The following step can take a long time, please be patient.'
'/usr/bin/perl' rakudo-j-build --setting=NULL.c --ll-exception --optimize=3 --target=jar --stagestats --output=blib/CORE.c.setting.jar 'gen/jvm/CORE.c.setting'
}
if [ ! -s "blib/CORE.c.setting.jar" ]; then
  for try in 1 2 3; do step_15 && break; echo "retry blib/CORE.c.setting.jar ($try)"; sleep 3; done
  [ -s "blib/CORE.c.setting.jar" ] || { echo "FAILED blib/CORE.c.setting.jar"; exit 1; }
else
  echo "skip blib/CORE.c.setting.jar (exists)"
fi
# --- step 16: blib/Perl6/BOOTSTRAP/v6d.jar
step_16() {
echo '+++ Compiling	blib/Perl6/BOOTSTRAP/v6d.jar'
java -Xmx14G --module-path /home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/truffle --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime --enable-native-access=org.graalvm.truffle --sun-misc-unsafe-memory-access=allow -cp 'blib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-tree-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/fastutil-8.5.19.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/jline-4.3.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/lz4-java-1.8.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/kotlin-stdlib-2.4.10.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/annotations-13.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-runtime.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/lib/nqp.jar:rakudo-runtime.jar:nqp/build/jvm/share/lib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-truffle.jar' nqp --module-path=blib --ll-exception --target=jar --output=blib/Perl6/BOOTSTRAP/v6d.jar --javaclass=perl6 gen/jvm/BOOTSTRAP/v6d.nqp
}
if [ ! -s "blib/Perl6/BOOTSTRAP/v6d.jar" ]; then
  for try in 1 2 3; do step_16 && break; echo "retry blib/Perl6/BOOTSTRAP/v6d.jar ($try)"; sleep 3; done
  [ -s "blib/Perl6/BOOTSTRAP/v6d.jar" ] || { echo "FAILED blib/Perl6/BOOTSTRAP/v6d.jar"; exit 1; }
else
  echo "skip blib/Perl6/BOOTSTRAP/v6d.jar (exists)"
fi
# --- step 17: blib/CORE.d.setting.jar
step_17() {
echo '+++ Compiling	blib/CORE.d.setting.jar'
'/usr/bin/perl' -I'/home/longwalker/code/raku/x.core/rakudo/tools/lib' -I'/home/longwalker/code/raku/x.core/rakudo/3rdparty/nqp-configure/lib' '/home/longwalker/code/raku/x.core/rakudo/Configure.pl' --backends=jvm --prefix='/home/longwalker/code/raku/x.core/raku-prefix' --silent-build --expand '/home/longwalker/code/raku/x.core/rakudo/tools/templates/6.d/core_sources' \
		 --out 'gen/jvm/core_sources.d' \
		 --set-var=backend=jvm
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm -p SETTING:: -f 'gen/jvm/core_sources.d' > 'gen/jvm/CORE.d.setting'
echo 'The following step can take a long time, please be patient.'
'/usr/bin/perl' rakudo-j-build --setting=NULL.d --ll-exception --optimize=3 --target=jar --stagestats --output=blib/CORE.d.setting.jar 'gen/jvm/CORE.d.setting'
}
if [ ! -s "blib/CORE.d.setting.jar" ]; then
  for try in 1 2 3; do step_17 && break; echo "retry blib/CORE.d.setting.jar ($try)"; sleep 3; done
  [ -s "blib/CORE.d.setting.jar" ] || { echo "FAILED blib/CORE.d.setting.jar"; exit 1; }
else
  echo "skip blib/CORE.d.setting.jar (exists)"
fi
# --- step 18: blib/Perl6/BOOTSTRAP/v6e.jar
step_18() {
echo '+++ Compiling	blib/Perl6/BOOTSTRAP/v6e.jar'
java -Xmx14G --module-path /home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/truffle --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime --enable-native-access=org.graalvm.truffle --sun-misc-unsafe-memory-access=allow -cp 'blib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-tree-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/fastutil-8.5.19.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/jline-4.3.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/lz4-java-1.8.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/kotlin-stdlib-2.4.10.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/annotations-13.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-runtime.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/lib/nqp.jar:rakudo-runtime.jar:nqp/build/jvm/share/lib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-truffle.jar' nqp --module-path=blib --ll-exception --target=jar --output=blib/Perl6/BOOTSTRAP/v6e.jar --javaclass=perl6 gen/jvm/BOOTSTRAP/v6e.nqp
}
if [ ! -s "blib/Perl6/BOOTSTRAP/v6e.jar" ]; then
  for try in 1 2 3; do step_18 && break; echo "retry blib/Perl6/BOOTSTRAP/v6e.jar ($try)"; sleep 3; done
  [ -s "blib/Perl6/BOOTSTRAP/v6e.jar" ] || { echo "FAILED blib/Perl6/BOOTSTRAP/v6e.jar"; exit 1; }
else
  echo "skip blib/Perl6/BOOTSTRAP/v6e.jar (exists)"
fi
# --- step 19: blib/CORE.e.setting.jar
step_19() {
echo '+++ Compiling	blib/CORE.e.setting.jar'
'/usr/bin/perl' -I'/home/longwalker/code/raku/x.core/rakudo/tools/lib' -I'/home/longwalker/code/raku/x.core/rakudo/3rdparty/nqp-configure/lib' '/home/longwalker/code/raku/x.core/rakudo/Configure.pl' --backends=jvm --prefix='/home/longwalker/code/raku/x.core/raku-prefix' --silent-build --expand '/home/longwalker/code/raku/x.core/rakudo/tools/templates/6.e/core_sources' \
		 --out 'gen/jvm/core_sources.e' \
		 --set-var=backend=jvm
'/home/longwalker/code/raku/x.core/rakudo/nqp/nqp-j-gradle' '/home/longwalker/code/raku/x.core/rakudo/tools/build/gen-cat.nqp' jvm -p SETTING:: -f 'gen/jvm/core_sources.e' > 'gen/jvm/CORE.e.setting'
echo 'The following step can take a long time, please be patient.'
'/usr/bin/perl' rakudo-j-build --setting=NULL.e --ll-exception --optimize=3 --target=jar --stagestats --output=blib/CORE.e.setting.jar 'gen/jvm/CORE.e.setting'
}
if [ ! -s "blib/CORE.e.setting.jar" ]; then
  for try in 1 2 3; do step_19 && break; echo "retry blib/CORE.e.setting.jar ($try)"; sleep 3; done
  [ -s "blib/CORE.e.setting.jar" ] || { echo "FAILED blib/CORE.e.setting.jar"; exit 1; }
else
  echo "skip blib/CORE.e.setting.jar (exists)"
fi
# --- step 20: rakudo-j
step_20() {
echo '+++ Setting up	rakudo-j'
'/usr/bin/perl' -I'/home/longwalker/code/raku/x.core/rakudo/tools/lib' -I'/home/longwalker/code/raku/x.core/rakudo/3rdparty/nqp-configure/lib' '/home/longwalker/code/raku/x.core/rakudo/tools/build/create-jvm-runner.pl' dev '/home/longwalker/code/raku/x.core/rakudo' . . '/home/longwalker/code/raku/x.core/raku-prefix/share/nqp' '/home/longwalker/code/raku/x.core/raku-prefix/share/nqp' '/home/longwalker/code/raku/x.core/raku-prefix/share/perl6' '/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-tree-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/fastutil-8.5.19.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/jline-4.3.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/lz4-java-1.8.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/kotlin-stdlib-2.4.10.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/annotations-13.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-runtime.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/lib/nqp.jar'
}
step_20
# --- step 21: rakudo-debug.jar
step_21() {
echo '+++ Compiling	rakudo-debug.jar'
java -Xmx14G --module-path /home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/truffle --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime --enable-native-access=org.graalvm.truffle --sun-misc-unsafe-memory-access=allow -cp 'blib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-tree-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/fastutil-8.5.19.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/jline-4.3.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/lz4-java-1.8.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/kotlin-stdlib-2.4.10.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/annotations-13.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-runtime.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/lib/nqp.jar:rakudo-runtime.jar:nqp/build/jvm/share/lib:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-truffle.jar' nqp --module-path=blib --ll-exception --target=jar --output=rakudo-debug.jar --javaclass=perl6 gen/jvm/rakudo-debug.nqp
}
if [ ! -s "rakudo-debug.jar" ]; then
  for try in 1 2 3; do step_21 && break; echo "retry rakudo-debug.jar ($try)"; sleep 3; done
  [ -s "rakudo-debug.jar" ] || { echo "FAILED rakudo-debug.jar"; exit 1; }
else
  echo "skip rakudo-debug.jar (exists)"
fi
# --- step 22: rakudo-debug-j
step_22() {
echo '+++ Setting up	rakudo-debug-j'
'/usr/bin/perl' -I'/home/longwalker/code/raku/x.core/rakudo/tools/lib' -I'/home/longwalker/code/raku/x.core/rakudo/3rdparty/nqp-configure/lib' '/home/longwalker/code/raku/x.core/rakudo/tools/build/create-jvm-runner.pl' dev-debug '/home/longwalker/code/raku/x.core/rakudo' . . '/home/longwalker/code/raku/x.core/raku-prefix/share/nqp' '/home/longwalker/code/raku/x.core/raku-prefix/share/nqp' '/home/longwalker/code/raku/x.core/raku-prefix/share/perl6' '/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/asm-tree-9.10.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/fastutil-8.5.19.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/jline-4.3.1.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/lz4-java-1.8.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/kotlin-stdlib-2.4.10.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/annotations-13.0.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/runtime/nqp-runtime.jar:/home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/lib/nqp.jar'
mkdir -p -- '/home/longwalker/code/raku/x.core/rakudo/gen/build_rakudo_home/templates'
cp -- src/runner/posix-runner-tmpl '/home/longwalker/code/raku/x.core/rakudo/gen/build_rakudo_home/templates'
echo '+++ Setting up JVM runner'
cp -- rakudo-j rakudo
chmod -- 755 rakudo
}
step_22
