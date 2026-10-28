// The release channels a build can listen to. One channel is the build's at a time
// (a setting), every GitHub release belongs to at most one of them (a rule), and the
// two facts meet in Update.m, which stores each channel's last answer apart from the
// others'. This header carries just the model, no UIKit: the same file compiles into
// the tweak, and into the Mac-side test tool that pins the rules down.
//
// The channels, and where each release comes from. All of this is decided by the
// release's tag and title first, and GitHub's own prerelease flag second -- the flag
// has been seen left at false on a release whose tag says otherwise (v2.2.0-pre went
// out with prerelease:false), so the tag wins whatever the wire says:
//
//   Stable  -- published, not a draft, and no pre-release identifier anywhere in the
//              tag: nothing matching -alpha, -nightly, -beta, -pre or -rc. A release
//              rounded off enough to be recommended to everyone.
//   Alpha   -- the tag names alpha. Today v0.22.0-alpha and v0.22.0-alpha.2 are that line.
//   Nightly -- the tag names nightly (the convention would be nightly-<date>). No release
//              of the repo's is one yet, so the channel answers "nothing" until one
//              exists; it never guesses.
//   None    -- everything else a repo publishes: -pre, -beta, -rc releases are test
//              builds neither channel is meant to hand out, so they count for no
//              channel at all and are never claimed as an update.
//
// The tag alone decides: a title naming the channel does not. The whole source of the
// live release list sits behind one check for this -- v2.2.0-pre's title carries the
// words "0.22.0-alpha.2" (an upstream component's version), and v1.0.2's carries
// "0.23.0-beta"; both titles would pull their releases into channels they do not
// belong to. A release shipping under a -pre tag is a pre-release whatever the prose
// says, and a folder-name alpha carried in a title is not a channel.
//
// Version ordering, document as follows: the tag loses its leading v or its leading
// word (nightly-), the digits before the first dash are the release line ("2.2.0"),
// and whatever follows the dash is the identifier list ("pre", "alpha.2"). Line
// numbers compare piece by piece, a missing piece counting zero. A release line the
// same as another's outranks it while it has no identifiers, and identifiers rank
// nightly < alpha < beta < pre < rc, with a number after an identifier counting up
// from one and numbers outranking names (the semver rule). So 0.14.1 < 0.15, and
// 2.2.0-pre < 2.2.0, and 3.1.0-alpha.1 > 3.1.0-nightly.2.
//
// The version a build claims for itself is SG_VERSION, the public PwEevee version
// the build was cut at -- not any internal upstream line.
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SGUpdateChannel) {
    SGUpdateChannelStable  = 0,
    SGUpdateChannelNightly = 1,
    SGUpdateChannelAlpha   = 2,
};

// The channel the build listens to, as the setting left it; settings are validated on
// read, so anything unknown in defaults comes back Stable.
SGUpdateChannel SGUpdateChannelNow(void);

// Listen to another channel from now on. Nothing is refetched here and no cache is
// torn down -- the caller follows with SGCheckForUpdate(YES), which answers for the
// new channel and leaves the old channel's answer where it was.
void SGUpdateChannelSelect(SGUpdateChannel channel);

// The row's word and the line under it, for the three rows the Updates page offers.
NSString *SGUpdateChannelTitle(SGUpdateChannel channel);
NSString *SGUpdateChannelDetail(SGUpdateChannel channel);

// Which channel a release belongs to, out of what GitHub said about it. NSNotFound is
// the answer for everything none of the channels hands out: drafts, betas, pre and rc
// builds, and anything with a tag too malformed to read.
NSInteger SGUpdateChannelFor(BOOL draft, BOOL prerelease, NSString *tag, NSString *title);

// The bucket names the replies come back under, in the SGUpdateChannel enumeration order.
NSArray<NSString *> *SGUpdateChannelBucketNames(void);

// A GitHub Releases reply (the JSON of /releases) into one bucket per channel: keys are
// the bucket names above, values are the release entries that belong there, newest first
// and GitHub's own order standing among versions that tie. Each entry keeps version
// (the tag without its v), notes, date and url. nil when the reply is not a release list
// at all -- a malformed body, a wrong shape -- so the caller may store nothing rather
// than a guess.
NSDictionary *SGUpdateChannelsFromReleasesJSON(NSData *data);

// The version rules themselves -- the test tool calls these directly.
BOOL SGVersionIsPrerelease(NSString *version);
NSComparisonResult SGVersionCompare(NSString *a, NSString *b);   // -1 a is older, 0 even, +1 a is newer

// Each channel keeps its own last answer and its own last-checked time, so results
// from one channel can never masquerade as another's and a switch needs no expiry
// crash: the new channel simply reads its own, empty until a check lands for it.
NSArray<NSDictionary *> *SGUpdateChannelStoredList(SGUpdateChannel channel);   // nil: never checked
NSTimeInterval SGUpdateChannelCheckedAt(SGUpdateChannel channel);              // 0: never checked
void SGUpdateChannelStoreList(SGUpdateChannel channel, NSArray<NSDictionary *> *list);
void SGUpdateChannelNoteChecked(SGUpdateChannel channel);
