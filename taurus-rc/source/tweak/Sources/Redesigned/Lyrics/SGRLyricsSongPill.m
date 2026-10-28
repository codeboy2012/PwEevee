// The glass player pill above the Lyrics page's preview: a play button and a search field. A song typed
// in is looked up on LRCLIB (open, no key), the matches listed over the preview, and the one tapped sets
// its lines going in the preview, so the look can be tried on any song, not only the sample's.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "LyricsLook.h"
#import "Shared/LyricsSources/LyricsSources.h"

static const CGFloat kRowHeight = 52;
static const NSInteger kMostResults = 6;

@interface SGRLyricsResultsList : UIView <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSArray<NSDictionary *> *songs;
@property (nonatomic, copy) void (^chose)(NSDictionary *song);
@end

@implementation SGRLyricsResultsList {
    UITableView *_table;
    UIVisualEffectView *_glass;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.layer.cornerRadius = 26;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;
    UIVisualEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    if (@available(iOS 26.0, *)) effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
    _glass = [[UIVisualEffectView alloc] initWithEffect:effect];
    _glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_glass];
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.backgroundColor = UIColor.clearColor;
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = kRowHeight;
    _table.separatorColor = [UIColor colorWithWhite:1 alpha:0.12];
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_table];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _glass.frame = self.bounds;
    _table.frame = self.bounds;
}

- (void)setSongs:(NSArray<NSDictionary *> *)songs {
    _songs = [songs copy];
    [_table reloadData];
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return MAX((NSInteger)_songs.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"song"] ?:
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"song"];
    cell.backgroundColor = UIColor.clearColor;
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.55];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    if (!_songs.count) {
        cell.textLabel.text = @"No songs with lyrics found";
        cell.detailTextLabel.text = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSDictionary *song = _songs[(NSUInteger)path.row];
    cell.textLabel.text = song[@"trackName"];
    cell.detailTextLabel.text = song[@"artistName"];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (_songs.count && _chose) _chose(_songs[(NSUInteger)path.row]);
}

@end

@interface SGRLyricsSongPill () <UITextFieldDelegate>
@end

@implementation SGRLyricsSongPill {
    UIVisualEffectView *_glass;
    UIButton *_play;
    UITextField *_field;
    SGRLyricsResultsList *_results;
    NSURLSessionDataTask *_task;
    NSUInteger _asked;
    BOOL _playing;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UIVisualEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    if (@available(iOS 26.0, *)) {
        UIGlassEffect *glass = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
        glass.interactive = YES;
        effect = glass;
    }
    _glass = [[UIVisualEffectView alloc] initWithEffect:effect];
    _glass.clipsToBounds = YES;
    _glass.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:_glass];

    _playing = YES;
    _play = [UIButton buttonWithType:UIButtonTypeSystem];
    _play.tintColor = UIColor.whiteColor;
    _play.accessibilityLabel = @"Pause preview";
    [_play addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventPrimaryActionTriggered];
    [_glass.contentView addSubview:_play];
    [self showPlayIcon];

    _field = [UITextField new];
    _field.textColor = UIColor.whiteColor;
    _field.tintColor = UIColor.whiteColor;
    _field.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    _field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Search a song to preview"
        attributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.5]}];
    _field.returnKeyType = UIReturnKeySearch;
    _field.autocorrectionType = UITextAutocorrectionTypeNo;
    _field.clearButtonMode = UITextFieldViewModeWhileEditing;
    UIImageView *glass = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]];
    glass.tintColor = [UIColor colorWithWhite:1 alpha:0.6];
    glass.frame = CGRectMake(0, 0, 28, 20);
    glass.contentMode = UIViewContentModeCenter;
    _field.leftView = glass;
    _field.leftViewMode = UITextFieldViewModeAlways;
    _field.delegate = self;
    [_field addTarget:self action:@selector(typed) forControlEvents:UIControlEventEditingChanged];
    [_glass.contentView addSubview:_field];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.bounds.size.height;
    _glass.frame = self.bounds;
    _glass.layer.cornerRadius = h / 2;
    _play.frame = CGRectMake(8, 0, h, h);
    _field.frame = CGRectMake(h + 4, 0, self.bounds.size.width - h - 16, h);
    _results.frame = self.resultsHost.bounds;
}

