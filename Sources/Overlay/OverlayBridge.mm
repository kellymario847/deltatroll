#import "OverlayBridge.h"
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

#import "imgui.h"
#import "imgui_impl_metal.h"
#import "DFClient.h"
#import "ExploitController.h"

// ---------------------------------------------------------------------------
// 覆盖层：透明 UIWindow(level=+100) + CAMetalLayer + ImGui。
// 游戏画面在上层（窗口层级低于游戏全屏窗口时直接盖不住——
// 原版做法是把覆盖层 level 设为 UIWindowLevelStatusBar+100 并配合
// accessibility-window-hosting entitlement 置顶）。菜单区域吃触摸，其余穿透。
// ---------------------------------------------------------------------------

static BOOL g_visible = NO;

/// 把触摸喂给 ImGui（菜单点按/滑条）
static void DT_FeedTouches(CGPoint p, BOOL down) {
    ImGuiIO &io = ImGui::GetIO();
    io.MousePos = ImVec2(p.x, p.y);
    io.MouseDown[0] = down;
}

/// 穿透容器：菜单捕获触摸时给 ImGui，否则返回 nil 穿透到游戏
@interface DTPassthroughView : UIView
@end
@implementation DTPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!g_visible) return nil;
    ImGuiIO &io = ImGui::GetIO();
    if (io.WantCaptureMouse) return self;
    return nil;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    DT_FeedTouches([touches.anyObject locationInView:self], YES);
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    DT_FeedTouches([touches.anyObject locationInView:self], YES);
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    DT_FeedTouches([touches.anyObject locationInView:self], NO);
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    DT_FeedTouches([touches.anyObject locationInView:self], NO);
}
@end

#pragma mark - 菜单配置（ImGui 内调整，对应原版 imgui.ini）

typedef struct {
    bool espBox = true;
    bool espHealth = true;
    bool espName = false;
    bool espSkeleton = false;
    bool espVisibleOnly = false;
    bool espEnemyOnly = true;
    float maxDistance = 300.f;
    int aimSmooth = 8;
} DTConfig;

static DTConfig g_cfg;

@implementation OverlayHost {
    UIWindow *_window;
    CAMetalLayer *_metalLayer;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _ps;
    CADisplayLink *_link;
    ImGuiContext *_imgui;
}

- (instancetype)initWithScene:(UIWindowScene *)scene {
    self = [super init];
    _device = MTLCreateSystemDefaultDevice();
    _queue = [_device newCommandQueue];

    _window = [[UIWindow alloc] initWithWindowScene:scene];
    _window.frame = UIScreen.mainScreen.bounds;
    _window.windowLevel = UIWindowLevelStatusBar + 100;
    _window.backgroundColor = UIColor.clearColor;
    _window.hidden = YES;
    _window.rootViewController = [UIViewController new];
    _window.rootViewController.view = [DTPassthroughView new];
    _window.rootViewController.view.userInteractionEnabled = YES;

    UIView *v = _window.rootViewController.view;
    v.backgroundColor = UIColor.clearColor;
    v.frame = _window.bounds;

    _metalLayer = [CAMetalLayer layer];
    _metalLayer.device = _device;
    _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _metalLayer.framebufferOnly = NO;
    _metalLayer.opaque = NO;
    _metalLayer.frame = v.bounds;
    [v.layer addSublayer:_metalLayer];

    // ImGui 初始化
    IMGUI_CHECKVERSION();
    _imgui = ImGui::CreateContext();
    ImGui::StyleColorsDark();
    ImGuiIO &io = ImGui::GetIO();
    io.IniFilename = "imgui.ini";
    ImGui_ImplMetal_Init(_device);

    // 顶点着色器/片元着色器（imgui_impl_metal 自带 default 渲染管线需要 shader，
    // 这里用 imgui_impl_metal 的 shader 编译路径，无须手写）
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(render)];
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    return self;
}

- (void)attachIfNeeded {
    if (_window.hidden && g_visible) _window.hidden = NO;
}

- (void)show { _window.hidden = NO; g_visible = YES; }
- (void)hide { _window.hidden = YES; g_visible = NO; }

