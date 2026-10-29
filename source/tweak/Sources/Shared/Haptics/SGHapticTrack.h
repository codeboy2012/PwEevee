// The pure steps of Music Haptics In the Background (SystemMusicHaptics.x), Foundation only so the Mac harness
// (harness/haptics/track.m) runs them as the tweak does.
//
// Spotify's ISRC comes from its own metadata, asked as the app asks it: a BatchedEntityRequest to spclient's
// extended-metadata with one entity and the TRACK_V4 extension, answered by a BatchedExtensionResponse whose
// entry holds the track's spotify.metadata.Track in a google.protobuf.Any. The field numbers are the ones
// in the descriptors Spotify 9.1.78's binary carries (extended_metadata.proto, entity_extension_data.proto,
// extension_kind.proto, metadata.proto). Apple's song is the one of its catalog's answers that is the same
// recording: the same ISRC, the same length within kHapticLengthSlack, and a haptic track.
#import <Foundation/Foundation.h>

// Milliseconds two lengths of one recording may differ by.
static const double kHapticLengthSlack = 2000;

// The code uppercased when it is an ISRC: two letters, three letters or digits, seven digits. Else nil.
NSString *SGHapticISRC(NSString *code);
// YES for spotify:track: and a 22-character base62 id, the only kind of URI with an ISRC to ask for.
BOOL SGHapticIsTrackURI(NSString *uri);
// The body of the extended-metadata request for one track's Track message.
NSData *SGHapticTrackRequest(NSString *trackURI);
// The ISRC in a reply to SGHapticTrackRequest(trackURI), or nil. `answered` says the reply did hold the track's
// Track message, with a 200 status for it, so a nil ISRC is final; NO means it may be worth asking again.
NSString *SGHapticISRCInReply(NSData *reply, NSString *trackURI, BOOL *answered);
// The catalog id of the song among Apple's (the data array of /v1/catalog/{storefront}/songs) that is the
// recording `isrc` names and is `ms` long, with a haptic track. Nil when none is.
NSString *SGHapticSongIn(NSArray *songs, NSString *isrc, double ms);
