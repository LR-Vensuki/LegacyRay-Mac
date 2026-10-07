#!/bin/sh
# LegacyRay for OS X: takes the daemon and its helpers out again, as root.
#   uninstall-helper.sh            keeps servers, subscriptions and settings
#   uninstall-helper.sh --purge    removes those too

PREFIX=/usr/local/legacyray
SYS="/Library/Application Support/LegacyRay"
PLIST=/Library/LaunchDaemons/com.legacyray.daemon.plist

if [ -f "$PLIST" ]; then launchctl unload "$PLIST" >/dev/null 2>&1; fi
if [ -x "$PREFIX/bin/legacyray-kick" ]; then "$PREFIX/bin/legacyray-kick" --awg-stop >/dev/null 2>&1; fi
pfctl -a com.apple/legacyray -F all >/dev/null 2>&1
rm -f "$PLIST" /var/tmp/legacyrayd.sock /var/tmp/legacyrayd.token
if [ "$(readlink /usr/local/bin/legacyrayctl 2>/dev/null)" = "$PREFIX/bin/legacyrayctl" ]; then
  rm -f /usr/local/bin/legacyrayctl
fi
rm -rf "$PREFIX"
if [ "$1" = "--purge" ]; then
  rm -rf "$SYS"
  rm -f /var/log/legacyray-system.log /var/log/legacyray-kick.log
fi
echo "legacyray-install: removed"
exit 0
