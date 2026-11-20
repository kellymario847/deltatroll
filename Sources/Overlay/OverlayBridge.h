#pragma once
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@class OverlayHost;

/// Swift 侧宿主（UIWindow 管理）
@interface OverlayHost : NSObject
- (instancetype)initWithScene:(UIWindowScene *)scene;
- (void)attachIfNeeded;
- (void)show;
- (void)hide;
@end

/// 桥：C++ ImGui 渲染回调挂载点
@interface OverlayBridge : NSObject
@property (nonatomic, weak) OverlayHost *overlay;
+ (instancetype)shared;
- (void)showOverlay;
@end

#ifdef __cplusplus
extern "C" {
#endif
/// ESP 渲染层每帧入口（在 OverlayBridge.mm 中实现，供 CADisplayLink 调用）
void DT_RenderFrame(void);
void DT_SetOverlayVisible(BOOL visible);
BOOL DT_OverlayVisible(void);
#ifdef __cplusplus
}
#endif
