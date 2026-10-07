#import "LRAppDelegate.h"
#import "LRMainWindowController.h"
#import "LRStatusMenu.h"
#import "LRHelperInstaller.h"
#import "LRImporter.h"
#import "LRBlocks.h"
#import "LRAlert.h"
#import "LRToast.h"
#import "LRDraw.h"
#import "LRTunnel.h"
#import "LRCatalog.h"
#import "LRDaemonClient.h"
#import "LRDaemonSettings.h"
#import "LRAWGProfiles.h"
#import "LRActivityLog.h"
#import "LRUpdateChecker.h"
#import "LRReminders.h"
#import "LRVersion.h"
#import "LRDashboardView.h"
#import "LRPreferencesController.h"
#import "LRCheckWindowController.h"
#import "LRDiagnosticsWindowController.h"
#import "LRAWGWindowController.h"
#import "LROwnServersWindowController.h"
#import "LRAboutWindowController.h"
#import "LRServerWindowController.h"
#import "LRShareWindowController.h"
#include "senko_paths.h"

@implementation LRAppDelegate

+ (LRAppDelegate *)shared {
    return (LRAppDelegate *)[NSApp delegate];
}

- (id)init {
    if ((self = [super init])) _windows = [[NSMutableDictionary alloc] init];
    return self;
}

- (void)dealloc {
    [_main release];
    [_statusMenu release];
    [_windows release];
    [_connectItem release];
    [super dealloc];
}

- (NSWindow *)mainWindow {
    return [_main window];
}

- (LRMainWindowController *)mainController {
    return _main;
}

#pragma mark menus

- (NSMenuItem *)item:(NSString *)title action:(SEL)action key:(NSString *)key in:(NSMenu *)menu {
    NSMenuItem *it = [menu addItemWithTitle:title action:action keyEquivalent:key ? key : @""];
    return it;
}

- (NSMenu *)submenu:(NSString *)title in:(NSMenu *)bar {
    NSMenuItem *holder = [bar addItemWithTitle:title action:NULL keyEquivalent:@""];
    NSMenu *m = [[[NSMenu alloc] initWithTitle:title] autorelease];
    [holder setSubmenu:m];
    return m;
}

