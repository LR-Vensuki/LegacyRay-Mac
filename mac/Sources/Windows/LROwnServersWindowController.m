#import "LROwnServersWindowController.h"
#import "LRAppDelegate.h"
#import "LRServerWindowController.h"
#import "LRForm.h"
#import "LRBlocks.h"
#import "LRDraw.h"
#import "LRAlert.h"
#import "LRToast.h"
#import "LRSSH.h"
#import "LRImporter.h"
#import "LRAWGProfiles.h"
#import "LRActivityLog.h"
#import <SystemConfiguration/SystemConfiguration.h>
#include "b64.h"

/* this mac's name, fit for a client label on the server */
static NSString *LRClientLabel(NSString *preferred) {
    NSString *raw = preferred;
    if (![raw length]) raw = [(NSString *)SCDynamicStoreCopyComputerName(NULL, NULL) autorelease];
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < [raw length] && [out length] < 24; ++i) {
        unichar c = [raw characterAtIndex:i];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
            c == '.' || c == '-' || c == '_')
            [out appendFormat:@"%C", c];
        else if (c == ' ' && [out length] && ![out hasSuffix:@"-"])
            [out appendString:@"-"];
    }
    while ([out hasSuffix:@"-"]) [out deleteCharactersInRange:NSMakeRange([out length] - 1, 1)];
    return [out length] ? out : @"mac";
}

static NSString *LRDecodeB64(NSString *text) {
    NSData *in = [text dataUsingEncoding:NSASCIIStringEncoding];
    size_t cap = b64_decoded_maxlen([in length]) + 1;
    unsigned char *out = malloc(cap);
    size_t n = 0;
    NSString *s = nil;
    if (out && b64_decode([in bytes], [in length], out, cap, &n) == 0)
        s = [[[NSString alloc] initWithBytes:out length:n encoding:NSUTF8StringEncoding] autorelease];
    free(out);
    return s;
}

@interface LRPaneView : NSView
@end
@implementation LRPaneView
- (BOOL)isFlipped { return YES; }
@end

@implementation LROwnServersWindowController

- (id)init {
    NSWindow *w = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 820, 620)
                                               styleMask:NSTitledWindowMask | NSClosableWindowMask |
                                                         NSMiniaturizableWindowMask | NSResizableWindowMask
                                                 backing:NSBackingStoreBuffered defer:YES] autorelease];
    [w setTitle:L(@"Own servers")];
    [w setMinSize:NSMakeSize(720, 540)];
    [w setReleasedWhenClosed:NO];
    if ((self = [super initWithWindow:w])) {
        _info = [[NSMutableDictionary alloc] init];
        _clients = [[NSMutableArray alloc] init];
        _sni = [@"www.microsoft.com" copy];
        _xray = YES;
        [self build];
        [w center];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadList)
                                                     name:LRServerHostsDidChangeNotification object:nil];
        [self reloadList];
        if (![_hosts count]) [self startSetup];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_job cancel];
    [_job release];
    [_list setDataSource:nil];
    [_list setDelegate:nil];
    [_list release];
    [_pane release];
    [_console release];
    [_stage release];
    [_hosts release];
    [_host release];
    [_sni release];
    [_info release];
    [_clients release];
    [super dealloc];
}

- (void)windowWillClose:(NSNotification *)n {
    [_job cancel];
}

#pragma mark layout

