# 标准测试流程与证书复用复测

日期：2026-10-24（UTC+8）。
完整运行：`results/suite-20261023T193745.058155Z`（目录时间为 UTC）。
运行开始时 HEAD 为 `59db99d`；测试工作树的源码 SHA-256 保存在 summary.json，
归档时核对其与最终提交快照一致。前一轮完整报告保留在 FULL_REPORT.md。

## 本次更新

根目录 AGENTS.md 指向 Verification/TESTING.md，维护者和其他 AI 共用同一流程：
选择 offline/Apple/full 范围、一次性环境配置、独立规范预期、完整结果判定、
失败证据保留、设备清理及标准覆盖边界。

普通测试不再调用 macOS `add-trusted-cert`、`remove-trusted-cert` 或创建钥匙串。
`tls_identity.py prepare/install/check/remove` 将环境管理与测试执行分开：
初次生成并授权一份 365 天 localhost 身份，之后仅只读检查和复用。
已有身份不覆盖；过期、不可信或证书/私钥不匹配时失败。
重跑 install 检查已可信身份时也不写入信任。

suite 的 Apple/full 范围增加 TLS 预检和真实 HTTP/2 transport 回归。
Go 服务支持读取外部证书/私钥；证据只复制公开证书。
CI full 支持 `HLS_TLS_IDENTITY`，由 runner 所有者预置一次信任，
不在 CI job 内执行 install。手机仍使用另一份临时证书并自动移除。

## 实际结果

本轮 **完整入口 passed，13 个步骤全部退出 0**，累计约 583 秒。
本次没有修改 Sources/HLSPlaylist，但仍重新执行整套媒体和真机测试。

| 验证 | 结果 |
|---|---|
| Runner 失败注入 | 13 tests，通过，新增未信任拒绝/重复 install 只读检查 |
| TLS transport | 2 tests，通过；真实 HTTP/2 连续复用，缺身份/权限错误/密钥不匹配拒绝，设备临时身份清理 |
| Swift ASan / Release | 各 77 tests / 9 suites，通过 |
| 规范 oracle / 边界 | 165 / 165；11 / 11 |
| 属性 / 变异 / 固定语料 | 2,000 份 × 6 断言、10,000 次变异、73 归档和 329 外部输入，无验收失败 |
| Apple 静态 | 15 / 15，含三组 PART，validator/report 均退出 0 |
| 动态 HTTP/2 / Apple LL | 78 / 78 独立断言；3 / 3 官方模式通过 |
| iOS/macOS 原生解析一致性 | 578 / 578 完整输出一致 |
| 真机 AVPlayer | 22 / 22：16 个播放正例、6 个带实际 422 的严格拒绝负例 |
| 真机本地 LL transport | 三组都具备真实 HTTP/2 blocking/v2 请求 |
| 清理 | device-cleanup 无错误；临时设备信任移除，自动 SSH control/服务端口关闭 |
| 真实缺证书启动负例 | suite --apple 在第一步 tls-identity 退出 1，不生成身份、不继续媒体测试 |

iOS/tvOS 构建及 CocoaPods 校验结果仍引用 `59db99d` 的上一轮记录，
本次没有修改库源码，未冒充又执行了一遍这些构建。
Apple 的 AES 解密说明和 range/字幕 SHOULD、真机 ECN SHOULD 继续保留，
完整通过不表示“零提示”。

## 证书更新弹窗的验证

native-audit.json 保存以下独立检查：

- 静态和动态官方测试公开证书的 SHA-256 相同，与持久身份一致。
- 整个媒体/真机运行前后 macOS 用户信任设置导出的 SHA-256 完全相同。
- 运行结束再次调用 install，拦截到的 security 命令只有两次 verify-cert，
  没有 trust 写入。
- localhost 的原生 SSL 验证退出 0，错误主机名退出 1，未关闭 TLS 校验。
- Mac 持久身份保留，私钥权限为 600；最终证据没有私钥。
- 手机临时证书的 present/trustedLocalhost 均为 false，清理职责分开记录。

首次授权和明确撤销/轮换仍属于环境管理，可能要求一次系统确认。
普通启动、静态和动态测试不再重复更新 Mac 信任。

## 标准结论与交付

本轮已执行的测试全部通过，未留下未解决的验收失败。
不能因此宣称 100% 符合全部 HLS/LL-HLS 条款，或所有测试点已被穷尽。
规范目录的 428 个 bis-22 加 226 个 RFC 8216 段落包含 SHOULD，
不是 654 个逐项认证结果。已有断言和外部义务见 Coverage.md、
RuntimeCoverage.md；尚未覆盖的媒体/解码器、其他 OS、SCTE-35 载荷、
完整 steering 调度和可选扩展播放行为仍需分别验证。

标准步骤见 TESTING.md。证据副本：
`../player/verification/hlsplaylist-20261023/certificate-workflow/`，
包含统一说明、完整结果、缺证书负例、native-audit、最终源码快照和
EvidenceManifest.json。不包含私钥、密码或 Apple 工具。
