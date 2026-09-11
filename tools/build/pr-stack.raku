#!/usr/bin/env raku
# pr-stack.raku -- rebuild a long branch as a stack of squashed PR sections.
#
# A plan directory holds one *.plan file per PR (format: see the header of
# docs/jvm-pr-stack.md, or FORMAT.md next to the plans).  Each file lists
# groups; each group becomes ONE commit made by cherry-picking its source
# commits (in the listed order) with --no-commit and committing the result
# with the group's message.  The last group of a file is that PR's boundary,
# and a branch named by the file's `branch:` line is put there.
#
#   check  --tree=DIR --base=REF --head=REF PLANDIR
#       parse every plan, resolve every hash, prove base..head is covered
#       exactly once (no strays, no duplicates), print the group counts.
#   build  --tree=DIR --base=REF --head=REF PLANDIR [--resume]
#       DIR must be a checkout of the repository whose HEAD you are willing
#       to lose (a scratch `git worktree`): the branch is rebuilt there from
#       BASE, and at the end the tree is compared with HEAD -- it must be
#       identical.  Progress is recorded in PLANDIR/.progress-<tree>; a
#       conflict stops the run with the group named, and --resume continues
#       after you have resolved it (leave the resolved changes staged, do
#       not commit them: the tool commits the group).
#
# The rebuilt commits keep the FIRST source commit's author (name, email) and
# calendar day, but are stamped after work hours (18:00-23:00, see
# after-hours-stamps); `= keep` groups reuse the source commit's message
# verbatim, every other group gets the plan's message plus --trailer.

my %*SUB-MAIN-OPTS = :named-anywhere;

class Group {
    has Str  $.subject;
    has Str  @.body;
    has Bool $.keep = False;
    has Str  @.hashes;
    has Int  $.line;
}
class Plan {
    has Str   $.file;
    has Str   $.pr;
    has Str   $.title;
    has Str   $.branch;
    has Group @.groups;
}

sub parse-plan(IO::Path $file --> Plan) {
    my ($pr, $title, $branch);
    my Group @groups;
    my ($subject, @body, @hashes, $keep, $gline);
    my $n = 0;
    sub flush() {
        return without $subject;
        die "$file:$gline: group '$subject' has no commits" unless @hashes;
        die "$file:$gline: a '= keep' group must have exactly one commit" if $keep && @hashes != 1;
        @groups.push: Group.new(:$subject, :body(@body.clone), :$keep, :hashes(@hashes.clone), :line($gline));
        $subject = Nil; @body = (); @hashes = (); $keep = False;
    }
    for $file.lines -> $raw {
        $n++;
        my $line = $raw.trim-trailing;
        next if $line ~~ /^ \s* '#' /;
        next if $line ~~ /^ \s* $/;
        if $line ~~ /^ 'pr:' \s* (\S+) / { $pr = ~$0; next }
        if $line ~~ /^ 'title:' \s* (.+) / { $title = ~$0; next }
        if $line ~~ /^ 'branch:' \s* (\S+) / { $branch = ~$0; next }
        if $line ~~ /^ '=' \s+ (.+) / {
            flush();
            $subject = ~$0; $gline = $n;
            $keep = $subject eq 'keep';
            next;
        }
        if $line ~~ /^ '-' \s+ (<xdigit> ** 7..40) / {
            die "$file:$n: a commit line before the first '= ' group" without $subject;
            @hashes.push: ~$0;
            next;
        }
        with $subject {
            die "$file:$n: body text after the commit lines of '$subject'" if @hashes;
            die "$file:$n: a '= keep' group takes no body" if $keep;
            @body.push: $line;
            next;
        }
        die "$file:$n: unrecognized line: $raw";
    }
    flush();
    die "$file: no 'pr:' line" without $pr;
    die "$file: no 'title:' line" without $title;
    $branch //= "pr/$pr";
    Plan.new(:file($file.basename), :$pr, :$title, :$branch, :@groups);
}

sub git(IO::Path $tree, *@args, Bool :$quiet, Bool :$ok) {
    my $p = run 'git', '-C', $tree.Str, |@args, :out, :err;
    my $out = $p.out.slurp(:close);
    my $err = $p.err.slurp(:close);
    if $p.exitcode != 0 && !$ok {
        note "git @args[] failed:\n$out$err";
        die "git failed";
    }
    $quiet ?? $p.exitcode !! $out.chomp;
}

