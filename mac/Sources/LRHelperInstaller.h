/* the privileged half of LegacyRay for os x: legacyrayd as a launchd daemon
   and its helpers in /usr/local/legacyray, installed from the app bundle
   through the authorization dialog the way mac apps did it before
   SMJobBless needed a developer id. the app reinstalls them whenever its
   bundle carries a different version than the one on disk */
#import <Foundation/Foundation.h>

typedef enum {
    LRHelperMissing = 0,
    LRHelperOutdated,      /* another version, or another account's */
    LRHelperReady
} LRHelperState;

@interface LRHelperInstaller : NSObject
+ (LRHelperState)state;
+ (NSString *)installedVersion;
+ (NSString *)bundledVersion;

/* explains, asks for the administrator password, installs. done runs on
   the main thread; cancelled is a NO with a nil error */
+ (void)installExplaining:(BOOL)explain done:(void (^)(BOOL ok, NSString *error))done;
/* purge also removes servers, subscriptions and settings */
+ (void)uninstallPurging:(BOOL)purge done:(void (^)(BOOL ok, NSString *error))done;
@end
