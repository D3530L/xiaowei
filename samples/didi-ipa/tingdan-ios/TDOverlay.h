#import <UIKit/UIKit.h>

@interface TDOverlay : NSObject
+ (instancetype)shared;
- (void)install;
- (void)showOrder:(NSDictionary *)order;
@end
