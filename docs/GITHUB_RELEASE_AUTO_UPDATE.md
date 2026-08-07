# GitHub Release 自动更新

## 玩家流程

Windows 发行包每次进程首次进入主菜单时检查一次：

```text
GitHub /releases/latest
→ 比较稳定语义版本
→ 精确选择 Windows ZIP 与 .sha256
→ 当前安装版本检查发行信任 Pin
→ 提示玩家
→ 可续传下载
→ ZIP SHA-256
→ schema v2 精确载荷 Manifest
→ detached CMS Manifest 签名 + 当前安装 Manifest signer Pin
→ StarWorld.exe Authenticode + 当前安装 Publisher Pin + 可信 TSA
→ 退出游戏
→ 外部助手切换目录
→ 启动新版本
→ 新版本回写启动确认
→ 删除备份
```

没有 Release、当前已经最新、编辑器、Headless 和 Release smoke 均不会弹出联网错误。主菜单保留“检查更新”手动入口。

## 为什么 SHA-256 不再单独作为发行身份

ZIP SHA-256 仍用于断点续传和下载损坏检测，但 ZIP、`.sha256` 与 ZIP 内 `update-manifest.json` 都来自同一个 GitHub Release。如果 Release 发布面被完全替换，攻击者可以同时替换三者，因此它们不能单独证明“这是 Star World 发行者发布的内容”。

Iteration 64 增加两个独立的密码学信任边界：

1. `StarWorld.exe` 必须通过 Windows Authenticode 信任，并匹配当前安装版本携带的发行证书 DER SHA-256 Pin；
2. `update-manifest.json` 必须存在 detached CMS/PKCS#7 签名 `update-manifest.p7s`，其 signer 证书必须匹配当前安装版本携带的 Manifest signer DER SHA-256 Pin。

Manifest 覆盖 PCK 与所有其它载荷，所以不能通过复用一个合法签名 EXE、再替换恶意 PCK 绕过认证。

## 固定 Release 资产

每个正式稳定 Release 对外仍包含：

```text
StarWorld-Windows-x86_64.zip
StarWorld-Windows-x86_64.zip.sha256
```

正式 ZIP 根目录至少包含：

```text
StarWorld.exe
StarWorld.pck
update-manifest.json
update-manifest.p7s
```

`update-manifest.json` 使用 schema/protocol 2，并声明：

```json
{
  "signature": {
    "format": "cms-detached",
    "digest": "sha256",
    "path": "update-manifest.p7s"
  }
}
```

签名文件属于 Manifest 元数据，不列入 Manifest 自身的 `files`，避免自引用；Manifest 的 `files` 必须精确覆盖 EXE、PCK 和所有其它安装载荷。

## 信任根来自当前安装版本

`data/update_trust_policy.json` 是当前安装版本的更新信任策略。它最多保留 4 个 Manifest signer Pin 和 4 个 EXE publisher Pin，以支持有界证书轮换。

关键规则：

- 本次目标 ZIP 无权决定本次验证使用哪些 Pin；
- 当前进程在下载/安装前读取当前版本 policy，并将其编码后传给外部 helper；
- helper 从当前 PCK 导出的 trust validator 执行认证；
- 只有认证成功后才允许目录 swap；
- 通过旧 Pin 认证并安装成功的新版本，可以携带下一轮证书轮换 Pin。

仓库默认 Pin 数组为空，因为真实发行证书尚未提供。空 Pin 是 fail-close 状态，不得用测试证书提交到 `master` 冒充生产身份。

## 首次启用与证书轮换

首次启用 publisher-pinned updater 时，需要通过手动/受控发布方式分发一个已经携带真实 Pin 的基线版本。没有可信旧版本，就不存在可安全自动建立的新信任根。

证书轮换采用 overlap：旧版本先发布同时信任旧/新证书的版本；确认该版本完成部署后，后续版本才能移除旧 Pin。不得让目标更新包自行要求客户端信任一个此前未知的 signer。