- (void)render {
    if (_window.hidden) return;

    @autoreleasepool {
        ImGuiIO &io = ImGui::GetIO();
        CGSize sz = _window.bounds.size;
        CGFloat scale = UIScreen.mainScreen.scale;
        io.DisplaySize = ImVec2(sz.width, sz.height);
        io.DisplayFramebufferScale = ImVec2(scale, scale);

        // 触摸注入 ImGui：menu 可见时转发，否则穿透
        // （原版用 _touchesEvent hook + IO MouseDown 注入，这里由 hitTest 拦截转发）

        id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
        if (!drawable) return;

        MTLRenderPassDescriptor *pd = [MTLRenderPassDescriptor renderPassDescriptor];
        pd.colorAttachments[0].texture = drawable.texture;
        pd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
        pd.colorAttachments[0].loadAction = MTLLoadActionClear;
        pd.colorAttachments[0].storeAction = MTLStoreActionStore;

        id<MTLCommandBuffer> cb = [_queue commandBuffer];
        id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:pd];
        if (!enc) return;

        ImGui_ImplMetal_NewFrame(pd);
        ImGui::NewFrame();

        DT_RenderFrame();   // ESP + 菜单

        ImGui::Render();
        ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), cb, enc);

        [enc endEncoding];
        [cb presentDrawable:drawable];
        [cb commit];
    }
}

/// 菜单区域吃触摸，其他区域穿透（返回 nil 即穿透）
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!g_visible) return nil;
    ImGuiIO &io = ImGui::GetIO();
    if (io.WantCaptureMouse) return _window.rootViewController.view;
    return nil;
}

@end

#pragma mark - OverlayBridge

@implementation OverlayBridge
+ (instancetype)shared {
    static OverlayBridge *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [OverlayBridge new]; });
    return s;
}
- (void)showOverlay { [self.overlay show]; }
@end

void DT_SetOverlayVisible(BOOL v) { g_visible = v; }
BOOL DT_OverlayVisible(void) { return g_visible; }

#pragma mark - 每帧 ESP + 菜单（C++）

void DT_RenderFrame() {
    ImGuiIO &io = ImGui::GetIO();

    // ---- ESP ----
    static DFEntity ents[128];
    NSInteger n = [[DFClient shared] fetchEntities:ents max:128];
    float sw = io.DisplaySize.x, sh = io.DisplaySize.y;
    ImDrawList *dl = ImGui::GetBackgroundDrawList();
    DFClient *cli = [DFClient shared];

    for (NSInteger i = 0; i < n; i++) {
        DFEntity *e = &ents[i];
        if (g_cfg.espEnemyOnly && !e->isEnemy) continue;
        if (g_cfg.espVisibleOnly && !e->visible) continue;

        float hx, hy, hz, fx, fy, fz;
        if (![cli worldToScreen:e->head screenW:sw screenH:sh x:&hx y:&hy depth:&hz]) continue;
        if (![cli worldToScreen:e->origin screenW:sw screenH:sh x:&fx y:&fy depth:&fz]) continue;
        if (hz < 0 || hz > g_cfg.maxDistance) continue;
        if (hx < -100 || hx > sw + 100 || hy < -100 || hy > sh + 100) continue;

        float h = fabsf(fy - hy);
        float w = h * 0.45f;
        ImU32 col = e->isEnemy
            ? (e->visible ? IM_COL32(255, 60, 60, 255) : IM_COL32(160, 60, 60, 160))
            : IM_COL32(60, 220, 60, 200);

        if (g_cfg.espBox)
            dl->AddRect(ImVec2(hx - w/2, hy), ImVec2(hx + w/2, fy), col, 0, 0, 1.5f);

        if (g_cfg.espHealth) {
            float pct = e->health > 100 ? 1 : (e->health < 0 ? 0 : e->health / 100.f);
            dl->AddRectFilled(ImVec2(hx - w/2 - 5, hy), ImVec2(hx - w/2 - 2, fy), IM_COL32(0,0,0,180));
            dl->AddRectFilled(ImVec2(hx - w/2 - 5, hy + h*(1-pct)), ImVec2(hx - w/2 - 2, fy),
                              IM_COL32((int)(255*(1-pct)), (int)(255*pct), 0, 255));
        }

        if (g_cfg.espName && e->name[0])
            dl->AddText(ImVec2(hx - w/2, hy - 14), col, e->name);
    }

    // ---- 菜单 ----
    ImGui::SetNextWindowSize(ImVec2(260, 300), ImGuiCond_FirstUseEver);
    ImGui::Begin("DeltaTroll", nullptr,
                 ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize);
    ImGui::Checkbox("透视方框", &g_cfg.espBox);
    ImGui::Checkbox("血条", &g_cfg.espHealth);
    ImGui::Checkbox("名字", &g_cfg.espName);
    ImGui::Checkbox("仅可见", &g_cfg.espVisibleOnly);
    ImGui::Checkbox("仅敌人", &g_cfg.espEnemyOnly);
    ImGui::SliderFloat("距离", &g_cfg.maxDistance, 50.f, 1000.f);
    ImGui::SliderInt("平滑", &g_cfg.aimSmooth, 1, 20);
    if (ImGui::Button("隐藏菜单")) DT_SetOverlayVisible(NO);
    ImGui::End();
}
