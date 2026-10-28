// Where the karaoke page gets its lines and its clock. The color-lyrics body is copied as it passes
// the same URLSession delegates AdBlock/AdNetwork.x reads, untouched, and kept per track, since the
// page may open long after the request finished. The clock is SPTEsperantoPlayer's state, asked for on
// every frame: the player is caught the first time the app asks it, and its position runs on by itself.
// With a source of the mod's on, the color-lyrics body is Shared/LyricsSources' to answer and it
// hands the lines over.
#import "Core/SGCore.h"
#import "Core/SGURLSession.h"
#import "Lyrics.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/LocalFiles/LocalLyrics.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/Sing/SGSingController.h"
#import "Shared/Player/PlayerState.h"
#import "Headers/SPTPlayer.h"
#import <mach-o/dyld.h>
#import <objc/runtime.h>

static const NSUInteger kKeptTracks = 40;
static const NSUInteger kSeenTracks = 200;
// A track whose request was lost may be asked for again after this long, twice as long after each loss
// in a row up to the most: soon enough for the song still playing, not so soon that a busy server is pressed.
static const NSTimeInterval kRetryPause = 10, kRetryPauseMost = 60;
// What spclient needs from a request to answer it as the signed-in app.
static NSString *const kSpclientHeaders[] = {@"authorization", @"client-token", @"app-platform", @"spotify-app-version", @"user-agent", @"accept-language"};

static NSMutableDictionary<NSString *, NSArray<SGKaraokeLine *> *> *sg_lyrics;
static NSMutableSet<NSString *> *sg_requested;
// Of those, the ones with a request still out or waiting out its pause. A full cache spares their lines
// and leaves them asked for, so no second request runs beside the first.
static NSMutableSet<NSString *> *sg_asking;
static NSMutableDictionary<NSString *, NSNumber *> *sg_losses;   // requests lost in a row, by track
static NSMutableSet<NSString *> *sg_looking;   // asked of the sources or spclient right now (SGKaraokeLooking)
static NSMutableDictionary<NSString *, NSNumber *> *sg_requestGeneration;
static NSDictionary<NSString *, NSString *> *sg_spclientHeaders;
static NSMutableArray<void (^)(NSDictionary<NSString *, NSString *> *)> *sg_headersWaiting;   // SGSpclientHeaders
static __weak id sg_player;
// Every track the player has reported, by id, so a source can name a track that is not the one
// playing at the moment it is asked: a lyrics request routinely lands a beat before the player
// moves on to its track. The last object seen is kept by pointer so the check on each call is free,
// and its id behind it, since the player hands out a fresh object with every state it reports.
static NSMutableDictionary<NSString *, SPTPlayerTrack *> *sg_seenTracks;
static __weak SPTPlayerTrack *sg_lastSeen;
static NSString *sg_lastSeenID;   // the player makes a new track object on every state it reports, so the id is what tells a change
static BOOL sg_ownSources;   // a source of the mod's answers the color-lyrics request, not Spotify
static char kBodyKey;

static NSString *trackInURL(NSURL *url) {
    NSString *path = url.path;
    NSRange marker = [path rangeOfString:@"/color-lyrics/v2/track/"];
    if (marker.location == NSNotFound) return nil;
    NSString *track = [[path substringFromIndex:NSMaxRange(marker)] componentsSeparatedByString:@"/"].firstObject;
    return track.length ? track : nil;
}

static void rememberHeaders(NSURLSession *session, NSURLRequest *request) {
    if (![request.URL.host containsString:@"spclient"]) return;
    NSMutableDictionary<NSString *, NSString *> *all = [NSMutableDictionary dictionary];
    [session.configuration.HTTPAdditionalHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSString.class]) all[[key lowercaseString]] = value;
    }];
    [request.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        all[key.lowercaseString] = value;
    }];
    if (!all[@"authorization"]) return;
    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < sizeof(kSpclientHeaders) / sizeof(*kSpclientHeaders); i++) {
        NSString *name = kSpclientHeaders[i];
        if (all[name]) headers[name] = all[name];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        sg_spclientHeaders = headers;
        NSArray *waiting = sg_headersWaiting;
        sg_headersWaiting = nil;
        for (void (^waiter)(NSDictionary<NSString *, NSString *> *) in waiting) waiter(headers);
    });
}