- (void)build {
    NSView *content = [[self window] contentView];
    [[self window] setDelegate:(id)self];
    NSRect b = [content bounds];
    _list = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 220, 400)];
    NSTableColumn *col = [[[NSTableColumn alloc] initWithIdentifier:@"h"] autorelease];
    [col setWidth:216];
    [col setEditable:NO];
    [_list addTableColumn:col];
    [_list setHeaderView:nil];
    [_list setRowHeight:34];
    [_list setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleSourceList];
    [_list setDataSource:self];
    [_list setDelegate:self];
    NSScrollView *ls = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 23, 220, NSHeight(b) - 23)] autorelease];
    [ls setDocumentView:_list];
    [ls setHasVerticalScroller:YES];
    [ls setBorderType:NSNoBorder];
    [ls setAutoresizingMask:NSViewHeightSizable];
    [content addSubview:ls];
    __block LROwnServersWindowController *me = self;
    NSButton *add = [[[NSButton alloc] initWithFrame:NSMakeRect(-1, 0, 32, 23)] autorelease];
    [add setBezelStyle:NSSmallSquareBezelStyle];
    [add setImage:[NSImage imageNamed:NSImageNameAddTemplate]];
    [add setToolTip:L(@"Set up a server")];
    [add lr_setBlock:^(id s) { [me startSetup]; }];
    NSButton *fill = [[[NSButton alloc] initWithFrame:NSMakeRect(30, 0, 191, 23)] autorelease];
    [fill setBezelStyle:NSSmallSquareBezelStyle];
    [fill setTitle:@""];
    [fill setEnabled:NO];
    [content addSubview:fill];
    [content addSubview:add];
    NSBox *line = [[[NSBox alloc] initWithFrame:NSMakeRect(220, 0, 1, NSHeight(b))] autorelease];
    [line setBoxType:NSBoxSeparator];
    [line setAutoresizingMask:NSViewHeightSizable];
    [content addSubview:line];

    CGFloat consoleH = 170;
    _pane = [[NSScrollView alloc] initWithFrame:NSMakeRect(221, consoleH + 30, NSWidth(b) - 221, NSHeight(b) - consoleH - 30)];
    [_pane setHasVerticalScroller:YES];
    [_pane setBorderType:NSNoBorder];
    [_pane setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [content addSubview:_pane];
    _stage = [LRLabel(@"", [NSFont boldSystemFontOfSize:11], nil) retain];
    [_stage setFrame:NSMakeRect(236, consoleH + 6, NSWidth(b) - 252, 16)];
    [_stage setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [content addSubview:_stage];
    NSScrollView *cs = [[[NSScrollView alloc] initWithFrame:NSMakeRect(232, 10, NSWidth(b) - 244, consoleH - 8)] autorelease];
    [cs setHasVerticalScroller:YES];
    [cs setBorderType:NSBezelBorder];
    [cs setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    _console = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(b) - 260, consoleH)];
    [_console setEditable:NO];
    [_console setRichText:NO];
    [_console setFont:[NSFont userFixedPitchFontOfSize:10]];
    [_console setAutoresizingMask:NSViewWidthSizable];
    [[_console textContainer] setWidthTracksTextView:YES];
    if (!SKIN->flat) {
        /* the terminal of 10.8, "homebrew" green on black would be a costume */
        [_console setBackgroundColor:[NSColor colorWithCalibratedWhite:0.96f alpha:1]];
    }
    [cs setDocumentView:_console];
    [content addSubview:cs];
}

- (void)setStage:(NSString *)text {
    [_stage setStringValue:text ? text : @""];
}

- (void)appendLine:(NSString *)line {
    NSTextStorage *ts = [_console textStorage];
    [ts appendAttributedString:[[[NSAttributedString alloc] initWithString:[line stringByAppendingString:@"\n"]
        attributes:[NSDictionary dictionaryWithObject:[NSFont userFixedPitchFontOfSize:10] forKey:NSFontAttributeName]] autorelease]];
    if ([ts length] > 60000) [ts deleteCharactersInRange:NSMakeRange(0, [ts length] - 50000)];
    [_console scrollRangeToVisible:NSMakeRange([ts length], 0)];
}

- (void)reloadList {
    [_hosts release];
    _hosts = [[LRServerHosts hosts] copy];
    [_list reloadData];
    if (!_setup && _host) {
        NSUInteger at = NSNotFound;
        for (NSUInteger i = 0; i < [_hosts count]; ++i)
            if ([((LRServerHost *)[_hosts objectAtIndex:i]).ident isEqualToString:_host.ident]) at = i;
        if (at != NSNotFound) [_list selectRowIndexes:[NSIndexSet indexSetWithIndex:at] byExtendingSelection:NO];
    }
}

#pragma mark setup

- (void)startSetup {
    [_job cancel];
    [_host release];
    _host = [[LRServerHost alloc] init];
    _host.port = 22;
    _host.user = @"root";
    _setup = YES;
    [_list deselectAll:nil];
    [self setStage:nil];
    [self showSetup];
}

