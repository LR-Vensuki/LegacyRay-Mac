/* blocks for menu items and controls: the 10.8 sdk has target/action only */
#import <Cocoa/Cocoa.h>

@interface NSMenu (LRBlocks)
- (NSMenuItem *)lr_addItem:(NSString *)title block:(void (^)(void))block;
- (NSMenuItem *)lr_addItem:(NSString *)title key:(NSString *)key block:(void (^)(void))block;
- (void)lr_addSeparator;
@end

@interface NSControl (LRBlocks)
/* replaces target and action */
- (void)lr_setBlock:(void (^)(id sender))block;
@end

/* a push button the way aqua draws it (rounded, regular size) */
NSButton *LRPushButton(NSString *title, void (^block)(id sender));
/* a check box, a label, a small grey note that wraps */
NSButton *LRCheckBox(NSString *title, BOOL on, void (^block)(BOOL on));
NSTextField *LRLabel(NSString *text, NSFont *font, NSColor *color);
NSTextField *LRWrappingLabel(NSString *text, NSFont *font, NSColor *color, CGFloat width);
