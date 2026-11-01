#import <Foundation/Foundation.h>

@interface TDAutoGrab : NSObject
+ (instancetype)shared;
@property(nonatomic, assign) BOOL enabled;
- (void)considerOrder:(NSDictionary *)order;
- (void)acceptOrder:(NSDictionary *)order;
@end
