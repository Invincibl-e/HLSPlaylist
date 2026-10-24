# HLSPlaylist 完整验证入口

当前标题兼容策略与新增公共语料流程见 [TESTING.md](TESTING.md) 和
[MAINTENANCE.md](../MAINTENANCE.md)。本文后面的早期严格拒绝计数为历史记录：
EXTINF 标题 TAB 现在必须正常解析、保留并重写；不能继续作为预期失败。
默认入口已加入 193 份公开原始清单、旧语料接受契约和规范组合测试。
公开语料中明确保留的 14 份拒绝是尚未支持的兼容边界，不能称为全量兼容通过。

维护者和其他 AI 请先读 [TESTING.md](TESTING.md)，其中包含统一测试步骤、
一次性证书配置、CI 环境及结果判定规则。历史整套验收对应 `59db99d`；
证书复用流程的完整复测见
[CERTIFICATE_WORKFLOW_REPORT.md](CERTIFICATE_WORKFLOW_REPORT.md)，不能混用提交身份。

本仓库现在独立维护，不再追踪 HLSPlaylist 上游实现；见
[MAINTENANCE.md](../MAINTENANCE.md)。本轮完整规范目录及覆盖边界见
[Coverage.md](Coverage.md)、[NormativeInventory.json](NormativeInventory.json)。
它们明确区分清单数据规则、实际媒体、跨刷新服务器和播放器义务。
HTTP/2 与真机补齐结果见 [FULL_REPORT.md](FULL_REPORT.md)，运行行为逐项映射见
[RuntimeCoverage.md](RuntimeCoverage.md)；旧报告及计数保留为历史记录。

统一入口（Swift ASan/覆盖率、Release/性能、固定规范 oracle、归档、外部语料、
属性/边界、验证器失败注入测试）：

```sh
python3 Verification/suite.py
HLS_APPLE_BIN=/usr/local/bin \
HLS_DEVICE_UDID=<USB-device-UDID> \
HLS_DEVICE_HELPER=<existing-trollstorehelper-path> \
python3 Verification/suite.py --profile full --live
```

完整入口自动建立 USB/SSH 连接、准备真实媒体、启动 HTTPS/HTTP/2 origin、
运行官方验证和真机测试，结束后卸载测试壳、移除证书及临时上传、关闭自己的服务
和连接。默认 USB SSH 本地端口为 2239，可用 `HLS_DEVICE_SSH_PORT` 修改。
这里移除的是手机临时证书；Mac 预置的 localhost 身份不再每轮添加/撤销。
首次运行 Apple/full 前按 TESTING.md 执行 `tls_identity.py prepare/install` 一次；
后续入口只执行 `check`，缺信任就失败，不再反复弹出证书授权。
优先使用 runner 的 SSH 密钥；实验设备密码可经环境 `SSHPASS` 配合
`sshpass -e` 使用，不写入源码或报告。已有连接可设置 `HLS_SSH_CONTROL`，
此时跳过自动连接创建，结束后不关闭该外部连接。手机需解锁。
`--fixtures /path/to/prepared/playback-fixtures` 可复用已准备的媒体。

完整环境需要 macOS/Xcode、Swift、Python 3 + requests、Go、ffmpeg/ffprobe、
支持 HTTP/2 的 curl、OpenSSL、iproxy、SSH，以及已安装的 Apple 验证工具。
本轮真机安装方式要求已授权的 rootless/TrollStore 实验设备；普通 iPhone
开发签名安装需要另行配置，不能直接当作同一个自动化环境。
GitHub Actions 的 `workflow_dispatch` 勾选 `full` 使用
`[self-hosted, macOS, hls-device]` runner；同名仓库变量提供上述路径、设备 ID
和端口，SSH 密钥/依赖在 runner 上预置。托管 runner 的离线任务单独标名，
不会冒充官方或真机验收。本仓库提交 workflow，远端 runner 需由维护者注册。