- (void)showPlayIcon {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
    [_play setImage:[UIImage systemImageNamed:_playing ? @"pause.fill" : @"play.fill" withConfiguration:config] forState:UIControlStateNormal];
    _play.accessibilityLabel = _playing ? @"Pause preview" : @"Play preview";
}

- (void)playTapped {
    _playing = !_playing;
    [self showPlayIcon];
    if (self.togglePlay) self.togglePlay(_playing);
}

- (void)showSong:(NSString *)title artist:(NSString *)artist {
    _field.text = artist.length ? [NSString stringWithFormat:@"%@ · %@", title, artist] : title;
}

#pragma mark - searching

- (void)typed {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(search) object:nil];
    if (_field.text.length < 2) {
        [self hideResults];
        return;
    }
    [self performSelector:@selector(search) withObject:nil afterDelay:0.45];
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(search) object:nil];
    [self search];
    [field resignFirstResponder];
    return YES;
}

- (void)hideResults {
    [_task cancel];
    _asked++;
    [UIView animateWithDuration:0.2 animations:^{ self->_results.alpha = 0; } completion:^(BOOL done) {
        if (self->_results.alpha == 0) [self->_results removeFromSuperview];
    }];
}

- (void)search {
    NSString *query = [_field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (query.length < 2) return;
    NSURLComponents *url = [NSURLComponents componentsWithString:@"https://lrclib.net/api/search"];
    url.queryItems = @[[NSURLQueryItem queryItemWithName:@"q" value:query]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.URL];
    [request setValue:@"PwEevee " @SG_VERSION forHTTPHeaderField:@"User-Agent"];
    request.timeoutInterval = 12;
    [_task cancel];
    NSUInteger asked = ++_asked;
    __weak SGRLyricsSongPill *weakSelf = self;
    _task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSMutableArray<NSDictionary *> *songs = [NSMutableArray array];
        if ([json isKindOfClass:NSArray.class]) {
            for (id record in json) {
                if (![record isKindOfClass:NSDictionary.class] || [record[@"instrumental"] boolValue]) continue;
                BOOL hasText = [record[@"syncedLyrics"] isKindOfClass:NSString.class] || [record[@"plainLyrics"] isKindOfClass:NSString.class];
                if (hasText && [record[@"trackName"] isKindOfClass:NSString.class]) [songs addObject:record];
                if (songs.count == kMostResults) break;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            SGRLyricsSongPill *pill = weakSelf;
            if (!pill || asked != pill->_asked || error.code == NSURLErrorCancelled) return;
            [pill showResults:songs];
        });
    }];
    [_task resume];
}

- (void)showResults:(NSArray<NSDictionary *> *)songs {
    UIView *host = self.resultsHost;
    if (!host) return;
    if (!_results) {
        _results = [SGRLyricsResultsList new];
        __weak SGRLyricsSongPill *weakSelf = self;
        _results.chose = ^(NSDictionary *song) { [weakSelf choose:song]; };
    }
    _results.songs = songs;
    if (_results.superview != host) {
        _results.alpha = 0;
        _results.frame = host.bounds;
        [host addSubview:_results];
    }
    [UIView animateWithDuration:0.2 animations:^{ self->_results.alpha = 1; }];
}

// The song's lines: timed where LRCLIB has them timed, plain text otherwise; looped to the end of the last line.
- (void)choose:(NSDictionary *)song {
    NSArray<SGKaraokeLine *> *lines = nil;
    NSString *synced = song[@"syncedLyrics"], *plain = song[@"plainLyrics"];
    if ([synced isKindOfClass:NSString.class]) lines = SGLyricsLRCResult(synced).karaokeLines;
    if (!lines.count && [plain isKindOfClass:NSString.class]) {
        NSMutableArray<NSString *> *texts = [NSMutableArray array];
        for (NSString *row in [plain componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            NSString *trimmed = [row stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (trimmed.length) [texts addObject:trimmed];
        }
        lines = SGKaraokeStaticLines(texts);
    }
    if (!lines.count) return;
    NSInteger end = 0;
    for (SGKaraokeLine *line in lines) end = MAX(end, SGKaraokeSungEnd(line));
    [self showSong:song[@"trackName"] artist:song[@"artistName"]];
    [_field resignFirstResponder];
    [self hideResults];
    _playing = YES;
    [self showPlayIcon];
    if (self.picked) self.picked(lines, end + 3000, song[@"trackName"], song[@"artistName"]);
}

@end
