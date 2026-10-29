#import "Core/SGCore.h"
#import "SGRHeaderInfo.h"
#import "SGRActionRow.h"
#import "SGRRestyle.h"
#import "SGRTokens.h"

const CGFloat SGRHeaderInfoBottom = 14;
const CGFloat SGRHeaderInfoTitleRise = 56;

// The text kSide in from the edges; Play at least kPlayWidth wide, the Music app's; the gaps between.
static const CGFloat kSide = 20, kPlayWidth = 148, kRowSpacing = 16, kRowAbove = 16, kAboutAbove = 14;
static const CGFloat kLogoWidthShare = 0.8, kLogoMaxHeight = 64;
// The card under the row: the gap above it and the widest it goes.
static const CGFloat kCardAbove = 20, kCardMaxWidth = 440;

static UILabel *infoLabel(UIView *parent, UIFont *font, UIColor *color, NSInteger lines, NSTextAlignment alignment) {
    UILabel *label = [UILabel new];
    label.font = font;
    label.textColor = color;
    label.numberOfLines = lines;
    label.textAlignment = alignment;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.hidden = YES;
    [parent addSubview:label];
    return label;
}

static BOOL setText(UILabel *label, NSString *text) {
    if ([label.text ?: @"" isEqualToString:text ?: @""]) return NO;
    label.text = text;
    label.hidden = text.length == 0;
    return YES;
}

@implementation SGRHeaderInfo {
    UILabel *_title, *_creator, *_length, *_about;
    UIImageView *_logo;
    UIImage *_titleImage;
    UIView *_card;
    SGRMirrorButton *_shuffle, *_trailing;
    SGRPlayCapsule *_play;
    UIScrollView *_albumControls;
    SGRMirrorButton *_albumDownload;
    __weak UIView *_creatorLink;
    NSUInteger _playerRefreshGeneration;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _title = infoLabel(self, SGRFont(UIFontTextStyleTitle2, UIFontWeightBold, UIContentSizeCategoryExtraLarge),
                       SGRPrimary(), 2, NSTextAlignmentCenter);
    _title.accessibilityTraits = UIAccessibilityTraitHeader;
    _creator = infoLabel(self, SGRFont(UIFontTextStyleBody, UIFontWeightRegular, UIContentSizeCategoryExtraLarge),
                         SGRSecondary(), 1, NSTextAlignmentCenter);
    _length = infoLabel(self, SGRFont(UIFontTextStyleFootnote, UIFontWeightRegular, UIContentSizeCategoryExtraLarge),
                        SGRTertiary(), 1, NSTextAlignmentCenter);
    _about = infoLabel(self, SGRFont(UIFontTextStyleFootnote, UIFontWeightRegular, UIContentSizeCategoryExtraLarge),
                       SGRSecondary(), 2, NSTextAlignmentNatural);

    _shuffle = [[SGRMirrorButton alloc] initWithFrame:CGRectZero];
    _shuffle.fallbackGlyph = [UIImage systemImageNamed:@"shuffle"];
    _shuffle.glyphColor = SGRPrimary();
    _shuffle.onGlyphColor = SGRAccent();
    _play = [[SGRPlayCapsule alloc] initWithFrame:CGRectZero];
    _play.fillColor = UIColor.whiteColor;
    _trailing = [[SGRMirrorButton alloc] initWithFrame:CGRectZero];
    for (UIView *button in @[_shuffle, _play, _trailing]) {
        button.hidden = YES;
        [self addSubview:button];
    }
    SGAddPlayerStateObserver(self);
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidBecomeActive:)
                                               name:UIApplicationDidBecomeActiveNotification object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == _creator) return [self sgr_creatorHit:point];
    return hit;
}

- (BOOL)showTitle:(NSString *)title creator:(NSString *)creator length:(NSString *)length about:(NSString *)about {
    BOOL changed = NO;
    changed |= setText(_title, title);
    changed |= setText(_creator, creator);
    changed |= setText(_length, length);
    changed |= setText(_about, about);
    if (changed) [self setNeedsLayout];
    return changed;
}

