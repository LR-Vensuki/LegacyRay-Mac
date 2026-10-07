/* a preferences pane laid out the way apple's were: right-aligned labels
   ending in a colon in the left column, controls left-aligned in the right
   one, small grey notes under them, rules between groups. rows stack from
   the top; -finish sizes the view to them */
#import <Cocoa/Cocoa.h>

@interface LRForm : NSView {
    CGFloat _width;
    CGFloat _labelWidth;
    CGFloat _y;
}
- (id)initWithWidth:(CGFloat)width labelWidth:(CGFloat)labelWidth;
@property (nonatomic, readonly) CGFloat controlX;
@property (nonatomic, readonly) CGFloat controlWidth;
/* a label in the left column and any view in the right one */
- (NSView *)addLabel:(NSString *)label view:(NSView *)view;
- (NSView *)addLabel:(NSString *)label view:(NSView *)view height:(CGFloat)height;
/* a view across the right column only, or across the whole pane */
- (NSView *)addView:(NSView *)view;
- (NSView *)addWideView:(NSView *)view height:(CGFloat)height;
- (NSButton *)addCheckBox:(NSString *)title on:(BOOL)on changed:(void (^)(BOOL on))changed;
- (NSPopUpButton *)addLabel:(NSString *)label popup:(NSArray *)titles selected:(NSInteger)selected
                    changed:(void (^)(NSInteger index))changed;
- (NSTextField *)addLabel:(NSString *)label field:(NSString *)value placeholder:(NSString *)placeholder
                    width:(CGFloat)width commit:(void (^)(NSString *value))commit;
- (NSTextField *)addNote:(NSString *)text;
- (NSTextField *)addHeader:(NSString *)text;
- (void)addSeparator;
- (void)addSpace:(CGFloat)points;
- (void)finish;
@end

/* a pop-up button of titles calling back with the index */
NSPopUpButton *LRPopUp(NSArray *titles, NSInteger selected, void (^changed)(NSInteger index));
