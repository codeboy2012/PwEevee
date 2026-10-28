#import <UIKit/UIKit.h>
@class SGRSingControl;
UIView *SGRSingControlForPage(UIView *page, CGRect lyrics, BOOL immersive, void (^hold)(BOOL));
void SGRSingControlDismiss(UIView *page);
void SGRSingControlRemoveForPage(UIView *page);