- (void)showTitleImage:(UIImage *)image {
    if (_titleImage == image) return;
    if (!_logo) {
        _logo = [UIImageView new];
        _logo.contentMode = UIViewContentModeScaleAspectFit;
        _logo.isAccessibilityElement = YES;
        _logo.accessibilityTraits = UIAccessibilityTraitHeader;
        _logo.alpha = 0;
        [self addSubview:_logo];
    }
    _titleImage = image;
    _title.accessibilityElementsHidden = image != nil;
    if (image) {
        if (!_logo.image) [UIView performWithoutAnimation:^{ self->_logo.frame = self->_title.frame; }];
        _logo.image = image;
        _logo.hidden = NO;
    }
    [self setNeedsLayout];
    void (^fade)(void) = ^{
        self->_logo.alpha = image ? 1 : 0;
        self->_title.alpha = image ? 0 : 1;
    };
    void (^faded)(BOOL) = ^(BOOL finished) {
        if (self->_titleImage) return;
        self->_logo.image = nil;
        self->_logo.hidden = YES;
    };
    if (!self.window) {
        fade();
        faded(YES);
        return;
    }
    SGRAnimate(SGRMotionFade, fade, faded);
    SGRAnimateLayout(self, ^{ [self layoutIfNeeded]; }, nil);
}

- (CGFloat)sgr_gapAfter:(UILabel *)label {
    return label == _title && _titleImage ? 8 : (label == _creator ? 4 : 2);
}

- (CGSize)sgr_sizeOf:(UILabel *)label width:(CGFloat)text {
    if (label != _title || !_titleImage) return [label sizeThatFits:CGSizeMake(text, CGFLOAT_MAX)];
    CGSize image = _titleImage.size;
    if (image.width <= 0 || image.height <= 0) return CGSizeZero;
    CGFloat scale = MIN(text * kLogoWidthShare / image.width, kLogoMaxHeight / image.height);
    return CGSizeMake(round(image.width * scale), round(image.height * scale));
}

- (void)showCreatorLink:(UIView *)control {
    _creatorLink = control;
    BOOL live = control != nil;
    if (_creator.userInteractionEnabled == live) return;
    _creator.userInteractionEnabled = live;
    _creator.accessibilityTraits = live ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
    if (!live || _creator.gestureRecognizers.count) return;
    [_creator addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(sgr_creatorTapped)]];
}

- (void)sgr_creatorTapped {
    SGRActivate(_creatorLink);
}

// The creator line takes a touch only where its text is; everything else of the view is the page's.
- (UIView *)sgr_creatorHit:(CGPoint)point {
    if (!_creator.userInteractionEnabled || _creator.hidden) return nil;
    CGSize text = [_creator sizeThatFits:CGSizeMake(_creator.bounds.size.width, CGFLOAT_MAX)];
    CGRect frame = _creator.frame;
    CGRect word = CGRectInset(CGRectMake(round(CGRectGetMidX(frame) - text.width / 2), frame.origin.y,
                                         MIN(text.width, frame.size.width), frame.size.height), -8, -6);
    return CGRectContainsPoint(word, point) ? _creator : nil;
}

- (void)showShuffle:(UIView *)shuffle play:(UIView *)play trailing:(UIView *)trailing
   trailingFallback:(UIImage *)trailingFallback playColor:(UIColor *)playColor {
    _trailing.fallbackGlyph = trailingFallback;
    if (_trailing.readState != self.trailingState) {
        _trailing.readState = self.trailingState;
        _trailing.stateOffSymbol = self.trailingOffSymbol;
        _trailing.stateOnSymbol = self.trailingOnSymbol;
    }
    if (shuffle) [_shuffle feedFrom:shuffle];
    if (play) {
        if (playColor) _play.contentColor = playColor;
        [_play feedFrom:play];
    }
    if (trailing) [_trailing feedFrom:trailing];

    BOOL changed = NO;
    NSArray<UIView *> *buttons = @[_shuffle, _play, _trailing];
    NSArray<NSNumber *> *shown = @[@(shuffle != nil), @(play != nil), @(trailing != nil)];
    for (NSUInteger i = 0; i < buttons.count; i++) {
        UIView *button = buttons[i];
        BOOL hide = !shown[i].boolValue;
        if (button.hidden == hide) continue;
        button.hidden = hide;
        changed = YES;
        if (!hide && self.window) {
            button.alpha = 0;
            SGRAnimate(SGRMotionFade, ^{ button.alpha = 1; }, nil);
        }
    }
    if (changed) [self setNeedsLayout];
}

