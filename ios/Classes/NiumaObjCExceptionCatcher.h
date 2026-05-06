#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// ObjC try/catch 桥——Swift 调 ObjC API 抛 `NSException` 时无法用
/// `do-catch` 抓（Swift `do-catch` 只抓 `Error` 协议）。把可能抛
/// `NSException` 的代码包在 `[NiumaObjCExceptionCatcher tryBlock:...]`
/// 里调用，把异常转成 Swift `Error`（`NSError`）让 Swift 端能优雅处理。
///
/// 用例：调私有 selector（如 `UIApplication.suspend`）时，未来 iOS 版本
/// 若 selector 行为变化抛异常，本桥避免线程崩。
@interface NiumaObjCExceptionCatcher : NSObject

/// 跑 [block]——若 block 抛 NSException，捕获后填 [error] 并返 `NO`；
/// 正常完成返 `YES`。`error` 可为 `NULL`。
///
/// 方法名特意叫 `catchExceptions:` 而不是 `tryBlock:`：Swift 把 ObjC
/// `+ tryBlock:error:` 自动改造成 `try(_:)`，撞 Swift 关键字。
+ (BOOL)catchExceptions:(__attribute__((noescape)) void (^)(void))block
                   error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
