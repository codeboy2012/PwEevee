#import <UIKit/UIKit.h>

#define SGKeyBlockTelemetry @"spotifyglass.blockTelemetry"
#define SGKeyCleanLinks @"spotifyglass.cleanLinks"

NSArray<NSString *> *SGBlockedLabels(void);
NSUInteger SGBlockedCount(NSString *label);
void SGResetBlocked(void);

// Clean shared links (CleanLinks.m): the tracking Spotify adds to the open.spotify.com links it copies and shares.
NSURL *SGCleanLinkURL(NSURL *url);
NSString *SGCleanLinksInText(NSString *text);
id SGCleanLinkObject(id object);

@class SGModSection;
// The telemetry switch and what it has stopped, on the Premium, ads & privacy page.
SGModSection *SGPrivacySection(void);
SGModSection *SGPrivacyCountersSection(void);
