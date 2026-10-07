#include "c_backend.h"

#include "core/net_safe.h"
#include "mac_sysproxy.h"

#include <pthread.h>
#include <stdio.h>
#include <string.h>

/* the open workers of direct connections and the control thread's probes
   both add bypasses; the rule writers keep their own state */
static pthread_mutex_t g_bypass_lock = PTHREAD_MUTEX_INITIALIZER;

#if !defined(LR_MACOS)
static void set_reason(char *reason, size_t cap, const char *text) {
    if (reason && cap) snprintf(reason, cap, "%s", text);
}
#endif

/* pf rewrites the destination, so the listener has to ask pf what it was.
   every ipfw fwd mode leaves the original destination on the accepted socket
   and needs the wildcard listener that getsockname can read it from */
static int enable_listener(loop_t *loop, int port, int sockname_dest) {
    loop_status_t rc = sockname_dest
        ? loop_enable_tproxy_sockname(loop, (uint16_t)port)
        : loop_enable_tproxy(loop, (uint16_t)port);
    return rc == LOOP_OK ? 0 : -1;
}

static int rung_ok(c_backend_t *cb, loop_t *loop, int port, int sockname_dest,
                   c_backend_verify_fn verify, void *verify_ctx) {
    if (enable_listener(loop, port, sockname_dest) != 0) {
        fprintf(stderr, "legacyrayd: c backend: transparent listener on port %d failed\n",
                port);
        return -1;
    }
    cb->redir_port = port;
    if (verify && verify(verify_ctx) != 0) {
        fprintf(stderr, "legacyrayd: c backend: rules were accepted but no traffic "
                        "reached the listener\n");
        loop_disable_tproxy(loop);
        cb->redir_port = 0;
        return -1;
    }
    return 0;
}

/* routing_exec_up proves each ruleset it gets accepted before it settles on
   it, so a pf variant the kernel ignores hands over to the next one */
#if defined(LR_MACOS)
typedef struct {
    c_backend_t *cb;
    loop_t *loop;
    c_backend_verify_fn verify;
    void *verify_ctx;
} rung_check_t;

static int rung_check(void *ctx, int port, int ipfw) {
    rung_check_t *rc = (rung_check_t *)ctx;
    return rung_ok(rc->cb, rc->loop, port, ipfw, rc->verify, rc->verify_ctx);
}
#endif