- (void)trailingStateChanged {
    if (_trailing.source) [_trailing feedFrom:_trailing.source];
}

- (void)refreshButtons {
    if (_shuffle.source) [_shuffle feedFrom:_shuffle.source];
    if (_play.source) [_play feedFrom:_play.source];
    if (_trailing.source) [_trailing feedFrom:_trailing.source];
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSUInteger generation = ++_playerRefreshGeneration;
    __weak SGRHeaderInfo *weakSelf = self;
    for (NSNumber *delay in @[@0, @0.25, @0.8]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            SGRHeaderInfo *strongSelf = weakSelf;
            if (strongSelf && generation == strongSelf->_playerRefreshGeneration) [strongSelf refreshButtons];
        });
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)note {
    NSUInteger generation = ++_playerRefreshGeneration;
    [self refreshButtons];
    __weak SGRHeaderInfo *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGRHeaderInfo *strongSelf = weakSelf;
        if (strongSelf && generation == strongSelf->_playerRefreshGeneration) [strongSelf refreshButtons];
    });
}

- (void)showAlbumShuffle:(UIView *)shuffle play:(UIView *)play download:(UIView *)download
                    add:(UIView *)add playColor:(UIColor *)playColor {
    if (!_albumControls) {
        _albumControls = [UIScrollView new];
        _albumControls.showsHorizontalScrollIndicator = NO;
        _albumControls.showsVerticalScrollIndicator = NO;
        _albumControls.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        _albumControls.delaysContentTouches = NO;
        _albumControls.directionalLockEnabled = YES;
        _albumControls.clipsToBounds = NO;
        _albumControls.accessibilityIdentifier = @"PwEevee.Album.Actions";
        [self addSubview:_albumControls];
        [_albumControls addSubview:_shuffle];
        _albumDownload = [[SGRMirrorButton alloc] initWithFrame:CGRectZero];
        _albumDownload.fallbackGlyph = [UIImage systemImageNamed:@"arrow.down"];
        _albumDownload.accessibilityIdentifier = @"PwEevee.Album.Download";
        [_albumControls addSubview:_albumDownload];
        [_albumControls addSubview:_trailing];
    }
    [self showShuffle:shuffle play:play trailing:add
     trailingFallback:[UIImage systemImageNamed:@"plus"] playColor:playColor];
    if (download) [_albumDownload feedFrom:download];
    BOOL hide = download == nil;
    if (_albumDownload.hidden != hide) {
        _albumDownload.hidden = hide;
        [self setNeedsLayout];
    }
}

- (void)showCard:(UIView *)card {
    if (_card == card) return;
    [_card removeFromSuperview];
    _card = card;
    if (card) {
        [self addSubview:card];
        if (self.window) {
            card.alpha = 0;
            SGRAnimate(SGRMotionFade, ^{ card.alpha = 1; }, nil);
        }
    }
    [self setNeedsLayout];
}

- (CGFloat)cardWidthForWidth:(CGFloat)width {
    return MIN(MAX(0, width - 2 * kSide), kCardMaxWidth);
}

// The card with the gap above it, or 0 with none.
- (CGFloat)cardBlockForWidth:(CGFloat)width {
    if (!_card) return 0;
    return kCardAbove + ceil([_card sizeThatFits:CGSizeMake([self cardWidthForWidth:width], CGFLOAT_MAX)].height);
}

