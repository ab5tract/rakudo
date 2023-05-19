# This file contains the default class for turning RakUAST::Doc::xxx
# classes into legacy pod6 objects.

class RakuAST::LegacyPodify {

    my int32 $nl     =     10;  # "\n"
    my int32 $space  =     32;  # " "
    my int32 $nbsp   = 0x00A0;  # NO-BREAK SPACE
    my int32 $nnbsp  = 0x202F;  # NARROW NO-BREAK SPACE
    my int32 $wj     = 0x2060;  # WORD JOINER
    my int32 $zwnbsp = 0xFEFF;  # ZERO WIDTH NO-BREAK SPACE
    my int   $gcprop = nqp::unipropcode("General_Category");

    # basically mangle text to just single spaces
    my sub sanitize(str $string, :$add-space --> Str:D) {
        return ' ' if $string eq "\n";

        nqp::strtocodes($string,nqp::const::NORMALIZE_NFC,my int32 @input);
        my int $end = nqp::elems(@input);
        return '' unless $end;

        # remove any trailing newlines
        nqp::while(
          $end && nqp::iseq_i(nqp::atpos_i(@input,--$end),$nl),
          nqp::pop_i(@input)
        );

        my int32 @output;
        my int32 $curr;
        my int32 $prev;
        my str   $prop;
        my int $i = -1;

        # step through all codes, make the non-breaking whitespace act as
        # normal characters, and collapse all other consecutive whitespace
        # into a single space character
        nqp::while(
          nqp::isle_i(++$i,$end),
          nqp::if(                                    # for all codes
            nqp::iseq_i(($curr = nqp::atpos_i(@input,$i)),$nbsp)
              || nqp::iseq_i($curr,$nnbsp)
              || nqp::iseq_i($curr,$wj)
              || nqp::iseq_i($curr,$zwnbsp),
            nqp::push_i(@output,$prev = $curr),       # non-breaking whitespace
            nqp::if(                                  # not nb whitespace
              nqp::iseq_s(($prop=nqp::getuniprop_str($curr,$gcprop)),'Zs')
                || nqp::iseq_s($prop,'Cf')
                || nqp::iseq_s($prop,'Cc'),
              nqp::if(                                # all other whitespace
                nqp::isne_i($prev,$space),
                nqp::push_i(@output,$prev = $space),  # after non-ws, add space
              ),
              nqp::push_i(@output,$prev = $curr)      # all ok, just copy
            )
          )
        );

        # add a space if there is something and were asked to add one
        @output.push($space) if $add-space && nqp::elems(@output);

        nqp::strfromcodes(@output)
    }

    # sanitize the given cell, including any handling of markup
    my sub table-sanitize($cell --> Str:D) {
        sanitize(nqp::istype($cell,RakuAST::Doc::Paragraph)
          ?? $cell.atoms.map({
               nqp::istype($_,Str)
                 ?? $_
                 !! .letter eq 'Z'
                   ?? ""
                   !! .Str
             }).join
          !! $cell
        ).trim.subst(Q/\+/, '+', :global).subst(Q/\|/, '|', :global)
    }

    # hide the outer markup
    my sub hide(RakuAST::Doc::Markup:D $markup) {
        my @atoms = $markup.atoms;
        given @atoms.head {
            nqp::istype($_,Str)
              ?? ($_ = $markup.opener ~ $_)
              !! @atoms.unshift($markup.opener)
        }
        given @atoms.tail {
            nqp::istype($_,Str)
              ?? ($_ = $_ ~ $markup.closer)
              !! @atoms.posh($markup.closer)
        }
        nqp::istype(@atoms.are,Str)
          ?? @atoms.join
          !! @atoms.map({ nqp::istype($_,Str) ?? $_ !! .podify }).Slip
    }

    # flatten the markup into a string, needed for V<>
    my sub flatten(RakuAST::Doc::Markup:D $markup, :$render --> Str:D) {
        my str @parts;
        for $markup.atoms {
            @parts.push: nqp::isstr($_) ?? $_ !! flatten($_, :render);
        }

        # V<> inside V<> *are* rendered
        if $render {
            @parts.unshift: '<';
            @parts.unshift: $markup.letter;
            @parts.push: '>';
        }

        nqp::join('',@parts)
    }

    # produce list without last if last is \n
    my sub no-last-nl(\list) {
        my @parts = list;
        @parts.pop if nqp::istype($_,Str) && $_ eq "\n" given @parts.tail;
        @parts
    }

