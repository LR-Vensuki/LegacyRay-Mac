#import "LRStationsScreen.h"
#import "LRStationCells.h"
#import "LRCatalog.h"
#import "LRTunnel.h"
#import "LRPrefs.h"
#import "LRDaemonClient.h"
#import "LRActivityLog.h"
#import "LRImporter.h"
#import "LRMenu.h"
#import "LRAlert.h"
#import "LRToast.h"
#import "LRDraw.h"
#import "LRStationScreen.h"
#import "LRSubscriptionScreen.h"
#import "LRAWGScreen.h"
#import "LRAWGProfiles.h"
#import "LRShareScreen.h"

#define LR_SECTION_AWG (-2)

@implementation LRStationsScreen
@synthesize embedded = _embedded;

- (id)init {
    if ((self = [super init])) {
        _backgroundStyle = LRBackgroundGrouped;
        self.title = L(@"Servers");
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _table.delegate = nil;
    _table.dataSource = nil;
    [_table release];
    [_empty release];
    [_rows release];
    [super dealloc];
}

- (CGFloat)margin {
    return LRPlateMargin(_table.bounds.size.width);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _header.title = self.title;
    __block LRStationsScreen *me = self;
    UIColor *ink = [LRHeaderBar glyphColor];
    [self.header setRightGlyph:LRGlyphPlus(16, ink) action:^(LRButton *b) {
        [LRImporter showMenuFrom:b host:me];
    }];
    [self.header setExtraGlyph:LRGlyphDots(18, ink) action:^(LRButton *b) { [me showListMenu:b]; }];
    _table = [[UITableView alloc] initWithFrame:self.contentView.bounds style:UITableViewStylePlain];
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self;
    _table.delegate = self;
    _table.indicatorStyle = UIScrollViewIndicatorStyleDefault;
    /* room under the last group, like a grouped table */
    _table.tableFooterView = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 20)] autorelease];
    _table.allowsSelectionDuringEditing = YES;
    [self.contentView addSubview:_table];
    UILongPressGestureRecognizer *lp = [[[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(longPress:)] autorelease];
    [_table addGestureRecognizer:lp];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(rebuild) name:LRCatalogDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(pingsChanged) name:LRCatalogPingNotification object:nil];
    [nc addObserver:self selector:@selector(pingsChanged) name:LRTunnelDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(rebuild) name:LRAWGProfilesDidChangeNotification object:nil];
    [self rebuild];
    if (![LRCatalog shared].loaded) [[LRCatalog shared] reload];
}

- (BOOL)wantsContentUnderHeader {
    return YES;
}

- (void)layoutContent {
    _table.frame = self.contentView.bounds;
    LRApplyHeaderCoverage(_table, self.headerCoverage);
    CGRect b = self.contentView.bounds;
    _empty.frame = CGRectMake(0, 0, b.size.width, b.size.height);
    [self layoutEmpty];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    cell.backgroundColor = [UIColor clearColor];
}

#pragma mark model

- (void)rebuild {
    LRCatalog *catalog = [LRCatalog shared];
    NSMutableArray *rows = [NSMutableArray array];
    NSArray *profiles = [LRAWGProfiles profiles];
    if ([profiles count] && !_arranging) {
        NSNumber *sid = [NSNumber numberWithInt:LR_SECTION_AWG];
        [rows addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"plate", @"kind", sid, @"sid", nil]];
        if (![LRPrefs sectionCollapsed:@"awg"])
            for (LRAWGProfile *p in profiles)
                [rows addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"awg", @"kind", sid, @"sid",
                                 p, @"profile", nil]];
    }
    for (LRSection *sec in catalog.sections) {
        [rows addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"plate", @"kind", sec, @"section", nil]];
        if ([sec collapsed] && !_arranging) continue;
        if (_arranging && ![sec isManual]) continue;
        for (LRServer *sv in sec.servers)
            [rows addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"server", @"kind", sec, @"section",
                             sv, @"server", nil]];
    }
    [_rows release];
    _rows = [rows retain];
    [_table reloadData];
    [self updateEmpty];
}

- (void)pingsChanged {
    for (UITableViewCell *cell in [_table visibleCells]) {
        NSIndexPath *ip = [_table indexPathForCell:cell];
        if (ip) [self configure:cell at:ip];
    }
}

- (NSDictionary *)rowAt:(NSIndexPath *)ip {
    return ip.row < (NSInteger)[_rows count] ? [_rows objectAtIndex:(NSUInteger)ip.row] : nil;
}

