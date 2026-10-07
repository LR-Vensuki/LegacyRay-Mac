#import "LRServerWindowController.h"
#import "LRAppDelegate.h"
#import "LRForm.h"
#import "LRBlocks.h"
#import "LRDraw.h"
#import "LRAlert.h"
#import "LRToast.h"
#import "LRTunnel.h"
#import "LRCatalog.h"
#import "LRModels.h"
#import "LRDaemonClient.h"
#import "LRDaemonSettings.h"
#import "LRActivityLog.h"

@implementation LRInfoHeader
@synthesize title = _title, subtitle = _subtitle, country = _country, icon = _icon;

- (void)dealloc {
    [_title release];
    [_subtitle release];
    [_country release];
    [_icon release];
    [super dealloc];
}

- (BOOL)isFlipped {
    return YES;
}

- (void)drawRect:(NSRect)dirty {
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    NSRect b = [self bounds];
    LRSkin *s = SKIN;
    if (s->flat) {
        [[NSColor whiteColor] setFill];
        NSRectFill(b);
        [s->separator setFill];
        NSRectFill(NSMakeRect(0, NSHeight(b) - 1, NSWidth(b), 1));
    } else {
        LRDrawDenim(b, 0.08f);
        LRFillVertical(ctx, NSRectToCGRect(b), [NSColor colorWithCalibratedWhite:1 alpha:0.10f],
                       [NSColor colorWithCalibratedWhite:0 alpha:0.15f]);
        LRDrawStitchLine(ctx, CGPointMake(0, NSHeight(b) - 5.5f), CGPointMake(NSWidth(b), NSHeight(b) - 5.5f));
        LRDrawStitchLine(ctx, CGPointMake(0, 4.5f), CGPointMake(NSWidth(b), 4.5f));
        CGContextSetRGBFillColor(ctx, 0, 0, 0, 0.9f);
        CGContextFillRect(ctx, CGRectMake(0, NSHeight(b) - 1, NSWidth(b), 1));
    }
    CGFloat x = 20;
    CGFloat mid = NSMidY(b);
    if ([_country length] == 2) {
        LRDrawFlag(ctx, _country, CGRectMake(x, round(mid - 20), 40, 40));
        x += 54;
    } else if (_icon) {
        [_icon drawInRect:NSMakeRect(x, round(mid - 20), 40, 40) fromRect:NSZeroRect operation:NSCompositeSourceOver
                 fraction:1 respectFlipped:YES hints:nil];
        x += 54;
    }
    NSRect tr = NSMakeRect(x, round(mid - ([_subtitle length] ? 21 : 11)), NSWidth(b) - x - 20, 22);
    NSRect sr = NSMakeRect(x, round(mid + 3), NSWidth(b) - x - 20, 17);
    if (s->flat) {
        LRDrawText(_title, tr, [LRSkin titleFont:17], s->pageInk, NSLeftTextAlignment);
        LRDrawText(_subtitle, sr, [LRSkin bodyFont:12], s->pageMuted, NSLeftTextAlignment);
    } else {
        LRDrawEngraved(_title, tr, [LRSkin titleFont:17], NSLeftTextAlignment, [NSColor whiteColor],
                       [NSColor colorWithCalibratedWhite:0 alpha:0.75f], -1);
        LRDrawEngraved(_subtitle, sr, [NSFont systemFontOfSize:12], NSLeftTextAlignment,
                       [NSColor colorWithCalibratedWhite:0.78f alpha:1], [NSColor colorWithCalibratedWhite:0 alpha:0.7f], -1);
    }
}
@end

@interface LRInfoContent : NSView
@end

@implementation LRInfoContent
- (BOOL)isFlipped {
    return YES;
}
@end