- (void)showSetup {
    __block LROwnServersWindowController *me = self;
    CGFloat width = MAX(480.0f, NSWidth([_pane frame]) - 16);
    LRPaneView *doc = [[[LRPaneView alloc] initWithFrame:NSMakeRect(0, 0, width, 100)] autorelease];
    LRInfoHeader *header = [[[LRInfoHeader alloc] initWithFrame:NSMakeRect(0, 0, width, 72)] autorelease];
    header.title = L(@"New server");
    header.subtitle = L(@"Xray Reality and AmneziaWG on your own VPS, over SSH");
    header.icon = [NSImage imageNamed:NSImageNameNetwork];
    [doc addSubview:header];
    LRForm *f = [[[LRForm alloc] initWithWidth:width labelWidth:200] autorelease];
    LRServerHost *h = _host;
    [f addLabel:L(@"Server address") field:h.host placeholder:@"203.0.113.10" width:220 commit:^(NSString *v) {
        h.host = LRTrim(v);
    }];
    [f addLabel:L(@"SSH port") field:[NSString stringWithFormat:@"%ld", (long)h.port] placeholder:@"22" width:70
         commit:^(NSString *v) {
        NSInteger p = [v integerValue];
        if (p > 0 && p < 65536) h.port = p;
    }];
    [f addLabel:L(@"User") field:h.user placeholder:@"root" width:140 commit:^(NSString *v) {
        if ([LRTrim(v) length]) h.user = LRTrim(v);
    }];
    BOOL key = h.auth == LRSSHAuthKey;
    _secretField = nil;
    _passphraseField = nil;
    [f addLabel:L(@"Sign in with") popup:[NSArray arrayWithObjects:L(@"Password"), L(@"Private key"), nil]
       selected:key ? 1 : 0 changed:^(NSInteger i) {
        h.auth = i == 1 ? LRSSHAuthKey : LRSSHAuthPassword;
        h.secret = nil;
        [me showSetup];
    }];
    if (key) {
        NSView *row = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, [f controlWidth], 32)] autorelease];
        NSTextField *state = LRLabel([h.secret length] ? L(@"Pasted") : L(@"Not set"), nil, nil);
        [state setFrame:NSMakeRect(0, 8, 90, 17)];
        [row addSubview:state];
        NSButton *paste = LRPushButton(L(@"Paste the Key"), ^(id s) {
            NSString *clip = LRPasteboardString();
            if ([clip rangeOfString:@"PRIVATE KEY"].location == NSNotFound) {
                [LRToast showError:L(@"Copy the private key (-----BEGIN ... PRIVATE KEY-----) first")];
                return;
            }
            h.secret = clip;
            [LRToast showSuccess:L(@"Key taken from the clipboard")];
            [me showSetup];
        });
        NSButton *file = LRPushButton(L(@"Choose a File…"), ^(id s) {
            NSOpenPanel *panel = [NSOpenPanel openPanel];
            [panel setShowsHiddenFiles:YES];
            [panel setDirectoryURL:[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@".ssh"]]];
            [panel beginSheetModalForWindow:[me window] completionHandler:^(NSInteger result) {
                if (result != NSFileHandlingPanelOKButton) return;
                NSString *text = [NSString stringWithContentsOfURL:[panel URL] encoding:NSUTF8StringEncoding error:NULL];
                if ([text rangeOfString:@"PRIVATE KEY"].location == NSNotFound) {
                    [LRToast showError:L(@"That file is not a private key")];
                    return;
                }
                h.secret = text;
                [me showSetup];
            }];
        });
        [paste setFrameOrigin:NSMakePoint(84, 0)];
        [file setFrameOrigin:NSMakePoint(NSMaxX([paste frame]), 0)];
        [row addSubview:paste];
        [row addSubview:file];
        [f addLabel:L(@"Private key") view:row];
        NSSecureTextField *pp = [[[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 22)] autorelease];
        [[pp cell] setPlaceholderString:L(@"None")];
        if (h.passphrase) [pp setStringValue:h.passphrase];
        _passphraseField = pp;
        [f addLabel:L(@"Key passphrase") view:pp];
    } else {
        NSSecureTextField *pw = [[[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 220, 22)] autorelease];
        if (h.secret) [pw setStringValue:h.secret];
        [[pw cell] setPlaceholderString:L(@"Password")];
        _secretField = pw;
        [f addLabel:L(@"Password") view:pw];
    }
    [f addNote:L(@"The sign-in stays on this Mac, in a file only your account can read, so the server can be managed later.")];
    [f addSeparator];
    [f addCheckBox:@"Xray Reality" on:_xray changed:^(BOOL on) { me->_xray = on; }];
    [f addCheckBox:@"AmneziaWG" on:_awg changed:^(BOOL on) { me->_awg = on; }];
    NSArray *snis = [NSArray arrayWithObjects:@"www.microsoft.com", @"www.apple.com", @"dl.google.com",
                     @"www.samsung.com", @"www.nvidia.com", nil];
    NSUInteger si = [snis indexOfObject:_sni];
    [f addLabel:L(@"Reality disguise site") popup:snis selected:si == NSNotFound ? 0 : (NSInteger)si changed:^(NSInteger i) {
        [me->_sni release];
        me->_sni = [[snis objectAtIndex:(NSUInteger)i] copy];
    }];
    [f addNote:L(@"Xray Reality works on any Linux with systemd. AmneziaWG needs Ubuntu and a VPS that allows kernel modules (KVM, not OpenVZ/LXC). The install takes a few minutes; the server needs internet access to download packages.")];
    NSButton *go = LRPushButton(_working ? L(@"Working...") : L(@"Connect and Install"), ^(id s) { [me startInstall]; });
    [go setEnabled:!_working];
    [go setKeyEquivalent:@"\r"];
    [go setFrameOrigin:NSMakePoint(-6, 0)];
    [f addView:go];
    [f finish];
    [f setFrameOrigin:NSMakePoint(0, 72)];
    [doc addSubview:f];
    [doc setFrameSize:NSMakeSize(width, 72 + NSHeight([f frame]))];
    [_pane setDocumentView:doc];
}