#pragma mark empty state

- (void)updateEmpty {
    LRCatalog *catalog = [LRCatalog shared];
    BOOL show = catalog.loaded ? [catalog isEmpty] : (catalog.lastError != nil);
    BOOL offline = catalog.loaded == NO;
    /* the ipad builds this pane before the daemon has answered once, so a view
       made while it was unreachable has to go when an empty catalog arrives,
       or "the daemon is silent" stays over a daemon that is running */
    if (_empty && (!show || offline != _emptyOffline)) {
        [_empty removeFromSuperview];
        [_empty release];
        _empty = nil;
    }
    if (!show) return;
    if (_empty) {
        [self layoutEmpty];
        return;
    }
    LRSkin *s = SKIN;
    __block LRStationsScreen *me = self;
    _empty = [[UIView alloc] initWithFrame:self.contentView.bounds];
    UILabel *title = [[[UILabel alloc] init] autorelease];
    title.tag = 1;
    title.backgroundColor = [UIColor clearColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = s->flat ? [LRSkin bodyFont:20] : [LRSkin boldFont:20];
    title.textColor = s->flat ? s->groupInk : s->groupHeader;
    title.shadowColor = s->flat ? nil : s->groupHeaderShadow;
    title.shadowOffset = CGSizeMake(0, 1);
    UILabel *text = [[[UILabel alloc] init] autorelease];
    text.tag = 2;
    text.backgroundColor = [UIColor clearColor];
    text.textAlignment = NSTextAlignmentCenter;
    text.numberOfLines = 0;
    text.font = [LRSkin bodyFont:s->flat ? 14 : 15];
    text.textColor = s->flat ? s->groupMuted : s->groupHeader;
    text.shadowColor = s->flat ? nil : s->groupHeaderShadow;
    text.shadowOffset = CGSizeMake(0, 1);
    _emptyOffline = offline;
    title.text = offline ? L(@"The daemon is silent") : L(@"No servers yet");
    text.text = offline ? L(@"LegacyRay could not reach its background service. Start it again, or reinstall the package if this keeps happening.")
                        : L(@"Add your first connection: paste a link, scan a QR code or add a subscription from your provider.");
    [_empty addSubview:title];
    [_empty addSubview:text];
    NSMutableArray *buttons = [NSMutableArray array];
    if (offline) {
        [buttons addObject:[LRButton buttonWithStyle:LRButtonGreen title:L(@"Start the daemon") action:^(LRButton *b) {
            [[LRDaemonClient shared] ensureDaemon:^(BOOL up, NSString *detail) {
                if (up) [[LRCatalog shared] reload];
                else [LRToast showError:detail];
            }];
        }]];
    } else {
        [buttons addObject:[LRButton buttonWithStyle:LRButtonGreen title:L(@"Paste from Clipboard")
                                              action:^(LRButton *b) { [LRImporter pasteFromClipboard]; }]];
        [buttons addObject:[LRButton buttonWithStyle:LRButtonMetal title:L(@"More ways to add")
                                              action:^(LRButton *b) { [LRImporter showMenuFrom:b host:me]; }]];
    }
    NSInteger tag = 10;
    for (LRButton *b in buttons) {
        b.tag = tag++;
        b.frame = CGRectMake(0, 0, 200, 42);
        b.titleLabel.font = [LRSkin boldFont:15];
        [_empty addSubview:b];
    }
    [self.contentView addSubview:_empty];
    [self layoutEmpty];
}

- (void)layoutEmpty {
    if (!_empty) return;
    CGRect b = self.contentView.bounds;
    _empty.frame = b;
    CGFloat w = MIN(b.size.width - 40, 320);
    CGFloat x = (b.size.width - w) / 2;
    UILabel *title = (UILabel *)[_empty viewWithTag:1];
    UILabel *text = (UILabel *)[_empty viewWithTag:2];
    CGSize ts = [text.text sizeWithFont:text.font constrainedToSize:CGSizeMake(w, 300)];
    CGFloat y = MAX(30, b.size.height * 0.22f) + self.headerCoverage;
    title.frame = CGRectMake(x, y, w, 26);
    text.frame = CGRectMake(x, y + 34, w, ceilf(ts.height));
    y += 34 + ceilf(ts.height) + 20;
    for (NSInteger tag = 10; [_empty viewWithTag:tag]; ++tag) {
        [_empty viewWithTag:tag].frame = CGRectMake(x, y, w, 42);
        y += 50;
    }
}

#pragma mark table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[_rows count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *row = [self rowAt:ip];
    NSString *kind = [row objectForKey:@"kind"];
    if ([kind isEqualToString:@"plate"]) {
        LRSection *sec = [row objectForKey:@"section"];
        return [LRPlateHeaderCell heightWithCountry:sec.countryCode usage:[self usageForSection:sec]
                                               note:[self noteForSection:sec]
                                              width:tableView.bounds.size.width margin:[self margin]];
    }
    return LR_STATION_ROW_HEIGHT;
}

