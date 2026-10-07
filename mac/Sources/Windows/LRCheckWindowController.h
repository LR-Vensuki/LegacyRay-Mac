/* the connection check: daemon, network, dns, the server's handshake, http
   through the tunnel and the path the mac takes without it, each with a lamp
   that goes amber while it runs and green or red after, and a verdict */
#import <Cocoa/Cocoa.h>

@class LRConnectionCheck;

@interface LRCheckWindowController : NSWindowController {
    LRConnectionCheck *_check;
    NSView *_steps;
    NSButton *_run;
    NSButton *_copy;
}
@end
