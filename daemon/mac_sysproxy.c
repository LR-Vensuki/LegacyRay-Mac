#include "mac_sysproxy.h"

#include <stdio.h>
#include <string.h>

#if defined(LR_MACOS)

#include "../common/senko_paths.h"

#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

#define NETWORKSETUP "/usr/sbin/networksetup"
/* one line per service: enabled, server, port and the name, tab separated,
   "-" for an empty server or port */
#define SYSPROXY_STATE SENKO_SYSTEM_DIR "/sysproxy.state"
#define SYSPROXY_MAX 24

typedef struct {
    char name[128];
    int  enabled;
    char server[128];
    char port[8];
} sysproxy_service_t;

static int g_active;

/* stdout of networksetup into buf; its errors stay out of the answer */
static int ns_run(char *const argv[], char *buf, size_t cap) {
    if (buf && cap) buf[0] = '\0';
    int fds[2];
    if (pipe(fds) != 0) return -1;
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, fds[1], STDOUT_FILENO);
    posix_spawn_file_actions_addopen(&fa, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addclose(&fa, fds[0]);
    posix_spawn_file_actions_addclose(&fa, fds[1]);
    pid_t pid = 0;
    int rc = posix_spawn(&pid, NETWORKSETUP, &fa, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&fa);
    close(fds[1]);
    if (rc != 0) {
        close(fds[0]);
        return -1;
    }
    size_t used = 0;
    char sink[512];
    for (;;) {
        char *dst = buf && used + 1 < cap ? buf + used : sink;
        size_t room = buf && used + 1 < cap ? cap - 1 - used : sizeof sink;
        ssize_t n = read(fds[0], dst, room);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) break;
        if (dst != sink) used += (size_t)n;
    }
    if (buf && cap) buf[used] = '\0';
    close(fds[0]);
    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static int ns(const char *verb, const char *service, const char *a, const char *b) {
    char *argv[] = { (char *)NETWORKSETUP, (char *)verb, (char *)service,
                     (char *)a, (char *)b, NULL };
    char out[512];
    int rc = ns_run(argv, out, sizeof out);
    /* networksetup exits 0 even when it prints "** Error" */
    return rc == 0 && !strstr(out, "Error") ? 0 : -1;
}

/* the value after "key: " on its own line */
static void field(const char *text, const char *key, char *out, size_t cap) {
    out[0] = '\0';
    size_t kl = strlen(key);
    for (const char *p = text; p && *p; ) {
        if (strncmp(p, key, kl) == 0 && p[kl] == ':') {
            p += kl + 1;
            while (*p == ' ') ++p;
            size_t n = strcspn(p, "\r\n");
            if (n >= cap) n = cap - 1;
            memcpy(out, p, n);
            out[n] = '\0';
            return;
        }
        p = strchr(p, '\n');
        if (p) ++p;
    }
}

/* the enabled network services; a leading '*' marks a disabled one */
static size_t list_services(sysproxy_service_t *svc, size_t cap) {
    static char out[8192];
    char *argv[] = { (char *)NETWORKSETUP, (char *)"-listallnetworkservices", NULL };
    if (ns_run(argv, out, sizeof out) != 0) return 0;
    size_t n = 0;
    char *line = out;
    int first = 1;
    while (line && *line && n < cap) {
        char *next = strchr(line, '\n');
        if (next) *next++ = '\0';
        /* "An asterisk (*) denotes that a network service is disabled." */
        if (!first && line[0] && line[0] != '*' &&
            strlen(line) < sizeof svc[n].name) {
            memset(&svc[n], 0, sizeof svc[n]);
            snprintf(svc[n].name, sizeof svc[n].name, "%s", line);
            n++;
        }
        first = 0;
        line = next;
    }
    return n;
}

static int save_state(const sysproxy_service_t *svc, size_t n) {
    char tmp[] = SYSPROXY_STATE ".tmp";
    int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0600);
    if (fd < 0) return -1;
    FILE *f = fdopen(fd, "w");
    if (!f) {
        close(fd);
        return -1;
    }
    for (size_t i = 0; i < n; ++i)
        fprintf(f, "%d\t%s\t%s\t%s\n", svc[i].enabled,
                svc[i].server[0] ? svc[i].server : "-",
                svc[i].port[0] ? svc[i].port : "-", svc[i].name);
    int ok = fflush(f) == 0 && fsync(fileno(f)) == 0;
    if (fclose(f) != 0) ok = 0;
    if (ok && rename(tmp, SYSPROXY_STATE) != 0) ok = 0;
    if (!ok) unlink(tmp);
    return ok ? 0 : -1;
}