每次生成独立的 `results/suite-<UTC timestamp>`，失败日志不会被覆盖。
完整 profile 缺工具、设备、用例或结果时失败，不静默跳过。
离线入口未请求的实时/官方测试显式记为 skipped；`--apple` 可单独追加静态验证。
`summary.json` 包含命令、退出码、耗时、Swift/Python 版本、源码与证据 SHA-256。
`passed` 表示列出的测试和门槛通过，不表示完整协议认证。
静态 PART 和动态 LL 都使用实际 HTTP/2，不再豁免官方错误 551002。
Apple AES 工具不做解密，完整 profile 另用真机验证换钥和播放。
原始媒体可先按本文后续 `playback_server.py --prepare` 的步骤准备；
脚本不会自动下载或分发 Apple 官方验证工具。

测试、固定语料、修复和证据保存在本项目。当前修复基于
`fix/uri-rewriting-cocoapods` 的
`716ea58772b7ab2a274880d0d4ec33bdc68be4d4`。后续用户已授权本地提交；
实际提交记录以 Git 历史为准。`results/` 是忽略版本管理的本地运行证据目录。
较早的严格解析审计见 [STANDARDS_REPORT.md](STANDARDS_REPORT.md) 和
[results/standards-strict](results/standards-strict)。默认严格解析、render 抛错，
移除宽松选项，decimal-integer 模型使用 UInt64。旧宽松行为及旧通过计数仅为历史。
FairPlay 原始流的后续排查与补测见 [FAIRPLAY_REPORT.md](FAIRPLAY_REPORT.md)；
新原始记录独立保存在 `results/fairplay-investigation-20261023`。

此前修复结论见 [FIX_REPORT.md](FIX_REPORT.md)，对应原始结果见
[results/repaired-716-final](results/repaired-716-final)。
随后按 HLS 规范恢复 FRAME-RATE 的三位小数，补充复测结果位于
[results/standard-decimals](results/standard-decimals)，详细说明见 FIX_REPORT.md。
[REPORT.md](REPORT.md) 及 `results/fix-716ea58` 为修复前的历史记录。
`results/repaired-716` 保存修复第一轮及其 Unicode 真机差异，不替换为通过记录。

复跑最终修复时，设置以下变量，再执行下文各命令，并令 build 的 scratch-path
与 `HLS_VERIFICATION_WORK` 一致：

```sh
export HLS_VERIFICATION_WORK=/tmp/hlsplaylist-validation/standards-strict
export HLS_VERIFICATION_RESULTS="$PWD/Verification/results/standards-strict"
```

## 固定证据

- `corpus/archive`：73 份历史归档清单；出处、负例和快照性质见
  `corpus/archive-sources.json`。快照不等于当前直播状态。
- `corpus/external`：hls.js、Shaka 原始测试文件及各自 LICENSE。
  `provenance.json` 固定提交、下载 URL 和 SHA-256。
- `external-inputs.json`：329 份完整静态字符串；处理模板转义、字符串拼接和数组
  `join`，不代入动态表达式。包含上游故意构造的错误输入。
- `Tests/HLSPlaylistTests/VerificationTests.swift`：离线回归、独立字段预期和
  修复回归断言；已去除旧 `withKnownIssue` 包装。
- `results/repaired-716-final/boundaries.json`：11 个额外要求的最小复现；包括隔离子进程中的溢出，
  以及关闭 live-offset 求值时不会崩溃的对照。

## 1. Swift 测试、Apple 实时清单、ASan、覆盖率

```sh
HLS_LIVE_TESTS=1 xcrun swift test \
  --scratch-path "${HLS_VERIFICATION_WORK:-/tmp/hlsplaylist-validation}/swift-build" \
  --sanitize address --enable-code-coverage
```