    # create podified contents for atoms
    method !contentify-atoms($ast) {
        my str @parts;
        my @atoms = $ast.atoms.map({
            nqp::istype($_,Str) ?? $_ !! .podify  # may Slip
        }).map({

            # collect any strings
            if nqp::istype($_,Str) {
                @parts.push: $_;
                Empty
            }

            # something else, produce with any strings preceding
            elsif @parts {
                my str $string = @parts.join;
                @parts = ();
                ($string, $_).Slip
            }

            # just produce, already podified
            else {
                $_
            }
        });

        # collect any uncollected strings so far
        @atoms.push: @parts.join if @parts;

        # string at left needs to be trimmed left
        if @atoms.head <-> $_ {
            $_ = .trim-leading if nqp::istype($_,Str);
        }

        # return strings if just strings
        nqp::istype(@atoms.are,Str) ?? @atoms.join !! @atoms
    }

    proto method podify(|) {*}

    # Base class catcher
    multi method podify(RakuAST::Doc:D $ast) {
        NYI("Podifying $ast.^name() objects").throw
    }

    # Odd value catcher, avoiding long dispatch options in error message
    multi method podify(Mu:D $ast) {
        die "You cannot podify a $ast.^name() instance: $ast.raku()";
    }
    multi method podify(Mu:U $ast) {
        die "You cannot podify a $ast.^name() type object";
    }

    multi method podify(RakuAST::Doc::Markup:D $ast) {
        my str $letter = $ast.letter;
        $letter eq ""
          ?? hide($ast)
          !! $letter eq 'V'
            ?? flatten($ast)
            !! Pod::FormattingCode.new(
                 type     => $letter,
                 meta     => $ast.meta,
                 contents => self!contentify-atoms($ast)
               )
    }

    multi method podify(RakuAST::Doc::Paragraph:D $ast) {
        my int $left = $ast.atoms.elems;
        Pod::Block::Para.new(
          contents => no-last-nl($ast.atoms).map({
              --$left;
              nqp::istype($_,Str)
                ?? sanitize($_, :add-space($left && .ends-with("\n"))) || Empty
                !! self.podify($_)
          }).Slip
        )
    }

    multi method podify(RakuAST::Doc::Block:D $ast) {
        my str $type  = $ast.type;
        my str $level = $ast.level;

        # these need code of its own, as the new grammar only collects
        # and does not do any interpretation
        unless $level {
            return self.podify-table($ast)
              if $type eq 'table';
            return self.podify-code($ast, $type)
              if $type eq 'code' | 'input' | 'output';
            return self.podify-implicit-code($ast)
              if $type eq 'implicit-code';
            return self.podify-defn($ast)
              if $type eq 'defn';
        }

        my $config   := $ast.config;
        my $contents := no-last-nl($ast.paragraphs).map({
            if nqp::istype($_,Str) {
                if sanitize(.trim-leading) -> $contents {
                    Pod::Block::Para.new(:$contents)
                }
            }
            else {
                self.podify($_)
            }
        }).List;

        $type
          ?? $type eq 'item'
            ?? Pod::Item.new(
                 level => $level ?? $level.Int !! 1, :$config, :$contents
               )
            !! $level
              ?? $type eq 'head'
                ?? Pod::Heading.new(:level($level.Int), :$config, :$contents)
                !! Pod::Block::Named.new(
                     :name($type ~ $level), :$config, :$contents
                   )
              # from here on without level
              !! $type eq 'comment'
                ?? Pod::Block::Comment.new(
                     :$config, :contents([$ast.paragraphs.head])
                   )
                !! $type eq 'config' && $ast.abbreviated
                  ?? Pod::Config.new(
                       :type($ast.paragraphs.head), :config($ast.config)
                     )
                  !! Pod::Block::Named.new(:name($type), :$config, :$contents)
          !! $contents  # no type means just a string
    }