void SGSpclientHeaders(void (^use)(NSDictionary<NSString *, NSString *> *headers)) {
    if (sg_spclientHeaders) {
        use(sg_spclientHeaders);
        return;
    }
    if (!sg_headersWaiting) sg_headersWaiting = [NSMutableArray array];
    [sg_headersWaiting addObject:[use copy]];
}

static SPTPlayerState *playerState(void);
static NSString *idOf(SPTPlayerTrack *track);

// The track after this one, when the player knows it.
static SPTPlayerTrack *upNextIn(SPTPlayerState *state) {
    id future = [state respondsToSelector:@selector(future)] ? state.future : nil;
    id next = [future isKindOfClass:NSArray.class] ? [(NSArray *)future firstObject] : nil;
    return [next isKindOfClass:objc_getClass("SPTPlayerTrack")] ? next : nil;
}

static BOOL hasTranslations(NSArray<SGKaraokeLine *> *lines) {
    for (SGKaraokeLine *line in lines) {
        if (line.translation.length) return YES;
    }
    return NO;
}

// Lines with no translation of their own take Musixmatch's community ones in the Lyrics page's language,
// whichever source they came from, Spotify's own included, matched by their text. Only the redesign shows
// translations, so the native look asks for none. The translated lines are copies kept in place of the
// lines: the lyrics view measures lines off the main thread, and a new array is what tells it to look.
// Musixmatch answers at once once it has answered, so lines kept again take the translations straight away.
static void translate(NSString *track) {
    NSString *language = SGRedesignedUI() ? SGLyricsTranslationLanguage() : nil;
    if (!language || hasTranslations(sg_lyrics[track])) return;
    SGMusixmatchTranslations(track, language, ^(NSDictionary<NSString *, NSString *> *byLine) {
        // Whatever is kept by now, which may be Spotify's timed lines in place of the plain ones asked for.
        NSArray<SGKaraokeLine *> *kept = sg_lyrics[track];
        if (!byLine || hasTranslations(kept)) return;
        NSArray<SGKaraokeLine *> *translated = SGMusixmatchTranslatedLines(kept, byLine);
        if (translated) sg_lyrics[track] = translated;
    });
}

NSNotificationName const SGKaraokeLinesDidChangeNotification = @"spotifyglass.karaoke.linesDidChange";

// The signed-in app's authorization, for a caller that needs to make its own spclient request.
NSString *SGKaraokeSpotifyAuthorization(void) {
    return sg_spclientHeaders[@"authorization"];
}

// Main queue only.
static void announce(NSString *track) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGKaraokeLinesDidChangeNotification object:track];
}

BOOL SGKaraokeLooking(NSString *trackID) {
    return trackID && [sg_looking containsObject:trackID];
}

// Main queue only. A full cache is emptied but for the track playing, the one up next and those still
// being asked for; what goes can be asked for again.
static void keep(NSString *track, NSArray<SGKaraokeLine *> *lines) {
    if (sg_lyrics.count >= kKeptTracks && !sg_lyrics[track]) {
        NSMutableSet<NSString *> *spared = [sg_asking mutableCopy];
        SPTPlayerState *state = playerState();
        NSString *playing = idOf(state.track), *next = idOf(upNextIn(state));
        if (playing) [spared addObject:playing];
        if (next) [spared addObject:next];
        for (NSString *kept in sg_lyrics.allKeys) {
            if ([spared containsObject:kept]) continue;
            [sg_lyrics removeObjectForKey:kept];
            [sg_requested removeObject:kept];
        }
    }
    sg_lyrics[track] = SGKaraokeInTimeOrder(lines);
    if (lines.count) translate(track);
    announce(track);
}

void SGKaraokeKeepLines(NSString *track, NSArray<SGKaraokeLine *> *lines) {
    dispatch_async(dispatch_get_main_queue(), ^{ keep(track, lines); });
}

