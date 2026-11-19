#pragma once
#import <Foundation/Foundation.h>

typedef struct {
    float x, y, z;
} DFVec3;

typedef struct {
    DFVec3 origin;      // 脚底世界坐标
    DFVec3 head;
    float  health;      // 0~100
    int    team;
    BOOL   isEnemy;
    BOOL   visible;
    char   name[64];
} DFEntity;

@interface DFClient : NSObject

+ (instancetype)shared;

/// 找游戏进程并建立 task port；未运行返回 NO（游戏启动后可重试）
- (BOOL)attachWithError:(NSString **)err;

/// 每帧调用：抓取实体快照，返回数量
- (NSInteger)fetchEntities:(DFEntity *)out max:(NSInteger)max;

/// 世界->屏幕（读游戏 ViewMatrix 投影）
- (BOOL)worldToScreen:(DFVec3)w screenW:(float)sw screenH:(float)sh
                     x:(float *)sx y:(float *)sy depth:(float *)sz;

/// 菜单配置透传（plist 热更偏移）
@property (nonatomic, strong) NSDictionary *offsets;

@end
