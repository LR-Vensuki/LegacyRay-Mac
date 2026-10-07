/* the os x face of app/Sources/Core/LRReminders.h: scheduled notifications in
   notification center (10.8+) a few days before a subscription runs out */
#import "LRReminders.h"
#import "LRModels.h"

#define LR_REMINDER_KEY @"lr-subscription"

@implementation LRReminders

+ (id)center {
    Class cls = NSClassFromString(@"NSUserNotificationCenter");
    return cls ? [cls performSelector:@selector(defaultUserNotificationCenter)] : nil;
}

+ (BOOL)enabled {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"LRSubReminders"];
    return v ? [v boolValue] : YES;
}

+ (void)setEnabled:(BOOL)on {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"LRSubReminders"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (!on) [self cancelAll];
}

+ (void)cancelAll {
    NSUserNotificationCenter *center = [self center];
    for (NSUserNotification *n in [center scheduledNotifications])
        if ([[n userInfo] objectForKey:LR_REMINDER_KEY]) [center removeScheduledNotification:n];
}

/* noon on the day, days before the expiry */
+ (NSDate *)noonDaysBefore:(NSInteger)days expiry:(NSDate *)expiry {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit
                                 fromDate:[expiry dateByAddingTimeInterval:-days * 86400.0]];
    [c setHour:12];
    return [cal dateFromComponents:c];
}

+ (void)scheduleForSubscriptions:(NSArray *)subscriptions {
    NSUserNotificationCenter *center = [self center];
    if (!center) return;
    [self cancelAll];
    if (![self enabled]) return;
    NSDate *now = [NSDate date];
    for (LRSubscription *sub in subscriptions) {
        if (!sub.expire) continue;
        NSDate *expiry = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)sub.expire];
        if ([expiry timeIntervalSinceDate:now] <= 0) continue;
        NSString *name = [sub.name length] ? sub.name : L(@"Subscription");
        for (NSNumber *d in [NSArray arrayWithObjects:[NSNumber numberWithInt:3], [NSNumber numberWithInt:1], nil]) {
            NSDate *fire = [self noonDaysBefore:[d integerValue] expiry:expiry];
            if ([fire timeIntervalSinceDate:now] <= 60) continue;
            NSUserNotification *n = [[[NSUserNotification alloc] init] autorelease];
            [n setTitle:@"LegacyRay"];
            [n setInformativeText:[d intValue] == 1
                ? [NSString stringWithFormat:L(@"The subscription “%@” ends tomorrow."), name]
                : [NSString stringWithFormat:L(@"The subscription “%@” ends in %d days."), name, [d intValue]]];
            [n setDeliveryDate:fire];
            [n setSoundName:NSUserNotificationDefaultSoundName];
            [n setUserInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:sub.index]
                                                       forKey:LR_REMINDER_KEY]];
            [center scheduleNotification:n];
        }
    }
}
@end
