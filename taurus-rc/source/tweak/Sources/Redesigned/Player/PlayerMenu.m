// Player redesign: the ⋯ opens the system menu (Redesigned/ContextMenu): Share, Add to playlist and Add to
// queue in a row at its top, then the player's own items here, then More with the rest of Spotify's rows. The
// player's items take over what Speed and pitch's block is on Spotify's sheet:
//
//     Speed, Pitch & Reverb   opens the sliders in a popover from the ⋯ (SGPlayerMenuSpeedPitch): speed,
//                             pitch, reverb and Pitch follows speed, as on Spotify's sheet (issue #14)
//     Lock Screen Style       chooses the lock screen's current artwork or Lyrics
//     Background Style        the six backgrounds offered in Player settings
//
// The item says under its name what is not as Spotify plays it, so the menu reads as a settings summary.
#import "Core/SGCore.h"
#import "Redesigned/ContextMenu/ContextMenu.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Player.h"

static __weak UIView *sg_moreButton;   // the ⋯ the sliders' panel comes from

static UIImage *symbol(NSString *name) {
    return [UIImage systemImageNamed:name];
}

static NSString *speedText(double speed) {
    NSString *text = [NSString stringWithFormat:@"%.2f", speed];
    while ([text hasSuffix:@"0"]) text = [text substringToIndex:text.length - 1];
    if ([text hasSuffix:@"."]) text = [text substringToIndex:text.length - 1];
    return [text stringByAppendingString:@"×"];
}

static NSString *semitonesText(float semitones) {
    if (semitones == 0) return @"Original";
    return [NSString stringWithFormat:@"%@%.0f %@", semitones > 0 ? @"+" : @"−", fabsf(semitones), fabsf(semitones) == 1 ? @"Semitone" : @"Semitones"];
}

// While pitch follows a speed that is not normal, the speed sets the pitch and the semitones are not played
// (SGTimePitch.h), so they stand aside, as on the sheet.
static BOOL pitchFollowing(void) {
    return SGPlayerSpeedAllowed() && SGPlayerPitchFollowsSpeed() && SGPlayerSpeed() != 1;
}

// One item for the three, which says what is not as Spotify plays it, or Normal.
static UIAction *soundMenu(void) {
    NSMutableArray<NSString *> *changed = [NSMutableArray array];
    if (SGPlayerSpeedAllowed() && fabs(SGPlayerSpeed() - 1) >= 0.01) [changed addObject:speedText(SGPlayerSpeed())];
    if (SGPlayerPitchAvailable() && !pitchFollowing() && SGPlayerPitch() != 0) [changed addObject:semitonesText(SGPlayerPitch())];
    // Speed/pitch not supported in this build
    return nil;
}

static UIMenu *backgroundStyleMenu(void) {
    NSArray<NSString *> *names = SGRPlayerBackgroundNames();
    SGRPlayerBackgroundKind current = SGRPlayerBackground();
    NSMutableArray<UIMenuElement *> *choices = [NSMutableArray arrayWithCapacity:names.count];
    for (NSUInteger index = 0; index < names.count; index++) {
        SGRPlayerBackgroundKind kind = (SGRPlayerBackgroundKind)index;
        UIAction *choice = [UIAction actionWithTitle:names[index]
                                               image:nil
                                          identifier:nil
                                             handler:^(UIAction *action) { SGRPlayerMenuSetBackground(kind); }];
        choice.state = kind == current ? UIMenuElementStateOn : UIMenuElementStateOff;
        [choices addObject:choice];
    }
    return [UIMenu menuWithTitle:@"Background Style"
                           image:symbol(@"circle.lefthalf.filled")
                      identifier:nil
                         options:UIMenuOptionsSingleSelection
                        children:choices];
}

static UIMenu *lockScreenStyleMenu(void) {
    NSString *current = SGLockScreenCurrentStarView();
    NSMutableArray<UIMenuElement *> *choices = [NSMutableArray array];
    for (NSString *view in SGLockScreenAvailableStarViews()) {
        UIAction *choice = [UIAction actionWithTitle:SGLockScreenStarViewName(view)
                                               image:nil
                                          identifier:nil
                                             handler:^(UIAction *action) {
            SGLockScreenStarSelectView(view);
        }];
        choice.state = [view isEqualToString:current] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [choices addObject:choice];
    }
    return [UIMenu menuWithTitle:@"Lock Screen Style"
                           image:symbol(@"star")
                      identifier:nil
                         options:UIMenuOptionsSingleSelection
                        children:choices];
}

static NSArray<UIMenuElement *> *playerItems(void) {
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    UIAction *sound = soundMenu();
    if (sound) [items addObject:sound];
    [items addObject:lockScreenStyleMenu()];
    [items addObject:backgroundStyleMenu()];
    return items;
}

// What the player is playing, from its URI (spotify:track:…, spotify:episode:…, spotify:local:…): a podcast's
// sheet has other rows than a song's.
static NSString *sheetKind(void) {
    NSArray<NSString *> *parts = [SGURIString(SGPlayerState().track.URI) componentsSeparatedByString:@":"];
    return parts.count > 2 ? parts[1] : @"";
}

void SGRPlayerMenuWatch(UIView *button) {
    sg_moreButton = button;
    SGRSystemMenuWatch(button, ^NSArray<UIMenuElement *> *{ return playerItems(); }, ^NSString *{ return sheetKind(); });
}