NSView *LRBuildInfoContent(NSWindow *window, LRInfoHeader *header, NSView *body, NSArray *buttons) {
    /* the default and its companions sit on the right; buttons tagged 1
       (edit, delete) on the left, the way apple's sheets part them */
    NSMutableArray *right = [NSMutableArray array], *left = [NSMutableArray array];
    CGFloat need = 28;
    for (NSButton *b in buttons) {
        NSRect f = [b frame];
        if ([[b title] length] && f.size.width < 90) f.size.width = 90;
        [b setFrame:f];
        need += f.size.width + 2;
        [([b tag] == 1 ? left : right) addObject:b];
    }
    if ([left count] && [right count]) need += 24;
    CGFloat w = MAX(NSWidth([body frame]), need);
    if (w > NSWidth([body frame])) [body setFrameSize:NSMakeSize(w, NSHeight([body frame]))];
    CGFloat headerH = header ? 72 : 0;
    CGFloat barH = [buttons count] ? 52 : 8;
    LRInfoContent *content = [[[LRInfoContent alloc] initWithFrame:
                               NSMakeRect(0, 0, w, headerH + NSHeight([body frame]) + barH)] autorelease];
    if (header) {
        [header setFrame:NSMakeRect(0, 0, w, headerH)];
        [content addSubview:header];
    }
    [body setFrameOrigin:NSMakePoint(0, headerH)];
    [content addSubview:body];
    CGFloat y = NSHeight([content frame]) - 44;
    CGFloat x = w - 14;
    for (NSUInteger i = 0; i < [right count]; ++i) {
        NSButton *b = [right objectAtIndex:i];
        NSRect f = [b frame];
        x -= f.size.width;
        f.origin = NSMakePoint(x, y);
        [b setFrame:f];
        if (i == 0) [b setKeyEquivalent:@"\r"];
        [content addSubview:b];
        x -= 2;
    }
    x = 14;
    for (NSButton *b in left) {
        NSRect f = [b frame];
        f.origin = NSMakePoint(x, y);
        [b setFrame:f];
        [content addSubview:b];
        x += f.size.width + 2;
    }
    [window setContentSize:[content frame].size];
    [window setContentView:content];
    return content;
}

static NSString *LRDateText(unsigned long long epoch) {
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
    [f setDateStyle:NSDateFormatterLongStyle];
    [f setTimeStyle:NSDateFormatterNoStyle];
    return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)epoch]];
}

@implementation LRServerWindowController

- (NSWindow *)makeWindow:(NSString *)title {
    NSWindow *w = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 460, 400)
                                               styleMask:NSTitledWindowMask | NSClosableWindowMask |
                                                         NSMiniaturizableWindowMask
                                                 backing:NSBackingStoreBuffered defer:YES] autorelease];
    [w setTitle:title];
    [w setReleasedWhenClosed:NO];
    return w;
}

- (id)initWithServer:(LRServer *)server {
    NSString *name = [[LRCatalog shared] displayNameForServer:server];
    if ((self = [super initWithWindow:[self makeWindow:name]])) {
        _server = [server retain];
        _results = [[NSMutableDictionary alloc] init];
        _running = [[NSMutableSet alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rebuild)
                                                     name:LRTunnelDidChangeNotification object:nil];
        [self rebuild];
        [[self window] center];
    }
    return self;
}

- (id)initWithSubscription:(LRSubscription *)subscription {
    if ((self = [super initWithWindow:[self makeWindow:subscription.name]])) {
        _subscription = [subscription retain];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(catalogChanged)
                                                     name:LRCatalogDidChangeNotification object:nil];
        [[LRDaemonClient shared] deviceHWID:^(NSString *hwid) {
            [_hwid release];
            _hwid = [hwid copy];
            [self rebuild];
        }];
        [self rebuild];
        [[self window] center];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_server release];
    [_subscription release];
    [_results release];
    [_running release];
    [_stages release];
    [_hwid release];
    [super dealloc];
}

- (void)rebuild {
    if (_server) [self buildServer];
    else [self buildSubscription];
}

/* the catalog was reloaded: find the same subscription again by its url */
- (void)catalogChanged {
    for (LRSubscription *s in [LRCatalog shared].subscriptions)
        if ([s.url isEqualToString:_subscription.url]) {
            [_subscription release];
            _subscription = [s retain];
            [[self window] setTitle:s.name];
            [self rebuild];
            return;
        }
}

#pragma mark server

- (NSString *)checkDetail:(NSString *)mode {
    if ([_running containsObject:mode]) return L(@"checking...");
    NSString *r = [_results objectForKey:mode];
    return r ? r : L(@"Not checked");
}

