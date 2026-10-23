# HLSPlaylist 验证与缺口复核

2026-10-23。本地 clone：`/Users/bytedance/Project/HLSPlaylist`。
本轮对真实 Swift 包进行测试，不以播放器的 Dart 扫描器代替它。
基础回归和有效归档的 Apple 对照支持常见场景，但新增边界已复现缺陷，
因此不能写成“所有 HLS 功能、所有播放场景都没有问题”。

## 被测版本

| 项目 | 值 |
| --- | --- |
| 原本地提交 | `716ea58772b7ab2a274880d0d4ec33bdc68be4d4` |
| 本轮被测提交 | `be2d8a9d6eef49054574b1a54ab0a8c43aa67df3`，获取时的 origin/main |
| 独立验证分支 | `verification/full-hls-20261023` |
| 生产 Swift 源码修改 | 无 |
| 播放器生产代码修改 | 无 |
| 原分支 | 保留 |

两个提交差异为 2 文件、47 行新增、8 行删除：
远端新增了**尾部 interstitial DATERANGE URI 的重写和回归测试**。
旧本地提交缺这个修复。后文数字属于 be2d8a9，不自动归于旧提交。

## 已执行的方法

| 方法 | 结果与范围 |
| --- | --- |
| 现有测试、Apple 实时清单 | 原有 37 个测试通过；Apple 两个主清单和其所有不同子清单真实下载、解析、往返 |
| 扩展 Swift 回归 | 44 个测试，无意外失败，**5 个已知问题仍可复现** |
| 73 份历史归档 | 73/73 解析成功，73/73 渲染稳定；归档含负例，这个数字不是合规通过率 |
| hls.js / Shaka | 固定版本原文件及 LICENSE；329 份静态完整输入，328 解析成功；唯一拒绝项为上游破损语法负例；两份变量边界往返不稳定 |
| Apple 官方对照 | original/render/rewrite 三组 ×（14 个结构入口 + 2 个真实媒体入口）= 48 次；有效归档场景没有新增失败 |
| 变异测试 | 5 个种子 × 2,000 = 10,000 次变异通过 |
| 独立属性 | 2,000 份生成清单 × 6 个条件 = 12,000 次检查通过；包含解包后的签名 URL 一致性 |
| ASan 与危险数值 | 常规测试未报告 ASan 内存错误；额外 live-offset 数值探针复现 Swift 整数溢出 trap |
| iPhone 直接解析 | 同一份 Swift 库源码编译为 iOS 15 executable，在 iPhone / iOS 15.5 直接解析、渲染、重写 73 份归档；73/73 接受，完整输出与 Mac 完全一致 |
| AVPlayer | 真机 19/19 个汇总场景通过；主执行 17 组，再重跑 FairPlay 2 组、补跑多语言轨道 2 组；保留各次数据及系统取消 |
| 当前 Dart 接入复核 | 同一批 73 份输入中 3 个入口明确拒绝，见下文 |

源文件覆盖率：行 **1430/1557，91.84%**；函数 **247/281，87.90%**；
区域 **761/842，90.38%**。这是本轮覆盖度，不是正确性证明。
完整命令、日志、覆盖率 JSON 和固定语料保存在本目录。

外部版本固定为：

- hls.js：`363359c5110aa4171cbc6b56138a200a5116384b`
- Shaka：`8f8cf0720c760d15a6f2eaf3693e3705069e27ce`

这里运行的是提取后的解析/保持性输入以及独立字段预期；
**没有宣称完整运行 hls.js 或 Shaka 的浏览器播放器测试套件**。
动态字符串不代入猜测值。

## Swift 库中已复现的缺口

| 项目 | 最小输入及实际结果 | 判断 |
| --- | --- | --- |
| Image playlist URI | `EXT-X-IMAGE-STREAM-INF:...,URI="tiles.m3u8"` 在 mapURIs 后仍为原 URI | 未建模的 tag 被保留，URI 未进入重写回调；作为代理需要补齐 |
| LL 扩展属性 | PRELOAD-HINT / RENDITION-REPORT 的 `X-NEW="preserve-me"` 被删除 | 与完整无损保持目标不符 |
| Key preload | Shaka 的 `TYPE=KEY,METHOD=AES-128,URI="next.key"` 渲染后丢 METHOD | 同属 PreloadHint 未保留其他属性的问题；不等于所有 LL-HLS 不可用 |
| 小数精度 | `EXTINF:0.123456789` 变为 `0.123457` | 序列化保留最多六位小数；严格无损不成立 |
| 整数溢出 | TARGETDURATION=`9223372036854775807`，读取 recommendedLiveOffset 触发 SIGTRAP | `targetDuration * 3` 在转换 Double 之前发生 Int 溢出；不读取该属性的对照能解析、渲染 |
| 完整严格校验 | strict 模式接受 NaN、inf、负时长、缺失/重复 TARGETDURATION、未闭合 key 引号 | strict 不是完整 RFC/Apple authoring validator；部分输入被容错或规范化 |
| 变量往返 | hls.js 两份变量边界第一次与第二次渲染不同 | 定义被前置，再次解析可能进行新的替换；含上游本来就用于错误处理的输入，不能全部称为合法 HLS 失败 |

