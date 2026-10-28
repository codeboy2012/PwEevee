// A local file's edit laid over what Spotify read from it (LocalFiles.h).
//
// -[SPTPlayerTrack metadata] is the one place: trackTitle, artistName, albumTitle and imageURL each read
// self.metadata and take title, artist_name, album_title and image_url from it (their code in the
// binary, through NSDictionary's spt_metadata_* in IDZKAdditions), and the player, the now playing bar
// and the system's now playing info are built from the player's track. So the names go in there, and
// the cover as an image address of the kind Spotify gives a local file, spotify:localfileimage:<path>.
//
// Spotify's loader hands such an address (three parts, no ipod-library in it) to
// SPTLocalAVAssetImageLoaderRequest, whose -loadLocalFileImage reads the cover out of the file at the
// path with AVAsset and passes its bytes to -dispatchSuccess:, which gives them to the delegate's
// imageLoaderRequest:didLoadImageData:. The request caches nothing (preventInMemoryCaching and
// preventPersistentCaching answer YES), so a stored cover is read from disk each time and passed on
// the same way. The system's now playing artwork is added too, in case Spotify fetches it apart.
#import <MediaPlayer/MediaPlayer.h>
#import "Core/SGCore.h"
#import "Headers/SPTLocalAVAssetImageLoaderRequest.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Player/NowPlayingExtras.h"
#import "Shared/Player/PlayerState.h"
#import "LocalFiles.h"

// Called for every track in every list many times a second: one prefix check for any other track.
static NSDictionary *withEdit(NSDictionary *metadata, NSString *uri) {
    NSDictionary *edit = SGLocalFileEditFor(uri);
    if (!edit) return metadata;
    NSMutableDictionary *edited = metadata ? [metadata mutableCopy] : [NSMutableDictionary dictionary];
    if ([edit[@"title"] length]) edited[@"title"] = edit[@"title"];
    if ([edit[@"artist"] length]) edited[@"artist_name"] = edit[@"artist"];
    if ([edit[@"album"] length]) edited[@"album_title"] = edit[@"album"];
    NSString *cover = SGLocalFileCoverURL(SGLocalFileCoverPath(edit));
    // Every size, since a reader may take any of them: Spotify's loader, and the redesign's artwork bridge
    // (Redesigned/Kit/SGRBridges.x), which reads the stored file itself.
    if (cover) {
        for (NSString *field in @[@"image_small_url", @"image_url", @"image_large_url", @"image_xlarge_url"]) edited[field] = cover;
    }
    return edited;
}

#pragma mark - the system's now playing artwork

@interface SGLocalFileNowPlaying : NSObject <SGPlayerStateObserver>
@end

@implementation SGLocalFileNowPlaying {
    NSString *_track;
}

// Spotify's info is matched by its title, which is the edited one when Spotify built it from the
// player's track and the file's own when it did not, so the artwork rides on either.
- (void)show:(SPTPlayerState *)state {
    NSString *uri = SGURIString(state.track.URI);
    NSString *path = SGLocalFileCoverPath(SGLocalFileEditFor(uri));
    UIImage *cover = path ? [UIImage imageWithContentsOfFile:path] : nil;
    if (!cover) {
        SGNowPlayingSetExtras(@"localFiles", nil, nil);
        SGNowPlayingSetExtras(@"localFiles.tags", nil, nil);
        return;
    }
    MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:cover.size requestHandler:^UIImage *(CGSize size) {
        return cover;
    }];
    SGNowPlayingSetExtras(@"localFiles", @{MPMediaItemPropertyArtwork: artwork}, SGLocalFileInfo(uri)[@"title"]);
    SGNowPlayingSetExtras(@"localFiles.tags", @{MPMediaItemPropertyArtwork: artwork}, SGLocalFileTags(uri)[@"title"]);
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *track = SGURIString(state.track.URI);
    if (!track || [track isEqualToString:_track]) return;
    _track = track;
    [self show:state];
}

- (void)editsChanged:(NSNotification *)note {
    if ([note.object isEqual:_track]) [self show:SGPlayerState()];
}

@end

#pragma mark - hooks

%hook SPTPlayerTrack
- (NSDictionary *)metadata {
    NSDictionary *metadata = %orig;
    NSString *uri = SGURIString(self.URI);
    return SGLocalFileIs(uri) ? withEdit(metadata, uri) : metadata;
}
%end

%hook SPTLocalAVAssetImageLoaderRequest
- (void)loadLocalFileImage {
    NSString *path = SGLocalFileCoverInURL(self.URL.absoluteString);
    if (!path) {
        %orig;
        return;
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        SGLog(@"local files: the cover %@ is gone, the track shows none", path.lastPathComponent);
        %orig;
        return;
    }
    [self dispatchSuccess:data];
}
%end

%ctor {
    %init;
    static SGLocalFileNowPlaying *nowPlaying;
    nowPlaying = [SGLocalFileNowPlaying new];
    SGAddPlayerStateObserver(nowPlaying);
    [NSNotificationCenter.defaultCenter addObserver:nowPlaying selector:@selector(editsChanged:) name:SGLocalFileEditsDidChangeNotification object:nil];
    SGRequireClasses(@[@"SPTPlayerTrack", @"SPTLocalAVAssetImageLoaderRequest"]);
}