实时测试会读取 Apple 两个主清单及它们引用的每个不同子清单。
原测试含 5 个种子 × 2,000 次变异。离线归档及外部回归直接使用本仓库语料。
Swift Testing 报告中的 “passed with known issues” 表示预期缺陷仍可复现，
不能解释为这些断言通过。

## 2. 归档、外部语料、独立属性和边界探针

```sh
xcrun swift build --package-path Verification \
  --scratch-path "${HLS_VERIFICATION_WORK:-/tmp/hlsplaylist-validation}/probe-build" \
  --sanitize address --enable-code-coverage
python3 Verification/run.py corpus boundaries properties
python3 Verification/standards.py
python3 Verification/audit_sources.py
```

属性生成器固定种子 8216，生成 2,000 份有效 VOD，每份检查 6 个条件：
解析成功、分片数、时长值、稳定渲染、重写次数、解包后签名 URL 完整一致。
测试高精度小数、非法数值及扩展属性另见边界探针。
每个危险边界在独立进程中运行，设有超时。
进程退出或超时是失败证据，不会被当作解析拒绝。

`python3 Verification/run.py prepare` 可按已保存的提交重新下载外部源文件。
`extract` 可离线重新提取；不自动升级已固定的上游版本。

## 3. Apple 官方 original / render / rewrite 对照

需要 Apple 官方 HTTP Live Streaming Validation Tools。工具不随本仓库分发。
本轮使用 `mediastreamvalidator 2.0.284 (2.0.284-260930)`。

```sh
HLS_APPLE_BIN=/usr/local/bin python3 Verification/apple.py original
HLS_APPLE_BIN=/usr/local/bin python3 Verification/apple.py render
HLS_APPLE_BIN=/usr/local/bin python3 Verification/apple.py rewrite
```

每组运行 14 个入口的结构验证和 TS、fMP4 两个媒体验证。
原始、渲染、重写三种模式都处理整个清单树。
本地服务只在脚本生命周期内运行，退出后关闭。
结构验证用 `-p --timeout 8`，媒体验证用 `--timeout 25`；
另有 45 秒进程超时。错误阈值为 `must_auth`。
JSON 的消息可能出现在树内多个位置，脚本递归统计；
是否失败使用官方工具退出码判断。

原输入可能已有问题，必须对照新增/消失的错误，而非只统计绝对成功率。
负例被渲染器规范化后“通过”也要报告。

## 4. AVPlayer 真机对照

`AVPlayerApp.swift` 是独立测试壳；没有修改 sibling player 的原生业务。
播放入口包含 TS、fMP4、AES-128 换钥、fMP4 byte range、滑动直播、
公开 LL-HLS、FairPlay、Shaka 多语言音轨/字幕和单次 503 恢复。
成功条件包括真实 `AVPlayerLayer.isReadyForDisplay`、播放推进超过 10 秒、
暂停/恢复、VOD seek；fMP4 还检查音轨和字幕选择及选择后推进。
FairPlay 另记录 SPC/CKC 流程中的证书和许可证计数；
系统 `AVErrorContentKeyRequestCancelled` 单独计数，不混入授权失败。

```sh
python3 Verification/playback_server.py --prepare
python3 Verification/playback_server.py
```

第二条命令在测试期间保持运行；完成后用 Ctrl-C 停止。
Apple 的原始 fMP4 采用 byte range；fixture 生成器正确提取初始化区及各分片范围，
再构造单文件范围清单。AES fixture 使用不同的密钥字节、URI 和显式 IV。
直播 fixture 每 6 秒滑动。媒体样本只下载到 `/tmp/hlsplaylist-validation`。

普通设备请使用 Xcode 开发签名部署测试壳。本轮使用已经授权的 rootless 实验手机；
对应测试壳可这样构建：

```sh
python3 Verification/build_app.py
iproxy -u <phone-udid> 2239 22
ssh -N -R 8899:127.0.0.1:8899 -p 2239 root@127.0.0.1
python3 Verification/phone.py install --helper <existing-trollstorehelper-path>
python3 Verification/phone.py launch
```