- (void)buildMenus {
    NSMenu *bar = [[[NSMenu alloc] initWithTitle:@""] autorelease];

    /* the application menu: its title is the app's name whatever this says */
    NSMenu *app = [self submenu:@"LegacyRay" in:bar];
    [self item:L(@"About LegacyRay") action:@selector(openAbout:) key:nil in:app];
    [self item:L(@"Check for Updates…") action:@selector(checkForUpdates:) key:nil in:app];
    [app addItem:[NSMenuItem separatorItem]];
    [self item:L(@"Preferences…") action:@selector(openPreferences:) key:@"," in:app];
    [app addItem:[NSMenuItem separatorItem]];
    NSMenuItem *services = [self item:L(@"Services") action:NULL key:nil in:app];
    NSMenu *servicesMenu = [[[NSMenu alloc] initWithTitle:L(@"Services")] autorelease];
    [services setSubmenu:servicesMenu];
    [NSApp setServicesMenu:servicesMenu];
    [app addItem:[NSMenuItem separatorItem]];
    [self item:L(@"Hide LegacyRay") action:@selector(hide:) key:@"h" in:app];
    NSMenuItem *others = [self item:L(@"Hide Others") action:@selector(hideOtherApplications:) key:@"h" in:app];
    [others setKeyEquivalentModifierMask:NSCommandKeyMask | NSAlternateKeyMask];
    [self item:L(@"Show All") action:@selector(unhideAllApplications:) key:nil in:app];
    [app addItem:[NSMenuItem separatorItem]];
    [self item:L(@"Quit LegacyRay") action:@selector(terminate:) key:@"q" in:app];

    NSMenu *file = [self submenu:L(@"File") in:bar];
    [file lr_addItem:L(@"Add Subscription…") key:@"n" block:^{ [LRImporter promptSubscription]; }];
    NSMenuItem *links = [file lr_addItem:L(@"Enter Links…") key:@"N" block:^{ [LRImporter promptManual]; }];
    (void)links;
    [file lr_addItem:L(@"Import File…") key:@"o" block:^{ [LRImporter chooseFile]; }];
    NSMenuItem *qr = [file lr_addItem:L(@"Read QR Code on Screen") key:@"r" block:^{ [LRImporter scanScreen]; }];
    [qr setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
    [file addItem:[NSMenuItem separatorItem]];
    [self item:L(@"Export Backup…") action:@selector(exportBackup:) key:nil in:file];
    [self item:L(@"Restore Backup…") action:@selector(restoreBackup:) key:nil in:file];
    [file addItem:[NSMenuItem separatorItem]];
    [self item:L(@"Close Window") action:@selector(performClose:) key:@"w" in:file];

    NSMenu *edit = [self submenu:L(@"Edit") in:bar];
    [self item:L(@"Undo") action:@selector(undo:) key:@"z" in:edit];
    [self item:L(@"Redo") action:@selector(redo:) key:@"Z" in:edit];
    [edit addItem:[NSMenuItem separatorItem]];
    [self item:L(@"Cut") action:@selector(cut:) key:@"x" in:edit];
    [self item:L(@"Copy") action:@selector(copy:) key:@"c" in:edit];
    [self item:L(@"Paste") action:@selector(paste:) key:@"v" in:edit];
    [self item:L(@"Select All") action:@selector(selectAll:) key:@"a" in:edit];

    NSMenu *conn = [self submenu:L(@"Connection") in:bar];
    [conn setDelegate:self];
    [_connectItem release];
    _connectItem = [[conn lr_addItem:L(@"Connect") key:@"k" block:^{ [[LRTunnel shared] toggle]; }] retain];
    [conn lr_addItem:L(@"Next Server") key:@"]" block:^{
        [[LRTunnel shared] seek:1];
        [_main.sidebar selectCurrent];
    }];
    [conn lr_addItem:L(@"Previous Server") key:@"[" block:^{
        [[LRTunnel shared] seek:-1];
        [_main.sidebar selectCurrent];
    }];
    NSMenuItem *fast = [conn lr_addItem:L(@"Connect to the Fastest") key:@"f" block:^{
        [_main.sidebar connectFastestOf:[LRCatalog shared].servers];
    }];
    [fast setKeyEquivalentModifierMask:NSCommandKeyMask | NSAlternateKeyMask];
    [conn addItem:[NSMenuItem separatorItem]];
    [conn lr_addItem:L(@"Check Latency of All") key:@"l" block:^{ [[LRCatalog shared] pingAll]; }];
    [conn lr_addItem:L(@"Update All Subscriptions") key:@"r" block:^{
        [LRToast show:L(@"Updating subscriptions...")];
        [[LRCatalog shared] refreshAllSubscriptions:^(NSUInteger ok, NSUInteger failed) {
            NSString *msg = [NSString stringWithFormat:L(@"Subscriptions updated: %lu/%lu"),
                             (unsigned long)ok, (unsigned long)(ok + failed)];
            if (failed) [LRToast showError:msg]; else [LRToast showSuccess:msg];
        }];
    }];
    [conn addItem:[NSMenuItem separatorItem]];
    [self item:L(@"Check the Connection…") action:@selector(openCheck:) key:@"i" in:conn];
    [self item:L(@"AmneziaWG Profiles…") action:@selector(openAWGProfiles:) key:nil in:conn];
    [self item:L(@"Own Servers…") action:@selector(openOwnServers:) key:nil in:conn];

    NSMenu *window = [self submenu:L(@"Window") in:bar];
    [self item:L(@"Minimize") action:@selector(performMiniaturize:) key:@"m" in:window];
    [self item:L(@"Zoom") action:@selector(performZoom:) key:nil in:window];
    [window addItem:[NSMenuItem separatorItem]];
    [self item:@"LegacyRay" action:@selector(showMainWindow:) key:@"1" in:window];
    [self item:L(@"Diagnostics") action:@selector(openDiagnostics:) key:@"2" in:window];
    [window addItem:[NSMenuItem separatorItem]];
    [self item:L(@"Bring All to Front") action:@selector(arrangeInFront:) key:nil in:window];
    [NSApp setWindowsMenu:window];

    NSMenu *help = [self submenu:L(@"Help") in:bar];
    [help lr_addItem:L(@"LegacyRay on GitHub") block:^{ [LRUpdateChecker openProjectPage]; }];
    [self item:L(@"Diagnostics") action:@selector(openDiagnostics:) key:nil in:help];
    if ([NSApp respondsToSelector:@selector(setHelpMenu:)]) [NSApp setHelpMenu:help];

    [NSApp setMainMenu:bar];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    LRTunnel *t = [LRTunnel shared];
    [_connectItem setTitle:[t isOn] ? L(@"Disconnect") : L(@"Connect")];
}

#pragma mark launch

- (void)applicationWillFinishLaunching:(NSNotification *)n {
    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
                                                       andSelector:@selector(handleURLEvent:reply:)
                                                     forEventClass:kInternetEventClass andEventID:kAEGetURL];
}

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    [self buildMenus];
    LRLog(@"app", @"started %s on OS X %@", LR_VERSION, LRMacSystemVersion());
    [LRAWGProfiles migrate];
    _statusMenu = [[LRStatusMenu alloc] init];
    _main = [[LRMainWindowController alloc] initMainWindow];
    [_main showWindow:nil];
    [[LRTunnel shared] start];
    _launched = YES;
    [self ensureHelper:^(BOOL ready) {
        if (!ready) return;
        [[LRCatalog shared] reload:^(BOOL ok) {
            if (ok && [LRPrefs refreshSubscriptionsOnOpen] && [[LRCatalog shared].subscriptions count])
                [[LRCatalog shared] refreshAllSubscriptions:nil];
        }];
        [[LRDaemonSettings shared] refresh];
        [LRUpdateChecker checkIfDue:^(LRRelease *release) { [self offerRelease:release]; }];
    }];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(languageChanged) name:LRLanguageDidChangeNotification object:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible {
    if (!visible) [self showMainWindow:nil];
    return YES;
}