复现原文、输出、预期及退出码在 `results/boundaries.json`、
`results/external.json` 和 `VerificationTests.swift`。
原有无损/容错测试覆盖到的部分确实通过；额外要求暴露的是原覆盖范围之外的问题。

`EXT-X-SKIP` 能解析并保留 skippedSegments，但源码没有将 delta 响应与前一份
清单合并的工具。单独解析 delta 不是完成直播状态合并。
这里将其列为**需要播放器状态/代理配合的能力**，不把纯解析器未实现播放器
行为本身记成解析缺陷。

## Apple 官方错误对照

使用 `mediastreamvalidator 2.0.284 (2.0.284-260930)`，
阈值 `must_auth`。统计递归遍历整个报告，成功/失败使用工具退出码。

| 场景 | 原始 | 往返 / 重写 | 解释 |
| --- | --- | --- | --- |
| Apple TS、fMP4 及有效控制入口 | 没有阈值失败 | 没有新增失败 | 支持该固定范围的结构及两组媒体数据 |
| gcore_ll 归档 | 已有 authoring 问题 | 相同错误集合 | 不是本轮重写引入；归档也不代表当前直播端 |
| 单独 delta | 已有错误 | 保留错误 | 缺少用于合并的前一份清单 |
| 缺失 TARGETDURATION | 失败 | 仍失败，新增 `622045` | 渲染器补写了 0，未修复源错误 |
| 重复 TARGETDURATION | `632010`、失败 | 错误消失、通过 | 渲染器只留下一个值，掩盖了原输入错误 |

三组的 16 条索引及官方详细 JSON/log 在 `results/apple`。
“渲染后通过”不能逆推原始输入合法。

## 当前播放器接入与 Swift 库的差异

直接导入 sibling player 的生产 `rewritePlaylist`，
运行同一批 73 份归档；70 份接受，3 个主入口明确拒绝：

| 输入 | 当前 Dart 结果 | Swift fork 对应能力 |
| --- | --- | --- |
| variables/master.m3u8 | `HLS variables are not supported` | 支持 DEFINE / 变量解析，但有上述变量边界 |
| steering/master.m3u8 | 拒绝 CONTENT-STEERING/SERVER-URI | mapURIs 覆盖 contentSteering URI |
| interstitial/master.m3u8 | 拒绝 DATERANGE/X-ASSET-URI | 覆盖 interstitial asset / asset-list URI，包括被测提交的尾部修复 |

这些是**当前接入层缺口**，不应算到 Swift 库头上。
反过来，Dart 扫描器已分类 IMAGE-STREAM-INF URI，
而 Swift fork 本轮复现了 image URI 漏重写；
两者不能用一个“功能完全相同”的结论概括。
SESSION-DATA / steering / interstitial 的 URI 重写，也不自动等于
内部 JSON 资源、pathway clone、实际插播生命周期和播放行为都已实现或验收。

## AVPlayer 验证边界

测试手机为 iPhone 12 / iOS 15.5。独立壳调用 AVFoundation，
测试服务调用本 clone 编译的 Swift Probe。
三组均使用同一 Mac 出口及手机 loopback 隧道；
raw 组清单正文原样转发，TS master 的 SHA-256 对照相同。
render 组处理整个请求到的清单树；rewrite 组执行 Swift mapURIs。
没有通过修改手机系统代理来改善某一组。

测试成功要求首帧、至少 10 秒推进、暂停/恢复、VOD seek；
fMP4 另检查音轨/字幕选择生效及之后继续推进。
轨道选择测试不代表已逐帧验证字幕画面和每种语言内容。
AES fixture 真正轮换密钥字节、URI 和 IV。
fMP4 range fixture 使用正确的初始化区和分片字节范围。
恢复场景只注入一次媒体 503，不能覆盖所有断网/鉴权/取消竞态。
FairPlay 证书和许可经测试转发端访问公开 DRMtoday 示例，
SPC/CKC 和解密由手机完成；模拟器结果不能替代它。