static size_t load_state(sysproxy_service_t *svc, size_t cap) {
    FILE *f = fopen(SYSPROXY_STATE, "r");
    if (!f) return 0;
    size_t n = 0;
    char line[512];
    while (n < cap && fgets(line, sizeof line, f)) {
        line[strcspn(line, "\r\n")] = '\0';
        char *fields[4];
        char *p = line;
        size_t k = 0;
        for (; k < 4 && p; ++k) {
            fields[k] = p;
            p = k < 3 ? strchr(p, '\t') : NULL;
            if (p) *p++ = '\0';
        }
        if (k < 4 || !fields[3][0]) continue;
        memset(&svc[n], 0, sizeof svc[n]);
        svc[n].enabled = fields[0][0] == '1';
        /* "-" stands for an empty field: a shell splitting on tabs would
           fold two of them into one */
        if (strcmp(fields[1], "-") != 0)
            snprintf(svc[n].server, sizeof svc[n].server, "%s", fields[1]);
        if (strcmp(fields[2], "-") != 0)
            snprintf(svc[n].port, sizeof svc[n].port, "%s", fields[2]);
        snprintf(svc[n].name, sizeof svc[n].name, "%s", fields[3]);
        n++;
    }
    fclose(f);
    return n;
}

/* every service back to what it had */
static void restore(const sysproxy_service_t *svc, size_t n) {
    for (size_t i = 0; i < n; ++i) {
        const sysproxy_service_t *s = &svc[i];
        if (s->server[0])
            (void)ns("-setsocksfirewallproxy", s->name, s->server,
                     s->port[0] ? s->port : "0");
        (void)ns("-setsocksfirewallproxystate", s->name, s->enabled ? "on" : "off", NULL);
    }
}

int mac_sysproxy_up(int socks_port, char *detail, size_t detail_cap) {
    if (detail && detail_cap) detail[0] = '\0';
    if (access(NETWORKSETUP, X_OK) != 0) {
        if (detail && detail_cap) snprintf(detail, detail_cap, "networksetup is missing");
        return -1;
    }
    mac_sysproxy_restore_stale();

    sysproxy_service_t svc[SYSPROXY_MAX];
    size_t n = list_services(svc, SYSPROXY_MAX);
    if (n == 0) {
        if (detail && detail_cap) snprintf(detail, detail_cap, "no network services");
        return -1;
    }
    for (size_t i = 0; i < n; ++i) {
        char out[1024];
        char *argv[] = { (char *)NETWORKSETUP, (char *)"-getsocksfirewallproxy",
                         svc[i].name, NULL };
        if (ns_run(argv, out, sizeof out) != 0) continue;
        char enabled[16];
        field(out, "Enabled", enabled, sizeof enabled);
        svc[i].enabled = strcmp(enabled, "Yes") == 0;
        field(out, "Server", svc[i].server, sizeof svc[i].server);
        field(out, "Port", svc[i].port, sizeof svc[i].port);
        /* our own port, left by a run whose state file is gone, is not
           something to put back */
        if (strcmp(svc[i].server, "127.0.0.1") == 0 && atoi(svc[i].port) == socks_port) {
            svc[i].enabled = 0;
            svc[i].server[0] = svc[i].port[0] = '\0';
        }
    }
    /* written before anything changes: a crash halfway still restores */
    if (save_state(svc, n) != 0) {
        if (detail && detail_cap) snprintf(detail, detail_cap, "cannot keep the old settings");
        return -1;
    }

    char port[8];
    snprintf(port, sizeof port, "%d", socks_port);
    size_t set = 0;
    for (size_t i = 0; i < n; ++i) {
        if (ns("-setsocksfirewallproxy", svc[i].name, "127.0.0.1", port) == 0 &&
            ns("-setsocksfirewallproxystate", svc[i].name, "on", NULL) == 0)
            set++;
        else
            fprintf(stderr, "legacyrayd: system proxy: %s refused the socks proxy\n",
                    svc[i].name);
    }
    if (set == 0) {
        restore(svc, n);
        unlink(SYSPROXY_STATE);
        if (detail && detail_cap)
            snprintf(detail, detail_cap, "networksetup did not take the proxy");
        return -1;
    }
    g_active = 1;
    fprintf(stderr, "legacyrayd: system proxy: socks 127.0.0.1:%d on %zu of %zu "
                    "network service(s)\n", socks_port, set, n);
    return 0;
}

void mac_sysproxy_down(void) {
    if (!g_active) return;
    g_active = 0;
    mac_sysproxy_restore_stale();
}

void mac_sysproxy_restore_stale(void) {
    sysproxy_service_t svc[SYSPROXY_MAX];
    size_t n = load_state(svc, SYSPROXY_MAX);
    struct stat st;
    if (n == 0) {
        if (lstat(SYSPROXY_STATE, &st) == 0) unlink(SYSPROXY_STATE);
        return;
    }
    restore(svc, n);
    unlink(SYSPROXY_STATE);
    fprintf(stderr, "legacyrayd: system proxy: settings of %zu network service(s) "
                    "restored\n", n);
}

#else

int mac_sysproxy_up(int socks_port, char *detail, size_t detail_cap) {
    (void)socks_port;
    if (detail && detail_cap) snprintf(detail, detail_cap, "not os x");
    return -1;
}

void mac_sysproxy_down(void) {}

void mac_sysproxy_restore_stale(void) {}

#endif