    method podify-table(RakuAST::Doc::Block:D $ast) {
        my @rows    = $ast.paragraphs.grep(RakuAST::Doc::Row);
        my $config := $ast.config;

        # Make sure that all rows have the same number of cells
        my $nr-columns := @rows.map(*.cells.elems).max;
        my sub spread(\cells) {
            cells.elems == $nr-columns
              ?? cells
              !! (cells.Slip, ("" xx $nr-columns - cells.elems).Slip)
        }

        # determine whether we have headers
        my $headers;
        with $config<header-row> -> $index {
            $headers := @rows.splice($index, 1);
        }

        # no explicit header specification: use legacy heuristic of
        # second divider being different from the first divider
        else {
            my $seen-row;
            my $first-divider;
            my int $other-dividers;

            # Create list of paragraphs without any trailing divider,
            # to make the header determination logic easier.
            my @paragraphs = $ast.paragraphs;
            @paragraphs.pop if nqp::istype(@paragraphs.tail,Str);

            for @paragraphs {
                # is it a divider?
                if nqp::istype($_,Str) {

                    # seen a divider after a row before?
                    if $first-divider.defined {
                        if $_ ne $first-divider {
                            $headers := @rows.shift;
                            last;  # different, we're done!
                        }
                        ++$other-dividers;
                    }

                    # seen a row before?
                    elsif $seen-row {
                        $first-divider := $_;
                    }
                }

                # it's a row
                else {
                    $seen-row = True;
                }
            }

            # set headers if only one divider was seen after the first row
            $headers := @rows.shift
              if !$headers && $first-divider.defined && !$other-dividers;
        }

        my $has-data;              # flag: True if actual rows where found
        my $previous-was-divider;  # flag: True if previous row was divider
        for $ast.paragraphs -> $row {
            if nqp::istype($row,Str) {
                if $previous-was-divider {
                    $ast.sorry-ad-hoc:
                      "Table has multiple interior row separator lines.",
                      "dummy argument that is somehow needed";
                    last;
                }
                $previous-was-divider := True;
            }
            else {
                $has-data             := True;
                $previous-was-divider := False;
            }
        }

        $ast.sorry-ad-hoc(
          "Table has no data.",
          "dummy argument that is somehow needed"
        ) unless $has-data;

        $headers := [spread .cells.map(&table-sanitize)] with $headers;
        Pod::Block::Table.new(
          caption  => $config<caption> // "",
          headers  => $headers // [],
          config   => $config,
          contents => @rows.map({ [spread .cells.map(&table-sanitize)] })
        )
    }

    method podify-code(RakuAST::Doc::Block:D $ast, Str:D $type) {
        my @contents = $ast.paragraphs.map({
            (nqp::istype($_,Str)
              ?? .split("\n", :v, :skip-empty)
              # assume a paragraph with string / markup atoms
              !! .atoms.map({
                    nqp::istype($_,Str)
                      ?? .split("\n", :v, :skip-empty).Slip
                      !! .podify
                 })
            ).Slip
        });

        ::("Pod::Block::$type.tc()").new: :@contents, :config($ast.config)
    }

    method podify-implicit-code(RakuAST::Doc::Block:D $ast) {
        Pod::Block::Code.new:
          :contents($ast.paragraphs.head.trim)
          :config($ast.config)
    }

    method podify-defn(RakuAST::Doc::Block:D $ast) {
        my @paragraphs = $ast.paragraphs;

        my $first := @paragraphs.shift;
        $first    := $first.atoms.map(*.Str).join
          unless nqp::istype($first,Str);
        my ($term, $para) = $first.split("\n",2).map(&sanitize);

        my @contents = Pod::Block::Para.new(:contents($para));
        for @paragraphs {
            @contents.push: nqp::istype($_,Str)
              ?? Pod::Block::Para.new(:contents(.chomp))
              !! .podify
        }

        Pod::Defn.new: :$term, :@contents, :config($ast.config)
    }

    multi method podify(RakuAST::Doc::Declarator:D $ast, $WHEREFORE) {
        sub normalize(@paragraphs) {
            @paragraphs
              .map(*.lines.map({.trim if $_}).Slip)
              .join(' ')
              .trim-trailing
        }

        my $leading := %*ENV<RAKUDO_POD_DECL_BLOCK_USER_FORMAT>
          ?? $ast.leading.join("\n")
          !! normalize($ast.leading);
        my $trailing := normalize $ast.trailing;

        my %args;
        %args<WHEREFORE> = $WHEREFORE;
        %args<leading>   = [$leading]  if $leading;
        %args<trailing>  = [$trailing] if $trailing;

        my $pod := Pod::Block::Declarator.new(|%args);
        $WHEREFORE.set_why($pod);
        $pod
    }
}

# vim: expandtab shiftwidth=4
