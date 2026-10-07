/* alerts, confirmations and one-line prompts with the ios app's api, as
   NSAlert sheets on the main window (app modal when it is away). the shared
   core calls these, so the shapes match app/Sources/Controls/LRAlert.h */
#import <Cocoa/Cocoa.h>

@interface LRAlert : NSObject
+ (void)showTitle:(NSString *)title message:(NSString *)message;
+ (void)confirmTitle:(NSString *)title message:(NSString *)message button:(NSString *)button
         destructive:(BOOL)destructive action:(void (^)(void))action;
+ (void)confirmTitle:(NSString *)title message:(NSString *)message button:(NSString *)button
         destructive:(BOOL)destructive action:(void (^)(void))action cancel:(void (^)(void))cancel;
+ (void)promptTitle:(NSString *)title message:(NSString *)message placeholder:(NSString *)placeholder
               text:(NSString *)text button:(NSString *)button done:(void (^)(NSString *value))done;
/* the general shape: buttons left to right as the user reads them (first is
   the default), the answer is the index; a window may be given to sheet on */
+ (void)runTitle:(NSString *)title message:(NSString *)message buttons:(NSArray *)buttons
       accessory:(NSView *)accessory window:(NSWindow *)window done:(void (^)(NSInteger index))done;
@end
