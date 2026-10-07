#import "LRSidebar.h"
#import "LRBlocks.h"
#import "LRDraw.h"
#import "LRCatalog.h"
#import "LRModels.h"
#import "LRTunnel.h"
#import "LRAWGProfiles.h"
#import "LRDaemonClient.h"
#import "LRActivityLog.h"
#import "LRAlert.h"
#import "LRToast.h"

/* one row of the list */
@interface LRSidebarRow : NSObject {
@public
    NSString *kind;           /* header, info, server, awg */
    LRSection *section;       /* nil for the amneziawg group */
    LRServer *server;
    LRAWGProfile *profile;
    BOOL first;
}
@end

@implementation LRSidebarRow
- (void)dealloc {
    [kind release];
    [section release];
    [server release];
    [profile release];
    [super dealloc];
}
@end

static LRSidebarRow *LRRow(NSString *kind, LRSection *section) {
    LRSidebarRow *r = [[[LRSidebarRow alloc] init] autorelease];
    r->kind = [kind retain];
    r->section = [section retain];
    return r;
}

#pragma mark cells

/* a row of the source list draws itself: the system cell views would need
   a nib for the two lines, the flag and the badge */
@interface LRSidebarCell : NSTableCellView {
@public
    LRSidebarRow *row;
    NSString *title, *meta, *detail, *country, *badge;
    NSColor *badgeColor;
    BOOL live, collapsed, hover, badgeText;
}
@end

@implementation LRSidebarCell