- (void)runCheck:(NSString *)mode {
    if ([_running containsObject:mode]) return;
    [_running addObject:mode];
    [self rebuild];
    [self retain];
    [[LRDaemonClient shared] checkIndex:_server.index mode:mode stages:^(NSArray *stages, int ms, NSString *error) {
        [_running removeObject:mode];
        [_results setObject:ms >= 0 ? [NSString stringWithFormat:@"%d %@", ms, L(@"ms")]
                                    : (error ? error : L(@"Failed")) forKey:mode];
        [_stages release];
        _stages = [stages retain];
        LRLog(@"ping", @"%@ check: %@", mode, ms >= 0 ? [NSString stringWithFormat:@"%d ms", ms] : @"failed");
        [self rebuild];
        [self release];
    }];
}

- (void)buildServer {
    LRServer *sv = _server;
    LRCatalog *catalog = [LRCatalog shared];
    LRTunnel *tunnel = [LRTunnel shared];
    LRSection *sec = [catalog sectionForServer:sv];
    LRInfoHeader *header = [[[LRInfoHeader alloc] initWithFrame:NSZeroRect] autorelease];
    header.title = [catalog displayNameForServer:sv];
    header.subtitle = [sv protocolSummary];
    header.country = [sv countryCode];
    LRForm *f = [[[LRForm alloc] initWithWidth:520 labelWidth:185] autorelease];
    NSFont *value = [NSFont systemFontOfSize:13];
    [f addLabel:L(@"Protocol") view:LRLabel([sv.proto uppercaseString], value, nil)];
    [f addLabel:L(@"Transport") view:LRLabel([sv.net uppercaseString], value, nil)];
    [f addLabel:L(@"Security") view:LRLabel([sv.security uppercaseString], value, nil)];
    NSTextField *addr = LRLabel([NSString stringWithFormat:@"%@ : %d", LRStealth(sv.host), sv.port], value, nil);
    [addr setSelectable:![LRPrefs stealthMode]];
    [f addLabel:L(@"Address") view:addr];
    if (sec) [f addLabel:L(@"Source") view:LRLabel(sec.title, value, nil)];
    if (!sv.supported) [f addNote:L(@"This build cannot dial this protocol (hysteria2 needs the newer core).")];
    [f addSeparator];
    NSArray *modes = [NSArray arrayWithObjects:@"tcp", @"handshake", @"proxy", nil];
    NSArray *names = [NSArray arrayWithObjects:L(@"TCP connect"), L(@"TLS / Reality handshake"), L(@"Real delay"), nil];
    __block LRServerWindowController *me = self;
    for (NSUInteger i = 0; i < [modes count]; ++i) {
        NSString *mode = [modes objectAtIndex:i];
        NSView *row = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, [f controlWidth], 24)] autorelease];
        NSTextField *res = LRLabel([self checkDetail:mode], value, nil);
        [res setFrame:NSMakeRect(0, 3, [f controlWidth] - 100, 17)];
        NSString *r = [_results objectForKey:mode];
        if (r && [r rangeOfString:L(@"ms")].location != NSNotFound) [res setTextColor:SKIN->good];
        else if (r) [res setTextColor:SKIN->bad];
        [row addSubview:res];
        NSButton *m = [[[NSButton alloc] initWithFrame:NSMakeRect([f controlWidth] - 96, 0, 96, 24)] autorelease];
        [m setBezelStyle:NSRoundedBezelStyle];
        [[m cell] setControlSize:NSSmallControlSize];
        [m setFont:[NSFont systemFontOfSize:11]];
        [m setTitle:L(@"Measure")];
        [m setEnabled:![_running containsObject:mode] && sv.supported];
        [m lr_setBlock:^(id s) { [me runCheck:mode]; }];
        [row addSubview:m];
        [f addLabel:[names objectAtIndex:i] view:row];
    }
    if ([_stages count]) {
        NSMutableArray *lines = [NSMutableArray array];
        for (LRCheckStage *st in _stages)
            [lines addObject:[NSString stringWithFormat:@"%@  %@  %d %@", st.ok ? @"✓" : @"✕", st.name, st.ms, L(@"ms")]];
        [f addNote:[lines componentsJoinedByString:@"\n"]];
    }
    [f addNote:L(@"The real delay goes through the server to a test page.")];
    [f finish];

    NSMutableArray *buttons = [NSMutableArray array];
    BOOL current = [LRPrefs selectedBackend] == LRBackendServer && catalog.selectedIndex == sv.index;
    BOOL live = current && tunnel.state == LRTunnelConnected;
    if (!live) [buttons addObject:LRPushButton([tunnel isOn] ? L(@"Switch to This Server") : L(@"Connect"), ^(id s) {
        [LRPrefs setSelectedBackend:LRBackendServer];
        [[LRTunnel shared] connectServerIndex:sv.index];
        [[me window] close];
    })];
    [buttons addObject:LRPushButton(L(@"Share…"), ^(id s) { [[LRAppDelegate shared] shareServer:sv]; })];
    [buttons addObject:LRPushButton(L(@"Copy Link"), ^(id s) {
        [[LRDaemonClient shared] serverLinkIndex:sv.index reply:^(NSString *link) {
            if (!link) { [LRToast showError:L(@"The link could not be read")]; return; }
            LRSetPasteboardString(link);
            [LRToast showSuccess:L(@"Link copied")];
        }];
    })];
    if (sv.group < 0) {
        NSButton *editKey = LRPushButton(L(@"Edit…"), ^(id s) { [me editLink]; });
        [editKey setTag:1];
        [buttons addObject:editKey];
        NSButton *deleteKey = LRPushButton(L(@"Delete…"), ^(id s) {
            [LRAlert runTitle:L(@"Delete Server") message:header.title
                      buttons:[NSArray arrayWithObjects:L(@"Delete"), L(@"Cancel"), nil]
                    accessory:nil window:[me window] done:^(NSInteger index) {
                if (index != 0) return;
                [[LRDaemonClient shared] deleteServerIndex:sv.index reply:^(NSString *reply) {
                    [[LRCatalog shared] reload];
                    [[me window] close];
                }];
            }];
        });
        [deleteKey setTag:1];
        [buttons addObject:deleteKey];
    }
    LRBuildInfoContent([self window], header, f, buttons);
}

