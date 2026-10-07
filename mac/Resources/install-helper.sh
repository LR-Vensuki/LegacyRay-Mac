#!/bin/sh
# LegacyRay for OS X: puts the daemon and its helpers in place, as root,
# from the app bundle. run by legacyray-install after the authorization
# dialog:  install-helper.sh <path to LegacyRay.app> <uid of the user>
# every step is idempotent; an update runs the same script again.

APP="$1"
USER_ID="$2"
SRC="$APP/Contents/Helpers"
PREFIX=/usr/local/legacyray
SYS="/Library/Application Support/LegacyRay"
DATA="$SYS/Data"
CFG="$SYS/legacyray.cfg"
PLIST=/Library/LaunchDaemons/com.legacyray.daemon.plist
LABEL=com.legacyray.daemon
TOOLS="legacyrayd legacyrayctl legacyray-kick legacyrayawgd legacyray-ssh"

say() { echo "legacyray-install: $*"; }
die() { say "$*" >&2; exit 1; }

[ -d "$SRC" ] || die "no helpers in $APP"
for t in $TOOLS; do [ -f "$SRC/$t" ] || die "missing $t"; done
case "$USER_ID" in ''|*[!0-9]*) die "bad uid" ;; esac
[ "$USER_ID" -gt 0 ] || die "bad uid"

# the running daemon and any amneziawg tunnel come down first; a tunnel that
# was up comes back on its own if the user asked for auto connect
if [ -f "$PLIST" ]; then launchctl unload "$PLIST" >/dev/null 2>&1; fi
if [ -x "$PREFIX/bin/legacyray-kick" ]; then "$PREFIX/bin/legacyray-kick" --awg-stop >/dev/null 2>&1; fi
pfctl -a com.apple/legacyray -F all >/dev/null 2>&1

mkdir -p "$PREFIX/bin" || die "cannot create $PREFIX"
for t in $TOOLS; do
  cp -f "$SRC/$t" "$PREFIX/bin/.$t.new" && mv -f "$PREFIX/bin/.$t.new" "$PREFIX/bin/$t" || die "cannot install $t"
done
cp -f "$SRC/VERSION" "$PREFIX/VERSION"
mkdir -p "$PREFIX/lib"
cp -f "$SRC/cacert.pem" "$PREFIX/lib/cacert.pem" || die "missing cacert.pem"
chown -R root:wheel "$PREFIX"
chmod 755 "$PREFIX" "$PREFIX/bin" "$PREFIX/lib" "$PREFIX"/bin/*
chmod 644 "$PREFIX/VERSION" "$PREFIX/lib/cacert.pem"
# the app asks it to start the daemon and to bring amneziawg up; it only
# answers root and the account the data folder belongs to
chmod 4755 "$PREFIX/bin/legacyray-kick"
mkdir -p /usr/local/bin && ln -sf "$PREFIX/bin/legacyrayctl" /usr/local/bin/legacyrayctl

mkdir -p "$SYS" "$DATA"
chown root:wheel "$SYS"
chmod 755 "$SYS"
chown -R "$USER_ID" "$DATA"
chmod 700 "$DATA"

if [ ! -s "$CFG" ]; then
  cat > "$CFG" <<'CFGEOF'
V1
SET socks_port 11080
SET socks_public 0
SET dns_upstream 1.1.1.1
SET dns_local_port 10053
SEL -1
CFGEOF
fi
chown root:wheel "$CFG"
chmod 600 "$CFG"

for log in /var/log/legacyray-system.log /var/log/legacyray-kick.log; do
  touch "$log"
  chown "$USER_ID":wheel "$log"
  chmod 640 "$log"
done

cp -f "$APP/Contents/Resources/com.legacyray.daemon.plist" "$PLIST" || die "cannot install $PLIST"
chown root:wheel "$PLIST"
chmod 644 "$PLIST"
launchctl load -w "$PLIST" || die "launchctl refused $PLIST"

# wait for the control socket, so the app finds the daemon on its first try
i=0
while [ $i -lt 50 ]; do
  [ -S /var/tmp/legacyrayd.sock ] && { say "ok"; exit 0; }
  sleep 0.2
  i=$((i + 1))
done
say "installed, the daemon is still starting"
exit 0