SSH 和 iproxy 在独立终端运行。使用已有 SSH 身份认证；
如环境已配置 `SSHPASS`，部署脚本通过 `sshpass -e` 使用它，不保存凭据。
手机需解锁。结束后执行 `phone.py stop`、`phone.py remove-upload`，
停止自己的服务和隧道。脚本不会修改系统代理设置。

手机可没有外网直连。三组使用相同的 Mac 网络出口：
`/raw/https/host/path` 原样转发字节，保留相对 URI；
`/render/https/host/path` 对每份清单执行 Swift parse/render；
`/start/.../rewrite` 对每份清单执行 Swift mapURIs。
raw/render 的传输路径映射不改写清单正文。
FairPlay 证书和授权通过测试转发端访问公开 DRMtoday 示例，
SPC 生成、CKC 处理和解密仍由手机系统完成。
日志保存状态及长度，不保存 SPC/CKC 内容。
测试壳默认在播放前准备证书。DRM 转发依赖 Requests，连接超时 3 秒、读取超时 30 秒；
server 运行环境需有 `requests`。如果现有 Python 使用 LibreSSL，
在任务专用 venv 中使用兼容的 `urllib3<2`，不要修改全局环境。
`_HLS_msn`、`_HLS_part`、`_HLS_skip` 和 Range 头会透传。

可选子集：构建参数 `--cases aes/original,range/rewrite --run rerun`，
或应用启动参数 `--cases=aes/original,range/rewrite --run=rerun`。
`--repeat 5` 可连续复跑；`--certificate-delay 35` 在本地转发端注入证书延迟，
`--on-demand-certificate` 复现旧测试壳在取钥回调后下载证书的流程。
FairPlay 阶段事件保存在 `fairplay-trace.jsonl` 和执行 JSON 的 `keyTrace`；
AVPlayer 错误事件保存在 `errorLogs`。
结果分别写入 `results/avplayer-device[-rerun].json` 或模拟器对应文件。
完成标记与 plannedCases 一起保存，避免把中途结果当作完整执行。
模拟器不能替代 FairPlay 真机验收。
修复前曾先完成 17 个主场景，再分别重跑 FairPlay 和补跑两个多语言轨道场景。
修复后一次运行覆盖完整的 19 个场景，见 FIX_REPORT.md。
`python3 Verification/summarize.py` 根据完整执行文件汇总最新结果；
保留各次尝试的数据，不覆盖失败记录。

### 直接在 iPhone 运行 Swift 解析器

```sh
python3 Verification/build_ios_probe.py
python3 Verification/run_ios_probe.py --device-os <version> --extended
```

复用上面的实验设备 SSH 连接。构建器编译本项目所有真实 Swift 库源码和同一份
Probe；移除的只有 Probe 的模块 import，不替换解析实现。
`--extended` 将 73 份归档、329 份外部输入和 11 个严格边界用例经 stdin
发送至手机，并增加当前 165 个固定规范 oracle，共 578 份，完整 JSON 结果与 Mac 逐项对照。
UTF-8 正文使用 base64 传输至 Data 解析入口，防止旧 Foundation 去掉 BOM。
标准审计修复在 iOS 15.5 的 464 份结果全部一致。
该 464 份为早期运行记录，最新完整执行数量以 FULL_REPORT.md 为准。
结束后删除测试目录 `/var/jb/tmp/hlsplaylist-verification`。

## 5. 与当前 Dart 接入对照

当 sibling clone 位于 `../player` 时：

```sh
python3 Verification/run.py player
```

`PlayerProbe.dart` 直接导入当前 production `rewritePlaylist`，运行相同的 73 份归档。
它用于确认集成差距，结果不算 Swift 库的验证证据。
本轮明确拒绝 variables、content steering、interstitial 三个入口；
具体异常见 `results/player-integration.json`。