static void received(NSURLSession *session, NSURLSessionTask *task, NSData *data) {
    rememberHeaders(session, SGURLSessionTaskRequest(task, NO));
    if (sg_ownSources || !trackInURL(SGURLSessionTaskURL(task))) return;
    NSMutableData *body = objc_getAssociatedObject(task, &kBodyKey);
    if (!body) objc_setAssociatedObject(task, &kBodyKey, (body = [NSMutableData data]), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [body appendData:data];
}

static void completed(NSURLSessionTask *task, NSError *error) {
    NSMutableData *body = objc_getAssociatedObject(task, &kBodyKey);
    if (!body) {
        NSString *path = SGURLSessionTaskURL(task).path;
        if (!sg_ownSources && [path.lowercaseString containsString:@"lyrics"]) SGLog(@"karaoke: lyrics request not read: %@ (error %@)", path, error);
        return;
    }
    objc_setAssociatedObject(task, &kBodyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSString *track = trackInURL(SGURLSessionTaskURL(task));
    if (error || !track) return;
    NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesFromBody(body);
    SGLog(@"karaoke: lyrics for %@, %lu bytes, %lu synced lines", track, (unsigned long)body.length, (unsigned long)lines.count);
    if (lines) SGKaraokeKeepLines(track, lines);
}

NSArray<SGKaraokeLine *> *SGKaraokeLinesForTrack(NSString *trackID) {
    return trackID ? sg_lyrics[trackID] : nil;
}

// Main queue only. The track stays asked for through the pause, so the readers asking on every tick
// send nothing until it is over.
static void askAgainLater(NSString *trackID) {
    NSUInteger losses = sg_losses[trackID].unsignedIntegerValue;
    NSUInteger generation = sg_requestGeneration[trackID].unsignedIntegerValue;
    sg_losses[trackID] = @(losses + 1);
    NSTimeInterval pause = MIN(kRetryPause * pow(2, losses), kRetryPauseMost);
    SGLog(@"karaoke: lyrics for %@ not answered, may ask again in %.0fs", trackID, pause);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(pause * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != sg_requestGeneration[trackID].unsignedIntegerValue) return;
        [sg_asking removeObject:trackID];
        [sg_requested removeObject:trackID];
    });
}

// Whether a loaded image has this file name; EeveeSpotify's Reincarnated fork also loads EeveeSwiftProtobuf.
static BOOL imageLoaded(NSString *wanted) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *image = _dyld_get_image_name(i);
        if (image && [@(image).lastPathComponent caseInsensitiveCompare:wanted] == NSOrderedSame) return YES;
    }
    return NO;
}

// Only loaded code counts, never a file's name: an IPA can keep EeveeSpotify's icons
// (EeveeSpotifyAnime@2x.png) after its dylib is gone. EeveeSpotify ships as EeveeSpotify.dylib, but an
// IPA builder can rename it (EeveeSpotify-6.6.dylib) or wrap it as EeveeSpotify.framework, so its Swift
// settings page, which every fork keeps under the module EeveeSpotify, counts as well. It may load after
// the mod, so a NO is asked again, though only once more images have loaded, and a YES is kept.
BOOL SGEeveeSpotifyInjected(void) {
    static BOOL found;
    static uint32_t looked;
    uint32_t images = _dyld_image_count();
    if (found || images == looked) return found;
    looked = images;
    if (imageLoaded(@"EeveeSpotify.dylib") || objc_getClass("_TtC12EeveeSpotify27EeveeSettingsViewController")) {
        found = YES;
        SGLog(@"lyrics: EeveeSpotify is injected");
    }
    return found;
}

// Whether EeveeSpotify answers Spotify's lyrics, read from its own settings in the standard defaults.
// It decides at launch and asks for a restart to change, so the first answer is kept. Anything not
// known to turn its lyrics off counts as on, a missing key and an unknown version included.
static BOOL eeveeLyricsOn(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        id source = [defaults objectForKey:@"lyricsSource"];      // 4 is "Do not replace lyrics"
        id patch = [defaults objectForKey:@"patchType"];          // Reincarnated: 0 not set, 1 off, 2 on
        BOOL sourceOff = [source isKindOfClass:NSNumber.class] && [source integerValue] == 4;
        BOOL unpatched = imageLoaded(@"EeveeSwiftProtobuf") && [patch isKindOfClass:NSNumber.class]
                      && ([patch integerValue] == 0 || [patch integerValue] == 1);
        on = !(getenv("EEVEE_DISABLE_ALL") || sourceOff || unpatched);
        SGLog(@"lyrics: EeveeSpotify's lyrics are %@ (lyricsSource %@, patchType %@)", on ? @"on" : @"off", source, patch);
    });
    return on;
}

BOOL SGLyricsStandAsideForEevee(void) {
    return SGEeveeSpotifyInjected() && eeveeLyricsOn() && !SGFlag(SGKeyLyricsBesideEevee, NO);
}

BOOL SGEeveeLyricsOn(void) {
    return SGEeveeSpotifyInjected() && eeveeLyricsOn();
}

