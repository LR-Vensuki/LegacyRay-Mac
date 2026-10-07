/* legacyray-install: the one tool the app runs through the os x
   authorization dialog (AuthorizationExecuteWithPrivileges). that call hands
   the tool an effective uid of 0 but leaves the real uid the user's, and a
   shell started that way drops root again, and launchctl run from it talks to
   the user's launchd instead of the system's. so this becomes root all the
   way and runs the installer script that sits next to it in the bundle.
   it is not setuid on disk: without the dialog it is just a user process */
#include <errno.h>
#include <libgen.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: legacyray-install install|uninstall [args]\n");
        return 64;
    }
    if (geteuid() != 0) {
        fprintf(stderr, "legacyray-install: not authorized\n");
        return 77;
    }
    if (setgid(0) != 0 || setuid(0) != 0) {
        fprintf(stderr, "legacyray-install: setuid: %s\n", strerror(errno));
        return 77;
    }
    const char *script;
    if (strcmp(argv[1], "install") == 0) script = "install-helper.sh";
    else if (strcmp(argv[1], "uninstall") == 0) script = "uninstall-helper.sh";
    else return 64;

    /* Contents/Helpers/legacyray-install -> Contents/Resources/<script> */
    char self[PATH_MAX], dir[PATH_MAX], path[PATH_MAX];
    if (!realpath(argv[0], self)) return 66;
    snprintf(dir, sizeof dir, "%s", self);
    char *d = dirname(dir);
    if (snprintf(path, sizeof path, "%s/../Resources/%s", d, script) >= (int)sizeof path) return 66;
    char resolved[PATH_MAX];
    if (!realpath(path, resolved)) {
        fprintf(stderr, "legacyray-install: no %s\n", script);
        return 66;
    }

    char *args[16];
    int n = 0;
    args[n++] = "/bin/sh";
    args[n++] = resolved;
    for (int i = 2; i < argc && n < 15; ++i) args[n++] = argv[i];
    args[n] = NULL;
    /* a clean environment: nothing the user set reaches a root shell */
    char *env[] = { "PATH=/usr/bin:/bin:/usr/sbin:/sbin", "LANG=C", NULL };
    execve("/bin/sh", args, env);
    fprintf(stderr, "legacyray-install: exec: %s\n", strerror(errno));
    return 71;
}