- (void)editLink {
    int idx = _server.index;
    [[LRDaemonClient shared] serverLinkIndex:idx reply:^(NSString *link) {
        [LRAlert promptTitle:L(@"Edit link") message:nil placeholder:@"vless://" text:link button:L(@"Save")
                        done:^(NSString *value) {
            NSString *clean = LRTrim(value);
            if (!clean) return;
            [[LRDaemonClient shared] replaceServerIndex:idx link:clean reply:^(NSString *reply) {
                if (LRReplyIsOK(reply)) {
                    [LRToast showSuccess:L(@"Server saved")];
                    [[LRCatalog shared] reload];
                    [[self window] close];
                } else {
                    [LRToast showError:LRErrorFromReply(reply) ? LRErrorFromReply(reply) : L(@"Invalid configuration link")];
                }
            }];
        }];
    }];
}

#pragma mark subscription

- (NSView *)usageGauge:(LRSubscription *)sub width:(CGFloat)width {
    NSView *box = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, 34)] autorelease];
    NSLevelIndicator *gauge = [[[NSLevelIndicator alloc] initWithFrame:NSMakeRect(0, 16, width, 16)] autorelease];
    [[gauge cell] setLevelIndicatorStyle:NSContinuousCapacityLevelIndicatorStyle];
    [gauge setMinValue:0];
    [gauge setMaxValue:100];
    [gauge setWarningValue:75];
    [gauge setCriticalValue:90];
    double frac = [sub usageFraction];
    [gauge setDoubleValue:frac < 0 ? 0 : frac * 100];
    [box addSubview:gauge];
    NSString *text = sub.total ? [NSString stringWithFormat:L(@"%@ of %@"), LRBytes([sub used]), LRBytes(sub.total)]
                               : [NSString stringWithFormat:L(@"%@ used, no limit"), LRBytes([sub used])];
    NSTextField *l = LRLabel(text, [NSFont systemFontOfSize:11], [NSColor disabledControlTextColor]);
    [l setFrame:NSMakeRect(0, 0, width, 14)];
    [box addSubview:l];
    return box;
}

- (void)update {
    if (_updating) return;
    _updating = YES;
    [self rebuild];
    [self retain];
    [[LRDaemonClient shared] refreshSubscriptionIndex:_subscription.index reply:^(NSString *reply) {
        _updating = NO;
        if (LRReplyIsOK(reply)) {
            LRLog(@"subscriptions", @"subscription updated");
            [LRToast showSuccess:LRTrim([reply substringFromIndex:MIN((NSUInteger)3, [reply length])])];
        } else {
            LRLogFail(@"subscriptions", @"update failed");
            [LRToast showError:LRErrorFromReply(reply) ? LRErrorFromReply(reply) : L(@"Subscription update failed")];
        }
        [[LRCatalog shared] reload];
        [self rebuild];
        [self release];
    }];
}

