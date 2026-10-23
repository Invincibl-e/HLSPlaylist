# HTTP/2、动态 LL-HLS 与真机完整补测

日期：2026-10-23 UTC。分支：`fix/uri-rewriting-cocoapods`。
本轮接续 `e6d65af`，保持独立维护，不再对齐上游实现。

本轮完整执行目录：`results/suite-20261023T191730.661796Z`。
构建兼容性目录：`results/platforms-20261023-full`。
完整入口最终状态为 **passed**，11 个步骤全部退出 0，步骤累计约 602 秒。
测试前后源码 SHA-256 一致；归档前再次核对源码及证据哈希。

## 修复和补齐

- 修复 `RECENTLY-REMOVED-DATERANGES=""` 被拒绝的问题；bis-22 明确允许空列表。
- 修复该字段内 TAB 分隔 ID 被全局控制字符检查拒绝的问题；例外严格限制到该
  字段，其他标签和属性的非法 TAB 仍拒绝。新增两个参数化 Swift 测试
  （七组输入）及三个独立规范 oracle。
- 用 Go 标准库提供真实 TLS/ALPN HTTP/2 transport。静态 PART 的三组
  original/render/rewrite 官方测试不再豁免 551002。
- 本地生成 300 秒 CMAF：600 个独立 0.5 秒 PART，每四个组成 2 秒 parent。
  检查所有 `tfdt`、9,000 个视频 packet 及关键帧；保存生成命令和媒体哈希。
- 本地动态双 rendition origin 覆盖滑动窗口、blocking reload、PART 越界滚动、
  delta YES/v2、DATERANGE 淘汰、preload 等待、byte range、取消和发布停滞。
  三种转换模式分别有独立 HTTP/2 断言和 Apple 媒体验证。
- `device.py` 自动构建、安装、运行 AVPlayer 测试壳及真实 Swift 库 Probe；
  空用例、漏结果、模拟器、无播放推进或 HTTP/2 降级均失败。
- `suite.py --profile full` 自动建立 USB SSH 连接，按阶段执行并保存证据。
  超时会先中断子进程、允许清理，再处理残留进程；失败注入测试实际验证
  子进程的 finally 清理能完成。
- CI 增加具备官方工具和真机的 self-hosted full job；缺前置条件直接失败。
  普通托管 runner 仍运行明确标注的 offline job，另有 iOS/tvOS/CocoaPods job。

## 验收记录

| 验证 | 最终结果 |
|---|---|
| Swift ASan、覆盖率、实时 Apple 清单 | 77 tests / 9 suites，通过 |
| Swift Release | 77 tests / 9 suites，通过；测试执行 0.645 秒 |
| 大清单性能 | 0.406 秒，低于 5 秒门槛 |
| 独立规范 oracle | 165 / 165 |
| 隔离边界、尾部 URI 位置 | 11 / 11；两种尾部位置均通过 |
| 固定属性生成、变异 | 2,000 份 × 6 断言；5 个种子 × 2,000 次变异，无失败 |
| 归档 / 外部语料 | 73 / 329 份；接受 18 / 93，接受结果稳定渲染 |
| 独立归档违规检查 | 55 个确定性负例全部拒绝 |
| 自动化失败注入 | 11 tests，通过，含超时后清理 |
| Apple 静态官方验证 | 15 / 15：TS、fMP4、AES、range、PART 各三种模式 |
| 动态 HTTP/2 独立断言 | 78 / 78 |
| Apple 动态 LL 官方验证 | 3 / 3；validator 和 hlsreport 均退出 0 |
| iOS 15.5 原生库 Probe | 578 / 578 完整输出与 Mac 一致 |
| iPhone 12 / iOS 15.5 AVPlayer | 22 / 22 预期成立：16 个播放正例、6 个严格拒绝负例 |
| 真机本地 LL HTTP/2 | 三组均有真实 HTTP/2 blocking + `_HLS_skip=v2` 请求 |
| AES / FairPlay | 换钥取到不同 key URI；FairPlay 原始流取得许可证并解密、播放、seek |
| 音轨 / 字幕 / 恢复 | 两种模式均完成实际切换后推进；一次 503 注入后恢复播放并 seek |
| 兼容性构建 | iOS / tvOS Simulator 构建及 CocoaPods iOS/macOS lint 全部退出 0 |
| 清理 | device-cleanup 无错误；证书 present/trustedLocalhost 均为 false；测试壳、临时路径和服务已清理 |

覆盖率补充材料位于 `final/coverage/`：Swift 单元测试执行覆盖本库
2,304 / 2,496 行（92.31%）。该统计不合并另行执行的 Probe/设备/官方验证，
也不把代码行覆盖率当作规范条款覆盖率。

完整证据副本位于 sibling player 的
`verification/hlsplaylist-20261023/full-http2-device/`，包含 131 份最终执行文件、
兼容性日志、前期尝试、源码快照和独立清理审计。`EvidenceManifest.json`
记录最终文件哈希及本地提交身份。

## 真实负例与提示的含义

公开 TS/fMP4/LL/FairPlay 源含有本库严格规则拒绝的原始清单；
六个对应转换场景是明确的负例。要求转发端真实返回 422 并记录解析原因，
不能把网络超时、HTTP 502 或播放器任意错误算作严格解析测试通过。
原始流不预先规范化，不将负例包装成正常播放的正例。

Apple 工具使用 `--exit-code.threshold must_auth`，不豁免 mandatory finding。
AES 的 111025 表示验证器不做解密，须结合真机换钥/解密/播放结果。
range fixture 保留 135048（建议声明独立分片）；
动态测试流没有音频，保留 242528 字幕 SHOULD；真机三组本地 LL 均记录
ECN SHOULD -15410。原始报告保留这些提示，不能称为“零提示”；
此前 HTTP/2 551002 错误在最终运行中已消失。

过程中曾出现合法空 v2 列表在 iOS 15.5 上播放停滞，以及本地 DATERANGE
过早移除导致 Apple 552026。失败尝试保留；origin 修复边界保留规则并产生真实
滚动 DATERANGE，最终 v2 播放不依赖放宽解析器。

## 复跑与维护边界

完整命令及 runner 配置见 [README.md](README.md)。已配置实验设备和官方工具后：

```sh
python3 Verification/suite.py --profile full --live
```

`HLS_APPLE_BIN`、`HLS_DEVICE_UDID`、`HLS_DEVICE_HELPER` 在环境中配置；
可复用指定 `--fixtures`。脚本自动清理测试壳、上传文件、临时证书信任、
HTTP 服务和自己创建的连接；外部传入的 SSH control 由其所有者管理。
官方 Apple 工具不随仓库分发；远端 self-hosted runner 注册由维护者配置。
本轮实际执行为本地运行与真机运行，不宣称已在 GitHub 执行远端任务。

规范目录包含 428 个 bis-22 和 226 个 RFC 8216 规范性段落，不等于
654 项认证通过。字段规则映射见 [Coverage.md](Coverage.md)，本轮跨刷新、
媒体、服务端、播放器行为映射见 [RuntimeCoverage.md](RuntimeCoverage.md)。
未覆盖的媒体格式/解码器、其他系统版本、SCTE-35 载荷语义、完整 steering
调度及可选扩展播放器行为不能由本库测试替代。
有限测试通过不是 Apple 颁发的全协议认证。