- (NSString *)metaForSection:(LRSection *)sec {
    NSUInteger n = [sec.servers count];
    return [NSString stringWithFormat:@"%lu %@", (unsigned long)n, LRPlural((NSInteger)n, L(@"server"),
            L(@"servers (few)"), L(@"servers"))];
}

/* the first caption line under a subscription: the traffic as the provider
   counts it, and the time left */
- (NSString *)usageForSection:(LRSection *)sec {
    LRSubscription *sub = sec.subscription;
    if (!sub || [sec isManual]) return nil;
    NSMutableArray *parts = [NSMutableArray array];
    unsigned long long used = [sub used];
    if (sub.total)
        [parts addObject:[NSString stringWithFormat:L(@"%@ of %@"), LRBytes(used), LRBytes(sub.total)]];
    else if (used)
        [parts addObject:[NSString stringWithFormat:L(@"%@ used"), LRBytes(used)]];
    NSInteger days = [sub daysLeft];
    if (days != NSIntegerMax)
        [parts addObject:days < 0 ? L(@"expired") : [NSString stringWithFormat:L(@"%ld d left"), (long)days]];
    return [parts count] ? [parts componentsJoinedByString:@" · "] : nil;
}

/* the second: what the provider wrote about the subscription (its
   description, or the announce line), on one paragraph */
- (NSString *)noteForSection:(LRSection *)sec {
    if ([sec isManual] || ![sec.subscription.summary length]) return nil;
    NSArray *lines = [sec.subscription.summary componentsSeparatedByCharactersInSet:
                      [NSCharacterSet newlineCharacterSet]];
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *line in lines) {
        NSString *t = LRTrim(line);
        if ([t length]) [kept addObject:t];
    }
    return [kept count] ? [kept componentsJoinedByString:@" "] : nil;
}

