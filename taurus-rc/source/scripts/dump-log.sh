#!/usr/bin/env bash
# Streams the tweak's log lines from the iPhone plugged into this Mac. Ctrl-C stops it.
#
#   scripts/dump-log.sh > out/spotifyglass.log     # then kill and relaunch Spotify on the phone
#   scripts/dump-log.sh -n                         # over Wi-Fi
#
# The hierarchy dumps arrive as numbered parts ("now playing hierarchy 3/9").
#
# Matched on the tweak's own prefix alone. -p Spotify used to work and now lets nothing through,
# not even the thousand lines a second Spotify(CoreFoundation) writes, once the app is signed under
# a certificate's App ID; every line SGLog writes carries [spotifyglass], which is enough on its own.
exec idevicesyslog -m "[spotifyglass]" "$@"
