diff --git a/tools/templates/jvm/Makefile.in b/tools/templates/jvm/Makefile.in
index e2027f598a..8a8977c935 100644
--- a/tools/templates/jvm/Makefile.in
+++ b/tools/templates/jvm/Makefile.in
@@ -152,36 +152,42 @@ $(RUNTIME_JAR): $(RUNTIME_SOURCES) @nfp(rakudo-runtime/build.gradle.kts)@ | $(NQ
 @bpm(RUN_RAKUDO_SCRIPT)@: @@nfp(@template(@backend_subdir@/rakudo-j-build.in)@)@@
 	$(NOECHO)$(RM_F) @q(@bpm(RUN_RAKUDO_SCRIPT)@)@
 	$(NOECHO)$(CONFIGURE) --expand @nfpq(@backend_subdir@/@bpm(RUN_RAKUDO_SCRIPT)@)@ --out @bpm(RUN_RAKUDO_SCRIPT)@ \
 		--set-var=base_dir=@q($(BASE_DIR))@ \
 		--set-var=java=$(JAVA) \
 		--set-var=classpath=@q(@nfp(./blib)@@cpsep@@nop($(BLD_NQP_JARS))@@cpsep@rakudo-runtime.jar@cpsep@rakudo.jar@cpsep@@nop($(SYSROOT))@@abs2rel(@nqp_classpath@)@)@
 
 # Milestone 7 Phase C: one training run of the trivial program fills the
 # dispatch slots of every artifact it loads (blib/*.jar, rakudo.jar and
 # nqp's lib jars). The stamp keeps make's graph honest; the grep is the
-# positive marker (a run that wrote nothing fails the build).
+# positive marker (a run that wrote nothing fails the build). The run writes
+# to the log and the log is shown afterwards, rather than piped through tee:
+# make gives each recipe line a plain sh with no pipefail, so a pipeline
+# would report tee's status and a trainer that died PART WAY -- after some
+# artifacts were rewritten, which the grep cannot tell apart from a whole
+# run -- would leave a half-trained build behind, green.
 #
 # The run rewrites those artifacts in its own order, which is not make's:
 # blib/Raku/Actions.jar landing a moment after blib/Raku/Grammar.jar would
 # make the next `make` recompile Grammar and everything below it. The
 # content changed but nothing went stale, so every rewritten artifact gets
 # one and the same mtime back -- make remakes on a STRICTLY newer
 # prerequisite -- and the stamp alone is newer than all of them. The trivial
 # program never loads 6.e (nor any later spec), so the settings and the
 # bootstraps join that one mtime explicitly: training is the last build
 # step, and everything the build produced is current as of it.
 @bpv(TRAIN_STAMP)@ = @nfp(@bpm(BLIB)@/.dispatch-trained)@
 
 @bpm(TRAIN_STAMP)@: @bsm(RAKUDO)@@for_specs( @bsm(SETTING_@ucspec@)@)@
 	@echo(+++ Training	dispatch slots)@
-	$(NOECHO)NQP_DISPATCH_RECORD=all @bpm(RUN_RAKUDO)@ -e '' 2>&1 | tee @nfpq(@bpm(BLIB)@/.dispatch-train.log)@
+	$(NOECHO)NQP_DISPATCH_RECORD=all @bpm(RUN_RAKUDO)@ -e '' > @nfpq(@bpm(BLIB)@/.dispatch-train.log)@ 2>&1 || { cat @nfpq(@bpm(BLIB)@/.dispatch-train.log)@; exit 1; }
+	$(NOECHO)cat @nfpq(@bpm(BLIB)@/.dispatch-train.log)@
 	$(NOECHO)grep -q 'dispatch-record: wrote' @nfpq(@bpm(BLIB)@/.dispatch-train.log)@
 	$(NOECHO)sed -n 's|^dispatch-record: wrote .* to ||p' @nfpq(@bpm(BLIB)@/.dispatch-train.log)@ | xargs touch -r @nfpq(@bpm(BLIB)@/.dispatch-train.log)@
 	$(NOECHO)touch -r @nfpq(@bpm(BLIB)@/.dispatch-train.log)@ @bsm(RAKUDO)@@for_specs( @bsm(SETTING_@ucspec@)@)@ @bpm(RAKUDO_BOOTSTRAP_PRECOMPS)@
 	$(NOECHO)touch $@
 
 $(J_RUNNER): @@script(create-jvm-runner.pl)@@@for_specs( @bsm(SETTING_@ucspec@)@)@ @bpm(TRAIN_STAMP)@
 	@echo(+++ Setting up	$@)@
 	$(NOECHO)$(PERL5) @shquot(@script(create-jvm-runner.pl)@)@ dev @q($(BASE_DIR))@ . . @q(@nqp_home@)@ @q(@static_nqp_home@)@ @q(@static_rakudo_home@)@ @q($(NQP_JARS))@
 
 @backend_prefix@-runner-default: @backend_prefix@-all
