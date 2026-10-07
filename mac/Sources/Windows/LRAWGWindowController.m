#import "LRAWGWindowController.h"
#import "LRAppDelegate.h"
#import "LRServerWindowController.h"
#import "LRForm.h"
#import "LRBlocks.h"
#import "LRDraw.h"
#import "LRAlert.h"
#import "LRToast.h"
#import "LRTunnel.h"
#import "LRAWGProfiles.h"
#import "LRImporter.h"
#import "LRActivityLog.h"
#include "senko_paths.h"
#import <spawn.h>
#import <sys/wait.h>

extern char **environ;

/* set or remove one key of [Interface], keeping the rest of the text */
static NSString *LRAWGSetField(NSString *config, NSString *key, NSString *value) {
    NSMutableArray *lines = [NSMutableArray arrayWithArray:[config componentsSeparatedByString:@"\n"]];
    NSString *want = [key lowercaseString];
    BOOL inInterface = NO;
    NSInteger interfaceEnd = -1;
    for (NSUInteger i = 0; i < [lines count]; ++i) {
        NSString *t = LRTrim([lines objectAtIndex:i]);
        if ([t hasPrefix:@"["]) {
            if (inInterface && interfaceEnd < 0) interfaceEnd = (NSInteger)i;
            inInterface = [[t lowercaseString] hasPrefix:@"[interface]"];
            continue;
        }
        NSRange eq = [t rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;
        if (![[LRTrim([t substringToIndex:eq.location]) lowercaseString] isEqualToString:want]) continue;
        if ([value length]) [lines replaceObjectAtIndex:i withObject:[NSString stringWithFormat:@"%@ = %@", key, value]];
        else [lines removeObjectAtIndex:i];
        return [lines componentsJoinedByString:@"\n"];
    }
    if (![value length]) return config;
    if (interfaceEnd < 0) interfaceEnd = (NSInteger)[lines count];
    while (interfaceEnd > 0 && ![LRTrim([lines objectAtIndex:(NSUInteger)interfaceEnd - 1]) length]) --interfaceEnd;
    [lines insertObject:[NSString stringWithFormat:@"%@ = %@", key, value] atIndex:(NSUInteger)interfaceEnd];
    return [lines componentsJoinedByString:@"\n"];
}

@interface LRFlippedView : NSView
@end
@implementation LRFlippedView
- (BOOL)isFlipped { return YES; }
@end

@implementation LRAWGWindowController

- (id)init {
    NSWindow *w = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 540)
                                               styleMask:NSTitledWindowMask | NSClosableWindowMask |
                                                         NSMiniaturizableWindowMask | NSResizableWindowMask
                                                 backing:NSBackingStoreBuffered defer:YES] autorelease];
    [w setTitle:L(@"AmneziaWG Profiles")];
    [w setMinSize:NSMakeSize(700, 480)];
    [w setReleasedWhenClosed:NO];
    if ((self = [super initWithWindow:w])) {
        [self build];
        [w center];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(reload) name:LRAWGProfilesDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(showDetail) name:LRTunnelDidChangeNotification object:nil];
        [self reload];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_list setDataSource:nil];
    [_list setDelegate:nil];
    [_list release];
    [_detailHolder release];
    [_profiles release];
    [_selected release];
    [_check release];
    [super dealloc];
}

