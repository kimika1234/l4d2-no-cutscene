# [L4D2] No Cutscene - 删除所有过场动画

> 跳过开场运镜 + 击杀中途运镜（point_viewcontrol 系列）+ 删除 ghostanim 演出实体
> 基于 SilverShot 的 [L4D & L4D2] First Map - Skip Intro Cutscenes (v1.13, GPLv3) 扩展

## 功能

| 目标 | 机制 | 手段 |
|------|------|------|
| 🎬 开场运镜 | `gameinstructor_nodraw` 事件触发 | 发 `FinishIntro` + `ReleaseSurvivorPositions` 直接结束开场 |
| 🎥 中途运镜 | `point_viewcontrol` / `_survivor` / `_multiplayer` | 0.3s 周期扫描 + `OnEntityCreated` 动态拦截，`RemoveEntity` 引擎级删除 |
| 👻 ghostanim 演出 | `models/ghostanim*.mdl` 透明动画替身 | 按模型名识别（prop_dynamic/_override/prop_physics），直接删除 |

## 部署方法

1. 把 `addons/` 目录内容复制到服务器 `left4dead2/` 目录（与现有 addons/ 合并）
2. 把 `cfg/` 目录内容复制到服务器 `left4dead2/` 目录（与现有 cfg/ 合并）
3. 重启服务器 或 控制台执行 `sm plugins load l4d2_no_cutscene`

文件结构（对齐服务器目录）：
```
left4dead2/
├── addons/sourcemod/plugins/l4d2_no_cutscene.smx   # 插件本体
├── addons/sourcemod/scripting/l4d2_no_cutscene.sp  # 源码
└── cfg/sourcemod/l4d2_no_cutscene.cfg              # ConVar 自动生成参考配置
```

## ConVar

| ConVar | 默认 | 说明 |
|--------|------|------|
| `l4d2_no_cutscene_allow` | 1 | 0=关闭 1=开启 |
| `l4d2_no_cutscene_mode` | 2 | 1=只跳开场 2=跳开场+杀中途运镜 |
| `l4d2_no_cutscene_intro_time` | 8.0 | 开场保护窗口秒数（先让 FinishIntro 解锁玩家再杀实体） |
| `l4d2_no_cutscene_kill_ghostanim` | 1 | 0=保留 ghostanim 1=删除演出实体 |

## 版本记录

### v1.0.2
- **修复核心坑**：point_viewcontrol 系列实体**不吃实体 `Kill` 输入**（`ent_fire ... Kill` 实测无效），改用 SourceMod `RemoveEntity()` 引擎级删除（等价 `ent_remove`），红场 `camera_intro_survivor` 实体实测 6→0
- 真实服务器验证：103 农场 57404 服，红场/baka3/dxyl 三张三方图连续切换零崩溃

### v1.0.1
- 修复 `gameinstructor_nodraw` 中途触发导致保护窗口反复刷新、扫描器永远不杀实体的问题（加 `g_bIntroDone` 标记）

### v1.0.0
- 初版：开场跳过 + 中途运镜击杀 + ghostanim 删除

## 许可

GPLv3（基于 SilverShot 的 l4d_skip_intro v1.13，含其版权头与变更日志）