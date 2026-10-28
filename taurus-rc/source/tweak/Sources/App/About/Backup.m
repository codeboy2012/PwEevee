#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "About.h"

static BOOL isSetting(NSString *key) {
    if (![key hasPrefix:@"spotifyglass."]) return NO;
    for (NSString *local in @[@"spotifyglass.adblock.counts", @"spotifyglass.privacy.counts", @"spotifyglass.update.",
                              @"spotifyglass.signing.", @"spotifyglass.onboarding.", @"spotifyglass.navbar.stock",
                              @"spotifyglass.redesign.navbar.stock", @"spotifyglass.flags.defaultOverridesSeeded"]) {
        if ([key hasPrefix:local]) return NO;
    }
    return YES;
}

static NSDictionary *storedDefaults(void) {
    return [NSUserDefaults.standardUserDefaults persistentDomainForName:NSBundle.mainBundle.bundleIdentifier] ?: @{};
}

static void showAlert(NSString *title, NSString *message, UIAlertAction *confirm) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    if (confirm) [alert addAction:confirm];
    [alert addAction:[UIAlertAction actionWithTitle:confirm ? @"Cancel" : @"OK" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

void SGExportSettings(void) {
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    [storedDefaults() enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if (isSetting(key) && [NSJSONSerialization isValidJSONObject:@[value]]) settings[key] = value;
    }];
    NSDictionary *file = @{
        @"mod": @(SG_VERSION),
        @"spotify": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown",
        @"settings": settings,
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:file options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"spotifyglass-settings.json"]];
    [data writeToURL:url atomically:YES];

    UIViewController *top = SGTopController();
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    sheet.popoverPresentationController.sourceView = top.view;
    [top presentViewController:sheet animated:YES completion:nil];
}

static Class kindOf(id value) {
    for (Class kind in @[NSNumber.class, NSString.class, NSArray.class, NSDictionary.class]) {
        if ([value isKindOfClass:kind]) return kind;
    }
    return Nil;
}

static void importSettings(NSDictionary *settings) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSDictionary *stored = storedDefaults();
    for (NSString *key in stored) {
        if (isSetting(key)) [store removeObjectForKey:key];
    }
    NSUInteger skipped = 0;
    for (NSString *key in settings) {
        id value = settings[key];
        id current = stored[key];
        BOOL fits = isSetting(key)
            && [NSPropertyListSerialization propertyList:value isValidForFormat:NSPropertyListBinaryFormat_v1_0]
            && (!current || kindOf(current) == kindOf(value));
        if (fits) [store setObject:value forKey:key];
        else skipped++;
    }
    SGLog(@"import: set %lu keys, skipped %lu", (unsigned long)(settings.count - skipped), (unsigned long)skipped);
    SGRestartSpotify();
}

@interface SGSettingsPicker : NSObject <UIDocumentPickerDelegate>
@end

@implementation SGSettingsPicker

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSData *data = [NSData dataWithContentsOfURL:urls.firstObject];
    id file = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSDictionary *settings = [file isKindOfClass:NSDictionary.class] ? file[@"settings"] : nil;
    if (![settings isKindOfClass:NSDictionary.class]) {
        showAlert(@"Not a settings file", @"Pick a file made by Export settings.", nil);
        return;
    }
    NSString *mod = [file[@"mod"] isKindOfClass:NSString.class] ? file[@"mod"] : @"unknown";
    NSString *message = [NSString stringWithFormat:@"Your settings are replaced by the file's, exported from version %@. Anything it does not have goes back to its default, and Spotify restarts.", mod];
    showAlert(@"Import settings?", message, [UIAlertAction actionWithTitle:@"Import and restart" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        importSettings(settings);
    }]);
}

@end

void SGImportSettings(void) {
    static SGSettingsPicker *delegate;
    if (!delegate) delegate = [SGSettingsPicker new];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
    picker.delegate = delegate;
    [SGTopController() presentViewController:picker animated:YES completion:nil];
}