- (void)build {
    NSView *content = [[self window] contentView];
    NSRect b = [content bounds];
    _list = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 230, 400)];
    NSTableColumn *col = [[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease];
    [col setWidth:226];
    [col setEditable:NO];
    [_list addTableColumn:col];
    [_list setHeaderView:nil];
    [_list setRowHeight:34];
    [_list setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleSourceList];
    [_list setDataSource:self];
    [_list setDelegate:self];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 23, 230, NSHeight(b) - 23)] autorelease];
    [scroll setDocumentView:_list];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSNoBorder];
    [scroll setAutoresizingMask:NSViewHeightSizable];
    [content addSubview:scroll];
    __block LRAWGWindowController *me = self;
    NSButton *add = [[[NSButton alloc] initWithFrame:NSMakeRect(-1, 0, 32, 23)] autorelease];
    [add setBezelStyle:NSSmallSquareBezelStyle];
    [add setImage:[NSImage imageNamed:NSImageNameAddTemplate]];
    [add lr_setBlock:^(id s) {
        NSMenu *m = [[[NSMenu alloc] initWithTitle:@""] autorelease];
        [m lr_addItem:L(@"Paste from Clipboard") block:^{ [LRImporter pasteFromClipboard]; }];
        [m lr_addItem:L(@"Import File…") block:^{ [LRImporter chooseFile]; }];
        [m lr_addItem:L(@"Enter Links…") block:^{ [LRImporter promptManual]; }];
        [m popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight([s bounds]) + 2) inView:s];
    }];
    NSButton *remove = [[[NSButton alloc] initWithFrame:NSMakeRect(30, 0, 32, 23)] autorelease];
    [remove setBezelStyle:NSSmallSquareBezelStyle];
    [remove setImage:[NSImage imageNamed:NSImageNameRemoveTemplate]];
    [remove lr_setBlock:^(id s) { [me deleteSelected]; }];
    NSButton *fill = [[[NSButton alloc] initWithFrame:NSMakeRect(61, 0, 170, 23)] autorelease];
    [fill setBezelStyle:NSSmallSquareBezelStyle];
    [fill setTitle:@""];
    [fill setEnabled:NO];
    for (NSButton *k in [NSArray arrayWithObjects:fill, add, remove, nil]) {
        [k setAutoresizingMask:NSViewMaxYMargin];
        [content addSubview:k];
    }
    NSBox *line = [[[NSBox alloc] initWithFrame:NSMakeRect(230, 0, 1, NSHeight(b))] autorelease];
    [line setBoxType:NSBoxSeparator];
    [line setAutoresizingMask:NSViewHeightSizable];
    [content addSubview:line];
    NSScrollView *ds = [[[NSScrollView alloc] initWithFrame:NSMakeRect(231, 0, NSWidth(b) - 231, NSHeight(b))] autorelease];
    [ds setHasVerticalScroller:YES];
    [ds setBorderType:NSNoBorder];
    [ds setDrawsBackground:YES];
    [ds setBackgroundColor:[NSColor windowBackgroundColor]];
    [ds setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    _detailHolder = [ds retain];
    [content addSubview:ds];
}

- (void)reload {
    [_profiles release];
    _profiles = [[LRAWGProfiles profiles] copy];
    [_list reloadData];
    NSUInteger at = NSNotFound;
    for (NSUInteger i = 0; i < [_profiles count]; ++i)
        if ([((LRAWGProfile *)[_profiles objectAtIndex:i]).path isEqualToString:_selected.path]) at = i;
    if (at == NSNotFound && [_profiles count]) {
        LRAWGProfile *active = [LRAWGProfiles active];
        at = 0;
        for (NSUInteger i = 0; i < [_profiles count]; ++i)
            if ([((LRAWGProfile *)[_profiles objectAtIndex:i]).path isEqualToString:active.path]) at = i;
    }
    if (at != NSNotFound) {
        [_selected release];
        _selected = [[_profiles objectAtIndex:at] retain];
        [_list selectRowIndexes:[NSIndexSet indexSetWithIndex:at] byExtendingSelection:NO];
    } else {
        [_selected release];
        _selected = nil;
    }
    [self showDetail];
}

- (void)selectProfile:(LRAWGProfile *)profile {
    [_selected release];
    _selected = [profile retain];
    [self reload];
}

- (void)deleteSelected {
    LRAWGProfile *p = _selected;
    if (!p) return;
    [LRAlert runTitle:L(@"Delete Profile") message:p.name
              buttons:[NSArray arrayWithObjects:L(@"Delete"), L(@"Cancel"), nil]
            accessory:nil window:[self window] done:^(NSInteger index) {
        if (index == 0) [LRAWGProfiles deleteProfile:p];
    }];
}

#pragma mark detail

- (BOOL)isLive {
    LRTunnel *t = [LRTunnel shared];
    return t.activeBackend == LRBackendAmneziaWG && [t isOn] &&
           [[[LRAWGProfiles active] path] isEqualToString:_selected.path];
}