- (void)saveName:(NSString *)name url:(NSString *)url header:(NSString *)header {
    [[LRDaemonClient shared] replaceSubscriptionIndex:_subscription.index name:name url:url header:header
                                                reply:^(NSString *reply) {
        if (LRReplyIsOK(reply)) {
            [LRToast showSuccess:L(@"Subscription saved")];
            LRLog(@"subscriptions", @"subscription edited");
        } else {
            [LRToast showError:LRErrorFromReply(reply) ? LRErrorFromReply(reply) : L(@"Could not save")];
        }
        [[LRCatalog shared] reload];
    }];
}

- (void)edit {
    LRSubscription *sub = _subscription;
    NSView *box = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 340, 88)] autorelease];
    NSArray *places = [NSArray arrayWithObjects:L(@"Subscription name"), @"https://", L(@"Header (optional)"), nil];
    NSArray *values = [NSArray arrayWithObjects:sub.name ? sub.name : @"", sub.url ? sub.url : @"",
                       sub.header ? sub.header : @"", nil];
    NSMutableArray *fields = [NSMutableArray array];
    for (NSUInteger i = 0; i < 3; ++i) {
        NSTextField *t = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 66 - i * 32.0f, 340, 22)] autorelease];
        [[t cell] setPlaceholderString:[places objectAtIndex:i]];
        [[t cell] setScrollable:YES];
        [t setStringValue:[values objectAtIndex:i]];
        [box addSubview:t];
        [fields addObject:t];
    }
    [LRAlert runTitle:L(@"Edit Subscription")
              message:L(@"An extra header is sent with every fetch, for panels that want one (Name: value).")
              buttons:[NSArray arrayWithObjects:L(@"Save"), L(@"Cancel"), nil]
            accessory:box window:[self window] done:^(NSInteger index) {
        if (index != 0) return;
        NSString *name = LRTrim([[fields objectAtIndex:0] stringValue]);
        NSString *url = LRTrim([[fields objectAtIndex:1] stringValue]);
        if (!name || !url) { [LRToast showError:L(@"Name and link are required")]; return; }
        [self saveName:name url:url header:LRTrim([[fields objectAtIndex:2] stringValue])];
    }];
}

