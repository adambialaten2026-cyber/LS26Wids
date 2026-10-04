#import "LSW.h"
#import <notify.h>
@interface CSCoverSheetViewController : UIViewController
@end

%hook CSCoverSheetViewController
- (void)viewDidLoad {
    %orig;
    [[LSWManager shared] attachToHostView:self.view];
}
- (void)viewDidLayoutSubviews {
    %orig;
    // keep the widget block as the top-most layer, above every other tweak
    [[LSWManager shared] bringToFront];
}
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [[LSWManager shared] reload];
}
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    [[LSWManager shared].block setEditing:NO animated:NO];
}
%end

%ctor {
    int token;
    notify_register_dispatch(LSW_RELOAD_NOTIF, &token, dispatch_get_main_queue(), ^(int t){
        [[LSWManager shared] reload];   // settings changed -> apply live, no respring
    });
}
