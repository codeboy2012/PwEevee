#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "About.h"
#import "App/Onboarding/Onboarding.h"
#import <dlfcn.h>

NSString *const SGSigningHelpURL = @"https://github.com/codeboy2012/PwEevee#3-signing";

static NSString *const kWarned = @"spotifyglass.signing.warned";
static BOOL sg_fixPending;

NSString *SGSigningAppIdentifier(void) {
    static NSString *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY);
        if (!security) return;
        CFTypeRef (*createFromSelf)(CFAllocatorRef) = dlsym(security, "SecTaskCreateFromSelf");
        CFTypeRef (*copyValue)(CFTypeRef, CFStringRef, CFErrorRef *) = dlsym(security, "SecTaskCopyValueForEntitlement");
        if (!createFromSelf || !copyValue) return;
        CFTypeRef task = createFromSelf(NULL);
        if (!task) return;
        CFTypeRef value = copyValue(task, CFSTR("application-identifier"), NULL);
        CFRelease(task);
        if (!value) return;
        if (CFGetTypeID(value) == CFStringGetTypeID()) {
            NSString *identifier = (__bridge NSString *)value;
            NSRange dot = [identifier rangeOfString:@"."];   // drop the team prefix
            cached = dot.location == NSNotFound ? [identifier copy]
                                               : [identifier substringFromIndex:dot.location + 1];
        }
        CFRelease(value);
    });
    return cached;
}

// Unreadable counts as fine: a guess here would cry wolf at a build that works.
BOOL SGSigningOpensFromLockScreen(void) {
    NSString *appID = SGSigningAppIdentifier();
    return !appID || [appID isEqualToString:NSBundle.mainBundle.bundleIdentifier];
}

static void showFix(void) {
    NSString *appID = SGSigningAppIdentifier();
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"?";
    UIViewController *top = SGTopController();
    if (!appID || !top) return;
    NSString *message = [NSString stringWithFormat:
        @"Sign Spotify again with the bundle id set to\n\n%@\n\n"
        @"In Feather that is the Identifier field; leave PPQ protection off, it appends a random "
        @"string and breaks this again.\n\n"
        @"Why: this build is installed as %@ but signed under the App ID %@. iOS opens the now "
        @"playing card by the App ID, so it asks for an app that is not there. Nothing else in the "
        @"mod is affected.", appID, bundleID, appID];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"The lock screen cannot open Spotify"
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy the bundle id" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = appID;
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Read more" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        SGOpenURL(SGSigningHelpURL);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:sheet animated:YES completion:nil];
}

// nil while the signature is sound, which is what keeps the row out of Mod Settings entirely.
SGModRow *SGSigningWarningRow(void) {
    if (SGSigningOpensFromLockScreen()) return nil;
    return SGWarningRow(@"The lock screen cannot open Spotify",
                        @"Tap for the fix",
                        ^{ showFix(); });
}

void SGCheckSigningOnce(void) {
    if (SGSigningOpensFromLockScreen()) return;
    if (SGFlag(SGKeyHideSigningWarning, NO)) return;
    NSString *appID = SGSigningAppIdentifier();
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    SGLog(@"signing: installed as %@ but signed under %@; the now playing card cannot open this build",
          NSBundle.mainBundle.bundleIdentifier, appID);
    if ([[store stringForKey:kWarned] isEqualToString:appID]) return;
    [store setObject:appID forKey:kWarned];

    // The first activation, plus a moment for Spotify's own start-up screens to get out of the way.
    __block id token = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                                      object:nil
                                                                       queue:nil
                                                                  usingBlock:^(NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:token];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // The welcome tour has the screen; it shows the fix when it goes.
            if (SGOnboardingShowing()) sg_fixPending = YES;
            else showFix();
        });
    }];
}

void SGShowSigningFixIfPending(void) {
    if (!sg_fixPending) return;
    sg_fixPending = NO;
    showFix();
}
