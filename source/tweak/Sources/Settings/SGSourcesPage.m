#import "Core/SGCore.h"
#import "SGPage.h"
#import "SGPageStyle.h"
#import "SGSourcesPage.h"

@implementation SGSource
+ (instancetype)sourceWithKey:(NSString *)key name:(NSString *)name detail:(NSString *)detail {
    SGSource *source = [self new];
    source.key = key;
    source.name = name;
    source.detail = detail;
    return source;
}
@end

typedef NS_ENUM(NSInteger, SGSourcesSection) {
    SGSourcesSectionOn = 0,
    SGSourcesSectionOff,
    SGSourcesSectionCount,
};

@interface SGSourcesPage : SGPage
@property (nonatomic, copy) NSString *note;
@property (nonatomic, copy) NSArray<SGSource *> *all;
@property (nonatomic, copy) NSArray<NSString *> *(^order)(void);
@property (nonatomic, copy) void (^setOrder)(NSArray<NSString *> *keys);
@property (nonatomic) NSUInteger minimumOnCount;
@end

@implementation SGSourcesPage {
    NSMutableArray<NSString *> *_on;    // keys, in the order they are asked
    NSMutableArray<NSString *> *_off;
    UIView *_footer;
}

- (SGSource *)sourceFor:(NSString *)key {
    for (SGSource *source in self.all) if ([source.key isEqualToString:key]) return source;
    return nil;
}

- (void)read {
    _on = [NSMutableArray array];
    for (NSString *key in self.order()) if ([self sourceFor:key] && ![_on containsObject:key]) [_on addObject:key];
    _off = [NSMutableArray array];
    for (SGSource *source in self.all) {
        if (![_on containsObject:source.key]) [_off addObject:source.key];
    }
}

- (void)save {
    self.setOrder(_on);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self read];
    self.tableView.editing = YES;
    self.tableView.allowsSelectionDuringEditing = YES;
    _footer = SGNote(self.note);
    self.tableView.tableFooterView = _footer;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _footer, 16, 24);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (NSMutableArray<NSString *> *)keysIn:(NSInteger)section {
    return section == SGSourcesSectionOn ? _on : _off;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return SGSourcesSectionCount;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self keysIn:section].count;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    if (section == SGSourcesSectionOn) return SGSectionHeader(table, _on.count ? @"Asked in this order" : @"None on");
    return _off.count ? SGSectionHeader(table, @"Off") : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return section == SGSourcesSectionOn || _off.count ? UITableViewAutomaticDimension : CGFLOAT_MIN;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"source");
    SGSource *provider = [self sourceFor:[self keysIn:path.section][(NSUInteger)path.row]];
    BOOL on = path.section == SGSourcesSectionOn;
    // The asked ones are numbered, so the order reads as an order rather than a list.
    NSString *title = on ? [NSString stringWithFormat:@"%ld. %@", (long)path.row + 1, provider.name] : provider.name;
    SGFillCell(cell, title, provider.detail, on ? nil : SGGrey(), on ? @"checkmark.circle.fill" : @"circle");
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (BOOL)tableView:(UITableView *)table canMoveRowAtIndexPath:(NSIndexPath *)path {
    return path.section == SGSourcesSectionOn;
}

- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path {
    return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)table editingStyleForRowAtIndexPath:(NSIndexPath *)path {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)table shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)path {
    return NO;
}

// Dragging stays inside the order; a source is switched on and off by tapping it, not by dropping
// it into the other section, so an order is never lost to a stray drag.
- (NSIndexPath *)tableView:(UITableView *)table targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to {
    return to.section == SGSourcesSectionOn ? to : from;
}

- (void)tableView:(UITableView *)table moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSString *key = _on[(NSUInteger)from.row];
    [_on removeObjectAtIndex:(NSUInteger)from.row];
    [_on insertObject:key atIndex:(NSUInteger)to.row];
    [self save];
    [table reloadData];   // the numbers in front of the names have all moved
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    NSString *key = [self keysIn:path.section][(NSUInteger)path.row];
    if (path.section == SGSourcesSectionOn) {
        if (_on.count <= self.minimumOnCount) return;
        [_on removeObject:key];
        // Back to where it sits among the sources that are off, in the order they all come in.
        NSUInteger at = 0;
        for (SGSource *source in self.all) {
            if ([source.key isEqualToString:key]) break;
            if ([_off containsObject:source.key]) at++;
        }
        [_off insertObject:key atIndex:at];
    } else {
        [_off removeObject:key];
        [_on addObject:key];
    }
    [self save];
    [table reloadData];
}

@end

UIViewController *SGSourcesPageMake(NSString *title, NSString *note, NSArray<SGSource *> *all,
                                    NSArray<NSString *> *(^order)(void), void (^setOrder)(NSArray<NSString *> *keys)) {
    return SGSourcesPageMakeWithMinimumOnCount(title, note, all, order, setOrder, 0);
}

UIViewController *SGSourcesPageMakeWithMinimumOnCount(NSString *title, NSString *note, NSArray<SGSource *> *all,
                                                      NSArray<NSString *> *(^order)(void),
                                                      void (^setOrder)(NSArray<NSString *> *keys),
                                                      NSUInteger minimumOnCount) {
    SGSourcesPage *page = [[SGSourcesPage alloc] initWithStyle:UITableViewStyleInsetGrouped];
    page.title = title;
    page.note = note;
    page.all = all;
    page.order = order;
    page.setOrder = setOrder;
    page.minimumOnCount = MIN(minimumOnCount, all.count);
    return page;
}
