#ifndef MAC_SYSPROXY_H
#define MAC_SYSPROXY_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* the last rung on os x: when pf will not turn the mac's own traffic around,
   every network service gets legacyrayd's socks port as its system proxy.
   apps that follow the proxy settings (safari, chrome, mail, app store and
   most of what is built on cfnetwork) then reach the tunnel by name. what each
   service had before is kept on disk, so a crash or a reboot puts it back.
   on ios these do nothing and up fails */
int  mac_sysproxy_up(int socks_port, char *detail, size_t detail_cap);
void mac_sysproxy_down(void);

/* the services a dead daemon left pointing at itself get their own settings
   back; called at startup (the uninstaller reads the same file) */
void mac_sysproxy_restore_stale(void);

#ifdef __cplusplus
}
#endif

#endif