- (void)startInstall {
    [[self window] makeFirstResponder:nil];
    if (_working) return;
    if (_secretField && _host.auth == LRSSHAuthPassword) _host.secret = [_secretField stringValue];
    if (_passphraseField) _host.passphrase = LRTrim([_passphraseField stringValue]);
    if (![_host.host length]) { [LRToast showError:L(@"Enter the server address")]; return; }
    if (![_host.secret length]) {
        [LRToast showError:_host.auth == LRSSHAuthKey ? L(@"Paste the private key") : L(@"Enter the password")];
        return;
    }
    if (!_xray && !_awg) { [LRToast showError:L(@"Choose what to install")]; return; }
    _working = YES;
    [self showSetup];
    [self setStage:L(@"Connecting...")];
    [self appendLine:[NSString stringWithFormat:@"== ssh %@@%@:%ld", _host.user, LRStealth(_host.host), (long)_host.port]];
    [self retain];
    [LRSSHJob probeKeyOf:_host done:^(NSString *type, NSString *hash, NSString *error) {
        if (!hash) {
            _working = NO;
            [self showSetup];
            [self setStage:error];
            [self appendLine:[@"✗ " stringByAppendingString:error ? error : @"ssh"]];
            [self release];
            return;
        }
        NSString *msg = [NSString stringWithFormat:L(@"%@ answered with the key\n%@\n%@\nIf your provider shows the server's key, compare them."),
                         _host.host, type, LRSSHFingerprint(hash)];
        [LRAlert runTitle:L(@"Is this your server?") message:msg
                  buttons:[NSArray arrayWithObjects:L(@"Trust and continue"), L(@"Cancel"), nil]
                accessory:nil window:[self window] done:^(NSInteger index) {
            if (index != 0) {
                _working = NO;
                [self showSetup];
                [self setStage:nil];
                [self release];
                return;
            }
            _host.hostKey = hash;
            _host.hostKeyType = type;
            [LRServerHosts save:_host];
            [self install];
            [self release];
        }];
    }];
}

- (void)install {
    NSMutableArray *commands = [NSMutableArray array];
    if (_xray) [commands addObject:@"install-xray"];
    if (_awg) [commands addObject:@"install-awg"];
    NSDictionary *vars = [NSDictionary dictionaryWithObjectsAndKeys:LRClientLabel(nil), @"LR_NAME", _sni, @"LR_SNI", nil];
    [self runCommands:commands at:0 vars:vars links:[NSMutableArray array] confs:[NSMutableArray array]
               errors:[NSMutableArray array]];
}

