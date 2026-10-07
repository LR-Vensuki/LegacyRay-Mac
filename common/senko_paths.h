#ifndef SENKO_PATHS_H
#define SENKO_PATHS_H

/* every file the daemon, its helpers and the app agree on. the ios build is a
   jailbreak package that owns /usr/bin and the mobile user's preferences; the
   os x build (LR_MACOS, mac/Makefile and daemon/Makefile.mac) installs its
   tools under /usr/local/legacyray and keeps everything it shares with the
   person using it in one folder of /Library/Application Support that the
   helper installer hands to that person */

#if defined(LR_MACOS)

#define SENKO_JBROOT ""
#define SENKO_PREFIX "/usr/local/legacyray"
#define SENKO_USR_BIN SENKO_PREFIX "/bin"
#define SENKO_USR_LIB SENKO_PREFIX "/lib"
#define SENKO_LAUNCH_DAEMONS "/Library/LaunchDaemons"
#define SENKO_SUBSTRATE_DIR SENKO_PREFIX "/nonexistent"

/* root's half: the daemon config and the device id */
#define SENKO_SYSTEM_DIR "/Library/Application Support/LegacyRay"
#define SENKO_DAEMON_CFG SENKO_SYSTEM_DIR "/legacyray.cfg"
#define SENKO_HWID_PATH  SENKO_SYSTEM_DIR "/hwid"
/* the user's half: owned by the account that installed the helper, mode 0700.
   the daemon reads what the app stages here and writes exports back */
#define SENKO_DATA_DIR   SENKO_SYSTEM_DIR "/Data"
#define SENKO_STATUS_STATE SENKO_DATA_DIR "/status.state"
#define SENKO_BACKUP_EXPORT SENKO_DATA_DIR "/legacyray-backup.lray"
/* the version of the helper tools on disk; the app reinstalls them when its
   own bundle carries a different one */
#define SENKO_HELPER_VERSION SENKO_PREFIX "/VERSION"
/* mozilla's roots for the daemon's own tls (subscriptions, updates): os x
   keeps its roots in the keychain, which openssl cannot read */
#define SENKO_CA_BUNDLE SENKO_USR_LIB "/cacert.pem"

#else

/* /var/jb keeps the universal payload away from the sealed root filesystem */
#if defined(SENKO_ROOTLESS)
#define SENKO_JBROOT "/var/jb"
#else
#define SENKO_JBROOT ""
#endif

#define SENKO_USR_BIN SENKO_JBROOT "/usr/bin"
#define SENKO_USR_LIB SENKO_JBROOT "/usr/lib"
#define SENKO_LAUNCH_DAEMONS SENKO_JBROOT "/Library/LaunchDaemons"
#define SENKO_SUBSTRATE_DIR SENKO_JBROOT "/Library/MobileSubstrate/DynamicLibraries"

#define SENKO_DAEMON_CFG "/var/root/Library/Preferences/legacyray.cfg"
/* the device id panels bind a subscription to. it stays outside the jailbreak
   root so the daemon and the ui, which run as different users, agree on one
   value and a jailbreak change does not hand the panel a new device */
#define SENKO_HWID_PATH "/var/mobile/Library/Preferences/com.legacyray.hwid"
#define SENKO_DATA_DIR "/var/mobile/Library/Preferences/LegacyRay"
#define SENKO_STATUS_STATE "/var/mobile/Library/Preferences/com.legacyray.status.state"
#define SENKO_BACKUP_EXPORT "/var/mobile/Documents/legacyray-backup.lray"
/* the roots the tls hook package installs */
#define SENKO_CA_BUNDLE SENKO_USR_LIB "/legacyraytlsfix/cacert.pem"

#endif

/* the control socket; the daemon writes its token next to it */
#define SENKO_CTL_SOCK "/var/tmp/legacyrayd.sock"

/* launchd redirects both daemon streams here, and the ui reads the same file */
#define SENKO_SYSTEM_LOG "/var/log/legacyray-system.log"
#define SENKO_KICK_LOG "/var/log/legacyray-kick.log"

/* the ui stages pasted or picked content here and the daemon consumes it. a
   fixed path keeps the privileged reader free of any caller supplied path */
#define SENKO_IMPORT_STAGE SENKO_DATA_DIR "/import.dat"
#define SENKO_BACKUP_IMPORT SENKO_DATA_DIR "/import.lray"
/* geosite / geoip downloads */
#define SENKO_GEO_DIR SENKO_DATA_DIR "/geo"
/* amneziawg keepalive policy the helper reads when a profile starts */
#define SENKO_POWER_CONF SENKO_DATA_DIR "/power.conf"
/* own servers set up over ssh */
#define SENKO_SSH_HOSTS SENKO_DATA_DIR "/servers.plist"

/* the amneziawg helper's state */
#define SENKO_AWG_PID "/var/run/legacyrayawgd.pid"
#define SENKO_AWG_STATUS "/var/run/legacyrayawgd.status"

/* a launch that dies before the first frame leaves nothing a user can reach,
   because the only reader of the report used to be the app that will not
   start. these paths are fixed so legacyrayctl can print them over ssh instead */
#define SENKO_CRASH_DIR    SENKO_DATA_DIR
#define SENKO_CRASH_LAST   SENKO_CRASH_DIR "/last-crash.log"
#define SENKO_CRASH_PREV   SENKO_CRASH_DIR "/previous-crash.log"
#define SENKO_CRASH_STAGE  SENKO_CRASH_DIR "/launch-stage.log"
#define SENKO_CRASH_SCREEN SENKO_CRASH_DIR "/screen.log"
/* consecutive launches that never reached the first frame; two of them turn
   the next launch into safe mode */
#define SENKO_CRASH_FAILS  SENKO_CRASH_DIR "/launch-fails.log"
/* present when safe mode was asked for by hand rather than earned by two dead
   launches. it survives a good launch, because leaving it is also a choice */
#define SENKO_CRASH_SAFE   SENKO_CRASH_DIR "/safe-mode.on"

#if defined(__APPLE__) && !defined(SENKO_HOST_TEST)
#include <sys/types.h>
#include <sys/stat.h>
/* the one account besides root that may drive the daemon. on ios that is
   mobile; on os x it is whoever owns the shared data folder, which the helper
   installer gives to the person who installed it */
static inline uid_t senko_client_uid(void) {
#if defined(LR_MACOS)
    struct stat st;
    if (stat(SENKO_DATA_DIR, &st) == 0 && st.st_uid != 0) return st.st_uid;
    return (uid_t)501;
#else
    return (uid_t)501;
#endif
}
static inline gid_t senko_client_gid(void) {
#if defined(LR_MACOS)
    /* the token and the socket belong to the client itself (mode 0600), not
       to its group: on os x every account shares the staff group */
    return (gid_t)0;
#else
    return (gid_t)501;
#endif
}
#endif

#endif
