#import "LRForm.h"
#import "LRBlocks.h"
#import <objc/runtime.h>

NSPopUpButton *LRPopUp(NSArray *titles, NSInteger selected, void (^changed)(NSInteger)) {
    NSPopUpButton *p = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 200, 26) pullsDown:NO] autorelease];
    [p addItemsWithTitles:titles];
    /* two titles may read the same; addItemsWithTitles would fold them */
    if ((NSInteger)[p numberOfItems] != (NSInteger)[titles count]) {
        [p removeAllItems];
        for (NSString *t in titles) {
            [[p menu] addItemWithTitle:t action:NULL keyEquivalent:@""];
        }
    }
    if (selected >= 0 && selected < [p numberOfItems]) [p selectItemAtIndex:selected];
    else [p selectItem:nil];
    [p sizeToFit];
    if (changed) {
        void (^cb)(NSInteger) = [[changed copy] autorelease];
        [p lr_setBlock:^(id sender) { cb([sender indexOfSelectedItem]); }];
    }
    return p;
}

/* commits a text field when editing ends (return or leaving it) */
@interface LRFieldCommitter : NSObject <NSTextFieldDelegate> {
@public
    void (^commit)(NSString *);
    NSString *last;
}
@end

@implementation LRFieldCommitter
- (void)dealloc {
    [commit release];
    [last release];
    [super dealloc];
}
- (void)controlTextDidEndEditing:(NSNotification *)n {
    NSString *v = [[n object] stringValue];
    if ([v isEqualToString:last]) return;
    [last release];
    last = [v copy];
    if (commit) commit(v);
}
@end

@implementation LRForm

- (id)initWithWidth:(CGFloat)width labelWidth:(CGFloat)labelWidth {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, width, 100)])) {
        _width = width;
        _labelWidth = labelWidth;
        _y = 20;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (CGFloat)controlX {
    return 20 + _labelWidth + 8;
}

- (CGFloat)controlWidth {
    return _width - [self controlX] - 20;
}

- (NSView *)addLabel:(NSString *)label view:(NSView *)view height:(CGFloat)height {
    CGFloat h = MAX(height, NSHeight([view frame]));
    if ([label length]) {
        NSTextField *l = LRLabel([label hasSuffix:@":"] ? label : [label stringByAppendingString:@":"],
                                 [NSFont systemFontOfSize:13], nil);
        [l setAlignment:NSRightTextAlignment];
        /* the label's baseline sits on the control's */
        CGFloat ly = _y + ([view isKindOfClass:[NSPopUpButton class]] ? 4 :
                           [view isKindOfClass:[NSTextField class]] ? 2 :
                           [view isKindOfClass:[NSButton class]] ? 1 : 2);
        [l setFrame:NSMakeRect(20, ly, _labelWidth, 17)];
        [self addSubview:l];
    }
    NSRect f = [view frame];
    f.origin = NSMakePoint([self controlX] - ([view isKindOfClass:[NSPopUpButton class]] ? 3 : 0), _y);
    if (f.size.width > [self controlWidth] + 4) f.size.width = [self controlWidth];
    [view setFrame:f];
    [self addSubview:view];
    _y += h + 8;
    return view;
}

- (NSView *)addLabel:(NSString *)label view:(NSView *)view {
    return [self addLabel:label view:view height:NSHeight([view frame])];
}

- (NSView *)addView:(NSView *)view {
    return [self addLabel:nil view:view];
}

- (NSView *)addWideView:(NSView *)view height:(CGFloat)height {
    [view setFrame:NSMakeRect(20, _y, _width - 40, height)];
    [self addSubview:view];
    _y += height + 8;
    return view;
}

- (NSButton *)addCheckBox:(NSString *)title on:(BOOL)on changed:(void (^)(BOOL))changed {
    NSButton *b = LRCheckBox(title, on, changed);
    _y -= 2;
    [self addView:b];
    _y -= 2;
    return b;
}

- (NSPopUpButton *)addLabel:(NSString *)label popup:(NSArray *)titles selected:(NSInteger)selected
                    changed:(void (^)(NSInteger))changed {
    NSPopUpButton *p = LRPopUp(titles, selected, changed);
    [self addLabel:label view:p];
    return p;
}

- (NSTextField *)addLabel:(NSString *)label field:(NSString *)value placeholder:(NSString *)placeholder
                    width:(CGFloat)width commit:(void (^)(NSString *))commit {
    NSTextField *f = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, width, 22)] autorelease];
    [f setStringValue:value ? value : @""];
    [[f cell] setPlaceholderString:placeholder];
    [[f cell] setScrollable:YES];
    if (commit) {
        LRFieldCommitter *c = [[[LRFieldCommitter alloc] init] autorelease];
        c->commit = [commit copy];
        c->last = [[f stringValue] copy];
        [f setDelegate:c];
        /* the field does not retain its delegate */
        objc_setAssociatedObject(f, @selector(addLabel:field:placeholder:width:commit:), c,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [self addLabel:label view:f];
    return f;
}

- (NSTextField *)addNote:(NSString *)text {
    _y -= 4;
    NSTextField *n = LRWrappingLabel(text, [NSFont systemFontOfSize:11], [NSColor disabledControlTextColor],
                                     [self controlWidth]);
    [self addView:n];
    _y += 2;
    return n;
}

- (NSTextField *)addHeader:(NSString *)text {
    NSTextField *h = LRLabel(text, [NSFont boldSystemFontOfSize:13], nil);
    [h setFrame:NSMakeRect(20, _y, _width - 40, 17)];
    [self addSubview:h];
    _y += 17 + 8;
    return h;
}

- (void)addSeparator {
    _y += 4;
    NSBox *line = [[[NSBox alloc] initWithFrame:NSMakeRect(20, _y, _width - 40, 1)] autorelease];
    [line setBoxType:NSBoxSeparator];
    [self addSubview:line];
    _y += 13;
}

- (void)addSpace:(CGFloat)points {
    _y += points;
}

- (void)finish {
    [self setFrameSize:NSMakeSize(_width, _y + 12)];
}
@end