sub load-plans(IO::Path $dir --> List) {
    my @files = $dir.dir(test => /'.plan' $/).sort(*.basename);
    die "no *.plan files in $dir" unless @files;
    @files.map(&parse-plan).List;
}

sub validate(IO::Path $tree, Str $base, Str $head, @plans) {
    my @range = git($tree, 'rev-list', '--reverse', "$base..$head").lines;
    my %pos = @range.antipairs;
    my %seen;
    my $errors = 0;
    my @resolved;
    for @plans -> $plan {
        for $plan.groups -> $g {
            my @full;
            for $g.hashes -> $h {
                my $full = git($tree, 'rev-parse', '--verify', '--quiet', "$h^\{commit\}", :ok);
                if $full eq '' { note "{$plan.file}:{$g.line}: $h does not resolve"; $errors++; next }
                if %seen{$full}:exists { note "{$plan.file}:{$g.line}: $h listed twice (first in %seen{$full})"; $errors++ }
                %seen{$full} = "{$plan.file}:{$g.line}";
                unless %pos{$full}:exists { note "{$plan.file}:{$g.line}: $h is not in $base..$head"; $errors++ }
                @full.push: $full;
            }
            @resolved.push: @full;
        }
    }
    for @range -> $c {
        next if %seen{$c}:exists;
        note "not covered by any plan: $c {git($tree, 'log', '-1', '--format=%s', $c)}";
        $errors++;
    }
    # order report: a group whose hashes are not ascending in history is a move
    my $moves = 0;
    for @plans -> $plan {
        my $last = -1;
        for $plan.groups -> $g {
            for $g.hashes -> $h {
                my $full = git($tree, 'rev-parse', '--verify', '--quiet', "$h^\{commit\}", :ok);
                next if $full eq '' || !(%pos{$full}:exists);
                if %pos{$full} < $last { $moves++ }
                $last = max($last, %pos{$full});
            }
        }
    }
    die "$errors problem(s) found" if $errors;
    say "plans cover $base..$head exactly once: {@range.elems} commits, {@plans.elems} PRs, {[+] @plans.map(*.groups.elems)} groups, $moves commits applied out of history order";
}

# Every rebuilt commit is stamped after work hours: the calendar day of the
# group's first source commit (never earlier than the previous group's day,
# so the log stays monotonic), the day's groups spread evenly over
# 18:00-23:00 in the source commit's own timezone.
sub after-hours-stamps(IO::Path $tree, @plans --> Hash) {
    my @keys;
    my %day; my %tz;
    my $prev-day = '';
    for @plans -> $plan {
        for $plan.groups.kv -> $i, $g {
            my $key = "{$plan.pr}/$i";
            my $ai = git($tree, 'log', '-1', '--format=%ai', $g.hashes[0]);   # 2026-08-13 14:22:01 +0200
            my ($day, $, $tz) = $ai.words;
            $day = $prev-day if $day lt $prev-day;
            $prev-day = $day;
            @keys.push: $key; %day{$key} = $day; %tz{$key} = $tz;
        }
    }
    my %per-day = @keys.classify({ %day{$_} });
    my %stamp;
    for %per-day.kv -> $day, @ks {
        my $n = @ks.elems;
        for @ks.kv -> $k, $key {
            my $secs = 18 * 3600 + (($k + 0.5) * 5 * 3600 / $n).Int;
            my $h = $secs div 3600; my $m = ($secs mod 3600) div 60; my $s = $secs mod 60;
            %stamp{$key} = sprintf "%s %02d:%02d:%02d %s", $day, $h, $m, $s, %tz{$key};
        }
    }
    %stamp;
}

multi sub MAIN('check', Str $plandir, Str :$tree!, Str :$base!, Str :$head!) {
    my @plans = load-plans($plandir.IO);
    validate($tree.IO, $base, $head, @plans);
    for @plans -> $p {
        say sprintf "  %-4s %-36s %3d -> %2d   %s", $p.pr, $p.branch, ([+] $p.groups.map(*.hashes.elems)), $p.groups.elems, $p.title;
    }
}