- (void)runCommands:(NSArray *)commands at:(NSUInteger)i vars:(NSDictionary *)vars links:(NSMutableArray *)links
              confs:(NSMutableArray *)confs errors:(NSMutableArray *)errors {
    if (i >= [commands count]) {
        [self finishWithLinks:links confs:confs errors:errors];
        return;
    }
    NSString *cmd = [commands objectAtIndex:i];
    [self setStage:[cmd isEqualToString:@"install-xray"] ? L(@"Installing Xray Reality...") : L(@"Installing AmneziaWG...")];
    [self appendLine:[NSString stringWithFormat:@"== %@", cmd]];
    [self retain];
    LRServerHost *host = _host;
    [_job release];
    _job = [[LRSSHJob run:cmd vars:vars on:host line:^(NSString *kind, NSString *text) {
        if ([kind isEqualToString:@"STEP"]) { [self setStage:text]; [self appendLine:[@"• " stringByAppendingString:text]]; }
        else if ([kind isEqualToString:@"LINK"]) { [links addObject:text]; [self appendLine:L(@"• a connection is ready")]; }
        else if ([kind isEqualToString:@"CONF"]) {
            NSString *conf = LRDecodeB64(text);
            if (conf) [confs addObject:conf];
            [self appendLine:L(@"• a connection is ready")];
        }
        else if ([kind isEqualToString:@"ERROR"]) [self appendLine:[@"✗ " stringByAppendingString:text]];
        else if ([kind isEqualToString:@"INFO"]) [self appendLine:[@"  " stringByAppendingString:text]];
        else if ([kind isEqualToString:@"STAGE"]) [self appendLine:[@"  ssh: " stringByAppendingString:text]];
        else if (![kind isEqualToString:@"DONE"]) [self appendLine:text];
    } done:^(BOOL ok, NSString *error) {
        if (ok) {
            if ([cmd isEqualToString:@"install-xray"]) host.hasXray = YES;
            else host.hasAWG = YES;
            [LRServerHosts save:host];
        } else {
            [errors addObject:error ? error : cmd];
            [self appendLine:[@"✗ " stringByAppendingString:error ? error : cmd]];
        }
        [self runCommands:commands at:i + 1 vars:vars links:links confs:confs errors:errors];
        [self release];
    }] retain];
}

- (void)finishWithLinks:(NSArray *)links confs:(NSArray *)confs errors:(NSArray *)errors {
    _working = NO;
    NSString *serverName = [_host displayName];
    for (NSString *link in links) [LRImporter importText:link];
    for (NSString *conf in confs)
        [LRAWGProfiles addConfig:conf name:[NSString stringWithFormat:@"%@ · AWG", serverName]
                            done:^(LRAWGProfile *p, NSString *error) { if (!p) [LRToast showError:error]; }];
    NSUInteger made = [links count] + [confs count];
    if (made) {
        LRLog(@"server", @"own server set up with %lu connection(s)", (unsigned long)made);
        [self setStage:[errors count] ? L(@"Partly done: see the log") : L(@"Done. The connections are in the server list.")];
        [LRToast showSuccess:L(@"Your server is ready")];
        _setup = NO;
        [self reloadList];
        [self showHost];
        [self refresh];
    } else {
        [self setStage:L(@"The install failed: see the log")];
        [LRToast showError:[errors count] ? [errors objectAtIndex:0] : L(@"The install failed")];
        [self showSetup];
    }
}

#pragma mark one server

- (void)refresh {
    if (!_host || _setup) return;
    [_info removeAllObjects];
    [_clients removeAllObjects];
    [self setStage:L(@"Asking the server...")];
    [self showHost];
    [_job cancel];
    [_job release];
    [self retain];
    _job = [[LRSSHJob run:@"status" vars:nil on:_host line:^(NSString *kind, NSString *text) {
        NSRange sp = [text rangeOfString:@" "];
        if ([kind isEqualToString:@"INFO"] && sp.location != NSNotFound)
            [_info setObject:[text substringFromIndex:sp.location + 1] forKey:[text substringToIndex:sp.location]];
        else if ([kind isEqualToString:@"CLIENT"] && sp.location != NSNotFound)
            [_clients addObject:[NSArray arrayWithObjects:[text substringToIndex:sp.location],
                                 [text substringFromIndex:sp.location + 1], nil]];
        else if ([kind isEqualToString:@"ERROR"]) [self appendLine:[@"✗ " stringByAppendingString:text]];
    } done:^(BOOL ok, NSString *error) {
        [self setStage:ok ? nil : error];
        if (!ok) [self appendLine:[@"✗ " stringByAppendingString:error ? error : @"status"]];
        [self showHost];
        [self release];
    }] retain];
}