- (void)dealloc {
    [row release];
    [title release];
    [meta release];
    [detail release];
    [country release];
    [badge release];
    [badgeColor release];
    [super dealloc];
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setBackgroundStyle:(NSBackgroundStyle)style {
    [super setBackgroundStyle:style];
    [self setNeedsDisplay:YES];
}

- (BOOL)selectedLook {
    return [self backgroundStyle] == NSBackgroundStyleDark;
}

- (void)drawHeader:(CGContextRef)ctx {
    LRSkin *s = SKIN;
    NSRect b = [self bounds];
    NSFont *font = s->flat ? [LRSkin labelFont:11] : [NSFont boldSystemFontOfSize:11];
    NSString *t = s->flat ? title : [title uppercaseString];
    CGFloat y = NSMaxY(b) - 19;
    CGFloat right = NSWidth(b) - 10;
    /* the count, and the triangle that folds the group */
    LRDrawChevron(ctx, CGPointMake(right - 4, y + 8), 3.5f, !collapsed,
                  LRColorAlpha(s->listHeader, 0.85f), 1.6f);
    right -= 14;
    NSFont *metaFont = [NSFont systemFontOfSize:11];
    CGFloat metaW = [meta length] ? MIN(LRTextSize(meta, metaFont).width, NSWidth(b) * 0.45f) : 0;
    if (metaW > 0) {
        NSRect mr = NSMakeRect(right - metaW, y + 1, metaW, 15);
        LRDrawEngraved(meta, mr, metaFont, NSRightTextAlignment, s->listHeader, s->listHeaderShadow, 1);
        right -= metaW + 8;
    }
    CGFloat x = 10;
    if ([country length] == 2) {
        LRDrawFlag(ctx, country, CGRectMake(x, y + 1, 14, 14));
        x += 19;
    }
    LRDrawEngraved(t, NSMakeRect(x, y, right - x, 16), font, NSLeftTextAlignment,
                   s->listHeader, s->listHeaderShadow, 1);
}

- (void)drawInfo {
    LRSkin *s = SKIN;
    NSRect b = [self bounds];
    NSFont *f = [NSFont systemFontOfSize:11];
    CGFloat y = 1;
    if ([title length]) {
        LRDrawText(title, NSMakeRect(12, y, NSWidth(b) - 22, 15), f, s->listMuted, NSLeftTextAlignment);
        y += 15;
    }
    if ([detail length]) {
        NSRect r = NSMakeRect(12, y, NSWidth(b) - 22, NSHeight(b) - y - 2);
        NSMutableParagraphStyle *p = [[[NSMutableParagraphStyle alloc] init] autorelease];
        [p setLineBreakMode:NSLineBreakByWordWrapping];
        [detail drawWithRect:r options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
                  attributes:[NSDictionary dictionaryWithObjectsAndKeys:f, NSFontAttributeName,
                              LRColorAlpha(s->listMuted, 0.85f), NSForegroundColorAttributeName,
                              p, NSParagraphStyleAttributeName, nil]];
    }
}

- (void)drawServer:(CGContextRef)ctx {
    LRSkin *s = SKIN;
    NSRect b = [self bounds];
    BOOL white = [self selectedLook];
    CGFloat midY = NSMidY(b);
    CGFloat x = 8;
    /* the lamp of the server the tunnel is on */
    if (live) LRDrawLED(ctx, CGPointMake(x + 3, midY), 3.5f, s->ledGreen, YES);
    x += 12;
    if ([country length] == 2) {
        LRDrawFlag(ctx, country, CGRectMake(x, round(midY - 9), 18, 18));
    } else {
        /* a plain disc with the protocol's first letter */
        CGRect disc = CGRectMake(x, round(midY - 9), 18, 18);
        CGContextSetRGBFillColor(ctx, 0, 0, 0, white ? 0.25f : 0.12f);
        CGContextFillEllipseInRect(ctx, disc);
        NSString *letter = [[detail length] ? [detail substringToIndex:1] : @"•" uppercaseString];
        LRDrawText(letter, NSMakeRect(disc.origin.x, disc.origin.y + 2, 18, 14), [NSFont boldSystemFontOfSize:9],
                   white ? [NSColor whiteColor] : s->listMuted, NSCenterTextAlignment);
    }
    x += 26;
    CGFloat right = NSWidth(b) - 8;
    if ([badge length] && badgeText) {
        NSFont *bf = [NSFont systemFontOfSize:10.5f];
        CGFloat bw = MIN(LRTextSize(badge, bf).width, 90);
        LRDrawText(badge, NSMakeRect(right - bw, midY - 7, bw, 14), bf, white ? [NSColor whiteColor] : badgeColor,
                   NSRightTextAlignment);
        right -= bw + 6;
    } else if ([badge length]) {
        NSFont *bf = [NSFont boldSystemFontOfSize:10];
        CGFloat bw = MAX(22.0f, LRTextSize(badge, bf).width + 12);
        CGRect pill = CGRectMake(right - bw, round(midY - 8), bw, 16);
        NSColor *fill = white ? [NSColor whiteColor] : badgeColor;
        LRDrawPill(ctx, pill, fill);
        LRDrawText(badge, NSMakeRect(pill.origin.x, pill.origin.y + 1.5f, bw, 14), bf,
                   white ? (badgeColor ? badgeColor : s->tint) : [NSColor whiteColor], NSCenterTextAlignment);
        right -= bw + 6;
    }
    NSFont *nameFont = [NSFont systemFontOfSize:13];
    NSFont *detailFont = [NSFont systemFontOfSize:10.5f];
    NSColor *ink = white ? [NSColor whiteColor] : s->listInk;
    NSColor *muted = white ? [NSColor colorWithCalibratedWhite:1 alpha:0.8f] : s->listMuted;
    if ([detail length]) {
        if (white && !s->flat)
            LRDrawText(title, NSMakeRect(x, midY - 16, right - x, 17), [NSFont boldSystemFontOfSize:13],
                       [NSColor colorWithCalibratedWhite:0 alpha:0.25f], NSLeftTextAlignment);
        LRDrawText(title, NSMakeRect(x, midY - 17, right - x, 17),
                   white && !s->flat ? [NSFont boldSystemFontOfSize:13] : nameFont, ink, NSLeftTextAlignment);
        LRDrawText(detail, NSMakeRect(x, midY + 1, right - x, 14), detailFont, muted, NSLeftTextAlignment);
    } else {
        LRDrawText(title, NSMakeRect(x, midY - 9, right - x, 17), nameFont, ink, NSLeftTextAlignment);
    }
}

- (void)drawRect:(NSRect)dirty {
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    NSString *k = row ? row->kind : nil;
    if ([k isEqualToString:@"header"]) [self drawHeader:ctx];
    else if ([k isEqualToString:@"info"]) [self drawInfo];
    else [self drawServer:ctx];
}
@end

#pragma mark the table

@implementation LRSidebarTable
- (void)keyDown:(NSEvent *)event {
    NSString *chars = [event charactersIgnoringModifiers];
    unichar c = [chars length] ? [chars characterAtIndex:0] : 0;
    id d = [self delegate];
    if ((c == NSCarriageReturnCharacter || c == NSEnterCharacter) && [d respondsToSelector:@selector(activateRow:)]) {
        [d performSelector:@selector(activateRow:) withObject:[NSNumber numberWithInteger:[self selectedRow]]];
        return;
    }
    if ((c == NSDeleteCharacter || c == NSDeleteFunctionKey) && [d respondsToSelector:@selector(deleteRow:)]) {
        [d performSelector:@selector(deleteRow:) withObject:[NSNumber numberWithInteger:[self selectedRow]]];
        return;
    }
    [super keyDown:event];
}

/* the context menu belongs to the row under the mouse, selected or not */
- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSInteger r = [self rowAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
    id d = [self delegate];
    if (r < 0 || ![d respondsToSelector:@selector(menuForRow:)]) return nil;
    return [d performSelector:@selector(menuForRow:) withObject:[NSNumber numberWithInteger:r]];
}
@end

#pragma mark the controller

@implementation LRSidebar
@synthesize view = _view, table = _table;

- (id)initWithOwner:(id<LRSidebarOwner>)owner {
    if ((self = [super init])) {
        _owner = owner;
        _rows = [[NSMutableArray alloc] init];
        [self buildView];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(rebuild) name:LRCatalogDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(refreshRows) name:LRCatalogPingNotification object:nil];
        [nc addObserver:self selector:@selector(refreshRows) name:LRTunnelDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(rebuild) name:LRAWGProfilesDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(rebuild) name:LRPrefsDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_table setDelegate:nil];
    [_table setDataSource:nil];
    [_view release];
    [_scroll release];
    [_table release];
    [_bottomBar release];
    [_empty release];
    [_emptyTitle release];
    [_emptyText release];
    [_emptyPrimary release];
    [_emptySecondary release];
    [_removeButton release];
    [_actionButton release];
    [_rows release];
    [super dealloc];
}

- (NSButton *)barButton:(NSString *)imageName frame:(NSRect)frame {
    NSButton *b = [[[NSButton alloc] initWithFrame:frame] autorelease];
    [b setBezelStyle:NSSmallSquareBezelStyle];
    [b setButtonType:NSMomentaryPushInButton];
    [b setImage:[NSImage imageNamed:imageName]];
    [b setImagePosition:NSImageOnly];
    [[b cell] setImageScaling:NSImageScaleProportionallyDown];
    return b;
}

- (void)buildView {
    NSRect frame = NSMakeRect(0, 0, 270, 400);
    _view = [[NSView alloc] initWithFrame:frame];
    [_view setAutoresizesSubviews:YES];
    CGFloat barH = 23;

    _table = [[LRSidebarTable alloc] initWithFrame:NSMakeRect(0, 0, 270, 400)];
    NSTableColumn *col = [[[NSTableColumn alloc] initWithIdentifier:@"main"] autorelease];
    [col setResizingMask:NSTableColumnAutoresizingMask];
    [_table addTableColumn:col];
    [_table setHeaderView:nil];
    [_table setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleSourceList];
    [_table setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
    [_table setFloatsGroupRows:NO];
    [_table setIntercellSpacing:NSMakeSize(0, 0)];
    [_table setAllowsEmptySelection:YES];
    [_table setDelegate:self];
    [_table setDataSource:self];
    [_table setTarget:self];
    [_table setDoubleAction:@selector(doubleClicked:)];
    [_table setAction:@selector(clicked:)];
    [col setWidth:270];

    _scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, barH, 270, 400 - barH)];
    [_scroll setDocumentView:_table];
    [_scroll setHasVerticalScroller:YES];
    [_scroll setAutohidesScrollers:YES];
    [_scroll setBorderType:NSNoBorder];
    [_scroll setDrawsBackground:NO];
    [_scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    /* yosemite: the sidebar is a vibrant pane; before it the source list
       paints its own blue grey */
    NSView *vibrant = SKIN->flat ? LRMakeVibrantView(frame, 0, 0) : nil;
    if (vibrant) {
        [vibrant setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [_view addSubview:vibrant];
        [_table setBackgroundColor:[NSColor clearColor]];
        [vibrant addSubview:_scroll];
    } else {
        [_view addSubview:_scroll];
    }

    /* the 10.8 gradient button bar: add, remove, actions */
    _bottomBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 270, barH)];
    [_bottomBar setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    NSButton *add = [self barButton:NSImageNameAddTemplate frame:NSMakeRect(-1, 0, 32, barH)];
    __block LRSidebar *me = self;
    [add lr_setBlock:^(id sender) { [me->_owner showImportMenuFrom:sender]; }];
    [add setToolTip:L(@"Add servers")];
    _removeButton = [[self barButton:NSImageNameRemoveTemplate frame:NSMakeRect(30, 0, 32, barH)] retain];
    [_removeButton lr_setBlock:^(id sender) { [me deleteRow:[NSNumber numberWithInteger:[me->_table selectedRow]]]; }];
    [_removeButton setToolTip:L(@"Delete")];
    _actionButton = [[self barButton:NSImageNameActionTemplate frame:NSMakeRect(61, 0, 40, barH)] retain];
    [_actionButton lr_setBlock:^(id sender) {
        NSMenu *menu = [me listMenu];
        [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight([sender bounds]) + 2) inView:sender];
    }];
    /* the rest of the bar, a plain square key that does nothing, like
       system preferences fills it */
    NSButton *filler = [[[NSButton alloc] initWithFrame:NSMakeRect(100, 0, 171, barH)] autorelease];
    [filler setBezelStyle:NSSmallSquareBezelStyle];
    [filler setTitle:@""];
    [filler setEnabled:NO];
    [filler setAutoresizingMask:NSViewWidthSizable];
    [_bottomBar addSubview:filler];
    [_bottomBar addSubview:add];
    [_bottomBar addSubview:_removeButton];
    [_bottomBar addSubview:_actionButton];
    [_view addSubview:_bottomBar];

    [self buildEmpty];
}

