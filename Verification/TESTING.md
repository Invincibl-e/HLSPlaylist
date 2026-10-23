# 标准测试流程：维护者与 AI 共用

先读本文，再执行测试。规范基线是 RFC 8216 和 bis-22；独立维护，不追踪上游。
上一轮整套媒体/真机验收基线见 FULL_REPORT.md（提交 `59db99d`）。
新的改动必须产生自己的运行记录，不能把旧报告称为本次测试。
所有命令从 HLSPlaylist 仓库根目录执行；在 sibling player 工作区时先
`cd ../HLSPlaylist`。新增的证书复用复测记录见 CERTIFICATE_WORKFLOW_REPORT.md。

## 1. 选择正确的验证范围

| 范围 | 命令 | 能证明什么 |
|---|---|---|
| 离线回归 | `python3 Verification/suite.py` | Swift ASan/Release、固定语料、独立 oracle、属性/边界、真实 iOS 模拟器 URI 断言、runner 失败判定 |
| 官方静态追加 | `python3 Verification/suite.py --apple --fixtures /path/to/playback-fixtures` | 离线回归加静态真实媒体的 Apple 验证，不含动态 LL 或真机 |
| 完整验收 | `python3 Verification/suite.py --profile full --live` | 上述测试加动态 HTTP/2、官方 LL、真实 iOS Probe、AVPlayer 全部场景 |
| 构建兼容性 | CI 的 platforms / cocoapods jobs | iOS/tvOS 构建、CocoaPods iOS/macOS lint，与 full 的媒体验收互补 |

修改解析、序列化、URI 重写或 LL 行为后先跑离线，再跑完整范围。
仅修改测试基础设施时至少跑对应回归与真实 transport；若没有重新跑完整
真机，报告必须保留上一轮整套验收的提交身份。
full 缺工具/设备/证书、空用例或漏结果必须失败，不能删除步骤使运行变绿。

URI 回归使用 `corpus/uri-oracles.json` 的 54 个固定预期（包含 RFC 3986
§5.4.1/§5.4.2 的全部 42 个 strict 示例），以及 seed 3986 的 2,000 个
路径构造用例（相对、根路径、network-path、绝对引用及重复斜杠）和
4 个深度边界；三项公开 API 均须与独立预期一致。
预期不使用 Foundation、被测库或 Python urljoin 生成。Swift 单元测试也
读取相同固定预期；HLS URI 属性测试扩展到 31 个，直接 encoded-path
测试扩展到 17 个，包含编码后的点与实际 dot-segment 混用、路径分号。
空引用只通过程序构造模型测试 RFC 工具行为，HLS `URI=""` 仍须拒绝。
模拟器直接编译同一份 library/Probe 源码并在实际 iOS runtime 执行；
`HLS_SIMULATOR_UDID` 可选定设备，否则复用已启动的 iOS；没有已启动设备时
按可用 runtime/type 创建干净的临时设备，退出时关闭并删除。显式指定设备
只关闭本次启动的实例，不删除。冷启动包含系统数据迁移，预算 600 秒；
整个模拟器步骤预算 1200 秒。超时仍失败，不能跳过 URI 断言。
`run_simulator_probe.py --fresh` 可单独验证临时设备的冷启动和清理流程。
缺少可用 iOS runtime 会让离线回归失败。
full 的 `ios-extended` 追加同一批 URI 用例，真机先独立检查 gold，再检查
与 Mac 完全相等。结果相等不能代替正确性断言。检查
`mac-uri-summary.json`、`ios-simulator-uri-summary.json`、
`simulator-summary.json` 和 full 的 `ios-device-uri-summary.json`。
旧 iOS 的 `URLComponents(url:)` 可把 encoded path 中的 `%2e` 解码成 `.`
并把路径分号改写为 `%3B`；后续归一化会改变资源身份。解析链路按 RFC
3986 §5.2/Appendix B 从原始编码字符串分解、合并和移除 dot-segments，
不让 Foundation 重组 path/query/fragment。最终 URL 构造仍使用系统 API。

`run.py` 将 work 路径规范为真实路径，避免 `/tmp` 与 `/private/tmp` 同时
指向一个 Swift/Clang 模块缓存而导致 Darwin duplicate-module 崩溃。
独立诊断重跑也应使用新的结果目录；不得覆盖 failed 的 suite 或把子集
重跑写成整套 full passed。

## 2. 一次配置 localhost 证书，后续测试复用

此前静态和动态阶段每次新增/删除证书信任，导致 macOS 反复要求授权。
当前标准流程完全移除测试中的 macOS trust 写入：
`suite.py` 和 `transport()` 只检查已配置的信任。

默认身份目录为 `~/.local/share/hlsplaylist-verification/tls`，
可由 `HLS_TLS_IDENTITY` 指向 runner 的独立持久目录。不要放入源码、
`Verification/results` 或证据包；私钥权限为 600。

首次由实验环境所有者执行：

