/* a key on the bar: the ios 6 bar button on the denim (dark glass in a
   pressed rim, a glyph or a word in white), a borderless word or glyph in
   the tint on yosemite. a menu, when set, drops from it on mouse down */
#import <Cocoa/Cocoa.h>

@interface LRBarKey : NSControl {
    NSString *_title;
    NSImage *_glyph;
    NSMenu *_dropMenu;
    BOOL _pressed;
    void (^_handler)(LRBarKey *key);
}
@property (nonatomic, copy) NSString *title;
@property (nonatomic, retain) NSImage *glyph;
@property (nonatomic, retain) NSMenu *dropMenu;
@property (nonatomic, copy) void (^handler)(LRBarKey *key);
+ (LRBarKey *)keyWithTitle:(NSString *)title handler:(void (^)(LRBarKey *key))handler;
+ (LRBarKey *)keyWithGlyph:(NSImage *)glyph handler:(void (^)(LRBarKey *key))handler;
/* the ink glyphs take on the bar */
+ (NSColor *)glyphInk;
- (CGFloat)preferredWidth;
@end