- (void)buildEmpty {
    _empty = [[NSView alloc] initWithFrame:NSMakeRect(0, 23, 270, 377)];
    [_empty setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    _emptyTitle = [LRLabel(@"", [NSFont boldSystemFontOfSize:13], [NSColor colorWithCalibratedWhite:0.35f alpha:1]) retain];
    [_emptyTitle setAlignment:NSCenterTextAlignment];
    _emptyText = [LRLabel(@"", [NSFont systemFontOfSize:11], [NSColor colorWithCalibratedWhite:0.45f alpha:1]) retain];
    [_emptyText setAlignment:NSCenterTextAlignment];
    [[_emptyText cell] setWraps:YES];
    [[_emptyText cell] setLineBreakMode:NSLineBreakByWordWrapping];
    __block LRSidebar *me = self;
    _emptyPrimary = [LRPushButton(L(@"Paste from Clipboard"), ^(id s) { [me primaryEmptyAction]; }) retain];
    _emptySecondary = [LRPushButton(L(@"More ways to add"), ^(id s) { [me->_owner showImportMenuFrom:s]; }) retain];
    [_empty addSubview:_emptyTitle];
    [_empty addSubview:_emptyText];
    [_empty addSubview:_emptyPrimary];
    [_empty addSubview:_emptySecondary];
}

- (void)layoutEmpty {
    NSRect b = [_scroll frame];
    [_empty setFrame:b];
    CGFloat w = MIN(NSWidth(b) - 30, 230);
    CGFloat x = round((NSWidth(b) - w) / 2);
    CGFloat textH = [[_emptyText cell] cellSizeForBounds:NSMakeRect(0, 0, w, 400)].height;
    CGFloat total = 18 + 8 + textH + 16 + 32 + 4 + 32;
    CGFloat top = round(NSHeight(b) * 0.55f + total / 2);   /* unflipped: y grows up */
    [_emptyTitle setFrame:NSMakeRect(x, top - 18, w, 18)];
    [_emptyText setFrame:NSMakeRect(x, top - 26 - textH, w, textH)];
    CGFloat by = top - 26 - textH - 16 - 32;
    [_emptyPrimary setFrame:NSMakeRect(round((NSWidth(b) - 200) / 2), by, 200, 32)];
    [_emptySecondary setFrame:NSMakeRect(round((NSWidth(b) - 200) / 2), by - 34, 200, 32)];
    [_emptySecondary setHidden:_offline];
}

- (void)primaryEmptyAction {
    if (_offline) {
        [_owner startDaemon];
        return;
    }
    id importer = NSClassFromString(@"LRImporter");
    [importer performSelector:@selector(pasteFromClipboard)];
}

- (void)updateEmpty {
    LRCatalog *catalog = [LRCatalog shared];
    BOOL empty = [_rows count] == 0 && (catalog.loaded || _offline);
    if (!empty) {
        [_empty removeFromSuperview];
        return;
    }
    if (_offline) {
        [_emptyTitle setStringValue:L(@"Service Stopped")];
        [_emptyText setStringValue:L(@"LegacyRay could not reach its background service. Start it again, or reinstall the helper if this keeps happening.")];
        [_emptyPrimary setTitle:L(@"Start the daemon")];
    } else {
        [_emptyTitle setStringValue:L(@"No servers yet")];
        [_emptyText setStringValue:L(@"Add your first connection: paste a link, scan a QR code or add a subscription from your provider.")];
        [_emptyPrimary setTitle:L(@"Paste from Clipboard")];
    }
    if (![_empty superview]) [[_scroll superview] addSubview:_empty positioned:NSWindowAbove relativeTo:_scroll];
    [self layoutEmpty];
}

- (void)setDaemonOffline:(BOOL)offline {
    if (offline == _offline) return;
    _offline = offline;
    [self rebuild];
}

#pragma mark rows

- (void)rebuild {
    LRCatalog *catalog = [LRCatalog shared];
    NSMutableArray *rows = [NSMutableArray array];
    if (!_offline) {
        for (LRSection *sec in catalog.sections) {
            LRSidebarRow *h = LRRow(@"header", sec);
            h->first = [rows count] == 0;
            [rows addObject:h];
            if ([sec collapsed]) continue;
            if ([self usageFor:sec] || [self noteFor:sec]) [rows addObject:LRRow(@"info", sec)];
            for (LRServer *sv in sec.servers) {
                LRSidebarRow *r = LRRow(@"server", sec);
                r->server = [sv retain];
                [rows addObject:r];
            }
        }
        NSArray *profiles = [LRAWGProfiles profiles];
        if ([profiles count]) {
            LRSidebarRow *h = LRRow(@"header", nil);
            h->first = [rows count] == 0;
            [rows addObject:h];
            if (![LRPrefs sectionCollapsed:@"awg"])
                for (LRAWGProfile *p in profiles) {
                    LRSidebarRow *r = LRRow(@"awg", nil);
                    r->profile = [p retain];
                    [rows addObject:r];
                }
        }
    }
    _rebuilding = YES;
    [_rows setArray:rows];
    [_table reloadData];
    [self selectCurrent];
    _rebuilding = NO;
    [self updateEmpty];
    [self updateButtons];
}

- (void)selectCurrent {
    NSInteger want = -1;
    BOOL awg = [LRPrefs selectedBackend] == LRBackendAmneziaWG;
    NSString *activePath = [[LRAWGProfiles active] path];
    int sel = [LRCatalog shared].selectedIndex;
    for (NSUInteger i = 0; i < [_rows count]; ++i) {
        LRSidebarRow *r = [_rows objectAtIndex:i];
        if (!awg && r->server && r->server.index == sel) want = (NSInteger)i;
        if (awg && r->profile && [r->profile.path isEqualToString:activePath]) want = (NSInteger)i;
    }
    BOOL was = _rebuilding;
    _rebuilding = YES;
    if (want >= 0) {
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)want] byExtendingSelection:NO];
        [_table scrollRowToVisible:want];
    } else {
        [_table deselectAll:nil];
    }
    _rebuilding = was;
}

