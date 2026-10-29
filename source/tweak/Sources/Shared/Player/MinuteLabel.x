// Spotify's sleep timer calls its one minute option (the flag ios-feature-sleeptimer.enable_one_minute_option)
// "1 minutes", in both places it lists the durations: the rows of its context menu sheet
// (SleepTimerActionsProviderImplementation's actions, drawn in ContextMenu_InternalImpl.ContextMenuTableViewCell)
// and the options sheet (PlaybackControl_SleepTimerImpl.OptionCell, a collection view cell). The text comes from
// Swift with no way in, so each of those cells has a label reading exactly "1 minutes" set right as it lays out.
// Only that English text is touched: any other language's, and every other label, stay as Spotify set them.
#import "Core/SGCore.h"

static void fixMinute(UIView *cell) {
    SGForEachView(cell, ^(UIView *view) {
        if (![view isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)view;
        if (label.text.length != 9 || ![label.text isEqualToString:@"1 minutes"]) return;
        // Through the attributed text, so the label keeps the font and color Spotify gave it.
        NSMutableAttributedString *text = [label.attributedText mutableCopy];
        [text replaceCharactersInRange:NSMakeRange(0, text.length) withString:@"1 minute"];
        label.attributedText = text;
    });
}

%hook _TtC24ContextMenu_InternalImpl24ContextMenuTableViewCell
- (void)layoutSubviews {
    %orig;
    fixMinute((UIView *)self);
}
%end

%hook _TtC30PlaybackControl_SleepTimerImpl10OptionCell
- (void)layoutSubviews {
    %orig;
    fixMinute((UIView *)self);
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"_TtC24ContextMenu_InternalImpl24ContextMenuTableViewCell", @"_TtC30PlaybackControl_SleepTimerImpl10OptionCell"]);
}
