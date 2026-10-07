#import "LRStatusMenu.h"
#import "LRAppDelegate.h"
#import "LRMainWindowController.h"
#import "LRBlocks.h"
#import "LRDraw.h"
#import "LRTunnel.h"
#import "LRCatalog.h"
#import "LRModels.h"
#import "LRAWGProfiles.h"
#import "LRImporter.h"

@implementation LRStatusMenu

- (id)init {
    if ((self = [super init])) {
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(update) name:LRTunnelDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(prefsChanged) name:LRPrefsDidChangeNotification object:nil];
        [self rebuild];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_blink invalidate];
    [_blink release];
    if (_item) [[NSStatusBar systemStatusBar] removeStatusItem:_item];
    [_item release];
    [_menu release];
    [super dealloc];
}

+ (BOOL)wanted {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"LRStatusItem"];
    return v ? [v boolValue] : YES;
}

- (void)prefsChanged {
    if ([LRStatusMenu wanted] != (_item != nil)) [self rebuild];
}

- (void)rebuild {
    if (_item) {
        [[NSStatusBar systemStatusBar] removeStatusItem:_item];
        [_item release];
        _item = nil;
    }
    if (![LRStatusMenu wanted]) {
        [self update];
        return;
    }
    _item = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength] retain];
    [_item setHighlightMode:YES];
    [_menu release];
    _menu = [[NSMenu alloc] initWithTitle:@"LegacyRay"];
    [_menu setDelegate:self];
    [_menu setAutoenablesItems:NO];
    [_item setMenu:_menu];
    [self update];
}

- (int)iconState {
    LRTunnel *t = [LRTunnel shared];
    if (t.state == LRTunnelConnected) return 2;
    if (t.state == LRTunnelConnecting || t.busy) return 1;
    if (t.state == LRTunnelError) return 3;
    return 0;
}

- (void)update {
    int state = [self iconState];
    BOOL blinking = state == 1;
    if (blinking && !_blink) {
        _blink = [[NSTimer scheduledTimerWithTimeInterval:0.55 target:self selector:@selector(blink:)
                                                 userInfo:nil repeats:YES] retain];
    } else if (!blinking && _blink) {
        [_blink invalidate];
        [_blink release];
        _blink = nil;
    }
    [_item setImage:LRStatusItemImage(blinking && _blinkOn ? 2 : state)];
    LRTunnel *t = [LRTunnel shared];
    NSString *tip = t.state == LRTunnelConnected ? L(@"Connected") : L(@"Not Connected");
    [_item setToolTip:[NSString stringWithFormat:@"LegacyRay — %@", tip]];
}

- (void)blink:(NSTimer *)timer {
    _blinkOn = !_blinkOn;
    [_item setImage:LRStatusItemImage(_blinkOn ? 2 : 1)];
}

#pragma mark the menu

- (NSImage *)flagImage:(NSString *)code {
    if ([code length] != 2) return nil;
    NSString *c = [[code copy] autorelease];
    return LRImageWithSize(NSMakeSize(16, 16), YES, ^(CGContextRef ctx, CGRect r) {
        LRDrawFlag(ctx, c, CGRectInset(r, 1, 1));
    });
}

- (NSImage *)dot:(NSColor *)color {
    NSColor *c = [[color copy] autorelease];
    return LRImageWithSize(NSMakeSize(16, 16), YES, ^(CGContextRef ctx, CGRect r) {
        LRDrawLED(ctx, CGPointMake(8, 8), 4, c, YES);
    });
}

- (NSString *)pingText:(LRServer *)sv {
    NSNumber *ping = [[LRCatalog shared] pingForServer:sv];
    if (!ping || [ping intValue] == LR_PING_RUNNING) return nil;
    if ([ping intValue] < 0) return L(@"no signal");
    return [NSString stringWithFormat:@"%d %@", [ping intValue], L(@"ms")];
}

