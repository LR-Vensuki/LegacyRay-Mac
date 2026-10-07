#import "LRDiagnosticsWindowController.h"
#import "LRBlocks.h"
#import "LRDraw.h"
#import "LRToast.h"
#import "LRAlert.h"
#import "LRTunnel.h"
#import "LRCatalog.h"
#import "LRModels.h"
#import "LRDaemonClient.h"
#import "LRNetInfo.h"
#import "LRActivityLog.h"
#import "LRHelperInstaller.h"
#import "LRVersion.h"
#include <sys/sysctl.h>

static NSString *LRMachine(void) {
    char buf[128] = "?";
    size_t size = sizeof buf;
    sysctlbyname("hw.model", buf, &size, NULL, 0);
    return [NSString stringWithUTF8String:buf];
}

void LRBuildDiagnosticReport(void (^done)(NSString *)) {
    void (^callback)(NSString *) = [[done copy] autorelease];
    LRDaemonClient *client = [LRDaemonClient shared];
    [client diagnostics:^(NSArray *facts) {
        [client daemonLogTail:^(NSString *log) {
            NSMutableString *r = [NSMutableString string];
            NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
            [f setDateFormat:@"yyyy-MM-dd HH:mm:ss Z"];
            [r appendFormat:@"LegacyRay diagnostic report\nGenerated: %@\n\n", [f stringFromDate:[NSDate date]]];
            [r appendString:@"Application\n-----------\n"];
            [r appendFormat:@"Version: %s (%s), OS X build\n", LR_VERSION, LR_BUILD_NUMBER];
            [r appendFormat:@"Mac: %@\nSystem: OS X %@\n", LRMachine(), LRMacSystemVersion()];
            [r appendFormat:@"Helper: %@ (bundle %@)\n", [LRHelperInstaller installedVersion] ?: @"none",
                [LRHelperInstaller bundledVersion]];
            [r appendFormat:@"Theme: %@ · Language: %@\n", [LRPrefs flatSkinActive] ? @"flat" : @"classic",
                LRLanguageName(LRCurrentLanguage())];
            [r appendFormat:@"Stealth: %@\n\n", [LRPrefs stealthMode] ? @"on" : @"off"];
            [r appendString:@"Connection\n----------\n"];
            LRTunnel *t = [LRTunnel shared];
            [r appendFormat:@"State: %@\nBackend: %@\n", [t stateTitle],
             t.activeBackend == LRBackendAmneziaWG ? @"amneziawg" : @"vless daemon"];
            LRServer *sv = [[LRCatalog shared] selectedServer];
            if (sv) [r appendFormat:@"Server: %@\n", [sv protocolSummary]];
            if (t.lastError) [r appendFormat:@"Last error: %@\n", LRRedact(t.lastError)];
            [r appendFormat:@"Network: %@\n", [LRNetInfo interfaceKind]];
            [r appendFormat:@"Servers: %lu · Subscriptions: %lu\n\n",
             (unsigned long)[[LRCatalog shared].servers count], (unsigned long)[[LRCatalog shared].subscriptions count]];
            [r appendString:@"Daemon state\n------------\n"];
            if (facts) for (LRDiagFact *fact in facts) [r appendFormat:@"%@ = %@\n", fact.key, LRRedact(fact.value)];
            else [r appendString:@"(the daemon did not answer)\n"];
            [r appendString:@"\nActivity\n--------\n"];
            [r appendString:[[LRActivityLog shared] textDump]];
            if ([log length]) {
                NSString *tail = [log length] > 12000 ? [log substringFromIndex:[log length] - 12000] : log;
                [r appendFormat:@"\nDaemon log (tail, redacted)\n---------------------------\n%@\n", LRRedact(tail)];
            }
            if (callback) callback(r);
        }];
    }];
}

@implementation LRDiagnosticsWindowController

- (id)init {
    NSWindow *w = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 720, 520)
                                               styleMask:NSTitledWindowMask | NSClosableWindowMask |
                                                         NSMiniaturizableWindowMask | NSResizableWindowMask
                                                 backing:NSBackingStoreBuffered defer:YES] autorelease];
    [w setTitle:L(@"Diagnostics")];
    [w setMinSize:NSMakeSize(560, 380)];
    [w setReleasedWhenClosed:NO];
    if ((self = [super initWithWindow:w])) {
        [self build];
        [w center];
        [w setFrameAutosaveName:@"LegacyRayDiagnostics"];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadActivity)
                                                     name:LRActivityDidChangeNotification object:nil];
        [self loadFacts];
        [self loadActivity];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_factsTable setDataSource:nil];
    [_activityTable setDataSource:nil];
    [_tabs release];
    [_factsTable release];
    [_activityTable release];
    [_logView release];
    [_fwView release];
    [_facts release];
    [_activity release];
    [super dealloc];
}

