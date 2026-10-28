#!/usr/bin/env perl
# ============================================================================
# refresh-health.pl — incident state, notification decisions, status merge
# ============================================================================
#
#   perl scripts/refresh-health.pl --status S --state H --rc N --stage SLUG \
#                                  --since STARTED [--cooldown SECONDS] [--now E]
#   perl scripts/refresh-health.pl --status S --state H --skipped locked
#   perl scripts/refresh-health.pl --status S --state H --record-notification \
#                                  --result ok|failed|not-configured [--error TEXT]
#
# The refresh wrapper calls this once per run, after the pipeline finished, and
# once more after it tried to deliver a notification. Everything it writes is
# derived from facts the wrapper observed; nothing here guesses that a run
# succeeded.
#
# Why a separate file from the status record: refresh-site.sh describes ONE run
# (what it fetched, whether it published). This describes the RUNNING STORY
# across runs — how many consecutive failures, when the last good run was, when
# the operator was last told, and whether an incident is still open. The status
# file keeps its existing shape and gains the health fields, so every existing
# consumer (the GitHub workflow reads `release`, humans read `state`) keeps
# working.
#
# Notification policy, in one place:
#   * a failure alerts on the first failed run (a new incident), then at most
#     once per cooldown (default 3600 s) while it keeps failing — a broken
#     pipeline that fails every fifteen minutes must not send four alerts an
#     hour forever;
#   * a recovery alerts once, when a run succeeds after an open incident, and is
#     retried after the cooldown if delivery itself failed;
#   * a lock-skip changes no counter and never alerts;
#   * a failed delivery keeps the incident open and records the failure, but it
#     never replaces or hides the pipeline's own error.
#
# Secret hygiene: error text is redacted (URLs and token/secret/password
# assignments) and truncated before it is stored, and the notification endpoint
# is never stored here at all — only whether delivery worked.
#
# Exit status: 0 recorded. 64 usage error (bad or missing arguments).
# ============================================================================
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use JSON::PP ();
use POSIX qw(strftime);
use Time::Local qw(timegm);
use File::Basename qw(dirname);
use File::Path qw(make_path);

my $DEFAULT_COOLDOWN =
    (defined $ENV{PWEEVEE_NOTIFY_COOLDOWN} && $ENV{PWEEVEE_NOTIFY_COOLDOWN} =~ /^\d+$/)
    ? $ENV{PWEEVEE_NOTIFY_COOLDOWN}
    : 3600;

my %OPT = (cooldown => $DEFAULT_COOLDOWN, rc => 0);
my $MODE = 'record';

my $ok = GetOptions(
    \%OPT,
    'status=s', 'state=s', 'since=s', 'stage=s', 'rc=i', 'skipped=s',
    'now=s', 'cooldown=i', 'record-notification', 'result=s', 'error=s',
    'help|h',
);
usage(0) if $OPT{help};
usage(64) unless $ok;
$MODE = 'notify' if $OPT{'record-notification'};
usage(64, '--state is required') unless defined $OPT{state} && length $OPT{state};
usage(64, '--status is required') unless defined $OPT{status} && length $OPT{status};

# ---------------------------------------------------------------- utilities

sub usage {
    my ($code, $why) = @_;
    print STDERR "$why\n" if defined $why && length $why;
    print STDERR <<'USAGE';
refresh-health.pl --status FILE --state FILE [--rc N] [--stage SLUG]
                  [--since ISO] [--cooldown SECONDS] [--now EPOCH|ISO]
                  [--skipped REASON]
refresh-health.pl --status FILE --state FILE --record-notification
                  --result ok|failed|not-configured [--error TEXT]
USAGE
    exit $code;
}

sub iso {
    my ($e) = @_;
    return undef unless defined $e;
    return strftime('%Y-%m-%dT%H:%M:%SZ', gmtime($e));
}

sub parse_when {
    my ($s) = @_;
    return time() unless defined $s && length $s;
    return int($s) if $s =~ /^\d+$/;
    if ($s =~ /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)Z$/) {
        return timegm($6, $5, $4, $3, $2 - 1, $1);
    }
    return time();
}

sub slurp {
    my ($p) = @_;
    open(my $f, '<:raw', $p) or return undef;
    local $/;
    my $d = <$f>;
    close $f;
    return $d;
}