- (void)refreshRows {
    NSRange visible = [_table rowsInRect:[_table visibleRect]];
    for (NSUInteger i = visible.location; i < NSMaxRange(visible) && i < [_rows count]; ++i) {
        LRSidebarCell *cell = [_table viewAtColumn:0 row:(NSInteger)i makeIfNecessary:NO];
        if (cell) {
            [self configure:cell row:[_rows objectAtIndex:i]];
            [cell setNeedsDisplay:YES];
        }
    }
    [self updateButtons];
}

- (void)updateButtons {
    LRSidebarRow *r = [self rowAt:[_table selectedRow]];
    [_removeButton setEnabled:r && ((r->server && r->server.group < 0) || r->profile ||
                                     ([r->kind isEqualToString:@"header"] && r->section.subscription))];
}

- (LRSidebarRow *)rowAt:(NSInteger)i {
    return i >= 0 && i < (NSInteger)[_rows count] ? [_rows objectAtIndex:(NSUInteger)i] : nil;
}

- (NSString *)usageFor:(LRSection *)sec {
    LRSubscription *sub = sec.subscription;
    if (!sub || [sec isManual]) return nil;
    NSMutableArray *parts = [NSMutableArray array];
    unsigned long long used = [sub used];
    if (sub.total) [parts addObject:[NSString stringWithFormat:L(@"%@ of %@"), LRBytes(used), LRBytes(sub.total)]];
    else if (used) [parts addObject:[NSString stringWithFormat:L(@"%@ used"), LRBytes(used)]];
    NSInteger days = [sub daysLeft];
    if (days != NSIntegerMax)
        [parts addObject:days < 0 ? L(@"expired") : [NSString stringWithFormat:L(@"%ld d left"), (long)days]];
    return [parts count] ? [parts componentsJoinedByString:@" · "] : nil;
}

