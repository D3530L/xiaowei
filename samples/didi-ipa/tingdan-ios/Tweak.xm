#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "TDStore.h"
#import "TDOverlay.h"
#import "TDAutoGrab.h"
#import <CoreLocation/CoreLocation.h>

static NSDictionary *TDNormalizeObject(id object) {
    if ([object isKindOfClass:NSDictionary.class]) return object;
    if ([object isKindOfClass:NSData.class]) {
        id json = [NSJSONSerialization JSONObjectWithData:object options:0 error:nil];
        if ([json isKindOfClass:NSDictionary.class]) return json;
    }
    if ([object isKindOfClass:NSString.class]) {
        NSData *data = [(NSString *)object dataUsingEncoding:NSUTF8StringEncoding];
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:NSDictionary.class]) return json;
    }
    return nil;
}

static void TDRecord(id object, NSString *source) {
    NSDictionary *order = TDNormalizeObject(object);
    if (order) {
        [[TDStore shared] recordOrder:order source:source];
        [[TDAutoGrab shared] considerOrder:order];
    }
}

%hook UIApplication
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    BOOL result = %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[TDOverlay shared] install];
    });
    return result;
}
%end

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *url = response.URL.absoluteString ?: request.URL.absoluteString ?: @"";
        if ([url rangeOfString:@"order" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [url rangeOfString:@"dispatch" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [url rangeOfString:@"push" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            TDRecord(data, url);
        }
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(request, wrapped);
}
%end

%hook NSObject
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    NSString *url = task.currentRequest.URL.absoluteString ?: @"";
    if ([url rangeOfString:@"order" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [url rangeOfString:@"dispatch" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        TDRecord(data, url);
    }
    %orig;
}
%end

%ctor {
    NSLog(@"[DidiTingdan] loaded for com.xiaojukeji.didi");
}
