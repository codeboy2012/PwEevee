// The surface PwEevee's Downloads page talks to. PwEevee's tweak (spotifyglass.dylib) never links this library:
// it finds SAPPwEeveeBridge with NSClassFromString, so a build without the companion (another Spotify version,
// no patched executable) simply has no class and the page says downloads are not available.
#import <Foundation/Foundation.h>
#import "AudioProbeUI.h"
#import "DownloadCompatibility.h"
#import "Diagnostics.h"
#import "TrackDownload.h"
#import "TrackJournal.h"

__attribute__((visibility("default")))
@interface SAPPwEeveeBridge : NSObject
+ (NSInteger)interfaceVersion;
+ (NSDictionary *)snapshot;
+ (NSString *)downloadSummary;
+ (BOOL)downloadActive;
+ (void)downloadTrack;
+ (void)downloadAlbum;
+ (void)checkTrack;
+ (void)cancelDownload;
+ (void)sendLog;
+ (void)refreshJournal;
+ (BOOL)diagnosticsEnabled;
+ (void)setDiagnosticsEnabled:(BOOL)enabled;
+ (NSString *)compatibilityText:(NSDictionary *)report;
+ (void)refreshCompatibility:(void (^)(NSDictionary *))completion;
+ (void)previewSlots:(void (^)(NSDictionary *, NSString *))completion;
+ (void)releaseSlots:(NSString *)planID cacheIDs:(NSArray *)cacheIDs completion:(void (^)(NSDictionary *, NSString *))completion;
+ (void)enableOffline:(void (^)(NSDictionary *, NSString *))completion;
+ (void)restoreKeyMode:(void (^)(BOOL, NSString *))completion;
+ (void)loadDetails:(BOOL)journal completion:(void (^)(NSDictionary *))completion;
@end

@implementation SAPPwEeveeBridge
+ (NSInteger)interfaceVersion { return 1; }
+ (NSDictionary *)snapshot { return [SAPSettingsActions snapshot]; }
+ (NSString *)downloadSummary { return SAPTrackDownloadSummary(); }
+ (BOOL)downloadActive { return SAPTrackDownloadActive(); }
+ (void)downloadTrack { [SAPSettingsActions perform:SAPSettingsDownload]; }
+ (void)downloadAlbum { [SAPSettingsActions perform:SAPSettingsDownloadAlbum]; }
+ (void)checkTrack { [SAPSettingsActions perform:SAPSettingsVerify]; }
+ (void)cancelDownload { [SAPSettingsActions perform:SAPSettingsCancelDownload]; }
+ (void)sendLog { [SAPSettingsActions perform:SAPSettingsSendLog]; }
+ (void)refreshJournal { [SAPSettingsActions perform:SAPSettingsRefreshJournal]; }
+ (BOOL)diagnosticsEnabled { return SAPDiagnosticsEnabled(); }
+ (void)setDiagnosticsEnabled:(BOOL)enabled {
    BOOL before = SAPDiagnosticsEnabled();
    SAPDiagnosticsSetEnabled(enabled);
    SAPJournalNoteAction(@"diagnostics_changed", @{@"before": @(before), @"after": @(SAPDiagnosticsEnabled())});
}
+ (NSString *)compatibilityText:(NSDictionary *)report { return SAPDownloadCompatibilityText(report); }
+ (void)refreshCompatibility:(void (^)(NSDictionary *))completion { [SAPSettingsActions refreshDownloadCompatibility:completion]; }
+ (void)previewSlots:(void (^)(NSDictionary *, NSString *))completion { [SAPSettingsActions previewOfflineDeviceSlots:completion]; }
+ (void)releaseSlots:(NSString *)planID cacheIDs:(NSArray *)cacheIDs completion:(void (^)(NSDictionary *, NSString *))completion {
    [SAPSettingsActions releaseOfflineDeviceSlots:planID cacheIDs:cacheIDs completion:completion];
}
+ (void)enableOffline:(void (^)(NSDictionary *, NSString *))completion { [SAPSettingsActions enableOfflineOnCurrentDevice:completion]; }
+ (void)restoreKeyMode:(void (^)(BOOL, NSString *))completion { [SAPSettingsActions setKeyRequestMode:0 completion:completion]; }
+ (void)loadDetails:(BOOL)journal completion:(void (^)(NSDictionary *))completion { [SAPSettingsActions loadDetails:journal completion:completion]; }
@end
