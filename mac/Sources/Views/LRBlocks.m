#import "LRBlocks.h"
#import <objc/runtime.h>

@interface LRBlockTarget : NSObject {
    void (^_block)(id);
}
- (id)initWithBlock:(void (^)(id))block;
- (void)invoke:(id)sender;
@end

@implementation LRBlockTarget
- (id)initWithBlock:(void (^)(id))block {
    if ((self = [super init])) _block = [block copy];
    return self;
}
- (void)dealloc {
    [_block release];
    [super dealloc];
}
- (void)invoke:(id)sender {
    if (_block) _block(sender);
}
@end

static char kLRBlockKey;

@implementation NSMenu (LRBlocks)
- (NSMenuItem *)lr_addItem:(NSString *)title key:(NSString *)key block:(void (^)(void))block {
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:title ? title : @"" action:NULL
                                            keyEquivalent:key ? key : @""] autorelease];
    if (block) {
        void (^b)(void) = [[block copy] autorelease];
        LRBlockTarget *t = [[[LRBlockTarget alloc] initWithBlock:^(id sender) { b(); }] autorelease];
        objc_setAssociatedObject(item, &kLRBlockKey, t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [item setTarget:t];
        [item setAction:@selector(invoke:)];
    }
    [self addItem:item];
    return item;
}

- (NSMenuItem *)lr_addItem:(NSString *)title block:(void (^)(void))block {
    return [self lr_addItem:title key:nil block:block];
}

- (void)lr_addSeparator {
    [self addItem:[NSMenuItem separatorItem]];
}
@end

@implementation NSControl (LRBlocks)
- (void)lr_setBlock:(void (^)(id))block {
    LRBlockTarget *t = block ? [[[LRBlockTarget alloc] initWithBlock:block] autorelease] : nil;
    objc_setAssociatedObject(self, &kLRBlockKey, t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self setTarget:t];
    [self setAction:t ? @selector(invoke:) : NULL];
}
@end

NSButton *LRPushButton(NSString *title, void (^block)(id)) {
    NSButton *b = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 100, 32)] autorelease];
    [b setBezelStyle:NSRoundedBezelStyle];
    [b setTitle:title];
    [b setFont:[NSFont systemFontOfSize:13]];
    [b sizeToFit];
    NSRect f = [b frame];
    f.size.width = MAX(f.size.width + 10, 96);
    [b setFrame:f];
    if (block) [b lr_setBlock:block];
    return b;
}

NSButton *LRCheckBox(NSString *title, BOOL on, void (^block)(BOOL)) {
    NSButton *b = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 200, 18)] autorelease];
    [b setButtonType:NSSwitchButton];
    [b setTitle:title];
    [b setFont:[NSFont systemFontOfSize:13]];
    [b setState:on ? NSOnState : NSOffState];
    [b sizeToFit];
    if (block) {
        void (^cb)(BOOL) = [[block copy] autorelease];
        [b lr_setBlock:^(id sender) { cb([sender state] == NSOnState); }];
    }
    return b;
}

NSTextField *LRLabel(NSString *text, NSFont *font, NSColor *color) {
    NSTextField *l = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 17)] autorelease];
    [l setBezeled:NO];
    [l setDrawsBackground:NO];
    [l setEditable:NO];
    [l setSelectable:NO];
    [l setStringValue:text ? text : @""];
    [l setFont:font ? font : [NSFont systemFontOfSize:13]];
    if (color) [l setTextColor:color];
    [[l cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    [l sizeToFit];
    return l;
}

NSTextField *LRWrappingLabel(NSString *text, NSFont *font, NSColor *color, CGFloat width) {
    NSTextField *l = LRLabel(text, font ? font : [NSFont systemFontOfSize:11],
                             color ? color : [NSColor disabledControlTextColor]);
    [[l cell] setWraps:YES];
    [[l cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [l setPreferredMaxLayoutWidth:width];
    NSRect r = [[l cell] cellSizeForBounds:NSMakeRect(0, 0, width, 10000)].width > 0
        ? NSMakeRect(0, 0, width, [[l cell] cellSizeForBounds:NSMakeRect(0, 0, width, 10000)].height)
        : NSMakeRect(0, 0, width, 17);
    [l setFrame:r];
    return l;
}
