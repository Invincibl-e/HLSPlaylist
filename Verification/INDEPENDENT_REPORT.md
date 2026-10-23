# HLSPlaylist 独立维护与规范验证报告

日期：2026-10-23。实现基线：`7664216`，分支
`fix/uri-rewriting-cocoapods`。本轮按照 RFC 8216 与
draft-pantos-hls-rfc8216bis-22（2026-05，协议 v13）继续审计，
明确不再以 HLSPlaylist 上游实现作为对齐目标。

结论：本轮发现的清单实现、模型序列化和测试失败判定问题已修复；
最终约定范围的测试通过。**不能据此声称所有 HLS/LL-HLS 条款均已实现、
或已完成“完美认证”**。完整 LL 服务端验收尚未通过；具体边界见下文。

## 本轮修复

| 问题 | 修复结果 |
|---|---|
| CONTENT-STEERING 重复及初始 pathway 引用 | 重复拒绝；引用须在 variant 中存在 |
| CHANNELS 内部语法未校验 | 校验整数、slash 参数、逗号标识符及合法字符 |
| 同 TYPE rendition group 的成员/属性一致性 | 按规范排除允许不同的字段后比较；不同 group ID 不误判为成员属性差异 |
| SESSION-DATA FORMAT 未处理 | URI 场景校验 JSON/RAW 枚举；未知值忽略标签；无 URI 时忽略 FORMAT |
| END-ON-NEXT 重叠 | 合并同 ID 属性后检查已知区间；未知时长不擅自当无限时长 |
| Interstitial 正例违规 | 校验资产来源二选一、X-ASSET-URI 为绝对 URI；修正违规正例 |
| PLAYLIST-TYPE / CUE 词法 | 拒绝非法 quoted/空白/空列表项；未知合法值按前向兼容处理；不将 SHOULD 去重升级为 MUST |
| 程序构造的 effective key context | 拒绝重复 KEYFORMAT 和 NONE 占位；文本中的合法 KEY 覆盖仍保留 |
| 连续 DISCONTINUITY 丢计数 | 用 UInt64 count 保存数量，Bool 为可推导属性，保留原 Bool 调用方式；计数及总序列防溢出 |
| I-frame/image variant 的扩展标签丢失 | 序列化输出各自扩展标签 |
| Probe / runner 可误报成功 | 输出数与顺序身份严格一致；崩溃/超时/非法状态失败；正例检查有效输出；所有属性、边界、尾部 URI 断言失败均退出非零 |
| 官方测试结果不够明确 | 独立运行目录，保留 JSON/日志/HTML；缺工具、缺报告、超时失败；诊断语料和独立正例分开 |

## 最终实际结果

最终目录：`Verification/results/suite-20261023T150931.560337Z`。
`summary.json` 状态为 `passed-with-limitations`，八个执行步骤退出码均为 0。
所有已记录源码 SHA-256 与最终测试后工作树一致。

| 验证 | 实际结果 |
|---|---|
| Swift ASan + coverage + Apple 实时清单 | 75 tests / 9 suites，通过；21.304 秒 |
| Swift Release 全量 | 75 tests / 9 suites，通过；0.555 秒 |
| Release 大清单性能阈值 | 通过；0.361 秒（阈值 5 秒） |
| 独立规范正负/语义 oracle | 162 / 162；拒绝须发生在 parse 阶段，不能用 render 失败代替 |
| 子进程边界 | 11 / 11 |
| 尾部 interstitial URI placement | 两种位置均通过 |
| 固定 VOD property | 2,000 份 × 6 条断言；0 failures |
| Swift 变异测试 | 5 个固定种子 × 2,000 次；无 trap |
| 验证器失败注入 | 7 tests；崩溃、漏输出、多输出、错身份、错状态、失败断言均不得变绿 |
| 归档 / 外部静态语料 | 73 / 329 份全部处理；接受 18 / 93；接受结果的稳定渲染通过 |
| 独立归档决定性违规检查 | 55 份存在明确违规；55 份全部拒绝 |
| iOS 15.5 直接执行真实库 Probe | 575 / 575 完整 JSON 与 Mac 一致；162 oracle 包含在内 |
| Apple 官方 TS/fMP4/AES/range | 4 个媒体族 × original/render/rewrite = 12 组，官方阈值下通过 |
| Apple PART 双 rendition 场景 | 3 组无额外 MUST 级清单/媒体错误；保留 HTTP/2 官方失败，不计完整 LL 通过 |

官方工具：mediastreamvalidator / hlsreport 2.0.284
（2.0.284-260930）。每组保留 JSON、原始日志及官方 HTML。
TS/fMP4/range 仍有 SHOULD 提示；AES 的 111025 明确表示工具不做解密。
三个 PART 模式的 551002 为 HTTP/1.1 测试 origin 不符合官方 HTTP/2 要求；
它没有被屏蔽，也没有被改写成官方验证成功。

PART 场景使用实际 fMP4 分片及同样的 parent 媒体字节，并建立两个互相
报告的 rendition。它验证静态清单和 PART 媒体一致性，不验证实时 blocking
reload、delta merge、hint 延迟交付、CDN、跨 rendition 的滑动时序。

## 全规范覆盖的准确含义

`NormativeInventory.json` 保留 428 个 bis-22、226 个 RFC 8216 的规范性
段落，包括 SHOULD。每项有源文 URL、SHA-256、节号、原始行及文本，
并关联已有固定 oracle。这个目录让遗漏可检查，**并非 654 项已认证结论**。
逐领域实施/测试/外部义务矩阵见 `Coverage.md`。

实际媒体封装/编码、SCTE-35 载荷、DRM 解密、服务器多次响应、父子清单
一致性、完整 Content Steering 和可选 interstitial/UI 调度属于不同层。
单个 playlist 数据库不能代替这些层的实现或认证。先前 AVPlayer/FairPlay
真机证据保留在上一轮报告，本轮没有重新播放全部 AVPlayer 场景，不将旧
播放结果冒充本轮新播放证据。

## 复跑、维护与证据

```sh
python3 Verification/suite.py
HLS_APPLE_BIN=/usr/local/bin python3 Verification/suite.py \
  --live --apple --fixtures /path/to/prepared/playback-fixtures
```

统一入口已加入 CI，CI 保存每次运行证据。每次使用新的 UTC 时间目录；
工具缺失、失败尝试、partial / skipped 状态均保持可见。
官方工具不随仓库分发。独立维护原则见根目录 `MAINTENANCE.md`；
原 LICENSE、来源及第三方测试许可证全部保留。

之前失败的 Apple PART 样本、错误的 rendition report URL 及中间运行均
独立保留，最终报告没有覆盖失败日志。最终用户证据副本位于 sibling
player 的 `verification/hlsplaylist-20261023/independent-audit`。
临时 HTTP 服务已由脚本关闭，iOS 测试目录已删除，任务自己的 SSH control
及 iproxy2239 已停止；用户已有代理及 iproxy8090 未改动。