- (void)run:(NSString *)cmd vars:(NSDictionary *)vars title:(NSString *)title {
    [self setStage:title];
    [self appendLine:[NSString stringWithFormat:@"== %@", cmd]];
    NSMutableArray *links = [NSMutableArray array];
    NSMutableArray *confs = [NSMutableArray array];
    NSString *clientName = [vars objectForKey:@"LR_NAME"];
    [self retain];
    [LRSSHJob run:cmd vars:vars on:_host line:^(NSString *kind, NSString *text) {
        if ([kind isEqualToString:@"LINK"]) [links addObject:text];
        else if ([kind isEqualToString:@"CONF"]) { NSString *c = LRDecodeB64(text); if (c) [confs addObject:c]; }
        else if ([kind isEqualToString:@"STEP"]) { [self setStage:text]; [self appendLine:[@"• " stringByAppendingString:text]]; }
        else if ([kind isEqualToString:@"ERROR"]) [self appendLine:[@"✗ " stringByAppendingString:text]];
        else if (![kind isEqualToString:@"DONE"] && ![kind isEqualToString:@"INFO"]) [self appendLine:text];
    } done:^(BOOL ok, NSString *error) {
        [self setStage:ok ? nil : error];
        if (!ok) [LRToast showError:error];
        NSString *payload = [links count] ? [links objectAtIndex:0] : ([confs count] ? [confs objectAtIndex:0] : nil);
        if (ok && payload)
            [[LRAppDelegate shared] shareText:payload title:clientName ? clientName : [_host displayName]
                                     subtitle:[links count] ? @"Xray Reality" : @"AmneziaWG"];
        if (ok) [self refresh];
        [self release];
    }];
}

- (void)addClient {
    __block LROwnServersWindowController *me = self;
    void (^ask)(NSString *) = ^(NSString *proto) {
        [LRAlert promptTitle:L(@"New client") message:L(@"A name for the person or device (letters, digits, dots, dashes)")
                 placeholder:@"friend" text:nil button:L(@"Create") done:^(NSString *value) {
            NSString *name = LRClientLabel(value);
            [me run:@"add-client" vars:[NSDictionary dictionaryWithObjectsAndKeys:proto, @"LR_PROTO", name, @"LR_NAME", nil]
              title:L(@"Creating the client...")];
        }];
    };
    if (_host.hasXray && _host.hasAWG) {
        [LRAlert runTitle:L(@"New client") message:nil
                  buttons:[NSArray arrayWithObjects:@"Xray Reality", @"AmneziaWG", L(@"Cancel"), nil]
                accessory:nil window:[self window] done:^(NSInteger index) {
            if (index == 0) ask(@"xray");
            else if (index == 1) ask(@"awg");
        }];
    } else {
        ask(_host.hasAWG ? @"awg" : @"xray");
    }
}

