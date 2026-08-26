#!/usr/bin/env raku
# Client for the JVM eval server (org.raku.nqp.tools.EvalServer).
#
# The protocol is one request per connection: send
# "cookie\0command\0arg...\0", then the server runs the command and streams
# whatever it printed back down the same socket. The server reads the request
# until EOF before it parses a byte, so the write side must be shut down while
# the read side stays open for the output -- a half-close that Raku's socket
# class does not expose, hence the one native call on the descriptor.
use NativeCall;

my constant SHUT_WR = 1;
sub posix-shutdown(int32, int32 --> int32) is native is symbol('shutdown') {*}
sub win32-shutdown(int32, int32 --> int32) is native('ws2_32') is symbol('shutdown') {*}
my &half-close = $*DISTRO.is-win ?? &win32-shutdown !! &posix-shutdown;

# @*ARGS directly: MAIN would parse a leading "-" in a passed-through
# argument as its own option.
if @*ARGS < 2 {
    note q:to/USAGE/;
        Usage: eval-client.raku TOKEN_FILE exit
        Usage: eval-client.raku TOKEN_FILE run args...
        USAGE
    exit 1;
}

my $token-file = @*ARGS.shift;
my $info = $token-file.IO.slurp;
$info ~~ / (\d+) ' ' (\S+) $$ / or die "cannot parse cookie file";
my ($port, $cookie) = +$0, ~$1;

my $sock = IO::Socket::INET.new(:host<127.0.0.1>, :$port);
$sock.write: ($cookie, |@*ARGS, '').join("\0").encode;
half-close($sock.native-descriptor, SHUT_WR) == 0
    or die "cannot half-close the request socket";

$*OUT.out-buffer = False;
while $sock.recv(:bin) -> $buf {
    last unless $buf.elems;
    $*OUT.write($buf);
}
$sock.close;