# tolerant by design: a truncated or hand-edited state file must never wedge
# the schedule, it just starts a fresh incident history and says so
sub read_json_file {
    my ($p) = @_;
    return (undef, 0) unless defined $p && length $p;
    my $raw = slurp($p);
    return (undef, 0) unless defined $raw;
    my $d = eval { JSON::PP->new->utf8->decode($raw) };
    return (ref $d eq 'HASH' ? $d : undef, ref $d eq 'HASH' ? 0 : 1);
}

sub prune {
    my ($v) = @_;
    if (ref $v eq 'HASH') {
        for my $k (keys %$v) {
            if (!defined $v->{$k}) { delete $v->{$k} }
            else                   { prune($v->{$k}) }
        }
    } elsif (ref $v eq 'ARRAY') {
        prune($_) for @$v;
    }
    return $v;
}

sub write_json_file {
    my ($path, $data) = @_;
    make_path(dirname($path));
    my $tmp = "$path.tmp.$$";
    open(my $f, '>:raw', $tmp) or die "write $tmp: $!\n";
    print {$f} JSON::PP->new->utf8->canonical->pretty->encode(prune($data));
    close $f or die "close $tmp: $!\n";
    rename($tmp, $path) or die "rename $tmp -> $path: $!\n";
}

# Anything that looks like a credential or an endpoint URL is removed before an
# error can reach the status file, the log or a notification body.
sub sanitize {
    my ($s) = @_;
    return '' unless defined $s;
    $s =~ s{https?://\S+}{<url>}g;
    $s =~ s{\b(token|secret|password|passwd|api[_-]?key|authorization|bearer)\b\s*[:=]?\s*\S+}{${1}=<redacted>}gi;
    $s =~ s/\s+/ /g;
    $s =~ s/^\s+|\s+$//g;
    $s = substr($s, 0, 300) . '...' if length($s) > 300;
    return $s;
}

my %LABEL = (
    fetch     => 'checking out the published tree',
    releases  => 'fetching GitHub release metadata',
    stats     => 'refreshing repository statistics',
    altsource => 'reading the SideloadLabs AltSource',
    render    => 'rendering the website',
    validate  => 'validating the rendered site',
    publish   => 'publishing to the live document root',
    pipeline  => 'refreshing the site',
    lock      => 'waiting for the previous run',
    done      => 'completing the refresh',
);

# ---------------------------------------------------------------- inputs

my $NOW      = parse_when($OPT{now});
my $NOW_ISO  = iso($NOW);
my $COOLDOWN = $OPT{cooldown} >= 0 ? $OPT{cooldown} : $DEFAULT_COOLDOWN;

my ($STATE, $state_corrupt) = read_json_file($OPT{state});
my $recovered = $state_corrupt ? 1 : 0;
$STATE = {} unless defined $STATE;

my ($STATUS, $status_corrupt) = read_json_file($OPT{status});
$STATUS = {} unless defined $STATUS;

# counters have to be numbers even after an interrupted write
$STATE->{schema} = 2;
$STATE->{consecutive_failures} =
    (defined $STATE->{consecutive_failures} && $STATE->{consecutive_failures} =~ /^\d+$/)
    ? $STATE->{consecutive_failures} : 0;
$STATE->{recovery_attempts} =
    (defined $STATE->{recovery_attempts} && $STATE->{recovery_attempts} =~ /^\d+$/)
    ? $STATE->{recovery_attempts} : 0;
$STATE->{incident_open} = _truth($STATE->{incident_open});
$STATE->{first_seen_at} //= $NOW_ISO;
$STATE->{state_recovered} = 1 if $recovered;
$STATE->{status_recovered} = 1 if $status_corrupt;

sub _truth { return (defined $_[0] && $_[0] && $_[0] ne 'false') ? 1 : 0 }

# A status file from an earlier run is not evidence about this one. When the
# wrapper fails before the pipeline starts (fetch, archive), `started` is older
# than this run and the record is rebuilt rather than reused.
my $fresh = 1;
if (defined $OPT{since} && length $OPT{since}) {
    my $started = $STATUS->{started} // '';
    $fresh = ($started ge $OPT{since}) ? 1 : 0;
}
if (!$fresh) {
    # the previous record still knows what is being served; keep that fact even
    # though it says nothing about this run
    if (($STATUS->{state} // '') eq 'ok' && length($STATUS->{release} // '')) {
        $STATE->{last_published_release} //= $STATUS->{release};
    }
    $STATUS = { started => $OPT{since}, finished => $NOW_ISO };
}

# ---------------------------------------------------------------- notify mode

if ($MODE eq 'notify') {
    my $result = $OPT{result} // '';
    usage(64, '--result must be ok, failed or not-configured')
        unless $result =~ /^(ok|failed|not-configured)$/;

    my $pending = $STATE->{pending_notification};
    $STATE->{last_notification} = $result;
    $STATE->{notify_attempt_epoch} = $NOW;
    $STATE->{last_notification_at} = $NOW_ISO;

    if ($result eq 'ok') {
        $STATE->{last_notified_at} = $NOW_ISO;
        $STATE->{notified_epoch}    = $NOW;
        delete $STATE->{last_notification_error};
    } else {
        $STATE->{last_notification_error} =
            sanitize($OPT{error} // ($result eq 'not-configured'
                ? 'no notification endpoint is configured' : 'delivery failed'));
    }

    if (ref $pending eq 'HASH') {
        my $kind = $pending->{kind} // '';
        if ($kind eq 'recovery') {
            if ($result eq 'ok' || $result eq 'not-configured') {
                # the incident is closed: a later failure starts a new one and
                # alerts immediately instead of waiting out a cooldown
                $STATE->{incident_open}   = 0;
                $STATE->{recovery_attempts} = 0;
                delete $STATE->{first_failure_at};
            } else {
                $STATE->{recovery_attempts}++;
            }
        } elsif ($kind eq 'failure') {
            $STATE->{incident_open} = 1;
        }
    }
    delete $STATE->{pending_notification};

    $STATUS->{notification} = {
        status => $result,
        at     => $NOW_ISO,
        error  => $STATE->{last_notification_error},
    };
    $STATUS->{incident}             = $STATE->{incident_open} ? 'open' : 'none';
    $STATUS->{consecutive_failures} = $STATE->{consecutive_failures};
    $STATUS->{health_updated_at}    = $NOW_ISO;

    write_json_file($OPT{state}, $STATE);
    write_json_file($OPT{status}, $STATUS);
    print JSON::PP->new->utf8->canonical->encode({
        recorded => $result,
        incident => $STATE->{incident_open} ? 'open' : 'none',
    }), "\n";
    exit 0;
}

# ---------------------------------------------------------------- record run

my $kind;
if (defined $OPT{skipped} && length $OPT{skipped}) { $kind = 'skipped' }
elsif (($OPT{rc} // 0) == 0)                      { $kind = 'success' }
else                                              { $kind = 'failure' }

my $stage = $OPT{stage} // '';
$stage = $STATUS->{stage} // '' if !length($stage) && $fresh;
$stage = 'lock' if $kind eq 'skipped';
$stage = 'pipeline' unless length $stage;

$STATE->{last_attempt_at} = $NOW_ISO;

if ($kind eq 'skipped') {
    $STATE->{last_state} = 'skipped';
    $STATE->{last_skip_at} = $NOW_ISO;
    $STATE->{last_skip_reason} = sanitize($OPT{skipped});
} elsif ($kind eq 'success') {
    $STATE->{last_state}      = 'ok';
    $STATE->{last_success_at} = $NOW_ISO;
    my $rel = $STATUS->{release} // '';
    $STATE->{last_published_release} = $rel if length $rel;
    $STATE->{consecutive_failures} = 0;
    delete $STATE->{last_error};
} else {
    $STATE->{last_state} = 'failed';
    $STATE->{last_stage} = $stage;
    $STATE->{consecutive_failures}++;
    $STATE->{first_failure_at} //= $NOW_ISO;
    $STATE->{incident_open} = 1;
    my $note = $STATUS->{note} // '';
    $STATE->{last_error} = sanitize(
        length($note) ? $note : "$LABEL{$stage} failed (exit " . ($OPT{rc} // 1) . ')');
}

# ---------------------------------------------------------------- decision

my $decision = { notify => 0, kind => 'none', reason => '' };

if ($kind eq 'failure') {
    my $new_incident = $STATE->{consecutive_failures} == 1 ? 1 : 0;
    my $since_attempt = $NOW - ($STATE->{notify_attempt_epoch} // 0);
    if ($new_incident || $since_attempt >= $COOLDOWN) {
        my $k   = $STATE->{consecutive_failures};
        my $rel = $STATE->{last_published_release} // '';
        my $first = $STATE->{first_failure_at} // $NOW_ISO;
        $decision = {
            notify => 1,
            kind   => 'failure',
            reason => $new_incident ? 'new incident' : 'cooldown elapsed',
            title  => 'PwEevee website refresh failed',
            text   => sprintf(
                'Refresh failed while %s (exit %d). Consecutive failures: %d since %s. '
              . 'The live site was not changed and still serves the last validated build '
              . '(release %s). Diagnostics: logs/refresh-status.json and logs/refresh.log '
              . 'on the site host.',
                $LABEL{$stage} // $stage, $OPT{rc} // 1, $k, $first,
                length($rel) ? $rel : 'unknown'),
        };
    } else {
        $decision->{reason} = 'cooldown';
    }
} elsif ($kind eq 'success' && $STATE->{incident_open}) {
    my $since_attempt = $NOW - ($STATE->{notify_attempt_epoch} // 0);
    if (($STATE->{recovery_attempts} // 0) == 0 || $since_attempt >= $COOLDOWN) {
        my $rel = $STATUS->{release} // $STATE->{last_published_release} // '';
        $decision = {
            notify => 1,
            kind   => 'recovery',
            reason => ($STATE->{recovery_attempts} // 0) == 0
                ? 'recovered after a failure' : 'recovery delivery retry',
            title  => 'PwEevee website refresh recovered',
            text   => sprintf(
                'Refresh succeeded at %s after %d failed run(s) since %s. '
              . 'The site now serves release %s.',
                $NOW_ISO, $STATE->{consecutive_failures},
                $STATE->{first_failure_at} // 'unknown',
                length($rel) ? $rel : 'unknown'),
        };
    } else {
        $decision->{reason} = 'cooldown';
    }
}

if ($decision->{notify}) {
    # Count the attempt now, not only after delivery: if the wrapper dies between
    # the decision and the delivery, the next run must not alert all over again.
    $STATE->{notify_attempt_epoch} = $NOW;
    $STATE->{pending_notification} = {
        kind  => $decision->{kind},
        title => $decision->{title},
        text  => $decision->{text},
        at    => $NOW_ISO,
    };
}

# ---------------------------------------------------------------- merge status

$STATUS->{state} = 'skipped' if $kind eq 'skipped';
$STATUS->{state} = 'failed'  if $kind eq 'failure';
$STATUS->{state} = 'ok'      if $kind eq 'success' && !length($STATUS->{state} // '');

$STATUS->{stage}     = $stage;
$STATUS->{started}   = $NOW_ISO  unless defined $STATUS->{started};
$STATUS->{finished}  = $NOW_ISO  unless defined $STATUS->{finished};
$STATUS->{release}   = $STATE->{last_published_release} // ''
    unless length($STATUS->{release} // '');
$STATUS->{changed}   = JSON::PP::false unless exists $STATUS->{changed};
$STATUS->{published} = JSON::PP::false unless exists $STATUS->{published};

$STATUS->{skipped_at} = $NOW_ISO if $kind eq 'skipped';
$STATUS->{checked_at} = $NOW_ISO;

$STATUS->{note} = 'another refresh is still running'
    if $kind eq 'skipped' && !length($STATUS->{note} // '');
# a pipeline note can carry a URL or a token; the stored copy is redacted
$STATUS->{note} = $STATE->{last_error} if $kind eq 'failure';

$STATUS->{last_success_at}        = $STATE->{last_success_at};
$STATUS->{last_published_release} = $STATE->{last_published_release};
$STATUS->{consecutive_failures}   = $STATE->{consecutive_failures};
$STATUS->{incident}               = $STATE->{incident_open} ? 'open' : 'none';
$STATUS->{notification}           = {
    status => $STATE->{last_notification} // 'none',
    at     => $STATE->{last_notified_at},
    error  => $STATE->{last_notification_error},
};
$STATUS->{health_updated_at} = $NOW_ISO;

write_json_file($OPT{state}, $STATE);
write_json_file($OPT{status}, $STATUS);

print JSON::PP->new->utf8->canonical->encode($decision), "\n";
exit 0;
