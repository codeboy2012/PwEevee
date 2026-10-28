#import "Core/SGLog.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "About.h"

@interface SGDeviceLogsPageController : SGPage
@property (nonatomic, copy) NSString *contents;
@end

@implementation SGDeviceLogsPageController

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Device Logs";
    _contents = SGLogContents();
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Copy"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self action:@selector(copyLogs)];
    UIBarButtonItem *share = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                           target:self action:@selector(shareLogs)];
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                             target:self action:@selector(refreshLogs)];
    self.navigationItem.rightBarButtonItems = @[share, refresh];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *note = SGNote(@"Logs are stored locally. They may contain diagnostic details; nothing is shared unless you choose Copy or Share.");
    self.tableView.tableHeaderView = note;
    SGFitNote(self.tableView, note, 12, 8);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    return MAX(280, table.bounds.size.height - table.adjustedContentInset.top - table.adjustedContentInset.bottom - 48);
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"device-logs");
    UITextView *text = (UITextView *)[cell.contentView viewWithTag:7101];
    if (!text) {
        text = [[UITextView alloc] initWithFrame:CGRectZero];
        text.tag = 7101;
        text.translatesAutoresizingMaskIntoConstraints = NO;
        text.backgroundColor = UIColor.clearColor;
        text.textColor = UIColor.whiteColor;
        text.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        text.textContainerInset = UIEdgeInsetsZero;
        text.textContainer.lineFragmentPadding = 0;
        text.editable = NO;
        text.selectable = YES;
        text.scrollEnabled = YES;
        text.showsVerticalScrollIndicator = YES;
        [cell.contentView addSubview:text];
        [NSLayoutConstraint activateConstraints:@[
            [text.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:8],
            [text.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-8],
            [text.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
            [text.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
        ]];
    }
    text.text = self.contents;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)refreshLogs {
    self.contents = SGLogContents();
    [self.tableView reloadData];
}

- (void)copyLogs {
    UIPasteboard.generalPasteboard.string = self.contents ?: @"";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Logs copied"
                                                                   message:@"The recent diagnostics are on the clipboard."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)shareLogs {
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[self.contents ?: @""] applicationActivities:nil];
    UIView *anchor = self.navigationController.navigationBar;
    share.popoverPresentationController.sourceView = anchor;
    share.popoverPresentationController.sourceRect = CGRectMake(anchor.bounds.size.width - 1, anchor.bounds.size.height - 1, 1, 1);
    [self presentViewController:share animated:YES completion:nil];
}

@end

UIViewController *SGDeviceLogsPage(void) {
    return [SGDeviceLogsPageController new];
}