- (void)showHost {
    __block LROwnServersWindowController *me = self;
    LRServerHost *h = _host;
    if (!h) return;
    CGFloat width = MAX(480.0f, NSWidth([_pane frame]) - 16);
    LRPaneView *doc = [[[LRPaneView alloc] initWithFrame:NSMakeRect(0, 0, width, 100)] autorelease];
    LRInfoHeader *header = [[[LRInfoHeader alloc] initWithFrame:NSMakeRect(0, 0, width, 72)] autorelease];
    header.title = [h displayName];
    NSMutableArray *what = [NSMutableArray array];
    if (h.hasXray) [what addObject:@"Xray Reality"];
    if (h.hasAWG) [what addObject:@"AmneziaWG"];
    header.subtitle = [what count] ? [what componentsJoinedByString:@" · "] : L(@"Nothing installed yet");
    header.icon = [NSImage imageNamed:NSImageNameNetwork];
    [doc addSubview:header];
    LRForm *f = [[[LRForm alloc] initWithWidth:width labelWidth:200] autorelease];
    NSFont *value = [NSFont systemFontOfSize:13];
    [f addLabel:L(@"Address") view:LRLabel(LRStealth([NSString stringWithFormat:@"%@:%ld", h.host, (long)h.port]), value, nil)];
    for (NSString *svc in [NSArray arrayWithObjects:@"xray", @"awg", nil]) {
        NSString *st = [_info objectForKey:svc];
        if (!st) continue;
        NSString *port = [_info objectForKey:[svc stringByAppendingString:@"-port"]];
        [f addLabel:[svc isEqualToString:@"xray"] ? @"Xray Reality" : @"AmneziaWG"
               view:LRLabel([NSString stringWithFormat:@"%@%@", st, port ? [@" · " stringByAppendingString:port] : @""],
                            value, [st isEqualToString:@"active"] ? SKIN->good : SKIN->bad)];
    }
    if ([_info objectForKey:@"uptime"]) [f addLabel:L(@"Uptime") view:LRLabel([_info objectForKey:@"uptime"], value, nil)];
    if ([_info objectForKey:@"load"]) [f addLabel:L(@"Load") view:LRLabel([_info objectForKey:@"load"], value, nil)];
    if (h.hostKey) [f addLabel:L(@"Host key") view:LRLabel(LRSSHFingerprint(h.hostKey), [NSFont userFixedPitchFontOfSize:10], nil)];
    [f addSeparator];
    [f addHeader:L(@"Clients")];
    for (NSArray *c in _clients) {
        NSArray *client = c;
        NSString *proto = [client objectAtIndex:0], *name = [client objectAtIndex:1];
        NSView *row = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, [f controlWidth], 26)] autorelease];
        NSTextField *l = LRLabel([proto isEqualToString:@"xray"] ? @"Reality" : @"AWG", value, [NSColor disabledControlTextColor]);
        [l setFrame:NSMakeRect(0, 5, 70, 17)];
        [row addSubview:l];
        CGFloat x = [f controlWidth];
        NSButton *revoke = [[[NSButton alloc] initWithFrame:NSMakeRect(x - 100, 0, 100, 24)] autorelease];
        [revoke setBezelStyle:NSRoundedBezelStyle];
        [[revoke cell] setControlSize:NSSmallControlSize];
        [revoke setFont:[NSFont systemFontOfSize:11]];
        [revoke setTitle:L(@"Revoke…")];
        [revoke lr_setBlock:^(id s) {
            [LRAlert runTitle:L(@"Revoke access") message:name
                      buttons:[NSArray arrayWithObjects:L(@"Revoke"), L(@"Cancel"), nil]
                    accessory:nil window:[me window] done:^(NSInteger index) {
                if (index == 0)
                    [me run:@"remove-client" vars:[NSDictionary dictionaryWithObjectsAndKeys:proto, @"LR_PROTO", name, @"LR_NAME", nil]
                      title:L(@"Revoking...")];
            }];
        }];
        [row addSubview:revoke];
        if ([proto isEqualToString:@"xray"]) {
            NSButton *share = [[[NSButton alloc] initWithFrame:NSMakeRect(x - 196, 0, 96, 24)] autorelease];
            [share setBezelStyle:NSRoundedBezelStyle];
            [[share cell] setControlSize:NSSmallControlSize];
            [share setFont:[NSFont systemFontOfSize:11]];
            [share setTitle:L(@"Share…")];
            [share lr_setBlock:^(id s) {
                [me run:@"share-client" vars:[NSDictionary dictionaryWithObjectsAndKeys:@"xray", @"LR_PROTO", name, @"LR_NAME", nil]
                  title:L(@"Asking the server...")];
            }];
            [row addSubview:share];
        }
        [f addLabel:name view:row];
    }
    if (![_clients count]) [f addNote:L(@"No clients reported yet.")];
    if (h.hasXray || h.hasAWG) {
        NSButton *add = LRPushButton(L(@"Add a Client…"), ^(id s) { [me addClient]; });
        [add setFrameOrigin:NSMakePoint(-6, 0)];
        [f addView:add];
    }
    [f addNote:L(@"Each client gets its own key: give one to each person or device, and revoke it without touching the others.")];
    [f addSeparator];
    NSMutableArray *keys = [NSMutableArray array];
    [keys addObject:LRPushButton(L(@"Refresh"), ^(id s) { [me refresh]; })];
    if (!h.hasXray) [keys addObject:LRPushButton(L(@"Install Xray"), ^(id s) {
        [me run:@"install-xray" vars:[NSDictionary dictionaryWithObjectsAndKeys:LRClientLabel(nil), @"LR_NAME", me->_sni, @"LR_SNI", nil]
          title:L(@"Installing Xray Reality...")];
        h.hasXray = YES;
        [LRServerHosts save:h];
    })];
    if (!h.hasAWG) [keys addObject:LRPushButton(L(@"Install AmneziaWG"), ^(id s) {
        [me run:@"install-awg" vars:[NSDictionary dictionaryWithObjectsAndKeys:LRClientLabel(nil), @"LR_NAME", nil]
          title:L(@"Installing AmneziaWG...")];
        h.hasAWG = YES;
        [LRServerHosts save:h];
    })];
    [keys addObject:LRPushButton(L(@"Restart Services"), ^(id s) { [me run:@"restart" vars:nil title:L(@"Restarting...")]; })];
    NSView *kv = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, width - 40, 32)] autorelease];
    CGFloat x = -6;
    for (NSButton *k in keys) {
        [k setFrameOrigin:NSMakePoint(x, 0)];
        x = NSMaxX([k frame]);
        [kv addSubview:k];
    }
    [f addWideView:kv height:32];
    NSView *kv2 = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, width - 40, 32)] autorelease];
    NSButton *uninstall = LRPushButton(L(@"Remove from the Server…"), ^(id s) {
        [LRAlert runTitle:L(@"Remove from the server")
                  message:L(@"Xray and AmneziaWG are stopped and their configuration is deleted. Every client loses access.")
                  buttons:[NSArray arrayWithObjects:L(@"Remove"), L(@"Cancel"), nil]
                accessory:nil window:[me window] done:^(NSInteger index) {
            if (index != 0) return;
            [me run:@"uninstall" vars:nil title:L(@"Removing...")];
            h.hasXray = NO;
            h.hasAWG = NO;
            [LRServerHosts save:h];
        }];
    });
    NSButton *forget = LRPushButton(L(@"Forget This Server…"), ^(id s) {
        [LRAlert runTitle:L(@"Forget this server")
                  message:L(@"Only the saved sign-in is deleted from this Mac. The server keeps running.")
                  buttons:[NSArray arrayWithObjects:L(@"Forget"), L(@"Cancel"), nil]
                accessory:nil window:[me window] done:^(NSInteger index) {
            if (index != 0) return;
            [LRServerHosts remove:h];
            [me->_host release];
            me->_host = nil;
            [me reloadList];
            [me startSetup];
        }];
    });
    [uninstall setFrameOrigin:NSMakePoint(-6, 0)];
    [forget setFrameOrigin:NSMakePoint(NSMaxX([uninstall frame]), 0)];
    [kv2 addSubview:uninstall];
    [kv2 addSubview:forget];
    [f addWideView:kv2 height:32];
    [f finish];
    [f setFrameOrigin:NSMakePoint(0, 72)];
    [doc addSubview:f];
    [doc setFrameSize:NSMakeSize(width, 72 + NSHeight([f frame]))];
    [_pane setDocumentView:doc];
}

