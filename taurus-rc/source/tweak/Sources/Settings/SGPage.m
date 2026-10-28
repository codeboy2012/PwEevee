#import "SGPage.h"
#import "SGPageStyle.h"
#import "Core/SGCore.h"


static BOOL sg_pagesConform;

@implementation SGPage

// Inset grouped cards on Spotify's dark grey, a hairline between the rows of a card.
- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.tableView.backgroundColor = SGPageBackground();
    self.tableView.separatorColor = [UIColor colorWithWhite:1 alpha:0.1];
    self.tableView.sectionHeaderTopPadding = 0;
}

- (NSString *)spt_pageIdentifier {
    return @"spotifyglass";
}

- (NSURL *)spt_pageURI {
    return [NSURL URLWithString:@"spotify:internal:spotifyglass"];
}

@end

void SGRegisterPages(void) {
    // Swift's own name for the protocol, which is what the runtime registers it under.
    Protocol *page = objc_getProtocol("_TtP19Tome_PageAttributes17SPTPageController_") ?: objc_getProtocol("SPTPageController");
    sg_pagesConform = page && class_addProtocol(SGPage.class, page);
    if (!sg_pagesConform) SGLog(@"SPTPageController not found, the mod's pages are presented instead of pushed");
}

void SGShowPage(UIViewController *owner, UIViewController *page) {
    if (owner.navigationController && sg_pagesConform) [owner.navigationController pushViewController:page animated:YES];
    else [owner presentViewController:[[UINavigationController alloc] initWithRootViewController:page] animated:YES completion:nil];
}
