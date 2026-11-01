#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "TDStore.h"
#import "TDOverlay.h"

static NSString *TDProbeLogPath(void) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/DidiTingdan"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"runtime.log"];
}

void TDProbeLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *text = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], line];
    NSString *path = TDProbeLogPath();
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:[text dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

static NSDictionary *TDJSON(id object) {
    if ([object isKindOfClass:NSDictionary.class]) return object;
    NSData *data = nil;
    if ([object isKindOfClass:NSData.class]) data = object;
    if ([object isKindOfClass:NSString.class]) data = [object dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static id TDRedactObject(id object);
static NSString *TDRedactText(NSString *text);

static void TDRecordPayload(id object, NSString *source, NSString *url) {
    NSDictionary *json = TDJSON(object);
    if (json) {
        [[TDStore shared] recordOrder:json source:source];
        TDProbeLog(@"JSON source=%@ url=%@ keys=%@ body=%@", source, url ?: @"", json.allKeys, TDRedactObject(json));
        return;
    }
    if ([object isKindOfClass:NSData.class]) {
        NSString *body = [[NSString alloc] initWithData:object encoding:NSUTF8StringEncoding];
        if (body.length) TDProbeLog(@"BODY source=%@ url=%@ body=%@", source, url ?: @"", body);
    }
}

static BOOL TDInterestingURL(NSString *url) {
    if (!url.length) return NO;
    NSArray *words = @[@"order", @"dispatch", @"push", @"driver", @"listen", @"grab", @"accept", @"websocket", @"token", @"deviceprint", @"devicetoken", @"risk-gateway", @"security.xiaojukeji.com"];
    for (NSString *word in words) {
        if ([url rangeOfString:word options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static BOOL TDInterestingPayload(id object) {
    NSString *text = nil;
    if ([object isKindOfClass:NSData.class]) text = [[NSString alloc] initWithData:object encoding:NSUTF8StringEncoding];
    else if ([object isKindOfClass:NSString.class]) text = object;
    else if ([object isKindOfClass:NSDictionary.class]) text = [(NSDictionary *)object description];
    if (!text.length) return NO;
    NSArray *words = @[@"token_config", @"auToken", @"ddfp", @"access_token", @"refresh_token", @"device_token", @"push_token", @"devicetoken", @"deviceprint", @"ticket"];
    for (NSString *word in words) {
        if ([text rangeOfString:word options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static id TDRedactObject(id object) {
    if ([object isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            NSString *name = [[key description] lowercaseString];
            BOOL secret = [name containsString:@"token"] || [name containsString:@"ticket"] || [name containsString:@"secret"] || [name containsString:@"cookie"] || [name containsString:@"authorization"] || [name containsString:@"password"] || [name containsString:@"ddfp"];
            result[key] = secret ? @"<redacted>" : TDRedactObject(value);
        }];
        return result;
    }
    if ([object isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [NSMutableArray array];
        for (id value in (NSArray *)object) [result addObject:TDRedactObject(value) ?: [NSNull null]];
        return result;
    }
    return object;
}

static NSString *TDRedactText(NSString *text) {
    if (!text.length) return @"";
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (object) {
        id redacted = TDRedactObject(object);
        NSData *encoded = [NSJSONSerialization dataWithJSONObject:redacted options:0 error:nil];
        return encoded ? [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding] : @"<json>";
    }
    return [NSString stringWithFormat:@"<non-json length=%lu>", (unsigned long)text.length];
}

static void TDProbeLogPayloadIfInteresting(id object, NSString *kind, NSString *url) {
    if (!TDInterestingPayload(object)) return;
    if ([object isKindOfClass:NSData.class]) {
        NSString *text = [[NSString alloc] initWithData:object encoding:NSUTF8StringEncoding];
        TDProbeLog(@"TK_%@ url=%@ length=%lu payload=%@", kind, url ?: @"", (unsigned long)[(NSData *)object length], TDRedactText(text));
    } else {
        TDProbeLog(@"TK_%@ url=%@ payload=%@", kind, url ?: @"", TDRedactObject(object));
    }
}

static void TDEnumerateClass(NSString *name);

static BOOL TDInterestingClassName(NSString *name) {
    NSArray *words = @[@"driver", @"dispatch", @"order", @"push", @"socket", @"listen", @"homepage", @"ride", @"trip", @"token", @"deviceprint"];
    for (NSString *word in words) {
        if ([name rangeOfString:word options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static void TDEnumerateLoadedClasses(void) {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return;
    Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * (NSUInteger)count);
    int actual = objc_getClassList(classes, count);
    TDProbeLog(@"CLASS_SCAN count=%d", actual);
    for (int i = 0; i < actual; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if (TDInterestingClassName(name)) TDEnumerateClass(name);
    }
    free(classes);
}

static void TDEnumerateClass(NSString *name) {
    Class cls = NSClassFromString(name);
    if (!cls) {
        TDProbeLog(@"CLASS_MISSING %@", name);
        return;
    }
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    TDProbeLog(@"CLASS_FOUND %@ methods=%u", name, count);
    for (unsigned int i = 0; i < count; i++) {
        SEL selector = method_getName(methods[i]);
        NSString *sel = NSStringFromSelector(selector);
        if ([sel rangeOfString:@"order" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [sel rangeOfString:@"dispatch" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [sel rangeOfString:@"push" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [sel rangeOfString:@"accept" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [sel rangeOfString:@"grab" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [sel rangeOfString:@"confirm" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [sel rangeOfString:@"switch" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [sel rangeOfString:@"message" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            TDProbeLog(@"METHOD %@ %@ types=%s", name, sel, method_getTypeEncoding(methods[i]));
        }
    }
    free(methods);
}

static void TDInstallInstanceSwizzle(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (!a || !b) {
        TDProbeLog(@"SWIZZLE_MISSING %@ %@", NSStringFromClass(cls), NSStringFromSelector(original));
        return;
    }
    method_exchangeImplementations(a, b);
    TDProbeLog(@"SWIZZLE_OK %@ %@", NSStringFromClass(cls), NSStringFromSelector(original));
}

@interface NSURLSession (DidiTingdanProbe)
@end

@implementation NSURLSession (DidiTingdanProbe)

- (NSURLSessionDataTask *)td_probe_dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSString *url = request.URL.absoluteString ?: @"";
    if (TDInterestingURL(url) || TDInterestingPayload(request.HTTPBody)) {
        TDProbeLog(@"REQUEST method=%@ url=%@ headers=%@ body=%@", request.HTTPMethod, url, TDRedactObject(request.allHTTPHeaderFields), TDRedactText([[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding]));
        TDProbeLogPayloadIfInteresting(request.HTTPBody, @"REQUEST", url);
    }
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *responseURL = response.URL.absoluteString ?: url;
        if (TDInterestingURL(responseURL) || TDInterestingPayload(data)) {
            TDProbeLog(@"RESPONSE status=%ld url=%@ error=%@", (long)[(NSHTTPURLResponse *)response statusCode], responseURL, error);
            TDProbeLogPayloadIfInteresting(data, @"RESPONSE", responseURL);
            TDRecordPayload(data, @"NSURLSession", responseURL);
        }
        if (completionHandler) completionHandler(data, response, error);
    };
    return [self td_probe_dataTaskWithRequest:request completionHandler:wrapped];
}

@end

@interface UIApplication (DidiTingdanProbe)
@end

@implementation UIApplication (DidiTingdanProbe)

- (BOOL)td_probe_sendAction:(SEL)action to:(id)target from:(id)sender forEvent:(UIEvent *)event {
    NSString *targetName = target ? NSStringFromClass([target class]) : @"nil";
    NSString *senderName = sender ? NSStringFromClass([sender class]) : @"nil";
    TDProbeLog(@"UI_ACTION selector=%@ target=%@ sender=%@", NSStringFromSelector(action), targetName, senderName);
    return [self td_probe_sendAction:action to:target from:sender forEvent:event];
}


- (BOOL)td_probe_application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    BOOL result = [self td_probe_application:application didFinishLaunchingWithOptions:options];
    TDProbeLog(@"APP_LAUNCHED bundle=%@ options=%@", NSBundle.mainBundle.bundleIdentifier, options);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[TDOverlay shared] install];
        for (NSString *name in @[@"HomepageDispatch", @"DriverSwitchRes", @"PushManager2", @"CHNDriver", @"DriverOrderRouteReq", @"DriverOrderRouteRes"]) TDEnumerateClass(name);
        TDEnumerateLoadedClasses();
    });
    return result;
}

@end

__attribute__((constructor))
static void DidiTingdanProbeInit(void) {
    @autoreleasepool {
        TDProbeLog(@"DYLIB_LOADED bundle=%@ version=%@", NSBundle.mainBundle.bundleIdentifier, [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]);
        TDInstallInstanceSwizzle(NSURLSession.class, @selector(dataTaskWithRequest:completionHandler:), @selector(td_probe_dataTaskWithRequest:completionHandler:));
        TDInstallInstanceSwizzle(UIApplication.class, @selector(application:didFinishLaunchingWithOptions:), @selector(td_probe_application:didFinishLaunchingWithOptions:));
        TDInstallInstanceSwizzle(UIApplication.class, @selector(sendAction:to:from:forEvent:), @selector(td_probe_sendAction:to:from:forEvent:));
        TDInstallInstanceSwizzle(NSURLSessionTask.class, @selector(resume), @selector(td_probe_resume));
        TDProbeLog(@"AUTO_GRAB_DISABLED probe_only=YES");
    }
}
