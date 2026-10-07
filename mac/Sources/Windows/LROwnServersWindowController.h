/* the user's own servers, set up and run over ssh the way the amnezia client
   does it: a list of servers on the left; on the right either the form for a
   new one (address, sign-in, what to install) or the chosen server's state,
   its clients and the management keys; a console under it with what the
   server answers, line by line */
#import <Cocoa/Cocoa.h>

@class LRServerHost, LRSSHJob;

@interface LROwnServersWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate> {
    NSTableView *_list;
    NSScrollView *_pane;
    NSTextView *_console;
    NSTextField *_stage;
    NSArray *_hosts;
    LRServerHost *_host;        /* the chosen one, or the one being set up */
    BOOL _setup;
    BOOL _working;
    BOOL _xray, _awg;
    NSString *_sni;
    NSMutableDictionary *_info;
    NSMutableArray *_clients;
    LRSSHJob *_job;
    NSSecureTextField *_secretField;      /* in the setup form, not retained */
    NSSecureTextField *_passphraseField;
}
@end
