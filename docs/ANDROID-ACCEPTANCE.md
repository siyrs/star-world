# Android 完整验收与兼容性记录

## 当前结论

2026-07-12 首轮检查暂无法执行 Android 安装和功能验收。当前项目是 Godot 4 的 Windows x64 游戏，仓库没有 Android 导出预设、Android Gradle 工程、APK/AAB 或 Android 启动 Activity。

因此，以下内容不能在当前版本宣称通过：

- 红米真机完整功能验收
- 小米真机完整功能验收
- 两个不同 Android 版本模拟器验收
- Android 版本兼容性验证

本记录只记录前置阻塞，不代表功能缺陷已经修复或 Android 兼容性已经验证。

## 检查证据

| 检查项 | 结果 |
|---|---|
| Godot 导出预设 | 仅有 `Windows Desktop` |
| 项目目标 | 文档明确为 Windows x86_64 |
| Android Gradle 工程 | 未发现 `build.gradle`、`settings.gradle`、`AndroidManifest.xml` 或 `gradlew` |
| Android 安装包 | 未发现 APK/AAB |
| Android 模拟器命令 | 当前环境未发现 `emulator` 命令，也没有可用 AVD 列表 |
| Android SDK | 已安装 Android 25 至 Android 36 平台，但没有可直接验收的 Android 构建产物 |

## 已连接真机

| 设备 | ADB 序列号 | Android 版本 | API | 状态 |
|---|---|---:|---:|---|
| 红米 Note 5 | `928bc814` | 9 | 28 | 已连接，等待 Android 包 |
| 小米 13 Ultra | `d93ec76` | 16 | 36 | 已连接，等待 Android 包 |

## 待补齐的验收条件

1. 增加 Godot Android 导出预设，并确认 Android 渲染、输入、权限和存档路径适配。
2. 导出可安装的 APK，明确包名、版本号和主 Activity。
3. 准备两个不同 Android API 级别的模拟器，并让它们出现在 `adb devices`。
4. 在四个目标设备上分别执行安装、冷启动、主菜单、建世界、探索、破坏/放置、背包、合成、战斗、生存、昼夜、保存/退出/恢复、设置、暂停、死亡/重生和返回流程。
5. 每台设备保存 UI 树、关键截图、安装/启动结果、崩溃日志和兼容性结论。
6. 对发现的问题建立独立问题编号，后续修复后再回归验证；当前阶段不修改实现。

## 验收状态

**Blocked：缺少 Android 构建目标和可安装包。**

Windows 发行包仍可按现有 Windows QA 记录使用；本文件专门记录 Android 验收前置条件，不覆盖 Windows 验收结论。
