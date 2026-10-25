package PwHttp;
# ============================================================================
# PwHttp — the one HTTP client the PwEevee website tooling uses
# ============================================================================
#
# Extracted from update-releases.pl so that every updater speaks to the network
# through exactly one implementation:
#
#   update-releases.pl    GitHub REST API      -> website/data/releases.json
#   update-altsource.pl   SideloadLabs source  -> website/data/altsource.json
#
# Core Perl only, plus whichever of curl/wget is installed. No CPAN.
#
# Token handling: a bearer token is handed to curl through a 0600 config file so
# it never appears in the process list, and it is never returned to the caller.
# wget cannot do that safely, so an authenticated request is refused there.
use strict;
use warnings;
use Exporter 'import';
use File::Path qw(make_path remove_tree);
use File::Spec;
use PwSite qw(slurp spew is_safe_url);

our @EXPORT_OK = qw(http_init http_client http_get http_head http_cleanup);

my $CLIENT;     # 'curl' | 'wget'
my $TMP;        # scratch directory for client config / stderr
my $UA = 'PwEevee-release-updater';

# ---------------------------------------------------------------- lifecycle

# http_init(tmp_dir => ..., user_agent => ...) -> 'curl' | 'wget'
#
# The scratch directory must be a REPO-RELATIVE path. On Windows the perl that
# ships with Git uses MSYS paths while curl.exe is a native binary, and the two
# disagree about what "/tmp/x" means; a relative path is understood identically
# by both.
sub http_init {
    my (%opt) = @_;
    $TMP = $opt{tmp_dir} || 'PwEvevee/build-system/_work/net';
    $UA  = $opt{user_agent} if $opt{user_agent};
    make_path($TMP);
    $CLIENT = pick_client();
    return $CLIENT;
}

sub http_client { return $CLIENT }

sub http_cleanup { remove_tree($TMP) if defined $TMP && -d $TMP }

sub pick_client {
    for my $c (qw(curl wget)) {
        my $null = File::Spec->devnull;
        return $c if system("$c --version > $null 2> $null") == 0;
    }
    die "neither curl nor wget is available; cannot reach the network\n";
}

# ---------------------------------------------------------------- requests

# http_get($url, %opt) -> ($status, $body) or, with with_headers => 1,
#                                ($status, $body, \%headers)
#
# $status is undef when the client could not run at all. Options:
#   headers      => [ 'Accept: application/json', ... ]
#   token        => bearer token (curl only)
#   timeout      => seconds (default 45)
#   with_headers => capture the response headers (curl dumps them to a temp
#                   file; wget already prints them to stderr and they are
#                   parsed from there). Callers that want response headers —
#                   for example conditional-request ETags — opt in here so the
#                   two-value contract of every existing caller stays
#                   untouched.
sub http_get {
    my ($url, %opt) = @_;
    die "http_init must be called before http_get\n" unless $CLIENT;
    my $timeout = $opt{timeout} || 45;
    my @headers = @{ $opt{headers} || [] };

    my $want_headers = $opt{with_headers};

    if ($CLIENT eq 'curl') {
        my $hdr_file = "$TMP/response-headers.txt";
        my $cfg = qq{url = "$url"\n};
        $cfg .= qq{header = "$_"\n} for @headers;
        $cfg .= qq{user-agent = "$UA"\n}
              . "silent\nshow-error\nlocation\n"
              . "max-time = $timeout\nretry = 2\n"
              . qq{write-out = "\\n%{http_code}"\n};
        $cfg .= qq{dump-header = "$hdr_file"\n} if $want_headers;
        $cfg .= qq{header = "Authorization: Bearer $opt{token}"\n} if $opt{token};
        my $out = run_curl($cfg);
        if ($want_headers) {
            return (undef, '', {}) unless defined $out;
            my ($code, $body) = split_status($out);
            return ($code, $body, parse_headers($hdr_file));
        }
        return (undef, '') unless defined $out;
        return split_status($out);
    }

    my @cmd = ('wget', '-q', '-O', '-', '--tries=2', "--timeout=$timeout",
               '--content-on-error', '--server-response', "--user-agent=$UA");
    push @cmd, "--header=$_" for @headers;
    push @cmd, $url;
    my $r = run_capture(\@cmd, 'wget.err');
    return (undef, '', {}) unless defined $r;
    my @codes = $r->{stderr} =~ m{HTTP/[\d.]+\s+(\d{3})}g;
    my $code  = @codes ? $codes[-1] + 0 : (length $r->{stdout} ? 200 : undef);
    if ($want_headers) {
        # wget's -S writes the response headers to stderr; parse from there.
        my %h;
        for my $line (split /\r?\n/, $r->{stderr}) {
            next unless $line =~ /^\s*([A-Za-z0-9-]+):\s*(.*?)\s*\r?$/;
            $h{ lc $1 } = $2;
        }
        return ($code, $r->{stdout}, \%h);
    }
    return ($code, $r->{stdout});
}