- (void)applicationDidBecomeActive:(NSNotification *)n {
    [[LRTunnel shared] pollNow];
}

- (void)application:(NSApplication *)app openFiles:(NSArray *)files {
    for (NSString *f in files) [LRImporter importFileAtPath:f];
    [app replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

/* development only (LRDeveloperNoHelper): open any window or pane by link,
   legacyray://dev/prefs/routing, /window/check, /theme/flat, /lang/en */
- (BOOL)handleDevURL:(NSURL *)url {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"LRDeveloperNoHelper"]) return NO;
    NSArray *parts = [[url path] pathComponents];
    NSString *what = [parts count] > 1 ? [parts objectAtIndex:1] : nil;
    NSString *arg = [parts count] > 2 ? [parts objectAtIndex:2] : nil;
    if ([what isEqualToString:@"prefs"]) {
        [self openPreferences:nil];
        if (arg) [(LRPreferencesController *)[_windows objectForKey:@"prefs"] selectPane:arg];
    } else if ([what isEqualToString:@"window"]) {
        if ([arg isEqualToString:@"check"]) [self openCheck:nil];
        else if ([arg isEqualToString:@"diag"]) [self openDiagnostics:nil];
        else if ([arg isEqualToString:@"awg"]) [self openAWGProfiles:nil];
        else if ([arg isEqualToString:@"ssh"]) [self openOwnServers:nil];
        else if ([arg isEqualToString:@"about"]) [self openAbout:nil];
        else if ([arg isEqualToString:@"main"]) [self showMainWindow:nil];
        else if ([arg isEqualToString:@"server"] && [[LRCatalog shared] selectedServer])
            [self showServer:[[LRCatalog shared] selectedServer]];
        else if ([arg isEqualToString:@"share"] && [[LRCatalog shared] selectedServer])
            [self shareServer:[[LRCatalog shared] selectedServer]];
        else if ([arg isEqualToString:@"import"]) [LRImporter promptManual];
    } else if ([what isEqualToString:@"theme"]) {
        [LRPrefs setTheme:[arg isEqualToString:@"flat"] ? LRThemeFlat :
                          [arg isEqualToString:@"classic"] ? LRThemeClassic : LRThemeAuto];
        [self rebuildInterface];
    } else if ([what isEqualToString:@"lang"]) {
        LRSetLanguageSetting([arg isEqualToString:@"en"] ? LRLanguageEnglish :
                             [arg isEqualToString:@"zh"] ? LRLanguageChinese :
                             [arg isEqualToString:@"ru"] ? LRLanguageRussian : LRLanguageAuto);
    } else if ([what isEqualToString:@"connect"]) {
        /* the last server whose name holds arg */
        LRServer *pick = nil;
        for (LRServer *sv in [LRCatalog shared].servers)
            if (!arg || [[[LRCatalog shared] displayNameForServer:sv] rangeOfString:arg].location != NSNotFound) pick = sv;
        if (pick) {
            [LRPrefs setSelectedBackend:LRBackendServer];
            [[LRTunnel shared] connectServerIndex:pick.index];
            [_main.sidebar selectCurrent];
        }
    } else if ([what isEqualToString:@"click"]) {
        /* a real click through the window server, at the middle of a control */
        NSView *v = [arg isEqualToString:@"card"] ? (NSView *)_main.dashboard.card : (NSView *)_main.dashboard.power;
        NSWindow *w = [v window];
        NSRect r = [w convertRectToScreen:[v convertRect:[v bounds] toView:nil]];
        CGFloat top = NSMaxY([[[NSScreen screens] objectAtIndex:0] frame]);
        CGPoint p = CGPointMake(NSMidX(r), top - NSMidY(r));
        NSLog(@"LRDEV click %@ at %@ target=%@ action=%@ enabled=%d cell=%@", arg, NSStringFromPoint(NSPointFromCGPoint(p)),
              [(NSControl *)v target], NSStringFromSelector([(NSControl *)v action]), [(NSControl *)v isEnabled],
              [(NSControl *)v cell]);
        CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, p, kCGMouseButtonLeft);
        CGEventRef up = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, p, kCGMouseButtonLeft);
        CGEventPost(kCGHIDEventTap, down);
        usleep(120000);
        CGEventPost(kCGHIDEventTap, up);
        CFRelease(down);
        CFRelease(up);
    } else if ([what isEqualToString:@"ping"]) {
        [[LRCatalog shared] pingAll];
    } else if ([what isEqualToString:@"reload"]) {
        [[LRCatalog shared] reload];
    } else if ([what isEqualToString:@"toast"]) {
        [LRToast showSuccess:arg ? arg : @"LegacyRay"];
    } else if ([what isEqualToString:@"close"]) {
        [[NSApp keyWindow] performClose:nil];
    }
    return YES;
}

