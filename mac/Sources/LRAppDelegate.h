/* the app: its menus, the main window, the menu bar item and every other
   window, opened on demand and kept while open. a menu bar app as much as a
   window app: closing the window leaves the tunnel and the menu bar item up */
#import <Cocoa/Cocoa.h>
#import "LRToast.h"

@class LRMainWindowController, LRStatusMenu, LRServer, LRSubscription, LRAWGProfile;

@interface LRAppDelegate : NSObject <NSApplicationDelegate, LRToastHost, NSMenuDelegate> {
    LRMainWindowController *_main;
    LRStatusMenu *_statusMenu;
    NSMutableDictionary *_windows;     /* name -> NSWindowController */
    NSMenuItem *_connectItem;
    BOOL _helperPrompted;
    BOOL _launched;
}
+ (LRAppDelegate *)shared;
- (NSWindow *)mainWindow;
- (LRMainWindowController *)mainController;

- (IBAction)showMainWindow:(id)sender;
- (IBAction)openPreferences:(id)sender;
- (IBAction)openCheck:(id)sender;
- (IBAction)openDiagnostics:(id)sender;
- (IBAction)openAWGProfiles:(id)sender;
- (IBAction)openOwnServers:(id)sender;
- (IBAction)openAbout:(id)sender;
- (IBAction)checkForUpdates:(id)sender;
- (IBAction)startDaemon:(id)sender;
- (IBAction)exportBackup:(id)sender;
- (IBAction)restoreBackup:(id)sender;

- (void)showServer:(LRServer *)server;
- (void)showSubscription:(LRSubscription *)subscription;
- (void)showAWGProfile:(LRAWGProfile *)profile;
- (void)shareServer:(LRServer *)server;
- (void)shareText:(NSString *)text title:(NSString *)title subtitle:(NSString *)subtitle;

/* a window controller by name, made once and kept until it closes */
- (id)windowNamed:(NSString *)name make:(id (^)(void))make;
- (void)forgetWindowNamed:(NSString *)name;

/* the helper check: installs or updates it when needed, then the daemon */
- (void)ensureHelper:(void (^)(BOOL ready))done;
/* a theme or language change rebuilds every window */
- (void)rebuildInterface;
@end