| 真机场景 | 原始 | 往返 | URI 重写 |
| --- | --- | --- | --- |
| Apple TS | 通过 | 通过 | 通过 |
| Apple fMP4 | 通过 | 通过 | 通过 |
| AES-128 换钥 / 显式 IV | 通过 | — | 通过 |
| fMP4 初始化区 / byte range | 通过 | — | 通过 |
| 滑动直播 | 通过 | — | 通过 |
| 公开 LL-HLS | 通过 | — | 通过 |
| FairPlay 解密播放 | 通过 | — | 通过 |
| Shaka 多语言音轨 / 字幕 | 通过 | — | 通过 |
| 单次媒体 503 及重试恢复 | — | — | 通过 |

多语言流实际提供 6 个音轨、4 个字幕选项；
两组都完成了英语→德语音轨、英语→希腊语字幕选择与切换后推进。
Apple fMP4 示例只提供一个可选音轨，因此它本身的选择测试不算多音轨切换证据。
真实切换结果见 `results/avplayer-device-tracks.json`。

FairPlay 原始组：2 次成功证书、2 次成功许可证。
重写组：2 次成功证书、1 次成功许可证、1 次系统取消的 key request；
两组都产生真实首帧并持续推进，且完成暂停/恢复/seek。
取消码 `AVFoundationErrorDomain/-11879` 对应 SDK 的
`AVErrorContentKeyRequestCancelled`，不是授权失败；
原始错误文本保留，并在汇总中单列取消，不隐藏其他 key 错误。
首次证书请求漏掉公开示例要求的 `x-dt-custom-data`，返回 400；
修正测试转发端后完整重跑，首次失败数据仍保留。

LL-HLS 观察到 `_HLS_msn` blocking reload 请求；日志也保留一次 origin 504。
本轮验证播放和请求透传，没有测量直播端到端延迟或证明每种 reload 条件均可靠。
恢复测试明确记录一个 503，随后同一媒体 URL 返回 200 并恢复播放。
最新条件逐项汇总见 `results/avplayer-summary.json`；
仅把带 `complete=true` 的对应执行文件用于最终结果。

初次测试壳的启动配置、手机外网不可达、初次 fixture 的 Range 构造问题
均保留为 `*-attempt1.json` 或中间日志。它们不作为库失败计数，
最终结果只用修正条件后完整执行的数据。
直接在手机执行 Swift parser 的独立结果见 `results/ios-archive-summary.json`；
这补充了 Mac 解析、手机播放实际输出之外的平台运行证据。

尚不能由本轮推导的结论包括：所有编码/容器/DRM 组合、所有 LL-HLS origin 行为、
delta 状态合并、content steering pathway 切换、真实 interstitial 插播、
长期直播重连、密钥过期/续租、后台/锁屏/AirPlay、多 engine 生命周期、
所有 malformed 输入和全量浏览器 conformance 套件。

## 文件与复跑

运行方法见 [README.md](README.md)；具体 JSON/log 见 [results](results)。
测试和固定语料以 HLSPlaylist 项目为主保存。
交付报告及证据压缩包另复制至 sibling player 的
`verification/hlsplaylist-20261023/`，便于在当前工作区打开。
本轮没有提交或推送，也没有修改生产实现来隐藏失败。
测试 App（真机与模拟器）、手机测试 executable、上传包已移除；
本轮 HTTP 服务、USB/SSH 隧道、日志采集进程已停止，Apple 工具挂载已卸载。
用户原有代理设置和其他服务未修改。

## 再次核对远端分支

用户要求更新后，重新 fetch origin、upstream，并用 `ls-remote --heads origin`
核对服务端分支。你的 fork 只有 `main` 和 `fix/uri-rewriting-cocoapods` 两个分支，
均为 `be2d8a9d6eef49054574b1a54ab0a8c43aa67df3`；这与上一轮被测版本相同。
CreatureSurvive 上游 main 为较早的 `8b9383c`。
本地 main 已从 `8b9383c` 快进至 `be2d8a9`，原 fix 分支及 verification 分支保留。

**variables、content steering、interstitial 确实存在于你的远端 Swift fork。**
前三项被拒绝的结果属于当前播放器的 Dart 映射器，不能称为 Swift 库缺失。
Swift 对基本 LL-HLS 的解析/重写/播放也已有通过证据；
LL 相关缺口具体指 PRELOAD-HINT / RENDITION-REPORT 的扩展属性保持。

最新 main 上复跑 14 项相关回归，无意外失败，仍记录 5 个已知问题；
11 个额外边界要求仍未满足，Image URI、属性保持、精度、溢出及完整严格校验
的复现结果未改变。新增核查记录见 `results/remote-recheck.json`、
`results/remote-check-tests.log`。