- (void)configure:(UITableViewCell *)cell at:(NSIndexPath *)ip {
    NSDictionary *row = [self rowAt:ip];
    NSString *kind = [row objectForKey:@"kind"];
    LRCatalog *catalog = [LRCatalog shared];
    LRTunnel *tunnel = [LRTunnel shared];
    CGFloat margin = [self margin];
    NSDictionary *next = ip.row + 1 < (NSInteger)[_rows count] ? [_rows objectAtIndex:(NSUInteger)ip.row + 1] : nil;
    NSDictionary *prev = ip.row > 0 ? [_rows objectAtIndex:(NSUInteger)ip.row - 1] : nil;
    BOOL last = !next || [[next objectForKey:@"kind"] isEqualToString:@"plate"];
    BOOL first = !prev || [[prev objectForKey:@"kind"] isEqualToString:@"plate"];
    LRPlatePosition position = first ? (last ? LRPlateSingle : LRPlateTop) : (last ? LRPlateBottom : LRPlateMiddle);
    __block LRStationsScreen *me = self;
    if ([kind isEqualToString:@"plate"]) {
        LRSection *sec = [row objectForKey:@"section"];
        if (!sec) {
            NSUInteger n = [[LRAWGProfiles profiles] count];
            NSString *meta = [NSString stringWithFormat:@"%lu %@", (unsigned long)n,
                              LRPlural((NSInteger)n, L(@"profile"), L(@"profiles (few)"), L(@"profiles"))];
            [(LRPlateHeaderCell *)cell showTitle:@"AmneziaWG" country:nil meta:meta usage:nil note:nil
                                       collapsed:[LRPrefs sectionCollapsed:@"awg"] margin:margin];
            return;
        }
        [(LRPlateHeaderCell *)cell showTitle:sec.title country:sec.countryCode meta:[self metaForSection:sec]
                                       usage:[self usageForSection:sec] note:[self noteForSection:sec]
                                   collapsed:[sec collapsed] && !_arranging margin:margin];
        return;
    }
    if ([kind isEqualToString:@"awg"]) {
        LRAWGProfile *p = [row objectForKey:@"profile"];
        BOOL isActive = [p.path isEqualToString:[[LRAWGProfiles active] path]];
        BOOL sel = isActive && [LRPrefs selectedBackend] == LRBackendAmneziaWG;
        BOOL live = sel && tunnel.activeBackend == LRBackendAmneziaWG && tunnel.state == LRTunnelConnected;
        [(LRStationCell *)cell showTitle:p.name detail:[p summary] selected:sel
                                    live:live margin:margin position:position];
        ((LRStationCell *)cell).infoAction = ^{
            [me presentSheet:[[[LRAWGProfileScreen alloc] initWithProfile:p] autorelease]];
        };
        return;
    }
    LRServer *sv = [row objectForKey:@"server"];
    LRSection *sec = [row objectForKey:@"section"];
    BOOL selected = [LRPrefs selectedBackend] == LRBackendServer && sv.index == catalog.selectedIndex;
    BOOL live = selected && tunnel.activeBackend == LRBackendServer && tunnel.state == LRTunnelConnected;
    [(LRStationCell *)cell showServer:sv name:[sec nameForServer:sv] ping:[catalog pingForServer:sv]
                             selected:selected live:live margin:margin position:position];
    ((LRStationCell *)cell).infoAction = _arranging ? nil : ^{ [me openServerDetail:sv]; };
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSString *kind = [[self rowAt:ip] objectForKey:@"kind"];
    UITableViewCell *cell;
    if ([kind isEqualToString:@"plate"]) {
        cell = [tableView dequeueReusableCellWithIdentifier:@"plate"];
        if (!cell) cell = [[[LRPlateHeaderCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                    reuseIdentifier:@"plate"] autorelease];
    } else {
        cell = [tableView dequeueReusableCellWithIdentifier:@"station"];
        if (!cell) cell = [[[LRStationCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                reuseIdentifier:@"station"] autorelease];
    }
    [self configure:cell at:ip];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *row = [self rowAt:ip];
    NSString *kind = [row objectForKey:@"kind"];
    if ([kind isEqualToString:@"plate"]) {
        if (_arranging) return;
        LRSection *sec = [row objectForKey:@"section"];
        if (sec) [[LRCatalog shared] setSection:sec collapsed:![sec collapsed]];
        else [LRPrefs setSection:@"awg" collapsed:![LRPrefs sectionCollapsed:@"awg"]];
        [self rebuild];
        return;
    }
    if ([kind isEqualToString:@"awg"]) {
        [self tuneToAWG:[row objectForKey:@"profile"]];
        return;
    }
    [self tuneTo:[row objectForKey:@"server"]];
}

#pragma mark arranging (manual stations and subscription order)

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)ip {
    return _arranging;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)ip {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)ip {
    return NO;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)ip {
    if (!_arranging) return NO;
    NSDictionary *row = [self rowAt:ip];
    NSString *kind = [row objectForKey:@"kind"];
    if ([kind isEqualToString:@"server"]) return YES;
    return [kind isEqualToString:@"plate"] && [row objectForKey:@"section"] != nil;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from
       toProposedIndexPath:(NSIndexPath *)to {
    NSDictionary *row = [self rowAt:from];
    if ([[row objectForKey:@"kind"] isEqualToString:@"server"]) {
        /* manual stations move only among themselves */
        LRSection *sec = [row objectForKey:@"section"];
        NSInteger first = NSNotFound, lastIdx = NSNotFound;
        for (NSUInteger i = 0; i < [_rows count]; ++i) {
            NSDictionary *r = [_rows objectAtIndex:i];
            if ([[r objectForKey:@"kind"] isEqualToString:@"server"] && [r objectForKey:@"section"] == sec) {
                if (first == NSNotFound) first = (NSInteger)i;
                lastIdx = (NSInteger)i;
            }
        }
        NSInteger r = MAX(first, MIN(lastIdx, to.row));
        return [NSIndexPath indexPathForRow:r inSection:0];
    }
    /* plates move among plates */
    NSInteger r = to.row;
    while (r < (NSInteger)[_rows count] &&
           ![[[_rows objectAtIndex:(NSUInteger)r] objectForKey:@"kind"] isEqualToString:@"plate"]) ++r;
    if (r >= (NSInteger)[_rows count]) r = (NSInteger)[_rows count] - 1;
    return [NSIndexPath indexPathForRow:r inSection:0];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSDictionary *row = [self rowAt:from];
    NSMutableArray *rows = [NSMutableArray arrayWithArray:_rows];
    [rows removeObjectAtIndex:(NSUInteger)from.row];
    [rows insertObject:row atIndex:(NSUInteger)to.row];
    if ([[row objectForKey:@"kind"] isEqualToString:@"server"]) {
        LRServer *sv = [row objectForKey:@"server"];
        LRSection *sec = [row objectForKey:@"section"];
        NSUInteger pos = 0;
        for (NSDictionary *r in rows) {
            if ([r objectForKey:@"server"] == sv) break;
            if ([r objectForKey:@"section"] == sec && [[r objectForKey:@"kind"] isEqualToString:@"server"]) ++pos;
        }
        [_rows release];
        _rows = [rows retain];
        [[LRDaemonClient shared] moveManualServerIndex:sv.index toPosition:(int)pos reply:^(NSString *reply) {
            /* the catalog reload below is all this needs; no screen state */
            if (!LRReplyIsOK(reply)) [LRToast showError:LRErrorFromReply(reply) ? LRErrorFromReply(reply) : L(@"Could not move")];
            [[LRCatalog shared] reload];
        }];
        return;
    }
    LRSection *sec = [row objectForKey:@"section"];
    NSUInteger pos = 0;
    for (NSDictionary *r in rows) {
        if (![[r objectForKey:@"kind"] isEqualToString:@"plate"] || ![r objectForKey:@"section"]) continue;
        if ([r objectForKey:@"section"] == sec) break;
        ++pos;
    }
    [_rows release];
    _rows = [rows retain];
    [[LRCatalog shared] moveSection:sec toPosition:pos];
    LRLog(@"stations", @"subscription order saved");
}

- (void)setArranging:(BOOL)on {
    _arranging = on;
    [self rebuild];
    [_table setEditing:on animated:YES];
    __block LRStationsScreen *me = self;
    if (on) {
        [self.header setRightTitle:L(@"Done") style:LRButtonGreen action:^(LRButton *b) {
            [me setArranging:NO];
        }];
        self.header.extraButton = nil;
        [LRToast show:L(@"Drag subscriptions and manual servers to change their order")];
    } else {
        UIColor *ink = [LRHeaderBar glyphColor];
        [self.header setRightGlyph:LRGlyphPlus(16, ink) action:^(LRButton *b) {
            [LRImporter showMenuFrom:b host:me];
        }];
        [self.header setExtraGlyph:LRGlyphDots(18, ink) action:^(LRButton *b) { [me showListMenu:b]; }];
    }
}

#pragma mark tuning

- (void)tuneTo:(LRServer *)sv {
    if (!sv) return;
    LRTunnel *t = [LRTunnel shared];
    [LRPrefs setSelectedBackend:LRBackendServer];
    BOOL switchNow = [t isOn] && t.activeBackend == LRBackendServer && sv.index != [LRCatalog shared].selectedIndex;
    if (switchNow) {
        [t connectServerIndex:sv.index];
    } else {
        [LRCatalog shared].selectedIndex = sv.index;
        [[NSNotificationCenter defaultCenter] postNotificationName:LRTunnelDidChangeNotification object:t];
    }
    LRLog(@"stations", @"station selected");
    [self pingsChanged];
    if (!_embedded && !switchNow && ![t isOn]) [LRToast show:[NSString stringWithFormat:L(@"%@ selected"),
                                                              [[LRCatalog shared] displayNameForServer:sv]]];
}

- (void)tuneToAWG:(LRAWGProfile *)profile {
    LRTunnel *t = [LRTunnel shared];
    BOOL other = profile && ![profile.path isEqualToString:[[LRAWGProfiles active] path]];
    if (profile) [LRAWGProfiles setActive:profile];
    [LRPrefs setSelectedBackend:LRBackendAmneziaWG];
    if ([t isOn] && (t.activeBackend == LRBackendServer || other)) {
        [t disconnect];
        [t performSelector:@selector(startAWG) withObject:nil afterDelay:1.5];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:LRTunnelDidChangeNotification object:t];
    [self pingsChanged];
}

#pragma mark fastest

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

#pragma mark menus

- (void)showListMenu:(UIView *)anchor {
    LRCatalog *catalog = [LRCatalog shared];
    __block LRStationsScreen *me = self;
    LRMenu *menu = [LRMenu menuWithTitle:nil];
    if ([catalog.servers count])
        [menu addItem:L(@"Connect to the fastest") action:^{ [me connectFastestOf:[LRCatalog shared].servers]; }];
    if ([catalog pinging]) [menu addItem:L(@"Stop latency checks") action:^{ [[LRCatalog shared] cancelPings]; }];
    else [menu addItem:L(@"Check latency of all") action:^{ [[LRCatalog shared] pingAll]; }];
    if ([catalog.subscriptions count])
        [menu addItem:L(@"Update all subscriptions") action:^{
            [LRToast show:L(@"Updating subscriptions...")];
            [[LRCatalog shared] refreshAllSubscriptions:^(NSUInteger ok, NSUInteger failed) {
                NSString *msg = [NSString stringWithFormat:L(@"Subscriptions updated: %lu/%lu"),
                                 (unsigned long)ok, (unsigned long)(ok + failed)];
                if (failed) [LRToast showError:msg]; else [LRToast showSuccess:msg];
            }];
        }];
    NSArray *sorts = [NSArray arrayWithObjects:L(@"Sort: as added"), L(@"Sort: by name"), L(@"Sort: by latency"), nil];
    LRSortMode next = (LRSortMode)(([LRPrefs sortMode] + 1) % 3);
    [menu addItem:[sorts objectAtIndex:next] action:^{ [LRPrefs setSortMode:next]; }];
    [menu addItem:L(@"Arrange") action:^{ [me setArranging:YES]; }];
    BOOL anyOpen = NO;
    for (LRSection *sec in catalog.sections) if (![sec collapsed]) anyOpen = YES;
    [menu addItem:anyOpen ? L(@"Collapse all") : L(@"Expand all") action:^{
        for (LRSection *sec in [LRCatalog shared].sections) [[LRCatalog shared] setSection:sec collapsed:anyOpen];
        [me rebuild];
    }];
    [menu addItem:L(@"AmneziaWG profiles") action:^{ [me presentSheet:[[[LRAWGScreen alloc] init] autorelease]]; }];
    [menu showFromView:anchor];
}

- (void)longPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan || _arranging) return;
    NSIndexPath *ip = [_table indexPathForRowAtPoint:[g locationInView:_table]];
    if (!ip) return;
    NSDictionary *row = [self rowAt:ip];
    NSString *kind = [row objectForKey:@"kind"];
    UITableViewCell *cell = [_table cellForRowAtIndexPath:ip];
    if ([kind isEqualToString:@"plate"]) {
        LRSection *sec = [row objectForKey:@"section"];
        if (sec) [self showSectionMenu:sec from:cell];
        else [self presentSheet:[[[LRAWGScreen alloc] init] autorelease]];
    } else if ([kind isEqualToString:@"server"]) {
        [self showStationMenu:[row objectForKey:@"server"] from:cell];
    } else {
        LRAWGProfile *p = [row objectForKey:@"profile"];
        [self presentSheet:[[[LRAWGProfileScreen alloc] initWithProfile:p] autorelease]];
    }
}

