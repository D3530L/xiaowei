#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "TDStore.h"

extern void TDProbeLog(NSString *format, ...);

@interface NSURLSessionTask (DidiTingdanTaskProbe)
@end

@implementation NSURLSessionTask (DidiTingdanTaskProbe)

- (void)td_probe_resume {
    NSURLRequest *request = self.currentRequest;
    NSString *url = request.URL.absoluteString ?: @"";
    if ([url rangeOfString:@"order" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [url rangeOfString:@"dispatch" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [url rangeOfString:@"driver" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [url rangeOfString:@"token" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [url rangeOfString:@"push" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        TDProbeLog(@"TASK_RESUME %@ %@", request.HTTPMethod ?: @"", url);
    }
    [self td_probe_resume];
}

@end