// Main queue only. NO, asking nothing, before any request of Spotify's has shown the headers, and with
// EeveeSpotify injected, whose lyrics answer the request: a second asker beside it froze Spotify after launch.
static BOOL requestFromSpotify(NSString *trackID) {
    NSDictionary<NSString *, NSString *> *headers = sg_spclientHeaders;
    if (!headers || SGLyricsStandAsideForEevee()) return NO;
    [sg_requested addObject:trackID];
    [sg_asking addObject:trackID];
    [sg_looking addObject:trackID];
    NSUInteger generation = sg_requestGeneration[trackID].unsignedIntegerValue;
    NSString *address = [NSString stringWithFormat:@"https://spclient.wg.spotify.com/color-lyrics/v2/track/%@?format=json&vocalRemoval=false&market=from_token", trackID];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:address]];
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:name];
    }];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    // The mod's own, so LyricsHook's request hook does not send it to the donor.
    [NSURLProtocol setProperty:@YES forKey:SGLyricsOwnRequestKey inRequest:request];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *body, NSURLResponse *response, NSError *error) {
        NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesFromBody(body);
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        SGLog(@"karaoke: fetched lyrics for %@: status %ld, %lu lines (%@), error %@", trackID,
              (long)status, (unsigned long)lines.count,
              SGKaraokeLinesTiming(lines) == SGKaraokeTimingNone ? @"untimed" : @"line timed", error);
        // A refused authorization is lost too: the captured one may have expired, and Spotify's next
        // spclient request brings a fresh one.
        BOOL lost = SGLyricsReplyFailed(response, error) || status == 401 || status == 403;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != sg_requestGeneration[trackID].unsignedIntegerValue) return;
            [sg_looking removeObject:trackID];
            if (lost) {
                askAgainLater(trackID);
            } else {
                [sg_asking removeObject:trackID];
                [sg_losses removeObjectForKey:trackID];
                // Asked after the chain found plain text only: Spotify's replace it only when they are timed.
                NSArray<SGKaraokeLine *> *kept = sg_lyrics[trackID];
                if (lines && !(kept && SGKaraokeLinesTiming(kept) <= SGKaraokeLinesTiming(lines))) {
                    keep(trackID, lines);
                    SGLyricsSetCredit(trackID, @"Spotify");
                    return;
                }
            }
            announce(trackID);
        });
    }] resume];
    return YES;
}

void SGKaraokeAskSpotifyForTiming(NSString *trackID) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!trackID || [sg_requested containsObject:trackID]) return;
        requestFromSpotify(trackID);
    });
}

// A local file the sources had nothing for is asked again this many times, on askAgainLater's pauses:
// nothing may mean a request was lost, and LRCLIB asked alone cannot say which it was, so a song it has
// nothing for is not asked for every minute while it plays. ponytail: an outage longer than the pauses
// (about two minutes) leaves the file without lyrics until its names are edited or Spotify restarts; a
// source answer that tells "lost" from "none" would lift that.
static const NSUInteger kLocalTries = 4;

// With no source of the mod's switched on, a local file still gets LRCLIB, the open and keyless floor of
// the order, by the names it goes by: spclient has nothing for it, and without this the redesign's
// lyrics, the lock screen and the Live Activity would have nothing to show. Answers NO, asking nothing,
// when the file has no title and artist to search with.
static BOOL askLrcLib(NSString *trackID, void (^done)(SGLyricsResult *lyrics)) {
    NSDictionary *info = SGLocalFileInfo(trackID);
    SGLyricsProvider *lrclib = SGLyricsProviderFor(@"lrclib");
    if (!lrclib.ask || ![info[@"title"] length] || ![info[@"artist"] length]) return NO;
    SGLyricsQuery *query = [SGLyricsQuery new];
    query.trackID = trackID;
    query.title = info[@"title"];
    query.artist = info[@"artist"];
    query.album = info[@"album"];
    query.seconds = [info[@"seconds"] integerValue];
    SGLog(@"karaoke: no source is on, asking LRCLIB for the local file \"%@\" by \"%@\"", query.title, query.artist);
    lrclib.ask(query, ^(SGLyricsResult *lyrics) {
        if (lyrics.karaokeLines && !lyrics.provider) lyrics.provider = lrclib.name;
        done(lyrics);
    });
    return YES;
}

