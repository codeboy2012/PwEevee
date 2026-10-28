// Upcoming concerts of an artist, read from Songkick's public pages: no account, no key.
// The redesigned artist page draws them (Redesigned/Artist/ArtistConcerts.m).
#import <UIKit/UIKit.h>
#import "Settings/SGModPage.h"

#define SGKeyConcerts @"spotifyglass.concerts"

@interface SGConcert : NSObject
@property (nonatomic, copy) NSString *identifier, *title, *venue, *city, *country, *ticketURL;
@property (nonatomic, copy) NSString *status;          // onsale, offsale, postponed, rescheduled
@property (nonatomic, strong) NSDate *date;            // the start, or noon of the day when no time is set
@property (nonatomic, strong) NSTimeZone *zone;        // the venue's
@property (nonatomic) BOOL hasTime;
@end

// The concerts of the artist, soonest first, on the main queue. The artist's name has to match the source's
// record of it (`artistID`, the Spotify id, is not used). An artist with none and a failed request both
// answer an empty array. Kept 6 hours.
void SGConcertsFetch(NSString *artistName, NSString *artistID, void (^done)(NSArray<SGConcert *> *concerts));

// What the card and the list say, in the language the app runs in (ConcertsStrings.m).
typedef NS_ENUM(NSInteger, SGConcertText) {
    SGConcertTextUpcoming,   // Upcoming Concerts
    SGConcertTextConcerts,   // Concerts
    SGConcertTextTickets,    // Tickets
};
NSString *SGConcertString(SGConcertText text);
// The locale the app's language names, for dates and numbers.
NSLocale *SGConcertLocale(void);
// "Concerts · 7" in that language, without a plural form to get wrong.
NSString *SGConcertCountLine(NSUInteger count);
// A date as the venue's clock shows it: month abbreviated (MMM), day (d), weekday (EEE), time (HH:mm).
NSString *SGConcertFormat(SGConcert *concert, NSString *template);
// The mark of the card, white on clear, as a template image.
UIImage *SGConcertsLogo(void);