- (void)checkHandshake {
    if (_checking || !_selected) return;
    _checking = YES;
    [_check release];
    _check = [L(@"Checking...") retain];
    [self showDetail];
    NSString *path = [[_selected.path copy] autorelease];
    [self retain];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        const char *bin = SENKO_USR_BIN "/legacyrayawgd";
        char *argv[] = { (char *)bin, (char *)"--handshake", (char *)[path fileSystemRepresentation],
                         (char *)"5000", NULL };
        NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
        pid_t pid = 0;
        int status = -1;
        if (posix_spawn(&pid, bin, NULL, NULL, argv, environ) == 0)
            while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
        int ms = (int)(([NSDate timeIntervalSinceReferenceDate] - start) * 1000);
        BOOL ok = pid > 0 && WIFEXITED(status) && WEXITSTATUS(status) == 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            _checking = NO;
            [_check release];
            _check = [(ok ? [NSString stringWithFormat:L(@"Handshake in %d ms"), ms] : L(@"No handshake")) retain];
            if (ok) LRLog(@"amneziawg", @"handshake ok");
            else LRLogFail(@"amneziawg", @"handshake failed");
            [self showDetail];
            [self release];
        });
    });
}

- (void)setField:(NSString *)key value:(NSString *)value {
    LRAWGProfile *p = _selected;
    NSString *config = LRAWGSetField([p config], key, LRTrim(value));
    [LRAWGProfiles updateProfile:p config:config done:^(BOOL ok, NSString *error) {
        if (ok) [LRToast showSuccess:L(@"Saved. Reconnect to apply.")];
        else [LRToast showError:error];
        [self showDetail];
    }];
}

- (void)editConfig {
    LRAWGProfile *p = _selected;
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 460, 280)] autorelease];
    [scroll setBorderType:NSBezelBorder];
    [scroll setHasVerticalScroller:YES];
    NSTextView *tv = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 440, 280)] autorelease];
    [tv setFont:[NSFont userFixedPitchFontOfSize:11]];
    [tv setRichText:NO];
    [tv setAutomaticQuoteSubstitutionEnabled:NO];
    [tv setAutomaticDashSubstitutionEnabled:NO];
    [tv setString:[p config] ? [p config] : @""];
    [scroll setDocumentView:tv];
    [LRAlert runTitle:p.name message:L(@"The whole configuration. It is checked before it is saved.")
              buttons:[NSArray arrayWithObjects:L(@"Save"), L(@"Cancel"), nil]
            accessory:scroll window:[self window] done:^(NSInteger index) {
        if (index != 0) return;
        [LRAWGProfiles updateProfile:p config:[[[tv string] copy] autorelease] done:^(BOOL ok, NSString *error) {
            if (ok) [LRToast showSuccess:L(@"Saved. Reconnect to apply.")];
            else [LRAlert showTitle:L(@"Invalid AmneziaWG profile") message:error];
            [self showDetail];
        }];
    }];
}

