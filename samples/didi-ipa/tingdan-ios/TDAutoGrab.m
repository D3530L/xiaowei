#import "TDAutoGrab.h"
#import "TDStore.h"

@implementation TDAutoGrab

+ (instancetype)shared {
    static TDAutoGrab *grabber;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        grabber = [TDAutoGrab new];
        grabber.enabled = YES;
    });
    return grabber;
}

- (void)considerOrder:(NSDictionary *)order {
    if (!self.enabled || ![order isKindOfClass:NSDictionary.class]) return;
    TDStore *store = [TDStore shared];
    if (!store.enabled || ![self withinTimeWindow]) return;
    double price = [self numberInOrder:order keys:@[@"price", @"amount", @"total_price"]];
    double pickupKm = [self numberInOrder:order keys:@[@"pickup_km", @"pickup_distance", @"from_distance"]];
    if (price < store.minimumPrice || price > store.maximumPrice || pickupKm > store.maximumPickupKm) return;
    [self acceptOrder:order];
}

- (void)acceptOrder:(NSDictionary *)order {
    // The exact iOS selector is resolved from the runtime-discovered driver class.
    // This adapter deliberately records the action until that selector is verified.
    NSMutableDictionary *event = [order mutableCopy];
    event[@"_td_action"] = @"accept_pending_runtime_selector";
    event[@"_td_action_time"] = @([[NSDate date] timeIntervalSince1970]);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TDAcceptRequested" object:event];
    NSLog(@"[DidiTingdan] accept requested oid=%@", event[@"oid"] ?: event[@"order_id"] ?: @"unknown");
}

- (BOOL)withinTimeWindow {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSInteger start = [defaults integerForKey:@"td_timeStart"];
    NSInteger end = [defaults integerForKey:@"td_timeEnd"];
    if (end == 0) end = 24;
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSInteger hour = [calendar component:NSCalendarUnitHour fromDate:NSDate.date];
    return start <= end ? (hour >= start && hour < end) : (hour >= start || hour < end);
}

- (double)numberInOrder:(NSDictionary *)order keys:(NSArray<NSString *> *)keys {
    for (NSString *key in keys) {
        id value = order[key];
        if ([value respondsToSelector:@selector(doubleValue)]) return [value doubleValue];
    }
    return 0.0;
}

@end