// Main queue only.
void SGKaraokeRequestLyrics(NSString *trackID) {
    if (!trackID || sg_lyrics[trackID] || [sg_requested containsObject:trackID]) return;
    // spclient has nothing for a local file, which only the sources can name. A file of the user's own,
    // linked to it or matching its names, comes before every source.
    BOOL local = SGLocalFileIs(trackID);
    BOOL selectedSource = SGLyricsProviderForTrack(trackID) != nil;
    SGLyricsResult *imported = local ? SGImportedLRCFor(trackID, nil, nil) : nil;
    if (imported && !selectedSource) {
        keep(trackID, imported.karaokeLines);
        SGLyricsSetCredit(trackID, imported.provider);
        return;
    }
    if (!sg_ownSources && !local && !selectedSource) {
        requestFromSpotify(trackID);
        return;
    }
    [sg_requested addObject:trackID];
    [sg_asking addObject:trackID];
    [sg_looking addObject:trackID];
    NSUInteger generation = sg_requestGeneration[trackID].unsignedIntegerValue;
    void (^answered)(SGLyricsResult *) = ^(SGLyricsResult *lyrics) {
        if (generation != sg_requestGeneration[trackID].unsignedIntegerValue) return;
        [sg_looking removeObject:trackID];
        if (lyrics.karaokeLines) {
            [sg_asking removeObject:trackID];
            [sg_losses removeObjectForKey:trackID];
            keep(trackID, lyrics.karaokeLines);   // on the main queue, where the sources answer
            SGLyricsSetCredit(trackID, lyrics.provider);
            // Plain text is shown while Spotify is asked whether it has the song timed; it has no local file.
            if (local || SGKaraokeLinesTiming(lyrics.karaokeLines) != SGKaraokeTimingNone) return;
        } else if (local) {
            // Asked again after a pause; a miss the sources keep answers at once then. An instrumental, or
            // a file out of tries, is left asked for: the readers ask on every tick, and an edit of its
            // names gives it a new key.
            if (!lyrics.instrumental && sg_losses[trackID].unsignedIntegerValue < kLocalTries) askAgainLater(trackID);
            else [sg_asking removeObject:trackID];
            announce(trackID);
            return;
        }
        if (selectedSource) {
            [sg_asking removeObject:trackID];
            [sg_requested removeObject:trackID];
            announce(trackID);
            return;
        }
        [sg_asking removeObject:trackID];
        [sg_requested removeObject:trackID];
        // Spotify is asked next, so the look goes on; with nothing to ask it with, it is over.
        if (!requestFromSpotify(trackID)) announce(trackID);
    };
    if (sg_ownSources || selectedSource) {
        SGLyricsFetch(trackID, answered);
    } else if (!askLrcLib(trackID, answered)) {
        [sg_asking removeObject:trackID];
        [sg_looking removeObject:trackID];
        announce(trackID);
    }

}

void SGKaraokeSetProviderForTrack(NSString *trackID, NSString *providerKey) {
    if (!trackID.length) {
        SGLog(@"karaoke: cannot set a source without a track id");
        return;
    }
    sg_requestGeneration[trackID] = @(sg_requestGeneration[trackID].unsignedIntegerValue + 1);
    SGLyricsSetProviderForTrack(trackID, providerKey);
    [sg_lyrics removeObjectForKey:trackID];
    [sg_requested removeObject:trackID];
    [sg_asking removeObject:trackID];
    [sg_looking removeObject:trackID];
    [sg_losses removeObjectForKey:trackID];
    SGKaraokeRequestLyrics(trackID);
}

id SGKaraokePlayer(void) {
    return sg_player;
}

static SPTPlayerState *playerState(void) {
    id player = sg_player;
    return [player respondsToSelector:@selector(state)] ? [(id<SPTPlayer>)player state] : nil;
}

NSString *SGKaraokePlayingTrack(void) {
    return idOf(playerState().track);
}

NSInteger SGKaraokePositionMs(void) {
    SPTPlayerState *state = playerState();
    if (!state) return -1;
    return (NSInteger)((state.isPaused ? state.positionAsOfTimestamp : state.position) * 1000);
}

NSInteger SGKaraokeDelayMs(void) {
    return SGInt(SGKeyLyricsDelay, 0);
}