- (NSTableView *)tableWithColumns:(NSArray *)cols {
    NSTableView *t = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 600, 300)] autorelease];
    for (NSArray *c in cols) {
        NSTableColumn *col = [[[NSTableColumn alloc] initWithIdentifier:[c objectAtIndex:0]] autorelease];
        [[col headerCell] setStringValue:[c objectAtIndex:1]];
        [col setWidth:[[c objectAtIndex:2] floatValue]];
        [col setEditable:NO];
        [[col dataCell] setFont:[NSFont systemFontOfSize:11]];
        [[col dataCell] setLineBreakMode:NSLineBreakByTruncatingTail];
        [t addTableColumn:col];
    }
    [t setUsesAlternatingRowBackgroundColors:YES];
    [t setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];
    [t setRowHeight:16];
    [t setDataSource:self];
    [t setDelegate:self];
    return t;
}

- (NSScrollView *)scroll:(NSView *)doc frame:(NSRect)frame {
    NSScrollView *s = [[[NSScrollView alloc] initWithFrame:frame] autorelease];
    [s setDocumentView:doc];
    [s setHasVerticalScroller:YES];
    [s setHasHorizontalScroller:NO];
    [s setBorderType:NSBezelBorder];
    [s setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    return s;
}

- (NSTextView *)textView {
    NSTextView *tv = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 600, 300)] autorelease];
    [tv setEditable:NO];
    [tv setRichText:NO];
    [tv setFont:[NSFont userFixedPitchFontOfSize:10]];
    [tv setAutoresizingMask:NSViewWidthSizable];
    [[tv textContainer] setWidthTracksTextView:YES];
    [tv setTextContainerInset:NSMakeSize(4, 4)];
    return tv;
}

- (NSTabViewItem *)tab:(NSString *)ident label:(NSString *)label view:(NSView *)view {
    NSTabViewItem *it = [[[NSTabViewItem alloc] initWithIdentifier:ident] autorelease];
    [it setLabel:label];
    NSView *holder = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 660, 380)] autorelease];
    [view setFrame:NSInsetRect([holder bounds], 10, 10)];
    [holder addSubview:view];
    [it setView:holder];
    return it;
}

- (void)build {
    NSView *content = [[self window] contentView];
    NSRect b = [content bounds];
    _tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(14, 50, NSWidth(b) - 28, NSHeight(b) - 62)];
    [_tabs setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_tabs setDelegate:self];
    _factsTable = [[self tableWithColumns:[NSArray arrayWithObjects:
        [NSArray arrayWithObjects:@"key", L(@"Fact"), [NSNumber numberWithFloat:220], nil],
        [NSArray arrayWithObjects:@"value", L(@"Value"), [NSNumber numberWithFloat:400], nil], nil]] retain];
    _activityTable = [[self tableWithColumns:[NSArray arrayWithObjects:
        [NSArray arrayWithObjects:@"date", L(@"Time"), [NSNumber numberWithFloat:140], nil],
        [NSArray arrayWithObjects:@"category", L(@"Area"), [NSNumber numberWithFloat:90], nil],
        [NSArray arrayWithObjects:@"message", L(@"Event"), [NSNumber numberWithFloat:380], nil], nil]] retain];
    _logView = [[self textView] retain];
    _fwView = [[self textView] retain];
    [_tabs addTabViewItem:[self tab:@"facts" label:L(@"Live state") view:[self scroll:_factsTable frame:NSZeroRect]]];
    [_tabs addTabViewItem:[self tab:@"log" label:L(@"Daemon log") view:[self scroll:_logView frame:NSZeroRect]]];
    [_tabs addTabViewItem:[self tab:@"activity" label:L(@"Recent activity") view:[self scroll:_activityTable frame:NSZeroRect]]];
    [_tabs addTabViewItem:[self tab:@"fw" label:L(@"Firewall rules") view:[self scroll:_fwView frame:NSZeroRect]]];
    [content addSubview:_tabs];

    __block LRDiagnosticsWindowController *me = self;
    NSArray *keys = [NSArray arrayWithObjects:
        LRPushButton(L(@"Save Report…"), ^(id s) { [me saveReport]; }),
        LRPushButton(L(@"Refresh"), ^(id s) { [me refreshTab]; }), nil];
    CGFloat x = NSWidth(b) - 14;
    for (NSButton *k in keys) {
        x -= NSWidth([k frame]);
        [k setFrameOrigin:NSMakePoint(x, 12)];
        [k setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
        [content addSubview:k];
    }
    NSPopUpButton *tools = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 16, 150, 26) pullsDown:YES] autorelease];
    NSMenu *tm = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    [tm lr_addItem:L(@"Tools") block:nil];
    [tm lr_addItem:L(@"Flush DNS cache") block:^{
        [[LRDaemonClient shared] flushTarget:@"dns" reply:^(NSString *reply) {
            if (LRReplyIsOK(reply)) [LRToast showSuccess:L(@"DNS cache flushed")];
            else [LRToast showError:LRErrorFromReply(reply)];
        }];
    }];
    [tm lr_addItem:L(@"Flush bypass table") block:^{
        [[LRDaemonClient shared] flushTarget:@"bypass" reply:^(NSString *reply) {
            if (LRReplyIsOK(reply)) [LRToast showSuccess:L(@"Bypass table flushed")];
            else [LRToast showError:LRErrorFromReply(reply)];
        }];
    }];
    [tm lr_addItem:L(@"Restart the daemon") block:^{
        [[LRDaemonClient shared] kickDaemon:^(BOOL ok, NSString *detail) {
            if (ok) [LRToast showSuccess:L(@"Daemon started")];
            else [LRToast showError:detail];
            [[LRCatalog shared] reload];
            [me loadFacts];
        }];
    }];
    [tm lr_addItem:L(@"Show the Log in Console") block:^{
        [[NSWorkspace sharedWorkspace] openFile:@"/var/log/legacyray-system.log" withApplication:@"Console"];
    }];
    [tm lr_addSeparator];
    [tm lr_addItem:L(@"Clear Activity") block:^{
        [LRAlert confirmTitle:L(@"Clear Activity?") message:nil button:L(@"Clear") destructive:YES action:^{
            [[LRActivityLog shared] clear];
        }];
    }];
    [tools setMenu:tm];
    [tools setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
    [content addSubview:tools];
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)item {
    [self refreshTab];
}

