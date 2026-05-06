#import "NiumaObjCExceptionCatcher.h"

@implementation NiumaObjCExceptionCatcher

+ (BOOL)catchExceptions:(void (^)(void))block
                   error:(NSError **)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            if (exception.name) {
                userInfo[@"name"] = exception.name;
            }
            if (exception.reason) {
                userInfo[@"reason"] = exception.reason;
            }
            if (exception.userInfo) {
                userInfo[@"objcUserInfo"] = exception.userInfo;
            }
            *error = [NSError errorWithDomain:@"cn.niuma.NiumaObjCException"
                                         code:0
                                     userInfo:userInfo];
        }
        return NO;
    }
}

@end