void SGKaraokeSeek(NSInteger ms) {
    id player = sg_player;
    if (![player respondsToSelector:@selector(seekTo:)]) {
        SGLog(@"seek: to %ld ms, but no player to seek", (long)ms);
        return;
    }
    // Where it was and where it is half a second on, with Karaoke's lead and the correction it takes off, so the log
    // says whether a seek lands where it was sent.
    NSInteger before = SGKaraokePositionMs();
    [(id<SPTPlayer>)player seekTo:ms / 1000.0];
    SGLog(@"seek: to %ld ms (sent %.3f s to %@) from %ld ms; Sing state %lu", (long)ms, ms / 1000.0,
          [player class], (long)before, (unsigned long)SGSingCurrentState());
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGLog(@"seek: half a second after the seek to %ld ms the position reads %ld ms (%ld ms off)", (long)ms,
              (long)SGKaraokePositionMs(), (long)(SGKaraokePositionMs() - ms - 500));
    });
}

// A Spotify track by its base62 id, a local file by its URI (Shared/LocalFiles/LocalFiles.h).
static NSString *idOf(SPTPlayerTrack *track) {
    id uri = track.URI;
    NSString *text = [uri isKindOfClass:NSURL.class] ? ((NSURL *)uri).absoluteString : [uri description];
    return [text hasPrefix:@"spotify:track:"] ? [text substringFromIndex:@"spotify:track:".length] : SGLocalFileLyricsKey(text);
}

// Tracks come in from the player and from every list that reads their metadata, so when the table
// is full it is emptied, all but the track playing, whose name the next lyrics request needs.
static void remember(SPTPlayerTrack *track, NSString *trackID) {
    @synchronized (sg_seenTracks) {
        if (sg_seenTracks.count >= kSeenTracks) {
            [sg_seenTracks removeAllObjects];
            SPTPlayerTrack *playing = sg_lastSeen;
            NSString *playingID = playing ? idOf(playing) : nil;
            if (playingID) sg_seenTracks[playingID] = playing;
        }
        sg_seenTracks[trackID] = track;
    }
}

SPTPlayerTrack *SGKaraokeTrackFor(NSString *trackID) {
    if (!trackID) return nil;
    @synchronized (sg_seenTracks) { return sg_seenTracks[trackID]; }
}

void SGKaraokeRememberTrack(SPTPlayerTrack *track) {
    if (!sg_seenTracks) return;
    NSString *trackID = idOf(track);
    if (trackID) remember(track, trackID);
}

// With a source of the mod's on, the walk for a track starts the moment the player moves to it and,
// for the track after it, while this one still plays: Spotify asks for a track's lyrics within a
// beat of starting it and gives its card list about a second to load, so an answer that is already
// in is what puts the card there. The track is named here, so no walk waits for a name.
static void prefetch(SPTPlayerTrack *track, NSString *trackID, SPTPlayerState *state) {
    // Spotify never asks for a local file's lyrics, so they are asked for and kept here, a source of the
    // mod's on or not (SGKaraokeRequestLyrics). The state is read on any thread, and the kept lines are
    // the main queue's.
    BOOL local = SGLocalFileIs(trackID);
    if (local) dispatch_async(dispatch_get_main_queue(), ^{ SGKaraokeRequestLyrics(trackID); });
    if (!sg_ownSources) return;
    if (!local) SGLyricsPrefetch(trackID);
    SPTPlayerTrack *next = upNextIn(state);
    NSString *nextID = idOf(next);
    if (!nextID || [nextID isEqualToString:trackID]) return;
    remember(next, nextID);
    SGLyricsPrefetch(nextID);
}

// A state the player reported or was asked for: a new track is remembered and its walk begun. From the
// -state hook on any thread, and from the player's own reports on the main one.
static void seen(SPTPlayerState *state) {
    SPTPlayerTrack *track = state.track;
    if (!track || track == sg_lastSeen) return;
    NSString *trackID = nil;
    @synchronized (sg_seenTracks) {
        if (track == sg_lastSeen) return;
        sg_lastSeen = track;
        trackID = idOf(track);
        if (!trackID || [trackID isEqualToString:sg_lastSeenID]) return;
        sg_lastSeenID = trackID;
    }
    remember(track, trackID);
    prefetch(track, trackID, state);
}

// The -state hook runs only when something asks the player, which nothing may do with the app in the
// background and nothing on screen. The player's own reports come there too, so the next track's walk
// begins as it starts and its lines are in for the lock screen.
@interface SGKaraokeTrackWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGKaraokeTrackWatcher
- (void)playerStateDidChange:(SPTPlayerState *)state {
    seen(state);
}
@end

