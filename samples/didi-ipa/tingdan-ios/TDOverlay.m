#import "TDOverlay.h"
#import "TDStore.h"

@interface TDOverlay ()
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) UILabel *label;
@end

@implementation TDOverlay

+ (instancetype)shared {
    static TDOverlay *overlay;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ overlay = [TDOverlay new]; });
    return overlay;
}

- (void)install {
    if (self.window) return;
    UIScreen *screen = UIScreen.mainScreen;
    self.window = [[UIWindow alloc] initWithFrame:CGRectMake(12, 72, screen.bounds.size.width - 24, 78)];
    self.window.windowLevel = UIWindowLevelAlert + 2;
    self.window.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.92];
    self.window.layer.cornerRadius = 10.0;
    self.window.clipsToBounds = YES;
    self.label = [[UILabel alloc] initWithFrame:CGRectInset(self.window.bounds, 12, 8)];
    self.label.numberOfLines = 0;
    self.label.textColor = UIColor.whiteColor;
    self.label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.label.text = @"听单插件已加载\n等待司机订单事件";
    [self.window addSubview:self.label];
    self.window.hidden = NO;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orderReceived:) name:@"TDOrderReceived" object:nil];
}

- (void)showOrder:(NSDictionary *)order {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *oid = [order[@"oid"] description] ?: [order[@"order_id"] description] ?: @"未知订单";
        NSString *price = [order[@"price"] description] ?: [order[@"amount"] description] ?: @"-";
        NSString *from = [order[@"from_name"] description] ?: [order[@"start_address"] description] ?: @"未知上车点";
        NSString *to = [order[@"to_name"] description] ?: [order[@"end_address"] description] ?: @"未知目的地";
        self.label.text = [NSString stringWithFormat:@"新订单 %@  ¥%@\n%@ → %@", oid, price, from, to];
        self.window.hidden = NO;
    });
}

- (void)orderReceived:(NSNotification *)note { [self showOrder:note.object]; }

@end