## 断电和中断续传

下载目录位于 `user://updates`。持久状态记录 Release tag、资产 URL/名称、预期长度/SHA-256、ETag 和已完成字节。

已有部分文件与目标资产完全一致时发送 `Range` 与 `If-Range`。服务器返回 `206` 且 `Content-Range` 起点正确时追加；返回 `200` 时安全从零开始；资产身份、长度或 SHA 改变时不得复用旧字节。每 256 KiB 刷新文件和状态。

## 安装、发行认证与回滚

运行中的 Windows EXE 不覆盖自己。主程序把 helper 与 trust validator 从**当前安装版本**写到 `user://updates`，启动独立 PowerShell 进程后退出。

helper 顺序固定：

1. 等待旧进程退出；
2. 再次校验 ZIP SHA-256；
3. 防 Zip Slip 解压到同卷 staging；
4. 校验 Manifest 版本、平台、精确文件集合、大小和逐文件 SHA-256；
5. 验证 detached CMS Manifest 签名及 Manifest signer Pin；
6. 验证 staged `StarWorld.exe` Authenticode、Publisher Pin、Code Signing EKU、可信时间戳和 Time Stamping EKU；
7. **只有 4-6 全部成功后**，才将安装目录移动为备份；
8. staging 原子移动为正式目录；
9. 启动新版本并等待 ACK；
10. 成功后删除备份。

PCK/Manifest/签名篡改在目录 swap 前失败。新进程退出、超时或版本不匹配仍走原有真实回滚。

## 正式发布

GitHub Hosted Actions 不保存 Star World 发行私钥，也不再自动创建/覆盖可被玩家自动安装的未签名 GitHub Release。

`.github/workflows/publish-windows-release.yml` 只生成 `REFERENCE-ONLY` 构建证据，用于导出/Smoke/旧协议兼容测试。

正式发布必须在受控 Windows 签名环境执行：

```powershell
pwsh -NoProfile -File tools/publish_signed_update_release.ps1 `
  -BuildDirectory D:\release\star-world `
  -Version 1.3.0 `
  -ManifestSigningCertificateThumbprint <manifest-signing-cert> `
  -ExpectedManifestSignerCertificateSha256 <manifest-cert-sha256> `
  -ExpectedPublisherCertificateSha256 <authenticode-publisher-cert-sha256>
```

该工具不会接收私钥文件。它要求：

- `StarWorld.exe` 已由真实发行证书 Authenticode 签名并具备可信 TSA；
- checkout HEAD 精确等于目标 tag；
- 生成 schema v2 Manifest；
- 从 `CurrentUser\\My` 的外部证书私钥生成 detached CMS；
- 用生产 trust validator 自验 EXE + Manifest；
- signed builder 再次核对 Manifest 精确覆盖实际字节且**不改写已签名 Manifest**；
- 最后才通过已认证的 `gh` 创建/覆盖 GitHub Release 资产。

## 质量门禁

永久测试包括：

- 语义版本和 Release 资产选择；
- Range/If-Range/ETag 与真实断点续传；
- schema v1 reference 与 schema v2 signed Manifest；
- detached CMS signer Pin；
- Windows Authenticode Publisher Pin；
- 可信 TSA 与 EKU；
- Manifest 字节篡改、CMS 字节篡改、错误 signer Pin、错误 publisher Pin、未签名 EXE 拒绝；
- PCK 在签名后被修改时 swap 前拒绝；
- 原有目录 swap、自动重启/ACK 与失败回滚；
- 首次启动真实更新提示与进度；
- 严格 Godot 导入、Runtime、桌面 UI 和 Windows Release smoke。

## 商业发布边界

Iteration 64 完成的是仓库侧验证和安全发布工具链，不生成真实 publisher/manifest signing 私钥，也不伪造真实证书 Pin。商业发布仍受 Iterations 60-63 的真实外部资格和签名要求约束。
