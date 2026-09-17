#!/bin/sh
# Regenerate the alert clips with the Mac's built-in voice. Run from anywhere:
#
#     sh Scripts/generate_audio.sh
#
# Then build and install the app as usual (README, "Weekly reinstall").
# To try a different voice:  say -v '?'   lists them;  then
#     python3 Scripts/generate_audio.py --engine say --voice Daniel
set -e
cd "$(dirname "$0")/.."
exec python3 Scripts/generate_audio.py --engine say "$@"