#pragma mark list

- (NSInteger)numberOfRowsInTableView:(NSTableView *)t {
    return (NSInteger)[_hosts count];
}

- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)c row:(NSInteger)row {
    NSTableCellView *cell = [t makeViewWithIdentifier:@"h" owner:self];
    if (!cell) {
        cell = [[[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 210, 34)] autorelease];
        [cell setIdentifier:@"h"];
        NSTextField *name = LRLabel(@"", [NSFont systemFontOfSize:13], nil);
        [name setFrame:NSMakeRect(10, 15, 196, 17)];
        [name setAutoresizingMask:NSViewWidthSizable];
        NSTextField *sub = LRLabel(@"", [NSFont systemFontOfSize:10.5f], [NSColor disabledControlTextColor]);
        [sub setFrame:NSMakeRect(10, 1, 196, 14)];
        [sub setAutoresizingMask:NSViewWidthSizable];
        [sub setTag:2];
        [cell addSubview:name];
        [cell addSubview:sub];
        [cell setTextField:name];
    }
    LRServerHost *h = [_hosts objectAtIndex:(NSUInteger)row];
    [[cell textField] setStringValue:[h displayName]];
    NSMutableArray *what = [NSMutableArray array];
    if (h.hasXray) [what addObject:@"Xray Reality"];
    if (h.hasAWG) [what addObject:@"AmneziaWG"];
    [(NSTextField *)[cell viewWithTag:2] setStringValue:[what count] ? [what componentsJoinedByString:@" · "] : LRStealth(h.host)];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)n {
    NSInteger row = [_list selectedRow];
    if (row < 0 || row >= (NSInteger)[_hosts count]) return;
    LRServerHost *h = [_hosts objectAtIndex:(NSUInteger)row];
    if (!_setup && [h.ident isEqualToString:_host.ident]) return;
    if (_working) return;
    [_host release];
    _host = [h retain];
    _setup = NO;
    [self refresh];
}
@end