- (NSString *)noteFor:(LRSection *)sec {
    if ([sec isManual] || ![sec.subscription.summary length]) return nil;
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *line in [sec.subscription.summary componentsSeparatedByCharactersInSet:
                            [NSCharacterSet newlineCharacterSet]]) {
        NSString *t = LRTrim(line);
        if ([t length]) [kept addObject:t];
    }
    return [kept count] ? [kept componentsJoinedByString:@" "] : nil;
}

- (NSString *)metaFor:(LRSidebarRow *)r {
    NSUInteger n = r->section ? [r->section.servers count] : [[LRAWGProfiles profiles] count];
    if (!r->section)
        return [NSString stringWithFormat:@"%lu %@", (unsigned long)n,
                LRPlural((NSInteger)n, L(@"profile"), L(@"profiles (few)"), L(@"profiles"))];
    return [NSString stringWithFormat:@"%lu %@", (unsigned long)n,
            LRPlural((NSInteger)n, L(@"server"), L(@"servers (few)"), L(@"servers"))];
}

- (void)configure:(LRSidebarCell *)cell row:(LRSidebarRow *)r {
    LRSkin *s = SKIN;
    LRCatalog *catalog = [LRCatalog shared];
    LRTunnel *tunnel = [LRTunnel shared];
    [cell->row release];
    cell->row = [r retain];
    [cell->title release]; cell->title = nil;
    [cell->meta release]; cell->meta = nil;
    [cell->detail release]; cell->detail = nil;
    [cell->country release]; cell->country = nil;
    [cell->badge release]; cell->badge = nil;
    [cell->badgeColor release]; cell->badgeColor = nil;
    cell->live = NO;
    cell->badgeText = NO;
    if ([r->kind isEqualToString:@"header"]) {
        cell->title = [(r->section ? r->section.title : @"AmneziaWG") copy];
        cell->country = [r->section isManual] ? nil : [r->section.countryCode copy];
        cell->meta = [[self metaFor:r] copy];
        cell->collapsed = r->section ? [r->section collapsed] : [LRPrefs sectionCollapsed:@"awg"];
        [cell setToolTip:r->section.subscription ? LRStealth(r->section.subscription.url) : nil];
        return;
    }
    if ([r->kind isEqualToString:@"info"]) {
        cell->title = [[self usageFor:r->section] copy];
        cell->detail = [[self noteFor:r->section] copy];
        [cell setToolTip:cell->detail];
        return;
    }
    if (r->profile) {
        cell->title = [r->profile.name copy];
        cell->detail = [[r->profile summary] copy];
        BOOL active = [r->profile.path isEqualToString:[[LRAWGProfiles active] path]];
        cell->live = active && tunnel.activeBackend == LRBackendAmneziaWG && tunnel.state == LRTunnelConnected;
        [cell setToolTip:nil];
        return;
    }
    LRServer *sv = r->server;
    cell->title = [[r->section nameForServer:sv] copy];
    cell->detail = [[sv protocolSummary] copy];
    cell->country = [[sv countryCode] copy];
    cell->live = [LRPrefs selectedBackend] == LRBackendServer && sv.index == catalog.selectedIndex &&
                 tunnel.activeBackend == LRBackendServer && tunnel.state == LRTunnelConnected;
    NSNumber *ping = [catalog pingForServer:sv];
    if (!sv.supported) {
        cell->badge = [L(@"unsupported") copy];
        cell->badgeColor = [s->ledOff retain];
    } else if (ping && [ping intValue] == LR_PING_RUNNING) {
        cell->badge = [@"···" copy];
        cell->badgeColor = [s->ledOff retain];
    } else if (ping && [ping intValue] < 0) {
        /* words, not a red pill: a pill with a dash reads as a delete key */
        cell->badge = [L(@"no signal") copy];
        cell->badgeColor = [s->bad retain];
        cell->badgeText = YES;
    } else if (ping) {
        int v = [ping intValue];
        cell->badge = [[NSString stringWithFormat:@"%d", v] copy];
        cell->badgeColor = [(v < 150 ? s->ledGreen : (v < 450 ? s->ledAmber : s->ledRed)) retain];
    }
    NSString *tip = [NSString stringWithFormat:@"%@\n%@:%d", cell->title, LRStealth(sv.host), sv.port];
    if (ping && [ping intValue] >= 0) tip = [tip stringByAppendingFormat:@"\n%d ms", [ping intValue]];
    else if (ping && [ping intValue] == LR_PING_FAILED) tip = [tip stringByAppendingFormat:@"\n%@", L(@"no signal")];
    [cell setToolTip:tip];
}

