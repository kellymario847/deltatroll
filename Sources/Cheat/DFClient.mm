#import "DFClient.h"
#import "ExploitController.h"
#import <mach/mach.h>

// ---------------------------------------------------------------------------
// DeltaForceClient：读三角洲行动进程内存。
//  路径：task_for_pid-allow entitlement -> task_for_pid(game) -> mach_vm_read。
//  有 entitlement 就不再用内核原语读游戏，ACE 只见普通 Mach 调用。
//  版本更新只动 DFConfig.plist（偏移/特征码），二进制不用重出。
// ---------------------------------------------------------------------------

@interface DFClient () {
    task_t _gameTask;
    pid_t  _gamePid;
    uint64_t _entityList;   // 已解析的全局实体列表地址
    uint64_t _viewMatrix;   // 视图矩阵地址
    BOOL   _resolved;
}
@end

@implementation DFClient

+ (instancetype)shared {
    static DFClient *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [DFClient new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    NSString *p = [[NSBundle mainBundle] pathForResource:@"DFConfig" ofType:@"plist"];
    _offsets = p ? [NSDictionary dictionaryWithContentsOfFile:p] : @{};
    return self;
}

// MARK: - 附加

- (BOOL)attachWithError:(NSString **)err {
    // 游戏进程名可能随渠道变化，配置里给候选列表
    NSArray *names = _offsets[@"ProcessNames"] ?: @[@"DeltaForce", @"delta", @"DeltaForceClient"];
    _gamePid = 0;
    for (NSString *n in names) {
        _gamePid = [self findPid:n];
        if (_gamePid) break;
    }
    if (!_gamePid) {
        if (err) *err = @"未找到游戏进程";
        return NO;
    }
    kern_return_t kr = task_for_pid(mach_task_self(), _gamePid, &_gameTask);
    if (kr != KERN_SUCCESS) {
        if (err) *err = [NSString stringWithFormat:@"task_for_pid 失败: %s", mach_error_string(kr)];
        _gameTask = MACH_PORT_NULL;
        return NO;
    }
    [self resolveGlobals];
    return YES;
}

- (pid_t)findPid:(NSString *)name {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t sz = 0;
    sysctl(mib, 4, NULL, &sz, NULL, 0);
    struct kinfo_proc *procs = (struct kinfo_proc *)malloc(sz);
    if (sysctl(mib, 4, procs, &sz, NULL, 0) != 0) { free(procs); return 0; }
    pid_t r = 0;
    int n = (int)(sz / sizeof(struct kinfo_proc));
    for (int i = 0; i < n; i++) {
        NSString *pname = [NSString stringWithUTF8String:procs[i].kp_proc.p_comm];
        if ([pname isEqualToString:name]) { r = procs[i].kp_proc.p_pid; break; }
    }
    free(procs);
    return r;
}

// MARK: - 全局地址解析（特征码优先，失败用静态偏移）

- (void)resolveGlobals {
    _resolved = NO;
    uint64_t img = [self mainImageBase];

    // 1) 特征码扫 __TEXT 解 adrp 引用（等价原版 pattern 方案）
    _entityList = [self scanGlobal:img
                            pattern:_offsets[@"EntityListPattern"]
                              addend:[_offsets[@"EntityListAddend"] unsignedLongLongValue]];
    _viewMatrix = [self scanGlobal:img
                            pattern:_offsets[@"ViewMatrixPattern"]
                              addend:[_offsets[@"ViewMatrixAddend"] unsignedLongLongValue]];

    // 2) 兜底：image base + 静态 RVA
    if (!_entityList) _entityList = img + [_offsets[@"EntityListRVA"] unsignedLongLongValue];
    if (!_viewMatrix) _viewMatrix = img + [_offsets[@"ViewMatrixRVA"] unsignedLongLongValue];

    _resolved = _entityList != 0 && _viewMatrix != 0;
}

- (uint64_t)mainImageBase {
    task_dyld_info_data_t dyldInfo;
    mach_msg_type_number_t cnt = TASK_DYLD_INFO_COUNT;
    if (task_info(_gameTask, TASK_DYLD_INFO, (task_info_t)&dyldInfo, &cnt) != KERN_SUCCESS) return 0;
    if (!dyldInfo.all_image_info_addr) return 0;
    // dyld_all_image_info -> infoArray[0].imageLoadAddress = 主二进制基址
    uint64_t infoArray = 0;
    [self read:dyldInfo.all_image_info_addr + 0x8 buf:&infoArray len:8]; // infoArray 偏移随 dyld 版本微调
    uint64_t base = 0;
    [self read:infoArray buf:&base len:8];
    return base;
}

- (BOOL)read:(uint64_t)addr buf:(void *)buf len:(size_t)len {
    vm_size_t out = 0;
    return mach_vm_read_overwrite(_gameTask, addr, len, (vm_address_t)buf, &out) == KERN_SUCCESS;
}

- (uint64_t)read64:(uint64_t)a { uint64_t v = 0; [self read:a buf:&v len:8]; return v; }
- (uint32_t)read32:(uint64_t)a { uint32_t v = 0; [self read:a buf:&v len:4]; return v; }
- (float)readF32:(uint64_t)a { float v = 0; [self read:a buf:&v len:4]; return v; }

/// 在 __TEXT 段扫特征码（格式 "48 8D ?? 91 C8 ?? ?? 91"），命中后解最近 adrp 的全局地址
- (uint64_t)scanGlobal:(uint64_t)img pattern:(NSString *)pat addend:(uint64_t)addend {
    if (!pat.length || !img) return 0;

    // 解析 pattern
    NSMutableData *bytes = [NSMutableData data];
    NSMutableData *mask  = [NSMutableData data];
    for (NSString *tok in [pat componentsSeparatedByString:@" "]) {
        if ([tok isEqual:@"??"]) { [bytes appendBytes:"\x00" length:1]; [mask appendBytes:"\x00" length:1]; }
        else { unsigned int b; [[NSScanner scannerWithString:tok] scanHexInt:&b];
               uint8_t bb = b; [bytes appendBytes:&bb length:1]; [mask appendBytes:@"\x01" length:1]; }
    }

    // 读 __TEXT（64MB 上限足够覆盖主二进制代码段）
    size_t scanSize = 64 * 1024 * 1024;
    uint8_t *buf = (uint8_t *)malloc(scanSize);
    if (![self read:img buf:buf len:scanSize]) { free(buf); return 0; }

    uint64_t result = 0;
    const uint8_t *pb = (const uint8_t *)bytes.bytes;
    const uint8_t *pm = (const uint8_t *)mask.bytes;
    size_t plen = bytes.length;
    for (size_t off = 0; off + plen < scanSize; off += 4) {
        BOOL hit = YES;
        for (size_t j = 0; j < plen; j++) if (pm[j] && buf[off+j] != pb[j]) { hit = NO; break; }
        if (!hit) continue;
        uint64_t hitVA = img + off;
        // 回退 0x100 字节找最近的 adrp，解码页基址
        for (uint64_t back = 0; back < 0x100; back += 4) {
            uint32_t ins = 0; [self read:hitVA - back buf:&ins len:4];
            if ((ins & 0x9F000000) == 0x90000000) {
                uint64_t pc = hitVA - back;
                uint64_t page = (pc & ~0xFFFULL)
                    + (((ins >> 29) & 3) << 12)
                    + (((ins >> 5) & 0x7FFFF) << 14 >> 2);
                result = addend ? page + addend : page;
                break;
            }
        }
        if (result) break;
    }
    free(buf);
    return result;
}

// MARK: - 实体抓取

- (NSInteger)fetchEntities:(DFEntity *)out max:(NSInteger)max {
    if (!_resolved || _gameTask == MACH_PORT_NULL) return 0;
    NSDictionary *o = _offsets;
    uint32_t nodeNext   = [o[@"NodeNext"] unsignedIntValue]   ?: 0x10;
    uint32_t nodeEntity = [o[@"NodeEntity"] unsignedIntValue] ?: 0x18;
    uint32_t entOrigin  = [o[@"EntOrigin"] unsignedIntValue];
    uint32_t entHealth  = [o[@"EntHealth"] unsignedIntValue];
    uint32_t entTeam    = [o[@"EntTeam"] unsignedIntValue];
    uint32_t entName    = [o[@"EntName"] unsignedIntValue];
    uint32_t entFlags   = [o[@"EntVisibleFlags"] unsignedIntValue];
    uint32_t visibleBit = [o[@"VisibleBit"] unsignedIntValue];
    if (!entOrigin || !entHealth) return 0;

    int myTeam = 0;
    NSInteger n = 0;
    uint64_t listRoot = [self read64:_entityList];
    uint64_t node = [self read64:listRoot + nodeNext];
    int guard = 0;
    while (node && node != listRoot && n < max && guard++ < 512) {
        uint64_t ent = [self read64:node + nodeEntity];
        if (ent) {
            DFEntity s = {};
            [self read:ent + entOrigin buf:&s.origin len:12];
            s.head = s.origin; s.head.z += 1.75f;
            s.health = [self readF32:ent + entHealth];
            s.team   = [self read32:ent + entTeam];
            if (myTeam == 0) myTeam = s.team;
            s.isEnemy = (s.team != myTeam);
            if (entFlags) {
                uint32_t f = [self read32:ent + entFlags];
                s.visible = (f & (1u << visibleBit)) != 0;
            } else s.visible = YES;
            if (entName) {
                uint64_t namePtr = [self read64:ent + entName];
                if (namePtr > 0x100000000) [self read:namePtr buf:s.name len:63];
            }
            if (s.health > 0) out[n++] = s;
        }
        node = [self read64:node + nodeNext];
    }
    return n;
}

// MARK: - 投影

- (BOOL)worldToScreen:(DFVec3)w screenW:(float)sw screenH:(float)sh
                     x:(float *)sx y:(float *)sy depth:(float *)sz {
    if (!_resolved) return NO;
    float m[16];
    if (![self read:_viewMatrix buf:m len:sizeof(m)]) return NO;
    float cx = m[0]*w.x + m[4]*w.y + m[8]*w.z  + m[12];
    float cy = m[1]*w.x + m[5]*w.y + m[9]*w.z  + m[13];
    float cw = m[3]*w.x + m[7]*w.y + m[11]*w.z + m[15];
    if (cw < 1.0f) return NO;
    *sx = (sw * 0.5f) + (cx / cw) * (sw * 0.5f);
    *sy = (sh * 0.5f) - (cy / cw) * (sh * 0.5f);
    *sz = cw;
    return YES;
}

@end
