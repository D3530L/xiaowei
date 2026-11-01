#import "TDStore.h"

@interface TDStore ()
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *orders;
@end

@implementation TDStore

+ (instancetype)shared {
    static TDStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [TDStore new];
        store.orders = [NSMutableArray array];
        store.enabled = YES;
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        store.minimumPrice = [defaults doubleForKey:@"td_priceMin"];
        store.maximumPrice = [defaults doubleForKey:@"td_priceMax"];
        if (store.maximumPrice <= 0.0) store.maximumPrice = 999999.0;
        store.maximumPickupKm = [defaults doubleForKey:@"td_pickupMaxKm"];
        if (store.maximumPickupKm <= 0.0) store.maximumPickupKm = 999.0;
        store.timeStart = [defaults integerForKey:@"td_timeStart"];
        store.timeEnd = [defaults integerForKey:@"td_timeEnd"];
        if (store.timeEnd == 0) store.timeEnd = 24;
    });
    return store;
}

- (void)recordOrder:(NSDictionary *)order source:(NSString *)source {
    if (!self.enabled || ![order isKindOfClass:NSDictionary.class]) return;
    NSMutableDictionary *copy = [order mutableCopy];
    copy[@"_td_source"] = source ?: @"unknown";
    copy[@"_td_time"] = @([[NSDate date] timeIntervalSince1970]);
    @synchronized (self) {
        [self.orders insertObject:copy atIndex:0];
        if (self.orders.count > 100) [self.orders removeLastObject];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TDOrderReceived" object:copy];
}

- (NSArray<NSDictionary *> *)recentOrders {
    @synchronized (self) { return [self.orders copy]; }
}

@end