#pragma mark table data

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)[_rows count];
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row {
    return NO;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    LRSidebarRow *r = [self rowAt:row];
    if ([r->kind isEqualToString:@"header"]) return r->first ? 28 : 34;
    if ([r->kind isEqualToString:@"info"]) {
        CGFloat h = [self usageFor:r->section] ? 17 : 2;
        NSString *note = [self noteFor:r->section];
        if (note) {
            CGFloat w = MAX(100.0f, NSWidth([_table bounds]) - 22);
            NSRect box = [note boundingRectWithSize:NSMakeSize(w, 1000) options:NSStringDrawingUsesLineFragmentOrigin
                                         attributes:[NSDictionary dictionaryWithObject:[NSFont systemFontOfSize:11]
                                                                                forKey:NSFontAttributeName]];
            h += MIN(ceil(box.size.height), 42);
        }
        return h + 4;
    }
    return 38;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    LRSidebarCell *cell = [tableView makeViewWithIdentifier:@"cell" owner:self];
    if (!cell) {
        cell = [[[LRSidebarCell alloc] initWithFrame:NSMakeRect(0, 0, 200, 38)] autorelease];
        [cell setIdentifier:@"cell"];
    }
    [self configure:cell row:[self rowAt:row]];
    [cell setNeedsDisplay:YES];
    return cell;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    LRSidebarRow *r = [self rowAt:row];
    return r && (r->server || r->profile);
}

- (void)tableViewColumnDidResize:(NSNotification *)n {
    /* the provider's note wraps to the new width */
    NSMutableIndexSet *info = [NSMutableIndexSet indexSet];
    for (NSUInteger i = 0; i < [_rows count]; ++i)
        if ([((LRSidebarRow *)[_rows objectAtIndex:i])->kind isEqualToString:@"info"]) [info addIndex:i];
    if ([info count]) [_table noteHeightOfRowsWithIndexesChanged:info];
    if ([_empty superview]) [self layoutEmpty];
}

#pragma mark picking

/* a click picks the server for the power button; with a tunnel up it
   switches over, once the selection has rested (arrow keys walk the list
   without reconnecting at every row) */
- (void)tableViewSelectionDidChange:(NSNotification *)n {
    [self updateButtons];
    if (_rebuilding) return;
    LRSidebarRow *r = [self rowAt:[_table selectedRow]];
    if (!r) return;
    if (r->server) {
        LRTunnel *t = [LRTunnel shared];
        BOOL backendChange = [LRPrefs selectedBackend] != LRBackendServer;
        [LRPrefs setSelectedBackend:LRBackendServer];
        [LRCatalog shared].selectedIndex = r->server.index;
        LRLog(@"stations", @"station selected");
        [[NSNotificationCenter defaultCenter] postNotificationName:LRTunnelDidChangeNotification object:t];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(switchIfOn) object:nil];
        if ([t isOn] && (t.activeBackend == LRBackendServer || backendChange))
            [self performSelector:@selector(switchIfOn) withObject:nil afterDelay:0.7];
    } else if (r->profile) {
        BOOL other = ![r->profile.path isEqualToString:[[LRAWGProfiles active] path]];
        LRTunnel *t = [LRTunnel shared];
        BOOL backendChange = [LRPrefs selectedBackend] != LRBackendAmneziaWG;
        [LRAWGProfiles setActive:r->profile];
        [LRPrefs setSelectedBackend:LRBackendAmneziaWG];
        if ([t isOn] && (backendChange || other)) {
            [t disconnect];
            [t performSelector:@selector(startAWG) withObject:nil afterDelay:1.5];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:LRTunnelDidChangeNotification object:t];
    }
}

- (void)switchIfOn {
    LRTunnel *t = [LRTunnel shared];
    LRServer *sv = [[LRCatalog shared] selectedServer];
    if (!sv || ![t isOn] || t.busy) return;
    [t connectServerIndex:sv.index];
}

- (void)clicked:(id)sender {
    NSInteger row = [_table clickedRow];
    LRSidebarRow *r = [self rowAt:row];
    if (!r || ![r->kind isEqualToString:@"header"]) return;
    /* a click on a group folds it */
    if (r->section) [[LRCatalog shared] setSection:r->section collapsed:![r->section collapsed]];
    else [LRPrefs setSection:@"awg" collapsed:![LRPrefs sectionCollapsed:@"awg"]];
    [self rebuild];
}

- (void)doubleClicked:(id)sender {
    [self activateRow:[NSNumber numberWithInteger:[_table clickedRow]]];
}

- (void)activateRow:(NSNumber *)n {
    LRSidebarRow *r = [self rowAt:[n integerValue]];
    if (!r) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(switchIfOn) object:nil];
    if (r->server) {
        if (!r->server.supported) {
            [LRToast showError:L(@"This protocol is not supported")];
            return;
        }
        [LRPrefs setSelectedBackend:LRBackendServer];
        [[LRTunnel shared] connectServerIndex:r->server.index];
    } else if (r->profile) {
        [LRAWGProfiles setActive:r->profile];
        [LRPrefs setSelectedBackend:LRBackendAmneziaWG];
        LRTunnel *t = [LRTunnel shared];
        if ([t isOn]) {
            [t disconnect];
            [t performSelector:@selector(startAWG) withObject:nil afterDelay:1.5];
        } else {
            [t startAWG];
        }
    }
}