- (CGFloat)contentHeightForWidth:(CGFloat)width {
    CGFloat text = MAX(0, width - 2 * kSide), height = 0;
    UILabel *previous = nil;
    for (UILabel *label in @[_title, _creator, _length]) {
        if (label.hidden) continue;
        if (previous) height += [self sgr_gapAfter:previous];
        height += ceil([self sgr_sizeOf:label width:text].height);
        previous = label;
    }
    if (previous) height += kRowAbove;
    height += SGRActionHeight;
    if (!_about.hidden) height += kAboutAbove + ceil([_about sizeThatFits:CGSizeMake(text, CGFLOAT_MAX)].height);
    return height;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, text = MAX(0, width - 2 * kSide);
    CGFloat y = round(self.bounds.size.height - SGRHeaderInfoBottom - [self contentHeightForWidth:width] - [self cardBlockForWidth:width]);

    UILabel *previous = nil;
    for (UILabel *label in @[_title, _creator, _length]) {
        if (label.hidden) continue;
        if (previous) y += [self sgr_gapAfter:previous];
        CGSize size = [self sgr_sizeOf:label width:text];
        CGFloat height = ceil(size.height);
        label.frame = CGRectMake(kSide, y, text, height);
        if (label == _title && _titleImage) {
            _logo.frame = CGRectMake(round((width - size.width) / 2), y, size.width, height);
            _logo.accessibilityLabel = _title.text;
        }
        y += height;
        previous = label;
    }
    if (previous) y += kRowAbove;

    CGFloat side = SGRActionHeight;
    if (_albumControls) {
        CGFloat playWidth = MIN(MAX(kPlayWidth, [_play sgr_width]), MAX(0, text - side - kRowSpacing));
        BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
        CGFloat playX = rtl ? kSide : width - kSide - playWidth;
        _play.frame = CGRectMake(playX, y, playWidth, side);
        CGFloat groupWidth = MAX(0, text - playWidth - kRowSpacing);
        _albumControls.frame = CGRectMake(rtl ? CGRectGetMaxX(_play.frame) + kRowSpacing : kSide,
                                          y, groupWidth, side);
        CGFloat x = 0;
        for (UIView *button in @[_shuffle, _albumDownload, _trailing]) {
            if (button.hidden) continue;
            button.frame = CGRectMake(x, 0, side, side);
            x += side + 12;
        }
        CGSize size = CGSizeMake(MAX(0, x - 12), side);
        if (!CGSizeEqualToSize(_albumControls.contentSize, size)) _albumControls.contentSize = size;
        _albumControls.scrollEnabled = size.width > groupWidth + 0.5;
        CGFloat limit = MAX(0, size.width - groupWidth);
        if (_albumControls.contentOffset.x > limit) _albumControls.contentOffset = CGPointMake(limit, 0);
    } else {
        CGFloat playWidth = MAX(kPlayWidth, [_play sgr_width]);
        CGRect play = CGRectMake(round((width - playWidth) / 2), y, playWidth, side);
        _play.frame = play;
        _shuffle.frame = CGRectMake(CGRectGetMinX(play) - kRowSpacing - side, y, side, side);
        _trailing.frame = CGRectMake(CGRectGetMaxX(play) + kRowSpacing, y, side, side);
    }
    y += side;

    if (!_about.hidden) {
        y += kAboutAbove;
        _about.frame = CGRectMake(kSide, y, text, ceil([_about sizeThatFits:CGSizeMake(text, CGFLOAT_MAX)].height));
    }

    if (_card) {
        CGFloat cardWidth = [self cardWidthForWidth:width];
        CGFloat cardHeight = ceil([_card sizeThatFits:CGSizeMake(cardWidth, CGFLOAT_MAX)].height);
        y += kCardAbove;
        _card.frame = CGRectMake(round((width - cardWidth) / 2), y, cardWidth, cardHeight);
        y += cardHeight;
    }
}

@end