- (void)refreshTab {
    NSString *ident = [[_tabs selectedTabViewItem] identifier];
    if ([ident isEqualToString:@"facts"]) [self loadFacts];
    else if ([ident isEqualToString:@"log"]) [self loadLog];
    else if ([ident isEqualToString:@"activity"]) [self loadActivity];
    else [self loadFirewall];
}

- (void)loadFacts {
    [[LRDaemonClient shared] diagnostics:^(NSArray *facts) {
        [_facts release];
        _facts = [facts retain];
        [_factsTable reloadData];
        if (!facts) [LRToast showError:L(@"The daemon did not answer")];
    }];
}

- (void)setText:(NSString *)text in:(NSTextView *)tv {
    [tv setString:text ? text : @""];
    [tv scrollRangeToVisible:NSMakeRange([[tv string] length], 0)];
}

- (void)loadLog {
    [self setText:L(@"Loading...") in:_logView];
    [[LRDaemonClient shared] daemonLogTail:^(NSString *text) {
        [self setText:text ? ([LRPrefs stealthMode] ? LRRedact(text) : text) : L(@"The daemon did not answer")
                   in:_logView];
    }];
}

- (void)loadFirewall {
    [self setText:L(@"Loading...") in:_fwView];
    [[LRDaemonClient shared] firewallConfig:^(NSString *text, NSString *error) {
        [self setText:text ? text : error in:_fwView];
    }];
}

- (void)loadActivity {
    [_activity release];
    _activity = [[[LRActivityLog shared] entries] copy];
    [_activityTable reloadData];
}

- (void)saveReport {
    [LRToast show:L(@"Collecting...")];
    LRBuildDiagnosticReport(^(NSString *report) {
        LRLog(@"diagnostics", @"diagnostic report created");
        NSSavePanel *panel = [NSSavePanel savePanel];
        [panel setNameFieldStringValue:@"legacyray-diagnostics.txt"];
        [panel setMessage:L(@"The report is privacy safe: links, IDs and addresses are replaced before it is written.")];
        [panel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger result) {
            if (result != NSFileHandlingPanelOKButton) return;
            [report writeToURL:[panel URL] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:[NSArray arrayWithObject:[panel URL]]];
        }];
    });
}

#pragma mark tables

- (NSInteger)numberOfRowsInTableView:(NSTableView *)t {
    return t == _factsTable ? (NSInteger)[_facts count] : (NSInteger)MIN([_activity count], (NSUInteger)500);
}

- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    NSString *c = [col identifier];
    if (t == _factsTable) {
        LRDiagFact *f = [_facts objectAtIndex:(NSUInteger)row];
        if ([c isEqualToString:@"key"]) return f.key;
        return [LRPrefs stealthMode] ? LRRedact(f.value) : f.value;
    }
    LRActivityEntry *e = [_activity objectAtIndex:(NSUInteger)row];
    if ([c isEqualToString:@"date"]) {
        static NSDateFormatter *df = nil;
        if (!df) {
            df = [[NSDateFormatter alloc] init];
            [df setDateStyle:NSDateFormatterShortStyle];
            [df setTimeStyle:NSDateFormatterMediumStyle];
        }
        return [df stringFromDate:e.date];
    }
    if ([c isEqualToString:@"category"]) return e.category;
    if (e.failure)
        return [[[NSAttributedString alloc] initWithString:e.message
            attributes:[NSDictionary dictionaryWithObject:SKIN->bad forKey:NSForegroundColorAttributeName]] autorelease];
    return e.message;
}

- (NSString *)tableView:(NSTableView *)t toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect
            tableColumn:(NSTableColumn *)col row:(NSInteger)row mouseLocation:(NSPoint)p {
    id v = [self tableView:t objectValueForTableColumn:col row:row];
    return [v isKindOfClass:[NSAttributedString class]] ? [v string] : v;
}
@end
