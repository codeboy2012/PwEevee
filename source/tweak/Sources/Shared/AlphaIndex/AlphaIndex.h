// The alphabet along the edge of a long playlist: a Liquid Glass capsule with A to Z and # in it. A finger
// dragged down it lights the letter with a glass lens, raises a glass bubble with the letter beside it, and
// jumps the list to the first row starting with that letter. A letter no row starts with is dimmed and skipped,
// to the next one that has rows. Only playlists and mixes (the playlist page) get it. Works with either look.
#import <UIKit/UIKit.h>
#import "Settings/SGModPage.h"

#define SGKeyAlphaIndex @"spotifyglass.alphaindex"

// A row's layoutSubviews tells the index it exists; the list the row is in gets the bar when it is a long,
// vertical list of titled rows.
void SGAlphaIndexNoteRow(UIView *row);

// The letter a title is filed under: A to Z with accents and case folded, # for digits and every other script.
NSString *SGAlphaIndexLetter(NSString *title);

// The colour of the bar's letters: the look's accent. Declared here, defined in App/ where both looks are known.
UIColor *SGAlphaIndexColor(void);

SGModRow *SGAlphaIndexRow(void);