int c_backend_start(c_backend_t *cb, loop_t *loop, int socks_port,
                    const char *server_ip, const char *server_ips,
                    const char *dns_upstream, int dns_local_port,
                    dns_block_response_t block_response,
                    ruleset_t *rules,
                    const senko_force_t *force,
                    c_backend_verify_fn verify, void *verify_ctx,
                    char *reason, size_t reason_cap) {
    if (!cb || !loop || !server_ip || !server_ips) return -1;
    memset(cb, 0, sizeof *cb);
    if (reason && reason_cap) reason[0] = '\0';

    int pinned_app_proxy = force && force->backend == SENKO_BACKEND_APP_PROXY;
    int force_pf_mode = force ? force->pf_mode : SENKO_PF_MODE_AUTO;

    /* pf, or numbered ipfw rules; this rung is the only one with a dns
       forwarder, so it is worth trying before the plain fwd ruleset. on os x
       every variant is proven before the ladder settles on it, and the check
       leaves the listener running on the one that passed; ios proves only
       the variant it settled on */
#if defined(LR_MACOS)
    rung_check_t check = { cb, loop, verify, verify_ctx };
    routing_exec_check_fn check_fn = rung_check;
    void *check_ctx = &check;
#else
    routing_exec_check_fn check_fn = NULL;
    void *check_ctx = NULL;
#endif
    if (!pinned_app_proxy &&
        routing_exec_up(&cb->rules, socks_port, server_ip, server_ips,
                        dns_upstream, dns_local_port, block_response,
                        rules, force_pf_mode, check_fn, check_ctx) == REXEC_OK) {
        if (check_fn || rung_ok(cb, loop, cb->rules.redir_port,
                                cb->rules.mode == ROUTING_MODE_IPFW,
                                verify, verify_ctx) == 0) {
            cb->active = 1;
            return 0;
        }
        routing_exec_down(&cb->rules);
    }
    /* a variant that passed the check and then lost its dns forwarder */
    if (cb->redir_port) {
        loop_disable_tproxy(loop);
        cb->redir_port = 0;
    }

    if (!pinned_app_proxy &&
        routing_fwd_up(&cb->fwd, socks_port, server_ip, server_ips) == 0) {
        if (rung_ok(cb, loop, cb->fwd.redir_port, 1, verify, verify_ctx) == 0) {
            cb->active = 1;
            return 0;
        }
        routing_fwd_down(&cb->fwd);
    }

#if defined(LR_MACOS)
    /* the mac has no connect hook; the system proxy is its "apps only" rung.
       pinning the app proxy pins this */
    char pf_why[192];
    snprintf(pf_why, sizeof pf_why, "%s", routing_exec_last_error());
    char proxy_why[96];
    if (mac_sysproxy_up(socks_port, proxy_why, sizeof proxy_why) == 0) {
        memset(&cb->fwd, 0, sizeof cb->fwd);
        cb->active = 1;
        cb->app_proxy = 1;
        cb->sys_proxy = 1;
        cb->redir_port = socks_port;
        if (!pinned_app_proxy)
            fprintf(stderr, "legacyrayd: c backend: pf did not carry traffic (%s), "
                            "using the system proxy\n", pf_why[0] ? pf_why : "no detail");
        return 0;
    }
    if (reason && reason_cap)
        snprintf(reason, reason_cap,
                 pinned_app_proxy ? "the system proxy could not be set (%s%s%s)"
                                  : "neither pf nor the system proxy took the traffic "
                                    "(%s%s%s)",
                 pinned_app_proxy ? proxy_why : pf_why[0] ? pf_why : "pf: no detail",
                 pinned_app_proxy ? "" : "; proxy: ",
                 pinned_app_proxy ? "" : proxy_why);
    memset(cb, 0, sizeof *cb);
    return -1;
#else
    /* without a firewall tool only hooked processes can be redirected, so this
       rung covers less of the device and stays last */
    if (routing_fwd_app_proxy_up(&cb->fwd, socks_port) == 0) {
        cb->active = 1;
        cb->app_proxy = 1;
        cb->redir_port = cb->fwd.redir_port;
        return 0;
    }

/* ipfw is off on ios 5 because its fwd ruleset panics that kernel, which
   leaves the substrate proxy as the only route and makes the hook, not the
   firewall, the thing the user has to install */
    set_reason(reason, reason_cap,
               pinned_app_proxy
                   ? "the connect hook was pinned but legacyraytlsfix is not loaded"
               : "no usable firewall backend (need pfctl, ipfw, or legacyraytlsfix)");
    memset(cb, 0, sizeof *cb);
    return -1;
#endif
}

void c_backend_stop(c_backend_t *cb, loop_t *loop) {
    if (!cb) return;
    if (loop) loop_disable_tproxy(loop);
    pthread_mutex_lock(&g_bypass_lock);
    if (cb->sys_proxy) mac_sysproxy_down();
    routing_exec_down(&cb->rules);
    routing_fwd_down(&cb->fwd);
    memset(cb, 0, sizeof *cb);
    pthread_mutex_unlock(&g_bypass_lock);
}

int c_backend_uses_tproxy(const c_backend_t *cb) {
    return cb && cb->active && !cb->app_proxy;
}

int c_backend_bypass_add_ipv4(c_backend_t *cb, const char *ip) {
    char literal[64];
    /* both rule writers paste the address straight into a pf table or an ipfw
       rule, so anything but a plain ipv4 literal has to stop here */
    pthread_mutex_lock(&g_bypass_lock);
    int rc = -1;
    if (!cb || !cb->active) {
        rc = -1;
    } else if (cb->app_proxy) {
        rc = 0; /* nothing redirects the daemon's own sockets */
    } else if (net_ipv4_literal(ip, literal, sizeof literal)) {
        if (cb->rules.mode != ROUTING_MODE_NONE)
            rc = routing_exec_bypass_add_ipv4(&cb->rules, literal);
        else if (cb->fwd.active)
            rc = routing_fwd_bypass_add_ipv4(&cb->fwd, literal);
    }
    pthread_mutex_unlock(&g_bypass_lock);
    return rc;
}

void c_backend_clear_stale(void) {
    mac_sysproxy_restore_stale();
    routing_exec_clear_stale();
    routing_fwd_clear_rules();
}