# Parse a curl dump-header file into a lowercase-keyed hash. Best-effort: an
# unreadable or missing file yields an empty hash, never an error.
sub parse_headers {
    my ($file) = @_;
    my %h;
    local $/;
    if (open my $fh, '<', $file) {
        for my $line (split /\r?\n/, <$fh>) {
            next unless $line =~ /^([A-Za-z0-9-]+):\s*(.*?)\s*\r?$/;
            $h{ lc $1 } = $2;
        }
        close $fh;
    }
    unlink $file if -f $file;
    return \%h;
}

# http_head($url) -> $status or undef
sub http_head {
    my ($url, %opt) = @_;
    die "http_init must be called before http_head\n" unless $CLIENT;
    return undef unless is_safe_url($url);
    my $timeout = $opt{timeout} || 30;

    if ($CLIENT eq 'curl') {
        my $out = run_curl(<<"CFG");
url = "$url"
head
silent
show-error
location
max-time = $timeout
user-agent = "$UA"
write-out = "\\n%{http_code}"
CFG
        return undef unless defined $out;
        my ($code) = split_status($out);
        return $code;
    }
    my $r = run_capture(['wget', '--spider', '-S', '-q', "--timeout=$timeout", $url], 'wget.err');
    return undef unless defined $r;
    my @codes = $r->{stderr} =~ m{HTTP/[\d.]+\s+(\d{3})}g;
    return $codes[-1];
}

# ---------------------------------------------------------------- plumbing

# curl's write-out appends "\n<status>" after the body.
sub split_status {
    my ($out) = @_;
    return ($1 + 0, $out) if $out =~ s/\r?\n(\d{3})[\r\n\s]*\z//;
    return (undef, $out);
}

# curl reads its options from a 0600 config file, so an Authorization header
# never shows up in the process list.
sub run_curl {
    my ($cfg) = @_;
    my $cfg_file = "$TMP/curl.conf";
    spew($cfg_file, $cfg);
    chmod 0600, $cfg_file;
    my $out = qx{curl --config "$cfg_file" 2>"$TMP/curl.err"};
    my $status = $?;
    unlink $cfg_file;
    return undef if $status == -1;
    if ($status != 0) {
        my $err = -f "$TMP/curl.err" ? slurp("$TMP/curl.err") : '';
        $err =~ s/\s+/ /g;
        warn "!! curl: $err\n" if $err =~ /\S/;
        return undef unless defined $out && length $out;
    }
    return $out;
}

# Runs a command, returning { stdout => ..., stderr => ... } or undef.
sub run_capture {
    my ($cmd, $errfile) = @_;
    my @quoted = map { my $s = $_; $s =~ s/"/\\"/g; qq{"$s"} } @$cmd;
    my $out = qx{@{[ join ' ', @quoted ]} 2>"$TMP/$errfile"};
    return undef if $? == -1;
    return {
        stdout => (defined $out ? $out : ''),
        stderr => (-f "$TMP/$errfile" ? slurp("$TMP/$errfile") : ''),
    };
}

1;
