/* LegacyRay for os x: every objective-c file sees Cocoa, the os x
   compatibility helpers, the localization macro, the skin and the prefs.
   the shared core in app/Sources/Core is compiled with this same prefix */
#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import "LRCompat.h"
#import "LRLocalization.h"
#import "LRSkin.h"
#import "LRPrefs.h"
#endif
