#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "About.h"
#import "App/Onboarding/Onboarding.h"

static void resetAll(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSUInteger removed = 0;
    for (NSString *key in [store persistentDomainForName:NSBundle.mainBundle.bundleIdentifier].allKeys) {
        if (![key hasPrefix:@"spotifyglass."]) continue;
        [store removeObjectForKey:key];
        removed++;
    }
    [store setBool:YES forKey:SGKeyStock];
    SGLog(@"reset: removed %lu keys", (unsigned long)removed);
    SGRestartSpotify();
}

static void confirmReset(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset all settings?"
                                                                  message:@"Every switch goes off, flag overrides and the tab bar layout are cleared, and Spotify restarts as it came, with the mod doing nothing until asked. Spotify's own settings are untouched."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset and restart" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { resetAll(); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static void clearStorage(void) {
    NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    if (!caches) {
        SGLog(@"storage: cache directory is unavailable");
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Storage could not be cleared"
                                                                       message:@"The tweak's cache directory could not be located."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
        return;
    }

    NSArray<NSString *> *relativePaths = @[
        @"spoti.pw/Motion", @"spoti.pw/Lyrics", @"spoti.pw/LockArtwork", @"spoti.pw/Translations",
        @"spoti.pw/AutoEq/INDEX.md", @"spoti.pw/AdBlock/live-config.txt",
    ];
    NSMutableArray<NSString *> *failures = [NSMutableArray array];
    NSUInteger removed = 0;
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSString *relativePath in relativePaths) {
        NSURL *url = caches;
        for (NSString *component in [relativePath componentsSeparatedByString:@"/"])
            url = [url URLByAppendingPathComponent:component];
        if (![files fileExistsAtPath:url.path]) continue;
        NSError *error = nil;
        if ([files removeItemAtURL:url error:&error]) removed++;
        else {
            [failures addObject:[NSString stringWithFormat:@"%@: %@", relativePath, error.localizedDescription ?: @"unknown error"]];
            SGLog(@"storage: could not remove %@ (%@)", relativePath, error);
        }
    }

    NSString *message = failures.count
        ? [NSString stringWithFormat:@"Removed %lu tweak cache item(s). Some files could not be removed:\n%@\n\nSpotify downloads and Spotify-owned caches were left untouched.",
           (unsigned long)removed, [failures componentsJoinedByString:@"\n"]]
        : [NSString stringWithFormat:@"Removed %lu tweak cache item(s). Spotify downloads and Spotify-owned caches were left untouched.",
           (unsigned long)removed];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:failures.count ? @"Some storage remains" : @"Storage cleared"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static void confirmClearStorage(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear cached files?"
                                                                  message:@"Remove downloaded artwork, lyrics and other nonessential tweak caches. Spotify downloads, Spotify-owned caches, settings and imported files are not touched."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear caches" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        clearStorage();
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static SGModRow *withSymbol(SGModRow *row, NSString *symbol) {
    row.symbol = symbol;
    return row;
}

// Build details, licenses, settings backup and reset.
UIViewController *SGAboutPage(void) {
    SGModRow *reset = withSymbol(SGActionRow(@"Reset all settings", nil, ^{ confirmReset(); }), @"trash");
    reset.color = SGRed();
    SGModRow *clear = withSymbol(SGActionRow(@"Clear cached files", nil, ^{ confirmClearStorage(); }), @"externaldrive");
    clear.color = SGRed();
    NSString *spotify = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
    SGModRow *updates = SGPageRow(@"Updates", ^UIViewController *{ return SGUpdatePage(); });
    updates.value = ^NSString *{ return SGUpdateStatus(); };
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObject:SGSection(nil, @[
        updates,
        SGStatRow(@"Version", ^NSString *{ return @(SG_VERSION); }),
        SGStatRow(@"Spotify", ^NSString *{ return spotify; }),
    ])];
    SGModRow *appIcon = SGAppIconRow();
    if (appIcon) [sections addObject:SGSection(nil, @[withSymbol(appIcon, @"app")])];
    [sections addObjectsFromArray:@[
        SGSection(nil, @[
            withSymbol(SGPageRow(@"Licenses", ^UIViewController *{ return SGLicensesPage(); }), @"doc.text"),
            withSymbol(SGPageRow(@"Device logs", ^UIViewController *{ return SGDeviceLogsPage(); }), @"list.bullet.rectangle"),
            withSymbol(SGActionRow(@"Welcome tour", nil, ^{ SGShowOnboarding(); }), @"map"),
        ]),
        SGSection(nil, @[
            withSymbol(SGActionRow(@"Export settings", nil, ^{ SGExportSettings(); }), @"square.and.arrow.up"),
            withSymbol(SGActionRow(@"Import settings", nil, ^{ SGImportSettings(); }), @"square.and.arrow.down"),
        ]),
        SGSection(nil, @[clear, reset]),
    ]];
    return [[SGModPage alloc] initWithTitle:@"Mod" intro:nil sections:sections footer:nil];
}