- (void)handleURLEvent:(NSAppleEventDescriptor *)event reply:(NSAppleEventDescriptor *)reply {
    NSString *s = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
    NSURL *url = s ? [NSURL URLWithString:s] : nil;
    if ([[url scheme] isEqualToString:@"legacyray"] && [[url host] isEqualToString:@"dev"] && [self handleDevURL:url])
        return;
    if (!url && s) {
        [LRImporter importText:s];
        return;
    }
    [LRImporter handleOpenURL:url];
}

#pragma mark helper and daemon

- (void)ensureHelper:(void (^)(BOOL))done {
    void (^callback)(BOOL) = [[done copy] autorelease];
    LRHelperState state = [LRHelperInstaller state];
    if (state == LRHelperReady) {
        [[LRDaemonClient shared] ensureDaemon:^(BOOL up, NSString *detail) {
            if (!up) LRLogFail(@"daemon", @"daemon offline: %@", detail);
            [[LRTunnel shared] pollNow];
            if (callback) callback(up);
        }];
        return;
    }
    _helperPrompted = YES;
    [LRHelperInstaller installExplaining:YES done:^(BOOL ok, NSString *error) {
        if (!ok) {
            if (error) [LRAlert showTitle:L(@"The Helper Was Not Installed") message:error];
            [[LRTunnel shared] pollNow];
            if (callback) callback(NO);
            return;
        }
        [LRToast showSuccess:L(@"The network helper is installed")];
        [[LRDaemonClient shared] ensureDaemon:^(BOOL up, NSString *detail) {
            [[LRTunnel shared] stop];
            [[LRTunnel shared] start];
            if (callback) callback(up);
        }];
    }];
}

- (IBAction)startDaemon:(id)sender {
    [self ensureHelper:^(BOOL ready) {
        if (!ready) return;
        [[LRCatalog shared] reload];
        [[LRDaemonSettings shared] refresh];
    }];
}

#pragma mark windows

- (id)windowNamed:(NSString *)name make:(id (^)(void))make {
    NSWindowController *wc = [_windows objectForKey:name];
    if (!wc && make) {
        wc = make();
        if (wc) {
            [_windows setObject:wc forKey:name];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowClosed:)
                                                         name:NSWindowWillCloseNotification object:[wc window]];
        }
    }
    return wc;
}

- (void)forgetWindowNamed:(NSString *)name {
    NSWindowController *wc = [_windows objectForKey:name];
    if (!wc) return;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowWillCloseNotification object:[wc window]];
    [[wc retain] autorelease];
    [_windows removeObjectForKey:name];
}

