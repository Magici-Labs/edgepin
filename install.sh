#!/bin/sh
# Builds EdgePin.app, installs it into ~/Applications and starts it. Re-run it
# after changing the code. Start at Login is a toggle in the app's menu.
#
# To remove:
#   pkill -x EdgePin; rm -rf ~/Applications/EdgePin.app
set -e

cd "$(dirname "$0")"
DEST="$HOME/Applications/EdgePin.app"

./make-app.sh
pkill -x EdgePin 2>/dev/null && sleep 0.5 || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R EdgePin.app "$DEST"
open "$DEST"

echo "installed $DEST"