- (void)buildSubscription {
    LRSubscription *sub = _subscription;
    __block LRServerWindowController *me = self;
    LRInfoHeader *header = [[[LRInfoHeader alloc] initWithFrame:NSZeroRect] autorelease];
    header.title = sub.name;
    LRSection *section = nil;
    for (LRSection *sec in [LRCatalog shared].sections) if (sec.sectionId == sub.index) section = sec;
    NSUInteger n = [section.servers count];
    header.subtitle = [NSString stringWithFormat:@"%lu %@", (unsigned long)n,
                       LRPlural((NSInteger)n, L(@"server"), L(@"servers (few)"), L(@"servers"))];
    header.country = section.countryCode;
    header.icon = [NSImage imageNamed:NSImageNameNetwork];
    LRForm *f = [[[LRForm alloc] initWithWidth:540 labelWidth:205] autorelease];
    NSFont *value = [NSFont systemFontOfSize:13];
    [f addLabel:L(@"Traffic") view:[self usageGauge:sub width:[f controlWidth]]];
    [f addLabel:L(@"Uploaded") view:LRLabel(LRBytes(sub.upload), value, nil)];
    [f addLabel:L(@"Downloaded") view:LRLabel(LRBytes(sub.download), value, nil)];
    NSString *expires = sub.expire ? LRDateText(sub.expire) : L(@"No expiration");
    NSInteger days = [sub daysLeft];
    if (days != NSIntegerMax)
        expires = [expires stringByAppendingFormat:@" (%@)", days < 0 ? L(@"expired")
                   : [NSString stringWithFormat:L(@"%ld d left"), (long)days]];
    NSTextField *exp = LRLabel(expires, value, days < 3 ? SKIN->bad : nil);
    [f addLabel:L(@"Expires") view:exp];
    if (sub.refillDate) [f addLabel:L(@"Traffic Refill") view:LRLabel(LRDateText(sub.refillDate), value, nil)];
    if (sub.updateIntervalHours)
        [f addLabel:L(@"Suggested Update Interval")
               view:LRLabel([NSString stringWithFormat:L(@"every %u h"), sub.updateIntervalHours], value, nil)];
    if ([sub.summary length] || [sub.webPageURL length] || [sub.supportURL length]) [f addSeparator];
    if ([sub.summary length]) [f addLabel:L(@"Provider") view:LRWrappingLabel(sub.summary, value, nil, [f controlWidth])];
    if ([sub.webPageURL length]) {
        NSButton *web = LRPushButton(L(@"Open the Web Page"), ^(id s) {
            NSURL *u = [NSURL URLWithString:sub.webPageURL];
            if (u) [[NSWorkspace sharedWorkspace] openURL:u];
        });
        [web setFrameOrigin:NSMakePoint(-6, 0)];
        [f addLabel:L(@"Web Page") view:web];
    }
    if ([sub.supportURL length] && ![sub.supportURL isEqualToString:sub.webPageURL]) {
        NSButton *sup = LRPushButton(L(@"Contact Support"), ^(id s) {
            NSString *u = sub.supportURL;
            NSURL *url = [NSURL URLWithString:u];
            if (url && ![[url scheme] length]) url = [NSURL URLWithString:[@"https://" stringByAppendingString:u]];
            if (url) [[NSWorkspace sharedWorkspace] openURL:url];
        });
        [f addLabel:L(@"Support") view:sup];
    }
    [f addSeparator];
    NSTextField *link = LRLabel(LRStealth(sub.url), [NSFont systemFontOfSize:12], nil);
    [link setSelectable:![LRPrefs stealthMode]];
    [f addLabel:L(@"Subscription Link") view:link];
    if ([sub.header length]) [f addLabel:L(@"Extra header") view:LRLabel(LRStealth(sub.header), value, nil)];
    NSString *ua = [[LRDaemonSettings shared] stringForKey:@"sub_user_agent"];
    [f addLabel:@"User-Agent" view:LRLabel(ua ? ua : @"Happ/3.26.1", value, nil)];
    NSTextField *hw = LRLabel(_hwid ? LRStealth(_hwid) : L(@"Loading..."), [NSFont userFixedPitchFontOfSize:11], nil);
    [hw setSelectable:YES];
    [f addLabel:@"HWID" view:hw];
    [f addNote:L(@"Panels see the device id and the user agent.")];
    [f finish];
    NSMutableArray *buttons = [NSMutableArray array];
    NSButton *upd = LRPushButton(_updating ? L(@"Updating...") : L(@"Update Now"), ^(id s) { [me update]; });
    [upd setEnabled:!_updating];
    [buttons addObject:upd];
    [buttons addObject:LRPushButton(L(@"Check Latency"), ^(id s) {
        for (LRSection *sec in [LRCatalog shared].sections)
            if (sec.sectionId == sub.index) [[LRCatalog shared] pingServers:sec.servers];
        [LRToast show:L(@"All configurations in this subscription are being pinged")];
    })];
    [buttons addObject:LRPushButton(L(@"Copy Link"), ^(id s) {
        LRSetPasteboardString(sub.url);
        [LRToast showSuccess:L(@"Link copied")];
    })];
    NSButton *editKey = LRPushButton(L(@"Edit…"), ^(id s) { [me edit]; });
    [editKey setTag:1];
    [buttons addObject:editKey];
    NSButton *deleteKey = LRPushButton(L(@"Delete…"), ^(id s) {
        [LRAlert runTitle:L(@"Delete Subscription") message:sub.name
                  buttons:[NSArray arrayWithObjects:L(@"Delete"), L(@"Cancel"), nil]
                accessory:nil window:[me window] done:^(NSInteger index) {
            if (index != 0) return;
            [[LRDaemonClient shared] deleteSubscriptionIndex:sub.index reply:^(NSString *reply) {
                LRLog(@"subscriptions", @"subscription deleted");
                [[LRCatalog shared] reload];
                [[me window] close];
            }];
        }];
    });
    [deleteKey setTag:1];
    [buttons addObject:deleteKey];
    LRBuildInfoContent([self window], header, f, buttons);
}
@end
