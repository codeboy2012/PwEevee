// The saved composition of the redesign's bar, as NSUserDefaults property lists, apart from the native look's.
#import "Navbar.h"
#import "Shared/Navigation/Links.h"

NSString *const SGRNavbarID = @"id";
NSString *const SGRNavbarTitle = @"title";
NSString *const SGRNavbarURI = @"uri";
NSString *const SGRNavbarIcon = @"icon";
NSString *const SGRNavbarIconSet = @"iconSet";
NSString *const SGRNavbarCustomIcon = @"customIcon";
NSString *const SGRNavbarHidden = @"hidden";

static NSString *const kNavbarLayout = @"spotifyglass.redesign.navbar.layout";
static NSString *const kNavbarStock = @"spotifyglass.redesign.navbar.stock";
static NSString *const kNavbarRemovedStock = @"spotifyglass.redesign.navbar.removedStock";

// Only property list types go in, so a corrupt read cannot be anything but an array of dictionaries.
static NSArray *listOfKind(NSString *key, Class kind) {
    NSArray *list = [NSUserDefaults.standardUserDefaults arrayForKey:key];
    for (id item in list) if (![item isKindOfClass:kind]) return @[];
    return list ?: @[];
}

NSArray<NSDictionary *> *SGRNavbarLayout(void) {
    return listOfKind(kNavbarLayout, NSDictionary.class);
}

void SGRSetNavbarLayout(NSArray<NSDictionary *> *layout) {
    [NSUserDefaults.standardUserDefaults setObject:layout ?: @[] forKey:kNavbarLayout];
}

NSString *SGRNavbarDefaultIcon(NSString *stockID) {
    static NSDictionary<NSString *, NSString *> *icons;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        icons = @{
            @"home": @"home",
            @"search": @"search",
            @"your library": @"collection",
            @"library": @"collection",
            @"liked songs": @"heart",
            @"playlists": @"playlist",
            @"albums": @"album",
            @"artists": @"artist",
            @"podcasts": @"podcasts",
            @"audiobooks": @"audiobook",
            @"downloads": @"downloaded",
            @"your episodes": @"bookmark",
            @"browse": @"browse",
            @"new releases": @"star",
            @"made for you": @"user",
            @"concerts": @"events",
            @"queue": @"queue",
            @"create": @"plus",
        };
    });
    return icons[stockID.lowercaseString];
}

BOOL SGRNavbarEntryHasCustomIcon(NSDictionary *entry) {
    if ([entry[SGRNavbarCustomIcon] boolValue] || entry[SGRNavbarIconSet] != nil) return YES;
    id iconValue = entry[SGRNavbarIcon];
    if (![iconValue isKindOfClass:NSString.class]) return NO;
    NSString *icon = iconValue;
    NSString *defaultIcon = SGRNavbarDefaultIcon(entry[SGRNavbarID]);
    if (!icon.length || [icon isEqualToString:@"star"] || [icon isEqualToString:defaultIcon]) return NO;
    NSUInteger duplicates = 0;
    for (NSDictionary *candidate in SGRNavbarLayout()) {
        id candidateIcon = candidate[SGRNavbarIcon];
        if ([candidate[SGRNavbarID] isEqual:entry[SGRNavbarID]] || candidate[SGRNavbarURI]
            || candidate[SGRNavbarCustomIcon] || candidate[SGRNavbarIconSet] != nil
            || ![candidateIcon isKindOfClass:NSString.class] || ![candidateIcon isEqualToString:icon]) continue;
        if (![icon isEqualToString:SGRNavbarDefaultIcon(candidate[SGRNavbarID])]) duplicates++;
    }
    return duplicates == 0;
}

NSArray<NSString *> *SGRNavbarStock(void) {
    return listOfKind(kNavbarStock, NSString.class);
}

void SGRSetNavbarStock(NSArray<NSString *> *stock) {
    [NSUserDefaults.standardUserDefaults setObject:stock ?: @[] forKey:kNavbarStock];
}

NSArray<NSString *> *SGRNavbarRemovedStock(void) {
    return listOfKind(kNavbarRemovedStock, NSString.class);
}

void SGRSetNavbarRemovedStock(NSArray<NSString *> *stock) {
    [NSUserDefaults.standardUserDefaults setObject:stock ?: @[] forKey:kNavbarRemovedStock];
}

NSURL *SGRNavbarTabURL(NSString *uri) {
    NSURL *url = SGSpotifyURIFromText(uri);
    if ([url.absoluteString isEqualToString:@"spotify:collection:playlists"]) return [NSURL URLWithString:@"spotify:playlists"];
    return url;
}