```sh
python3 Verification/tls_identity.py prepare
python3 Verification/tls_identity.py install
python3 Verification/tls_identity.py check
```

`prepare` 生成 365 天 localhost 自签名证书，不写系统信任，已有文件不覆盖。
`install` 是唯一的一次授权入口：macOS 可能要求确认，SSL 信任限定 localhost；
已经可信时再运行 install 只检查，不重复写入。
`check` 检查文件、权限、到期时间、证书/私钥匹配和 macOS SSL trust，完全只读。
证书距离到期不足一天或不可信时失败，不偷偷换证书，不回退到 `curl -k`。
其他 AI 不要在每次测试前执行 install，更不要为消除弹窗关闭 TLS 校验。

完整/Apple 测试的 TLS 预检必须通过后才能验证官方媒体。实际 transport
使用同一份持久证书；证据仅复制公钥证书，私钥留在身份目录。
临时 Go 服务退出后关闭端口，不撤销持久身份信任。
手机的信任库是另一份：真机仍用临时证书，自动添加、检查并移除，
不会修改 Mac 的持久身份。

弃用环境时由所有者显式运行 `python3 Verification/tls_identity.py remove`，
撤销精确证书的信任并删除钥匙串中的证书；该管理动作也可能要求授权。
本地证书/私钥文件留供检查，若需更新证书，先撤销旧证书，再移走身份目录，
重新 prepare/install。普通测试和 CI 不自动执行这些管理动作。

## 3. full 环境与 CI

- macOS/Xcode、Swift、Python + requests、Go、ffmpeg/ffprobe、OpenSSL、
  支持 HTTP/2 的 curl、SSH、iproxy 和官方 Apple 验证工具。
- `HLS_APPLE_BIN`：官方工具目录；不分发官方二进制。
- `HLS_TLS_IDENTITY`：预置的持久身份目录；CI 使用与预置信任相同的登录用户。
- `HLS_DEVICE_UDID`、`HLS_DEVICE_HELPER`：已授权 rootless/TrollStore 实验手机；
  默认 SSH 端口 2239，可设置 `HLS_DEVICE_SSH_PORT`，手机需解锁。
- 预置 SSH 密钥优先；已有连接可设置 `HLS_SSH_CONTROL`。不把密码写入仓库。

GitHub Actions full 使用 `[self-hosted, macOS, hls-device]`，先由所有者预置
证书信任和设备，再在 workflow_dispatch 选择 full。普通托管 runner 的
offline job 不计作真机验收。不要在 CI job 内运行 install。
普通开发签名 iPhone 不具备此实验手机部署方式，需要另行配置安装适配。

## 4. 新结果的验收与交付

每次 suite 生成独立 `results/suite-<UTC>`；保留失败记录，不覆盖旧证据。
读 `summary.json`，检查 profile、全部 steps 退出码和源文件哈希；必须完成
全部步骤后才有 passed。官方报告必须同时存在 JSON/HTML 且工具退出 0；
继续保留 SHOULD 消息，不能把官方 `must_auth` 门槛描述为零警告。

真机同时核对 `device-checks.json`、`device-transport-checks.json`、
完整 AVPlayer 记录和 `ios-extended-summary.json`。当前基线是 22 场景：
16 个正常播放、6 个严格解析负例。负例必须有真实 server 422 和解析原因；
任意网络失败不能算拒绝验证成功。三组本地 LL 必须有 HTTP/2 blocking/v2
wire 记录，不能只根据首帧判断。
新增规范 oracle 的预期必须独立取自规范；拒绝要求发生在 parse 阶段，
不能用 render 失败、渲染器自动修正输入或被测库输出反推预期来代替。

清理核对 `device-cleanup.json`、device trust 的 remove 结果以及服务退出。
Mac 的预置证书属于 runner 长期配置，不再要求每轮撤销；设备临时证书仍需移除。
报告说明源码提交、实际执行范围、结果和限制。最终证据可归档到 sibling
player 的 `verification/hlsplaylist-20261023/`，仅包含公开证书和哈希，不含私钥。
提交测试与说明，未经授权不推送远端、不修改 player 业务或依赖锁。

## 5. 对“100% 符合标准”的准确回答

当前整套已执行用例通过；不是所有条款均被证明符合，也不是 Apple 认证。
NormativeInventory.json 收录 428 个 bis-22 和 226 个 RFC 8216 规范性段落，
包含 SHOULD。它用于发现遗漏；段落清单、节号映射、代码覆盖率均不等于
654 个已逐项验证的义务，多个要求可能在同一个段落中。

Coverage.md 与 RuntimeCoverage.md 区分已有可执行断言和外部义务。
仍不能从本库测试证明所有编解码/媒体格式、所有 OS/播放器、SCTE-35
载荷、完整 Content Steering 调度、可选扩展的完整播放行为，以及每一种
可能的输入/跨刷新状态。没有依据就不能说“所有需要测试的点都已穷尽”。
发现新条款或问题后更新映射、补独立预期的正负例、修复并按受影响范围复测。