- (void)openServerDetail:(LRServer *)sv {
    LRStationScreen *screen = [[[LRStationScreen alloc] initWithServer:sv] autorelease];
    if (_embedded) [self presentSheet:screen];
    else [self openScreen:screen];
}

- (void)openSubscription:(LRSubscription *)sub {
    LRSubscriptionScreen *screen = [[[LRSubscriptionScreen alloc] initWithSubscription:sub] autorelease];
    if (_embedded) [self presentSheet:screen];
    else [self openScreen:screen];
}

- (void)showStationMenu:(LRServer *)sv from:(UIView *)anchor {
    __block LRStationsScreen *me = self;
    NSString *name = [[LRCatalog shared] displayNameForServer:sv];
    LRMenu *menu = [LRMenu menuWithTitle:name];
    [menu addItem:[[LRTunnel shared] isOn] ? L(@"Switch to this server") : L(@"Connect")
           action:^{
        [LRPrefs setSelectedBackend:LRBackendServer];
        [[LRTunnel shared] connectServerIndex:sv.index];
    }];
    [menu addItem:L(@"Check latency") action:^{ [[LRCatalog shared] pingServers:[NSArray arrayWithObject:sv]]; }];
    [menu addItem:L(@"Details") action:^{ [me openServerDetail:sv]; }];
    [menu addItem:L(@"Share") action:^{
        [[LRDaemonClient shared] serverLinkIndex:sv.index reply:^(NSString *link) {
            if (!link) { [LRToast showError:L(@"The link could not be read")]; return; }
            LRShareScreen *share = [[[LRShareScreen alloc] initWithTitle:name payload:link] autorelease];
            share.subtitle = [sv protocolSummary];
            [me presentSheet:share];
        }];
    }];
    [menu addItem:L(@"Copy link") action:^{
        [[LRDaemonClient shared] serverLinkIndex:sv.index reply:^(NSString *link) {
            if (!link) { [LRToast showError:L(@"The link could not be read")]; return; }
            [UIPasteboard generalPasteboard].string = link;
            [LRToast showSuccess:L(@"Link copied")];
        }];
    }];
    if (sv.group < 0)
        [menu addDestructiveItem:L(@"Delete") action:^{
            [LRAlert confirmTitle:L(@"Delete Server") message:name button:L(@"Delete") destructive:YES action:^{
                [[LRDaemonClient shared] deleteServerIndex:sv.index reply:^(NSString *reply) {
                    if (LRReplyIsOK(reply)) {
                        LRLog(@"stations", @"station deleted");
                        [[LRCatalog shared] reload];
                    } else [LRToast showError:LRErrorFromReply(reply) ? LRErrorFromReply(reply) : L(@"Could not delete")];
                }];
            }];
        }];
    [menu showFromView:anchor];
}

