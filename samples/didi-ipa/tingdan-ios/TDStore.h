#import <Foundation/Foundation.h>

@interface TDStore : NSObject
+ (instancetype)shared;
@property(nonatomic, assign) BOOL enabled;
@property(nonatomic, assign) double minimumPrice;
@property(nonatomic, assign) double maximumPrice;
@property(nonatomic, assign) double maximumPickupKm;
@property(nonatomic, assign) NSInteger timeStart;
@property(nonatomic, assign) NSInteger timeEnd;
- (void)recordOrder:(NSDictionary *)order source:(NSString *)source;
- (NSArray<NSDictionary *> *)recentOrders;
@end