- (void)exportConf {
    LRAWGProfile *p = _selected;
    NSString *safe = [[p.name componentsSeparatedByCharactersInSet:
                       [[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@"_"];
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setNameFieldStringValue:[([safe length] ? safe : @"amneziawg") stringByAppendingString:@".conf"]];
    [panel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger result) {
        if (result != NSFileHandlingPanelOKButton) return;
        [[p config] writeToURL:[panel URL] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }];
}

- (void)showDetail {
    LRAWGProfile *p = _selected;
    NSScrollView *ds = (NSScrollView *)_detailHolder;
    CGFloat width = MAX(440.0f, NSWidth([ds frame]) - 16);
    if (!p) {
        LRFlippedView *empty = [[[LRFlippedView alloc] initWithFrame:NSMakeRect(0, 0, width, 300)] autorelease];
        NSTextField *t = LRWrappingLabel(L(@"No profiles yet. Add a .conf with [Interface] and [Peer] (WireGuard or AmneziaWG 1.0, 1.5 and 2.0), or an Amnezia vpn:// key, with the + button."),
                                         [NSFont systemFontOfSize:13], [NSColor disabledControlTextColor], width - 80);
        [t setFrameOrigin:NSMakePoint(40, 60)];
        [empty addSubview:t];
        [ds setDocumentView:empty];
        return;
    }
    __block LRAWGWindowController *me = self;
    NSDictionary *f = [p fields];
    LRTunnel *t = [LRTunnel shared];
    BOOL live = [self isLive];
    BOOL chosen = [[[LRAWGProfiles active] path] isEqualToString:p.path] &&
                  [LRPrefs selectedBackend] == LRBackendAmneziaWG;
    LRFlippedView *doc = [[[LRFlippedView alloc] initWithFrame:NSMakeRect(0, 0, width, 100)] autorelease];
    LRInfoHeader *header = [[[LRInfoHeader alloc] initWithFrame:NSMakeRect(0, 0, width, 72)] autorelease];
    header.title = p.name;
    header.subtitle = [p summary];
    header.icon = LRImageWithSize(NSMakeSize(40, 40), YES, ^(CGContextRef ctx, CGRect r) {
        LRDrawLED(ctx, CGPointMake(20, 20), 13, live ? SKIN->ledGreen : (chosen ? SKIN->ledAmber : SKIN->ledOff), YES);
    });
    [header setAutoresizingMask:NSViewWidthSizable];
    [doc addSubview:header];
    LRForm *form = [[[LRForm alloc] initWithWidth:width labelWidth:200] autorelease];
    NSFont *value = [NSFont systemFontOfSize:13];
    [form addLabel:L(@"Type") view:LRLabel([p isAmnezia] ? @"AmneziaWG" : @"WireGuard", value, nil)];
    if ([f objectForKey:@"endpoint"]) [form addLabel:L(@"Endpoint") view:LRLabel(LRStealth([f objectForKey:@"endpoint"]), value, nil)];
    if ([f objectForKey:@"address"]) [form addLabel:L(@"Address") view:LRLabel(LRStealth([f objectForKey:@"address"]), value, nil)];
    if ([f objectForKey:@"dns"]) [form addLabel:@"DNS" view:LRLabel([f objectForKey:@"dns"], value, nil)];
    NSString *allowed = [f objectForKey:@"allowedips"];
    if (allowed) {
        NSUInteger n = [[allowed componentsSeparatedByString:@","] count];
        BOOL full = [allowed rangeOfString:@"0.0.0.0/0"].location != NSNotFound;
        [form addLabel:L(@"Routes") view:LRLabel(full ? L(@"All traffic")
                                                 : [NSString stringWithFormat:L(@"%lu networks"), (unsigned long)n], value, nil)];
    }
    [form addLabel:L(@"State") view:LRLabel(live ? [t stateTitle] : (_check ? _check : L(@"Not Connected")), value,
                                            live ? SKIN->good : nil)];
    NSView *keys = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, [form controlWidth], 32)] autorelease];
    NSButton *conn = LRPushButton(live ? L(@"Disconnect") : L(@"Connect"), ^(id s) {
        if ([me isLive]) { [[LRTunnel shared] disconnect]; return; }
        [LRAWGProfiles setActive:me->_selected];
        [LRPrefs setSelectedBackend:LRBackendAmneziaWG];
        LRTunnel *tunnel = [LRTunnel shared];
        if ([tunnel isOn]) {
            [tunnel disconnect];
            [tunnel performSelector:@selector(startAWG) withObject:nil afterDelay:1.5];
        } else [tunnel startAWG];
    });
    NSButton *check = LRPushButton(_checking ? L(@"Checking...") : L(@"Check the Handshake"), ^(id s) { [me checkHandshake]; });
    [check setEnabled:!_checking];
    [conn setFrameOrigin:NSMakePoint(-6, 0)];
    [check setFrameOrigin:NSMakePoint(NSMaxX([conn frame]), 0)];
    [keys addSubview:conn];
    [keys addSubview:check];
    [form addView:keys];
    NSView *keys2 = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, [form controlWidth], 32)] autorelease];
    NSArray *more = [NSArray arrayWithObjects:
        LRPushButton(L(@"Share…"), ^(id s) {
            [[LRAppDelegate shared] shareText:[me->_selected config] title:me->_selected.name subtitle:[me->_selected summary]];
        }),
        LRPushButton(L(@"Export…"), ^(id s) { [me exportConf]; }),
        LRPushButton(L(@"Rename…"), ^(id s) {
            [LRAlert promptTitle:L(@"Rename Profile") message:nil placeholder:L(@"Name") text:me->_selected.name
                          button:L(@"Save") done:^(NSString *v) {
                NSString *name = LRTrim(v);
                if (name) [LRAWGProfiles renameProfile:me->_selected to:name];
            }];
        }), nil];
    CGFloat x = -6;
    for (NSButton *k in more) {
        [k setFrameOrigin:NSMakePoint(x, 0)];
        x = NSMaxX([k frame]);
        [keys2 addSubview:k];
    }
    [form addView:keys2];
    if (!chosen)
        [form addCheckBox:L(@"Use this profile for the big button") on:NO changed:^(BOOL on) {
            if (!on) return;
            [LRAWGProfiles setActive:me->_selected];
            [LRPrefs setSelectedBackend:LRBackendAmneziaWG];
            [[NSNotificationCenter defaultCenter] postNotificationName:LRTunnelDidChangeNotification object:nil];
        }];
    [form addSeparator];
    [form addHeader:L(@"Obfuscation")];
    NSArray *names = [NSArray arrayWithObjects:@"Jc", @"Jmin", @"Jmax", @"S1", @"S2", @"S3", @"S4",
                      @"H1", @"H2", @"H3", @"H4", @"PersistentKeepalive", @"MTU", nil];
    for (NSString *k in names) {
        NSString *v = [f objectForKey:[k lowercaseString]];
        if (!v && ([k isEqualToString:@"S3"] || [k isEqualToString:@"S4"])) continue;
        NSString *placeholder = [k isEqualToString:@"MTU"] ? @"1420" : ([k isEqualToString:@"PersistentKeepalive"] ? L(@"Off") : @"—");
        CGFloat w = [k hasPrefix:@"H"] ? 220 : 90;
        NSTextField *field = [form addLabel:k field:v placeholder:placeholder width:w commit:^(NSString *nv) {
            [me setField:k value:nv];
        }];
        [field setFont:[NSFont userFixedPitchFontOfSize:12]];
    }
    NSUInteger signatures = 0;
    for (NSString *k in [NSArray arrayWithObjects:@"i1", @"i2", @"i3", @"i4", @"i5", nil])
        if ([[f objectForKey:k] length]) ++signatures;
    [form addLabel:L(@"Signature packets (I1–I5)")
              view:LRLabel(signatures ? [NSString stringWithFormat:@"%lu", (unsigned long)signatures] : L(@"None"), value, nil)];
    [form addNote:L(@"Change a value and press Return. The values must match the server's; a wrong one stops the handshake. Applies on the next connect.")];
    NSButton *edit = LRPushButton(L(@"Edit the Configuration…"), ^(id s) { [me editConfig]; });
    [edit setFrameOrigin:NSMakePoint(-6, 0)];
    [form addView:edit];
    [form finish];
    [form setFrameOrigin:NSMakePoint(0, 72)];
    [doc addSubview:form];
    [doc setFrameSize:NSMakeSize(width, 72 + NSHeight([form frame]))];
    NSPoint scrolled = [[ds contentView] bounds].origin;
    [ds setDocumentView:doc];
    [[ds contentView] scrollToPoint:scrolled];
}