- (void)showSectionMenu:(LRSection *)sec from:(UIView *)anchor {
    __block LRStationsScreen *me = self;
    LRMenu *menu = [LRMenu menuWithTitle:sec.title];
    LRSubscription *sub = sec.subscription;
    if (sub) {
        [menu addItem:L(@"Subscription info") action:^{ [me openSubscription:sub]; }];
        [menu addItem:L(@"Update now") action:^{
            [LRToast show:L(@"Updating subscription...")];
            [[LRDaemonClient shared] refreshSubscriptionIndex:sub.index reply:^(NSString *reply) {
                if (LRReplyIsOK(reply)) [LRToast showSuccess:LRTrim([reply substringFromIndex:MIN((NSUInteger)3, [reply length])])];
                else [LRToast showError:LRErrorFromReply(reply) ? LRErrorFromReply(reply) : L(@"Subscription update failed")];
                [[LRCatalog shared] reload];
            }];
        }];
    }
    if ([sec.servers count]) {
        [menu addItem:L(@"Connect to the fastest") action:^{ [me connectFastestOf:sec.servers]; }];
        [menu addItem:L(@"Check latency of this list") action:^{ [[LRCatalog shared] pingServers:sec.servers]; }];
    }
    NSUInteger at = [[LRCatalog shared].sections indexOfObjectIdenticalTo:sec];
    if (at != NSNotFound && at > 0)
        [menu addItem:L(@"Move up") action:^{ [[LRCatalog shared] moveSection:sec toPosition:at - 1]; }];
    if (at != NSNotFound && at + 1 < [[LRCatalog shared].sections count])
        [menu addItem:L(@"Move down") action:^{ [[LRCatalog shared] moveSection:sec toPosition:at + 1]; }];
    if (sub) {
        [menu addDestructiveItem:L(@"Delete Subscription") action:^{
            [LRAlert confirmTitle:L(@"Delete Subscription") message:sec.title button:L(@"Delete")
                      destructive:YES action:^{
                [[LRDaemonClient shared] deleteSubscriptionIndex:sub.index reply:^(NSString *reply) {
                    if (LRReplyIsOK(reply)) LRLog(@"subscriptions", @"subscription deleted");
                    else [LRToast showError:LRErrorFromReply(reply) ? LRErrorFromReply(reply) : L(@"Could not delete")];
                    [[LRCatalog shared] reload];
                }];
            }];
        }];
    } else if ([sec isManual] && [sec.servers count]) {
        [menu addDestructiveItem:L(@"Delete all manual servers") action:^{
            [LRAlert confirmTitle:L(@"Delete all manual servers")
                          message:L(@"Only manually added servers are removed. Subscriptions stay.")
                           button:L(@"Delete") destructive:YES action:^{
                [[LRDaemonClient shared] clearManualServers:^(NSString *reply) {
                    [[LRCatalog shared] reload];
                }];
            }];
        }];
    }
    [menu showFromView:anchor];
}
@end