- (void)addServer:(LRServer *)sv name:(NSString *)name to:(NSMenu *)menu indent:(NSInteger)indent {
    LRCatalog *catalog = [LRCatalog shared];
    LRTunnel *t = [LRTunnel shared];
    NSString *title = name;
    NSString *ping = [self pingText:sv];
    NSMenuItem *it = [menu lr_addItem:title block:^{
        [LRPrefs setSelectedBackend:LRBackendServer];
        [[LRTunnel shared] connectServerIndex:sv.index];
    }];
    if (ping) {
        /* the latency in grey after the name, like mail's counts */
        NSMutableAttributedString *a = [[[NSMutableAttributedString alloc] initWithString:title
            attributes:[NSDictionary dictionaryWithObject:[NSFont menuFontOfSize:14] forKey:NSFontAttributeName]] autorelease];
        [a appendAttributedString:[[[NSAttributedString alloc] initWithString:[@"   " stringByAppendingString:ping]
            attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont menuFontOfSize:11], NSFontAttributeName,
                        [NSColor disabledControlTextColor], NSForegroundColorAttributeName, nil]] autorelease]];
        [it setAttributedTitle:a];
    }
    [it setImage:[self flagImage:[sv countryCode]]];
    [it setIndentationLevel:indent];
    BOOL selected = [LRPrefs selectedBackend] == LRBackendServer && sv.index == catalog.selectedIndex;
    [it setState:selected ? NSOnState : NSOffState];
    [it setEnabled:sv.supported && !t.busy];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    LRTunnel *t = [LRTunnel shared];
    LRCatalog *catalog = [LRCatalog shared];
    LRSkin *s = SKIN;

    NSString *state;
    NSColor *lamp;
    switch (t.state) {
        case LRTunnelConnected: state = L(@"Connected"); lamp = s->ledGreen; break;
        case LRTunnelConnecting: state = L(@"Connecting…"); lamp = s->ledAmber; break;
        case LRTunnelError: state = L(@"Connection Failed"); lamp = s->ledRed; break;
        case LRTunnelOffline: state = L(@"Service Stopped"); lamp = s->ledOff; break;
        default: state = L(@"Not Connected"); lamp = s->ledOff; break;
    }
    if (t.busy && t.state != LRTunnelConnected) { state = L(@"Connecting…"); lamp = s->ledAmber; }
    NSMenuItem *head = [menu lr_addItem:[NSString stringWithFormat:@"LegacyRay: %@", state] block:nil];
    [head setEnabled:NO];
    [head setImage:[self dot:lamp]];
    NSString *where = nil;
    if ([LRPrefs selectedBackend] == LRBackendAmneziaWG) where = [[LRAWGProfiles active] name];
    else if ([catalog selectedServer]) where = [catalog displayNameForServer:[catalog selectedServer]];
    if (where) {
        NSString *line = where;
        if (t.state == LRTunnelConnected)
            line = [NSString stringWithFormat:@"%@ · %@ · ↓ %@ ↑ %@", where, LRDuration([t liveUptime]),
                    LRBytes(t.bytesDown), LRBytes(t.bytesUp)];
        NSMenuItem *w = [menu lr_addItem:line block:nil];
        [w setEnabled:NO];
        [w setIndentationLevel:1];
    }
    [menu lr_addSeparator];
    NSMenuItem *toggle = [menu lr_addItem:[t isOn] ? L(@"Disconnect") : L(@"Connect") block:^{
        if ([LRTunnel shared].state == LRTunnelOffline && ![[LRTunnel shared] isOn])
            [[LRAppDelegate shared] startDaemon:nil];
        else [[LRTunnel shared] toggle];
    }];
    [toggle setEnabled:[t isOn] || [catalog selectedServer] || [LRPrefs selectedBackend] == LRBackendAmneziaWG];

    /* servers: one submenu per group when there are several groups */
    NSArray *sections = catalog.sections;
    NSArray *profiles = [LRAWGProfiles profiles];
    if ([sections count] || [profiles count]) {
        NSMenuItem *serversItem = [menu lr_addItem:L(@"Servers") block:nil];
        NSMenu *servers = [[[NSMenu alloc] initWithTitle:@""] autorelease];
        [servers setAutoenablesItems:NO];
        BOOL nested = [sections count] + ([profiles count] ? 1 : 0) > 1;
        for (LRSection *sec in sections) {
            NSMenu *target = servers;
            if (nested) {
                NSMenuItem *g = [servers lr_addItem:sec.title block:nil];
                [g setImage:[self flagImage:sec.countryCode]];
                target = [[[NSMenu alloc] initWithTitle:@""] autorelease];
                [target setAutoenablesItems:NO];
                [g setSubmenu:target];
                BOOL holdsSelection = NO;
                for (LRServer *sv in sec.servers) if (sv.index == catalog.selectedIndex) holdsSelection = YES;
                [g setState:holdsSelection && [LRPrefs selectedBackend] == LRBackendServer ? NSMixedState : NSOffState];
            }
            for (LRServer *sv in sec.servers) [self addServer:sv name:[sec nameForServer:sv] to:target indent:0];
            if ([sec.servers count] > 1) {
                [target lr_addSeparator];
                NSArray *list = sec.servers;
                [target lr_addItem:L(@"Connect to the Fastest") block:^{
                    [[[LRAppDelegate shared] mainController].sidebar connectFastestOf:list];
                }];
            }
        }
        if ([profiles count]) {
            NSMenu *target = servers;
            if (nested) {
                NSMenuItem *g = [servers lr_addItem:@"AmneziaWG" block:nil];
                target = [[[NSMenu alloc] initWithTitle:@""] autorelease];
                [target setAutoenablesItems:NO];
                [g setSubmenu:target];
            }
            NSString *active = [[LRAWGProfiles active] path];
            for (LRAWGProfile *p in profiles) {
                NSMenuItem *it = [target lr_addItem:p.name block:^{
                    [LRAWGProfiles setActive:p];
                    [LRPrefs setSelectedBackend:LRBackendAmneziaWG];
                    LRTunnel *tun = [LRTunnel shared];
                    if ([tun isOn]) {
                        [tun disconnect];
                        [tun performSelector:@selector(startAWG) withObject:nil afterDelay:1.5];
                    } else [tun startAWG];
                }];
                [it setState:[LRPrefs selectedBackend] == LRBackendAmneziaWG && [p.path isEqualToString:active]
                     ? NSOnState : NSOffState];
            }
        }
        [serversItem setSubmenu:servers];
    }
    NSMenuItem *add = [menu lr_addItem:L(@"Add Servers") block:nil];
    [add setSubmenu:[LRImporter menu]];
    [menu lr_addSeparator];
    [menu lr_addItem:L(@"Open LegacyRay") block:^{ [[LRAppDelegate shared] showMainWindow:nil]; }];
    [menu lr_addItem:L(@"Check the Connection…") block:^{ [[LRAppDelegate shared] openCheck:nil]; }];
    [menu lr_addItem:L(@"Preferences…") block:^{ [[LRAppDelegate shared] openPreferences:nil]; }];
    [menu lr_addSeparator];
    [menu lr_addItem:L(@"Quit LegacyRay") block:^{ [NSApp terminate:nil]; }];
}
@end