static SGKaraokeTrackWatcher *sg_trackWatcher;

%hook SPTEsperantoPlayer
- (id)state {
    if (!sg_player) sg_player = self;
    SPTPlayerState *state = %orig;
    seen(state);
    return state;
}
%end

%hook SPTDataLoaderService
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    received(session, task, data);
    %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    completed(task, error);
    %orig;
}
%end

%hook _TtC26Connectivity_HttpClientKit20HttpClientURLSession
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    received(session, task, data);
    %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    completed(task, error);
    %orig;
}
%end

// With nothing of the karaoke's on, the headers are still read for SGSpclientHeaders' other askers
// (Native iOS Music Haptics, which can be picked at any moment).
%group SGSpclientHeadersOnly
%hook SPTDataLoaderService
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    rememberHeaders(session, SGURLSessionTaskRequest(task, NO));
    %orig;
}
%end

%hook _TtC26Connectivity_HttpClientKit20HttpClientURLSession
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    rememberHeaders(session, SGURLSessionTaskRequest(task, NO));
    %orig;
}
%end
%end

%ctor {
    // The sources that search by name learn the name from the player, so the player is caught
    // whenever one is on, not only for the redesign's lyrics and the lock screen.
    if (!SGRedesignedUI() && !SGFlag(SGKeyLockScreenLyrics, NO) && !SGLyricsEnabled()
        && SGLockScreenEffectiveArtwork() != SGLockArtworkLyrics
        && !(SGLockScreenCanvasLyricsEnabled() && SGLockArtworkHasMotion(SGLockScreenEffectiveArtwork()))) {
        %init(SGSpclientHeadersOnly);
        return;
    }
    sg_seenTracks = [NSMutableDictionary dictionary];
    sg_lyrics = [NSMutableDictionary dictionary];
    sg_requested = [NSMutableSet set];
    sg_asking = [NSMutableSet set];
    sg_requestGeneration = [NSMutableDictionary dictionary];
    sg_losses = [NSMutableDictionary dictionary];
    sg_looking = [NSMutableSet set];
    sg_ownSources = SGLyricsEnabled();
    // A rename gives the file playing a new lyrics key at once, with no new state from the player to
    // bring it here, so the new key is asked for now; the redesign's lyrics view shows what comes in.
    // Posted on the main thread.
    [NSNotificationCenter.defaultCenter addObserverForName:SGLocalFileEditsDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        NSString *key = SGLocalFileLyricsKey(note.object);
        if (key && [key isEqualToString:SGKaraokePlayingTrack()]) SGKaraokeRequestLyrics(key);
    }];
    // An imported or deleted LRC file can change any local file's lyrics, found or missed: they are
    // forgotten, but for a look still out, and the file playing is asked for again.
    [NSNotificationCenter.defaultCenter addObserverForName:SGImportedLRCDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        for (NSString *track in [sg_requested setByAddingObjectsFromArray:sg_lyrics.allKeys]) {
            if (!SGLocalFileIs(track) || [sg_looking containsObject:track]) continue;
            [sg_lyrics removeObjectForKey:track];
            [sg_requested removeObject:track];
            [sg_asking removeObject:track];
            [sg_losses removeObjectForKey:track];
        }
        NSString *playing = SGKaraokePlayingTrack();
        if (!SGLocalFileIs(playing)) return;
        SGKaraokeRequestLyrics(playing);
        announce(playing);
    }];
    // Spotify asks for a track's lyrics only while a page of its own shows them, so a track the player
    // moved on to in the background came back to the app with none, and the redesign's lyrics, which
    // ask for nothing themselves, stayed empty. They are asked for here as the app becomes active again,
    // which also follows Control Center, a call or Siri without the background.
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        NSString *playing = SGKaraokePlayingTrack();
        if (playing && !sg_lyrics[playing] && !SGKaraokeLooking(playing)) SGKaraokeRequestLyrics(playing);
    }];
    sg_trackWatcher = [SGKaraokeTrackWatcher new];
    SGAddPlayerStateObserver(sg_trackWatcher);
    %init;
    SGLog(@"karaoke: on");
    SGRequireClasses(@[
        @"SPTEsperantoPlayer", @"SPTPlayerState",
        @"SPTDataLoaderService", @"_TtC26Connectivity_HttpClientKit20HttpClientURLSession",
    ]);
}