#pragma mark list

- (NSInteger)numberOfRowsInTableView:(NSTableView *)t {
    return (NSInteger)[_profiles count];
}

- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)row {
    LRAWGProfile *p = [_profiles objectAtIndex:(NSUInteger)row];
    return p.name;
}

- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)c row:(NSInteger)row {
    NSTableCellView *cell = [t makeViewWithIdentifier:@"p" owner:self];
    if (!cell) {
        cell = [[[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 220, 34)] autorelease];
        [cell setIdentifier:@"p"];
        NSTextField *name = LRLabel(@"", [NSFont systemFontOfSize:13], nil);
        [name setFrame:NSMakeRect(10, 15, 200, 17)];
        [name setAutoresizingMask:NSViewWidthSizable];
        NSTextField *sub = LRLabel(@"", [NSFont systemFontOfSize:10.5f], [NSColor disabledControlTextColor]);
        [sub setFrame:NSMakeRect(10, 1, 200, 14)];
        [sub setAutoresizingMask:NSViewWidthSizable];
        [cell addSubview:name];
        [cell addSubview:sub];
        [cell setTextField:name];
        [sub setTag:2];
    }
    LRAWGProfile *p = [_profiles objectAtIndex:(NSUInteger)row];
    [[cell textField] setStringValue:p.name];
    [(NSTextField *)[cell viewWithTag:2] setStringValue:[p summary]];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)n {
    NSInteger row = [_list selectedRow];
    if (row < 0 || row >= (NSInteger)[_profiles count]) return;
    LRAWGProfile *p = [_profiles objectAtIndex:(NSUInteger)row];
    if ([p.path isEqualToString:_selected.path]) return;
    [_selected release];
    _selected = [p retain];
    [_check release];
    _check = nil;
    [self showDetail];
}
@end