- (void)deleteRow:(NSNumber *)n {
    LRSidebarRow *r = [self rowAt:[n integerValue]];
    if (!r) return;
    if (r->server && r->server.group < 0) [self deleteServer:r->server];
    else if (r->profile) [self deleteProfile:r->profile];
    else if ([r->kind isEqualToString:@"header"] && r->section.subscription) [self deleteSection:r->section];
    else if (r->server) [LRToast show:L(@"Servers of a subscription are removed with the subscription")];
}

#pragma mark actions

- (void)deleteServer:(LRServer *)sv {
    NSString *name = [[LRCatalog shared] displayNameForServer:sv];
    [LRAlert confirmTitle:L(@"Delete Server") message:name button:L(@"Delete") destructive:YES action:^{
        [[LRDaemonClient shared] deleteServerIndex:sv.index reply:^(NSString *reply) {
            if (LRReplyIsOK(reply)) {
                LRLog(@"stations", @"station deleted");
                [[LRCatalog shared] reload];
            } else [LRToast showError:LRErrorFromReply(reply) ? LRErrorFromReply(reply) : L(@"Could not delete")];
        }];
    }];
}

- (void)deleteProfile:(LRAWGProfile *)p {
    [LRAlert confirmTitle:L(@"Delete Profile") message:p.name button:L(@"Delete") destructive:YES action:^{
        [LRAWGProfiles deleteProfile:p];
    }];
}

- (void)deleteSection:(LRSection *)sec {
    LRSubscription *sub = sec.subscription;
    [LRAlert confirmTitle:L(@"Delete Subscription") message:sec.title button:L(@"Delete") destructive:YES action:^{
        [[LRDaemonClient shared] deleteSubscriptionIndex:sub.index reply:^(NSString *reply) {
            if (LRReplyIsOK(reply)) LRLog(@"subscriptions", @"subscription deleted");
            else [LRToast showError:LRErrorFromReply(reply) ? LRErrorFromReply(reply) : L(@"Could not delete")];
            [[LRCatalog shared] reload];
        }];
    }];
}

- (void)connectFastestOf:(NSArray *)servers {
    [LRToast show:[NSString stringWithFormat:L(@"Measuring %lu servers..."), (unsigned long)[servers count]]];
    [[LRCatalog shared] pickFastestOf:servers done:^(LRServer *best, int ms) {
        if (!best) {
            [LRToast showError:L(@"No server answered")];
            return;
        }
        LRLog(@"stations", @"fastest station picked (%d ms)", ms);
        [LRToast showSuccess:[NSString stringWithFormat:L(@"%@ · %d ms"),
                              [[LRCatalog shared] displayNameForServer:best], ms]];
        [LRPrefs setSelectedBackend:LRBackendServer];
        [[LRTunnel shared] connectServerIndex:best.index];
    }];
}

- (void)copyLinkOf:(LRServer *)sv {
    [[LRDaemonClient shared] serverLinkIndex:sv.index reply:^(NSString *link) {
        if (!link) { [LRToast showError:L(@"The link could not be read")]; return; }
        LRSetPasteboardString(link);
        [LRToast showSuccess:L(@"Link copied")];
    }];
}

- (void)refreshSubscription:(LRSubscription *)sub {
    [LRToast show:L(@"Updating subscription...")];
    [[LRDaemonClient shared] refreshSubscriptionIndex:sub.index reply:^(NSString *reply) {
        if (LRReplyIsOK(reply)) [LRToast showSuccess:LRTrim([reply substringFromIndex:MIN((NSUInteger)3, [reply length])])];
        else [LRToast showError:LRErrorFromReply(reply) ? LRErrorFromReply(reply) : L(@"Subscription update failed")];
        [[LRCatalog shared] reload];
    }];
}

#pragma mark menus

- (NSMenu *)listMenu {
    LRCatalog *catalog = [LRCatalog shared];
    __block LRSidebar *me = self;
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    [menu setAutoenablesItems:NO];
    NSMenuItem *it = [menu lr_addItem:L(@"Connect to the fastest") block:^{
        [me connectFastestOf:[LRCatalog shared].servers];
    }];
    [it setEnabled:[catalog.servers count] > 0];
    if ([catalog pinging]) [menu lr_addItem:L(@"Stop latency checks") block:^{ [[LRCatalog shared] cancelPings]; }];
    else [[menu lr_addItem:L(@"Check latency of all") block:^{ [[LRCatalog shared] pingAll]; }]
          setEnabled:[catalog.servers count] > 0];
    it = [menu lr_addItem:L(@"Update all subscriptions") block:^{
        [LRToast show:L(@"Updating subscriptions...")];
        [[LRCatalog shared] refreshAllSubscriptions:^(NSUInteger ok, NSUInteger failed) {
            NSString *msg = [NSString stringWithFormat:L(@"Subscriptions updated: %lu/%lu"),
                             (unsigned long)ok, (unsigned long)(ok + failed)];
            if (failed) [LRToast showError:msg]; else [LRToast showSuccess:msg];
        }];
    }];
    [it setEnabled:[catalog.subscriptions count] > 0];
    [menu lr_addSeparator];
    NSMenuItem *sortItem = [menu lr_addItem:L(@"Sort servers") block:nil];
    NSMenu *sorts = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    NSArray *names = [NSArray arrayWithObjects:L(@"As added"), L(@"By name"), L(@"By latency"), nil];
    for (NSUInteger i = 0; i < [names count]; ++i) {
        NSMenuItem *s = [sorts lr_addItem:[names objectAtIndex:i] block:^{ [LRPrefs setSortMode:(LRSortMode)i]; }];
        [s setState:[LRPrefs sortMode] == (LRSortMode)i ? NSOnState : NSOffState];
    }
    [sortItem setSubmenu:sorts];
    BOOL anyOpen = NO;
    for (LRSection *sec in catalog.sections) if (![sec collapsed]) anyOpen = YES;
    [menu lr_addItem:anyOpen ? L(@"Collapse all") : L(@"Expand all") block:^{
        for (LRSection *sec in [LRCatalog shared].sections) [[LRCatalog shared] setSection:sec collapsed:anyOpen];
        [me rebuild];
    }];
    [menu lr_addSeparator];
    [menu lr_addItem:L(@"AmneziaWG profiles…") block:^{ [me->_owner openAWGProfiles]; }];
    return menu;
}

