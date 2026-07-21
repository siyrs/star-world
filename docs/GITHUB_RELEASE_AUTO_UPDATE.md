# GitHub Release 自动更新

## 玩家流程

Windows 发行包每次进程首次进入主菜单时检查一次：

```text
GitHub /releases/latest
→ 比较稳定语义版本
→ 精确选择 Windows ZIP 与 .sha256
→ 提示玩家
→ 可续传下载
→ SHA-256 与包清单双重校验
→ 退出游戏
→ 外部助手切换目录
→ 启动新版本
→ 新版本回写启动确认
→ 删除备份
```

没有 Release、当前已经最新、编辑器、Headless 和 Release smoke 均不会弹出联网错误。主菜单保留“检查更新”手动入口。

## 固定 Release 资产

每个稳定 Release 必须包含：

```text
StarWorld-Windows-x86_64.zip
StarWorld-Windows-x86_64.zip.sha256
```

ZIP 根目录包含：

```text
StarWorld.exe
StarWorld.pck
update-manifest.json
```

客户端只接受 GitHub 官方下载域名、固定资产名、稳定版本、非 Draft、非 Prerelease 的最新 Release。

## 断电和中断续传

下载目录位于 `user://updates`。持久状态记录：

- Release tag；
- 资产 URL 与名称；
- 预期长度；
- 预期 SHA-256；
- ETag；
- 已完成字节。

已有部分文件与目标资产完全一致时发送：

```http
Range: bytes=N-
If-Range: <etag>
```

服务器返回 `206` 且 `Content-Range` 起点正确时追加。服务器忽略 Range 返回 `200` 时清空旧部分并从零下载。资产身份、长度或 SHA 改变时不得复用旧字节。每 256 KiB 刷新文件和状态，进程、网络或电源中断后可以继续。

## 安装和回滚

运行中的 Windows EXE 不负责覆盖自己。主程序把助手写到用户更新目录，启动独立 PowerShell 进程后退出。

助手执行：

1. 等待旧进程退出；
2. 再次校验 ZIP SHA-256；
3. 防 Zip Slip 解压到同卷临时目录；
4. 校验 Manifest 版本、平台、文件大小和逐文件 SHA-256；
5. 将安装目录移动为备份；
6. 将完整 staging 目录原子移动为正式目录；
7. 启动新的 `StarWorld.exe`；
8. 等待新进程写入版本确认；
9. 确认成功后删除备份。

新进程退出、超时或版本不匹配时，助手停止失败进程、删除新目录并恢复备份。玩家存档位于用户数据目录，不参与程序目录切换。

## 发布

`Publish Windows GitHub Release` 工作流由 `vX.Y.Z` tag 或手动指定已有 tag 触发：

```text
标签与 CURRENT_VERSION 一致性
→ 严格项目导入
→ 更新静态合同
→ Windows Release 导出
→ EXE/PCK 清单
→ ZIP 与 SHA-256
→ 禁用联网的发行包 smoke
→ GitHub Release 创建/覆盖资产
```

升级版本时必须同步：

- `StarWorldAppVersion.CURRENT_VERSION`；
- `project.godot` 的 `config/version`；
- `export_presets.cfg` 的文件和产品版本；
- tag `vX.Y.Z`。

## 质量门禁

永久测试包括：

- 语义版本和 Release 资产选择；
- 可信域名和 Draft/Prerelease 拒绝；
- Range、If-Range、ETag、206/200/416 边界；
- ZIP Manifest 和路径白名单；
- 首次启动真实更新提示与进度；
- Windows 真实目录切换；
- 新版本真实自动启动和 ACK；
- ACK 失败真实回滚；
- 全量 Runtime、完整桌面输入/UI 和 Windows Release smoke。