multi sub MAIN('build', Str $plandir, Str :$tree!, Str :$base!, Str :$head!, Bool :$resume, Str :$trailer) {
    my $dir = $tree.IO;
    my @plans = load-plans($plandir.IO);
    validate($dir, $base, $head, @plans);
    my $progress = $plandir.IO.add(".progress-{$dir.basename}");
    my %done = $resume && $progress.e ?? $progress.lines.map({ $_ => True }) !! ();
    unless $resume {
        die "$dir is not clean; refusing to build" if git($dir, 'status', '--porcelain').chars;
        git($dir, 'checkout', '--detach', $base);
        $progress.spurt('');
    }
    my $trailer-text = $trailer // '';
    my %stamp = after-hours-stamps($dir, @plans);
    for @plans -> $plan {
        for $plan.groups.kv -> $i, $g {
            my $key = "{$plan.pr}/$i";
            next if %done{$key};
            for $g.hashes -> $h {
                my $rc = git($dir, 'cherry-pick', '--no-commit', '--allow-empty', $h, :quiet, :ok);
                if $rc != 0 {
                    # an empty pick (a revert pair netting to nothing) leaves a clean tree
                    my $dirty = git($dir, 'diff', '--cached', '--quiet', :quiet, :ok) != 0
                             || git($dir, 'diff', '--quiet', :quiet, :ok) != 0;
                    my $conflicts = git($dir, 'diff', '--name-only', '--diff-filter=U');
                    if $conflicts.chars {
                        note "CONFLICT in {$plan.file} group $i ('{$g.subject}') at $h:\n$conflicts";
                        note "resolve in $dir, `git add` the files, then rerun with --resume (the group is committed by the tool)";
                        exit 2;
                    }
                    if !$dirty {
                        note "  (empty: $h)";
                        git($dir, 'cherry-pick', '--quit', :quiet, :ok);
                        next;
                    }
                    note "cherry-pick $h failed in {$plan.file} group $i";
                    exit 2;
                }
            }
            my $first = $g.hashes[0];
            my ($an, $ae) = git($dir, 'log', '-1', '--format=%an%n%ae', $first).lines;
            my $when = %stamp{$key};
            my @env = "GIT_AUTHOR_NAME=$an", "GIT_AUTHOR_EMAIL=$ae",
                      "GIT_AUTHOR_DATE=$when", "GIT_COMMITTER_DATE=$when";
            my $staged = git($dir, 'diff', '--cached', '--quiet', :quiet, :ok) != 0;
            unless $staged {
                note "  group $i of {$plan.file} ('{$g.subject}') produced no change -- skipped";
                $progress.spurt("$key\n", :append);
                next;
            }
            my $msg;
            if $g.keep {
                $msg = git($dir, 'log', '-1', '--format=%B', $first) ~ "\n";
            }
            else {
                $msg = $g.subject ~ "\n";
                $msg ~= "\n" ~ $g.body.join("\n") ~ "\n" if $g.body;
                $msg ~= "\n$trailer-text\n" if $trailer-text.chars;
            }
            my $mf = $plandir.IO.add('.msg');
            $mf.spurt($msg);
            my $p = run 'env', |@env, 'git', '-C', $dir.Str, 'commit', '--quiet', '-F', $mf.Str, :out, :err;
            die "commit failed: {$p.err.slurp}" if $p.exitcode;
            say sprintf "%-5s %-40s <- %d", $plan.pr, $g.subject.substr(0, 40), $g.hashes.elems;
            $progress.spurt("$key\n", :append);
        }
        git($dir, 'branch', '-f', $plan.branch, 'HEAD');
        say "== {$plan.branch} at {git($dir, 'rev-parse', '--short', 'HEAD')}: {$plan.title}";
    }
    my $same = git($dir, 'diff', '--quiet', $head, 'HEAD', :quiet, :ok) == 0;
    say $same
        ?? "TREE IDENTICAL to $head: {git($dir, 'rev-list', '--count', "$base..HEAD")} commits over $base"
        !! "TREE DIFFERS from $head -- do not use this branch";
    exit($same ?? 0 !! 1);
}