- (void)windowClosed:(NSNotification *)n {
    NSWindow *w = [n object];
    for (NSString *name in [_windows allKeys]) {
        NSWindowController *wc = [_windows objectForKey:name];
        if ([wc window] == w) {
            /* let the close finish before the controller goes */
            [[wc retain] autorelease];
            [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowWillCloseNotification object:w];
            [_windows removeObjectForKey:name];
            break;
        }
    }
}

/* a window taller than the screen it opens on comes down to fit */
- (void)fitOnScreen:(NSWindow *)w {
    NSScreen *screen = [w screen] ? [w screen] : [NSScreen mainScreen];
    NSRect vis = [screen visibleFrame], f = [w frame];
    if (NSHeight(f) <= NSHeight(vis) && NSMaxY(f) <= NSMaxY(vis)) return;
    if (NSHeight(f) > NSHeight(vis)) {
        if (!([w styleMask] & NSResizableWindowMask)) return;
        f.size.height = NSHeight(vis);
    }
    f.origin.y = NSMaxY(vis) - NSHeight(f);
    [w setFrame:f display:YES];
}

- (void)present:(NSString *)name make:(id (^)(void))make {
    NSWindowController *wc = [self windowNamed:name make:make];
    LRActivateApp();
    [self fitOnScreen:[wc window]];
    [wc showWindow:nil];
    [[wc window] makeKeyAndOrderFront:nil];
}

- (IBAction)showMainWindow:(id)sender {
    LRActivateApp();
    [_main showWindow:nil];
    [[_main window] makeKeyAndOrderFront:nil];
}

- (IBAction)openPreferences:(id)sender {
    [self present:@"prefs" make:^id { return [[[LRPreferencesController alloc] init] autorelease]; }];
}

- (IBAction)openCheck:(id)sender {
    [self present:@"check" make:^id { return [[[LRCheckWindowController alloc] init] autorelease]; }];
}

- (IBAction)openDiagnostics:(id)sender {
    [self present:@"diag" make:^id { return [[[LRDiagnosticsWindowController alloc] init] autorelease]; }];
}

- (IBAction)openAWGProfiles:(id)sender {
    [self present:@"awg" make:^id { return [[[LRAWGWindowController alloc] init] autorelease]; }];
}

- (IBAction)openOwnServers:(id)sender {
    [self present:@"ssh" make:^id { return [[[LROwnServersWindowController alloc] init] autorelease]; }];
}

- (IBAction)openAbout:(id)sender {
    [self present:@"about" make:^id { return [[[LRAboutWindowController alloc] init] autorelease]; }];
}

- (void)showServer:(LRServer *)server {
    NSString *name = [NSString stringWithFormat:@"server.%d", server.index];
    [self present:name make:^id { return [[[LRServerWindowController alloc] initWithServer:server] autorelease]; }];
}

- (void)showSubscription:(LRSubscription *)subscription {
    NSString *name = [NSString stringWithFormat:@"sub.%d", subscription.index];
    [self present:name make:^id {
        return [[[LRServerWindowController alloc] initWithSubscription:subscription] autorelease];
    }];
}

- (void)showAWGProfile:(LRAWGProfile *)profile {
    [self openAWGProfiles:nil];
    LRAWGWindowController *wc = [_windows objectForKey:@"awg"];
    [wc selectProfile:profile];
}

- (void)shareServer:(LRServer *)server {
    NSString *title = [[LRCatalog shared] displayNameForServer:server];
    NSString *subtitle = [server protocolSummary];
    [[LRDaemonClient shared] serverLinkIndex:server.index reply:^(NSString *link) {
        if (!link) { [LRToast showError:L(@"The link could not be read")]; return; }
        [self shareText:link title:title subtitle:subtitle];
    }];
}

- (void)shareText:(NSString *)text title:(NSString *)title subtitle:(NSString *)subtitle {
    LRShareWindowController *wc = [[[LRShareWindowController alloc] initWithTitle:title payload:text] autorelease];
    wc.subtitle = subtitle;
    [_windows setObject:wc forKey:[NSString stringWithFormat:@"share.%p", wc]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowClosed:)
                                                 name:NSWindowWillCloseNotification object:[wc window]];
    LRActivateApp();
    [wc showWindow:nil];
}

#pragma mark backup

