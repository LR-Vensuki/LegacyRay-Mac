#import "LRAlert.h"

/* NSAlert answers sheets through a delegate selector until 10.9; this keeps
   the block alive until it does */
@interface LRAlertRunner : NSObject {
    void (^_done)(NSInteger);
    NSInteger _count;
}
- (id)initWithDone:(void (^)(NSInteger))done count:(NSInteger)count;
- (void)finish:(NSInteger)code;
@end

@implementation LRAlertRunner
- (id)initWithDone:(void (^)(NSInteger))done count:(NSInteger)count {
    if ((self = [super init])) {
        _done = [done copy];
        _count = count;
    }
    return self;
}

- (void)dealloc {
    [_done release];
    [super dealloc];
}

- (void)finish:(NSInteger)code {
    NSInteger index = code - NSAlertFirstButtonReturn;
    if (index < 0 || index >= _count) index = _count - 1;
    if (_done) _done(index);
}

- (void)alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)code contextInfo:(void *)info {
    [[alert window] orderOut:nil];
    [self finish:code];
    [self release];
}
@end

@implementation LRAlert

+ (void)runTitle:(NSString *)title message:(NSString *)message buttons:(NSArray *)buttons
       accessory:(NSView *)accessory window:(NSWindow *)window done:(void (^)(NSInteger))done {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:title ? title : @""];
    [alert setInformativeText:message ? message : @""];
    for (NSString *b in buttons) [alert addButtonWithTitle:b];
    /* escape picks the last key when it is a cancel */
    if ([buttons count] > 1) {
        NSButton *last = [[alert buttons] lastObject];
        if ([[last title] isEqualToString:L(@"Cancel")]) [last setKeyEquivalent:@"\033"];
    }
    if (accessory) [alert setAccessoryView:accessory];
    LRAlertRunner *runner = [[LRAlertRunner alloc] initWithDone:done count:(NSInteger)[buttons count]];
    NSWindow *host = window ? window : LRHostWindow();
    if (host && ![host attachedSheet]) {
        if (accessory) [[alert window] setInitialFirstResponder:
                        [accessory isKindOfClass:[NSTextField class]] ? accessory : nil];
        [alert beginSheetModalForWindow:host modalDelegate:runner
                         didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:NULL];
        if (accessory) [[alert window] makeFirstResponder:accessory];
        return;
    }
    LRActivateApp();
    if (accessory) {
        [alert layout];
        [[alert window] makeFirstResponder:accessory];
    }
    NSInteger code = [alert runModal];
    [runner finish:code];
    [runner release];
}

+ (void)showTitle:(NSString *)title message:(NSString *)message {
    [self runTitle:title message:message buttons:[NSArray arrayWithObject:L(@"OK")]
         accessory:nil window:nil done:nil];
}

+ (void)confirmTitle:(NSString *)title message:(NSString *)message button:(NSString *)button
         destructive:(BOOL)destructive action:(void (^)(void))action {
    [self confirmTitle:title message:message button:button destructive:destructive action:action cancel:nil];
}

+ (void)confirmTitle:(NSString *)title message:(NSString *)message button:(NSString *)button
         destructive:(BOOL)destructive action:(void (^)(void))action cancel:(void (^)(void))cancel {
    void (^yes)(void) = [[action copy] autorelease];
    void (^no)(void) = [[cancel copy] autorelease];
    [self runTitle:title message:message
           buttons:[NSArray arrayWithObjects:button ? button : L(@"OK"), L(@"Cancel"), nil]
         accessory:nil window:nil done:^(NSInteger index) {
        if (index == 0) { if (yes) yes(); }
        else if (no) no();
    }];
}

+ (void)promptTitle:(NSString *)title message:(NSString *)message placeholder:(NSString *)placeholder
               text:(NSString *)text button:(NSString *)button done:(void (^)(NSString *))done {
    NSTextField *field = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 22)] autorelease];
    [[field cell] setPlaceholderString:placeholder];
    [[field cell] setScrollable:YES];
    [[field cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    if (text) [field setStringValue:text];
    void (^callback)(NSString *) = [[done copy] autorelease];
    [self runTitle:title message:message
           buttons:[NSArray arrayWithObjects:button ? button : L(@"OK"), L(@"Cancel"), nil]
         accessory:field window:nil done:^(NSInteger index) {
        if (index == 0 && callback) callback([field stringValue]);
    }];
}
@end