- (NSMenu *)menuForRow:(NSNumber *)n {
    LRSidebarRow *r = [self rowAt:[n integerValue]];
    if (!r) return nil;
    __block LRSidebar *me = self;
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    [menu setAutoenablesItems:NO];
    if (r->server) {
        LRServer *sv = r->server;
        [menu lr_addItem:[[LRTunnel shared] isOn] ? L(@"Switch to this server") : L(@"Connect") block:^{
            [me activateRow:n];
        }];
        [menu lr_addItem:L(@"Check latency") block:^{ [[LRCatalog shared] pingServers:[NSArray arrayWithObject:sv]]; }];
        [menu lr_addSeparator];
        [menu lr_addItem:L(@"Details…") block:^{ [me->_owner openServer:sv]; }];
        [menu lr_addItem:L(@"Share…") block:^{ [me->_owner shareServer:sv]; }];
        [menu lr_addItem:L(@"Copy link") block:^{ [me copyLinkOf:sv]; }];
        if (sv.group < 0) {
            [menu lr_addSeparator];
            [menu lr_addItem:L(@"Delete…") block:^{ [me deleteServer:sv]; }];
        }
        return menu;
    }
    if (r->profile) {
        LRAWGProfile *p = r->profile;
        [menu lr_addItem:[[LRTunnel shared] isOn] ? L(@"Switch to this profile") : L(@"Connect") block:^{
            [me activateRow:n];
        }];
        [menu lr_addItem:L(@"Details…") block:^{ [me->_owner openAWGProfile:p]; }];
        [menu lr_addSeparator];
        [menu lr_addItem:L(@"Delete…") block:^{ [me deleteProfile:p]; }];
        return menu;
    }
    LRSection *sec = r->section;
    if (!sec) {
        [menu lr_addItem:L(@"AmneziaWG profiles…") block:^{ [me->_owner openAWGProfiles]; }];
        return menu;
    }
    LRSubscription *sub = sec.subscription;
    if (sub) {
        [menu lr_addItem:L(@"Subscription info…") block:^{ [me->_owner openSubscription:sub]; }];
        [menu lr_addItem:L(@"Update now") block:^{ [me refreshSubscription:sub]; }];
        if ([sub.webPageURL length])
            [menu lr_addItem:L(@"Open the provider's page") block:^{
                NSURL *u = [NSURL URLWithString:sub.webPageURL];
                if (u) [[NSWorkspace sharedWorkspace] openURL:u];
            }];
        [menu lr_addSeparator];
    }
    if ([sec.servers count]) {
        [menu lr_addItem:L(@"Connect to the fastest") block:^{ [me connectFastestOf:sec.servers]; }];
        [menu lr_addItem:L(@"Check latency of this list") block:^{ [[LRCatalog shared] pingServers:sec.servers]; }];
    }
    NSUInteger at = [[LRCatalog shared].sections indexOfObjectIdenticalTo:sec];
    if (at != NSNotFound && ([[LRCatalog shared].sections count] > 1)) {
        [menu lr_addSeparator];
        [[menu lr_addItem:L(@"Move up") block:^{ [[LRCatalog shared] moveSection:sec toPosition:at - 1]; }]
         setEnabled:at > 0];
        [[menu lr_addItem:L(@"Move down") block:^{ [[LRCatalog shared] moveSection:sec toPosition:at + 1]; }]
         setEnabled:at + 1 < [[LRCatalog shared].sections count]];
    }
    if (sub) {
        [menu lr_addSeparator];
        [menu lr_addItem:L(@"Delete Subscription…") block:^{ [me deleteSection:sec]; }];
    } else if ([sec isManual] && [sec.servers count]) {
        [menu lr_addSeparator];
        [menu lr_addItem:L(@"Delete all manual servers…") block:^{
            [LRAlert confirmTitle:L(@"Delete all manual servers")
                          message:L(@"Only manually added servers are removed. Subscriptions stay.")
                           button:L(@"Delete") destructive:YES action:^{
                [[LRDaemonClient shared] clearManualServers:^(NSString *reply) { [[LRCatalog shared] reload]; }];
            }];
        }];
    }
    return menu;
}
@end