- (IBAction)exportBackup:(id)sender {
    [[LRDaemonClient shared] exportBackup:^(NSString *reply) {
        if (!LRReplyIsOK(reply)) {
            [LRToast showError:LRErrorFromReply(reply) ? LRErrorFromReply(reply) : L(@"Backup export failed")];
            return;
        }
        NSData *data = [NSData dataWithContentsOfFile:@SENKO_BACKUP_EXPORT];
        if (![data length]) {
            [LRToast showError:L(@"Backup export failed")];
            return;
        }
        NSSavePanel *panel = [NSSavePanel savePanel];
        NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
        [f setDateFormat:@"yyyy-MM-dd"];
        [panel setNameFieldStringValue:[NSString stringWithFormat:@"LegacyRay %@.lray", [f stringFromDate:[NSDate date]]]];
        [panel setAllowedFileTypes:[NSArray arrayWithObject:@"lray"]];
        [panel setMessage:L(@"The backup holds every server, subscription, rule and daemon setting, keys included. Keep it private.")];
        void (^save)(NSInteger) = ^(NSInteger result) {
            [[NSFileManager defaultManager] removeItemAtPath:@SENKO_BACKUP_EXPORT error:NULL];
            if (result != NSFileHandlingPanelOKButton) return;
            NSError *err = nil;
            if ([data writeToURL:[panel URL] options:NSDataWritingAtomic error:&err]) {
                LRLog(@"backup", @"backup exported");
                [LRToast showSuccess:L(@"Backup saved")];
            } else {
                [LRToast showError:[err localizedDescription]];
            }
        };
        NSWindow *host = LRHostWindow();
        if (host) [panel beginSheetModalForWindow:host completionHandler:save];
        else save([panel runModal]);
    }];
}

- (IBAction)restoreBackup:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowedFileTypes:[NSArray arrayWithObjects:@"lray", @"senko", nil]];
    [panel setMessage:L(@"Choose a LegacyRay backup (.lray)")];
    void (^open)(NSInteger) = ^(NSInteger result) {
        if (result != NSFileHandlingPanelOKButton) return;
        [LRImporter importFileAtPath:[[panel URL] path]];
    };
    NSWindow *host = LRHostWindow();
    if (host) [panel beginSheetModalForWindow:host completionHandler:open];
    else open([panel runModal]);
}

#pragma mark updates

- (void)offerRelease:(LRRelease *)release {
    [LRAlert runTitle:L(@"Update Available")
              message:[NSString stringWithFormat:L(@"Version %@ is available.\nCurrently installed: %@."),
                       release.version, @LR_VERSION]
              buttons:[NSArray arrayWithObjects:L(@"View Release"), L(@"Later"), nil]
            accessory:nil window:nil done:^(NSInteger index) {
        if (index == 0) [LRUpdateChecker openRelease:release];
    }];
}

- (IBAction)checkForUpdates:(id)sender {
    [LRToast show:L(@"Checking for updates...")];
    [LRUpdateChecker checkNow:^(LRRelease *release, NSString *error) {
        if (!release) {
            [LRAlert showTitle:L(@"Update Check Failed") message:error ? error : L(@"Unable to reach GitHub")];
            return;
        }
        if ([release isNewer]) [self offerRelease:release];
        else [LRAlert showTitle:L(@"LegacyRay Is Up to Date")
                        message:[NSString stringWithFormat:L(@"Version %@ is the newest one."), @LR_VERSION]];
    }];
}

#pragma mark rebuilding

- (void)languageChanged {
    [self performSelector:@selector(rebuildInterface) withObject:nil afterDelay:0.2];
}

- (void)rebuildInterface {
    [LRSkin reload];
    LRFlushSkinCaches();
    [self buildMenus];
    NSRect frame = [[_main window] frame];
    BOOL visible = [[_main window] isVisible];
    [[_main window] orderOut:nil];
    [_main autorelease];
    _main = [[LRMainWindowController alloc] initMainWindow];
    [[_main window] setFrame:frame display:NO];
    if (visible) [_main showWindow:nil];
    [_statusMenu rebuild];
    /* every other window closes; preferences come straight back */
    BOOL prefs = [_windows objectForKey:@"prefs"] != nil;
    for (NSString *name in [_windows allKeys]) [[[_windows objectForKey:name] window] close];
    if (prefs) [self openPreferences:nil];
    [[LRTunnel shared] pollNow];
    [[LRCatalog shared] rebuildSections];
    [[NSNotificationCenter defaultCenter] postNotificationName:LRCatalogDidChangeNotification object:nil];
}

#pragma mark LRToastHost

- (NSView *)toastHostView {
    return [_main dashboard];
}

- (CGFloat)toastTopInset {
    return [[_main dashboard] topInset];
}
@end
