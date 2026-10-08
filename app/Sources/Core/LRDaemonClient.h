/* the app side of the legacyrayd control socket. every call runs the socket
   exchange on a background queue and answers on the main thread; a nil reply
   means the daemon did not answer at all. the protocol is senko's, with the
   legacyray additions (SUBEXTRA, the new settings keys, rule types) */
#import <Foundation/Foundation.h>
#include "senko_paths.h"
#import "LRModels.h"

#define LR_DAEMON_SOCKET @SENKO_CTL_SOCK
/* the client adds one of these lines to a CONNECT or DISCONNECT reply that
   stopped before its final state: the daemon closed the socket, or the wait
   ran out */
#define LR_REPLY_CLOSED  "LRCLIENT closed"
#define LR_REPLY_TIMEOUT "LRCLIENT timeout"

/* "connected" / "connecting" / "idle" / "error" out of a STATE reply */
NSString *LRStateFromReply(NSString *reply, long *uptime);
/* the text after ERR in a reply, or nil */
NSString *LRErrorFromReply(NSString *reply);
/* YES when some line of the reply starts with OK */
BOOL LRReplyIsOK(NSString *reply);

@interface LRDaemonClient : NSObject {
    NSString *_socketPath;
    uint64_t _trafficUp;
    uint64_t _trafficDown;
    BOOL _trafficKnown;
    NSMutableArray *_ensureWaiters; /* callers of the ensureDaemon in flight */
}

+ (LRDaemonClient *)shared;

- (id)initWithSocketPath:(NSString *)path;

/* a connected, authenticated control socket for a conversation that stays
   open (the WATCH stream), or -1. it blocks, so call it off the main thread */
- (int)openControlSocket;

- (void)sendCommand:(NSString *)cmd reply:(void (^)(NSString *reply))done;
- (void)sendCommand:(NSString *)cmd timeoutMs:(int)timeoutMs
              reply:(void (^)(NSString *reply))done;

/* daemon lifecycle */
- (void)probeDaemon:(void (^)(BOOL up))done;
- (void)kickDaemon:(void (^)(BOOL ok, NSString *detail))done;
- (void)ensureDaemon:(void (^)(BOOL up, NSString *detail))done;

/* catalog */
- (void)listCatalog:(void (^)(NSArray *servers, NSArray *subs, NSArray *order))done;
- (void)serverLinkIndex:(int)idx reply:(void (^)(NSString *link))done;
- (void)addServerLink:(NSString *)link reply:(void (^)(NSString *reply))done;
- (void)replaceServerIndex:(int)idx link:(NSString *)link reply:(void (^)(NSString *reply))done;
- (void)deleteServerIndex:(int)idx reply:(void (^)(NSString *reply))done;
- (void)clearManualServers:(void (^)(NSString *reply))done;
- (void)addSubscriptionURL:(NSString *)url name:(NSString *)name
                     reply:(void (^)(NSString *reply))done;
- (void)replaceSubscriptionIndex:(int)idx name:(NSString *)name url:(NSString *)url
                          header:(NSString *)header reply:(void (^)(NSString *reply))done;
- (void)deleteSubscriptionIndex:(int)idx reply:(void (^)(NSString *reply))done;
- (void)refreshSubscriptionIndex:(int)idx reply:(void (^)(NSString *reply))done;
- (void)moveSection:(int)sectionId toPosition:(int)position reply:(void (^)(NSString *reply))done;
- (void)moveManualServerIndex:(int)idx toPosition:(int)position
                        reply:(void (^)(NSString *reply))done;
/* raw pasted or picked content, parsed by the daemon */
- (void)importContent:(NSData *)data reply:(void (^)(NSString *reply))done;

/* tunnel */
- (void)status:(void (^)(NSString *state, long uptime, BOOL trafficKnown,
                         uint64_t up, uint64_t down))done;
- (void)connectIndex:(int)idx reply:(void (^)(NSString *reply))done;
- (void)disconnect:(void (^)(NSString *reply))done;

/* checks: mode is tcp, proxy, tunnel or handshake */
- (void)checkIndex:(int)idx mode:(NSString *)mode reply:(void (^)(int ms, NSString *error))done;
- (void)checkIndex:(int)idx mode:(NSString *)mode
            stages:(void (^)(NSArray *stages, int ms, NSString *error))done;

/* settings, rules, diagnostics */
- (void)daemonSettings:(void (^)(NSDictionary *settings))done;
- (void)setSetting:(NSString *)key value:(NSString *)value reply:(void (^)(NSString *reply))done;
- (void)listRules:(void (^)(NSArray *rules))done;
- (void)addRuleAction:(NSString *)action type:(NSString *)type value:(NSString *)value
                reply:(void (^)(NSString *reply))done;
- (void)deleteRuleIndex:(int)index reply:(void (^)(NSString *reply))done;
- (void)diagnostics:(void (^)(NSArray *facts))done;
- (void)firewallConfig:(void (^)(NSString *text, NSString *error))done;
- (void)flushTarget:(NSString *)what reply:(void (^)(NSString *reply))done;
/* geosite / geoip data: "GEO site category-ru 1093" style lines and the
   final OK / ERR text. update downloads, so it can take a minute */
- (void)geoStatus:(void (^)(NSArray *lines, NSString *summary, BOOL ok))done;
- (void)geoUpdate:(void (^)(NSArray *lines, NSString *summary, BOOL ok))done;
- (void)deviceHWID:(void (^)(NSString *hwid))done;
- (void)resetDeviceHWID:(void (^)(NSString *hwid, NSString *error))done;
- (void)daemonLogTail:(void (^)(NSString *text))done;
/* fetch a url through the daemon's own tls stack: ios 4-6 cannot speak the
   tls versions github and most panels require any more */
- (void)fetchURL:(NSString *)url reply:(void (^)(NSData *body, NSString *error))done;

/* backup: export writes ~/Documents/legacyray-backup.lray, restore reads the
   staged copy the app writes first */
- (void)exportBackup:(void (^)(NSString *reply))done;
- (void)restoreBackupData:(NSData *)data reply:(void (^)(NSString *reply))done;

/* amneziawg, driven through the setuid helper */
- (void)startAWGAtPath:(NSString *)path reply:(void (^)(NSString *status))done;
- (void)stopAWG:(void (^)(NSString *status))done;
- (void)awgStatus:(void (^)(NSString *status))done;
- (void)validateAWGAtPath:(NSString *)path reply:(void (^)(NSString *status))done;

/* install a .deb over the running package */
- (void)updatePackageAtPath:(NSString *)path progress:(void (^)(NSString *line))progress
                      reply:(void (^)(NSString *status))done;
@end
