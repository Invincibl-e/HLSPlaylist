# HLSPlaylist 标准审计与严格复测

补充：原始 FairPlay 已在后续排查中成功播放，包括 35 秒受控证书延迟及连续 5 次复测。
原因、测试壳/DRM 转发修改和全部失败记录见 [FAIRPLAY_REPORT.md](FAIRPLAY_REPORT.md)。
下方 19 路统计保留当时结果；库源码和严格校验未因本次补测而改变。

2026-10-23；实现位于 HLSPlaylist 当前 `fix/uri-rewriting-cocoapods` 工作树，
起始基线为 `716ea58772b7ab2a274880d0d4ec33bdc68be4d4`；本报告记录提交前的验证。
后续用户已授权本地提交，实际提交记录以 Git 历史为准。
本报告取代旧 FIX_REPORT 中关于宽松处理及全部语料接受的当前行为描述；
历史测试记录仍保留。

按照用户要求，清单解析默认严格，序列化也校验模型。违反已实现的标准语法、
字段及单清单约束即抛错，不补零、不丢非法属性、不静默修复原始输入。
标准明确要求忽略的未知标签、未知枚举和未知 REQ- 属性，仍按标准处理。

## 规范与范围

- [RFC 8216](https://www.rfc-editor.org/rfc/rfc8216.html)。
- [HLS 2nd Edition draft-pantos-hls-rfc8216bis-22](https://datatracker.ietf.org/doc/html/draft-pantos-hls-rfc8216bis-22)，
  固定 2026-05 版本。LL-HLS 等新增规则按此版本；它是 Internet-Draft，
  不能称为已经发布的新版 RFC。
- URI 语法参考 [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986.html)。
- 逐项实施记录见 [StandardsAudit.md](StandardsAudit.md)。

本库检查可从单份清单及调用方提供的变量上下文观察到的约束。
这次审计和测试不构成所有 RFC 要求的形式化证明或认证：媒体编码/封装、
跨刷新序列一致性、跨 rendition 同步、所有扩展专用语义，需要额外输入及验证。
数值模型仍用 Double/Date 保存浮点值，保留可表示精度，不承诺任意长小数原文保真。
FRAME-RATE 按规范输出三位小数。

## 主要修改

| 项目 | 当前行为 |
|---|---|
| 文本与属性 | 精确 EXTM3U、UTF-8/NFC、BOM/控制字符、LF/CRLF、严格属性分隔/引号/重复检查 |
| 整数与小数 | decimal-integer 使用 UInt64，完整支持 0…2^64−1；拒绝符号、指数、溢出、非 ASCII 数字；有符号小数仅用于允许的字段 |
| 标签语义 | 必需/互斥/唯一字段、主媒体混合、标签顺序、范围继承、目标时长和最低协议版本检查 |
| 主清单 | rendition 分组/引用、DEFAULT/NAME、SESSION-DATA/KEY 及已知字段类型检查 |
| 加密与初始化 | KEY 方法/IV/格式版本检查；MAP 保存声明时密钥，输出先设置 MAP 密钥，再恢复分片密钥 |
| 变量 | 前序定义、IMPORT/QUERYPARAM 上下文；只替换 URI、quoted-string 和 hexadecimal-sequence，不递归展开 |
| LL-HLS | PART/INFO/SERVER-CONTROL、时长上下界及例外、PRELOAD、相对 RENDITION-REPORT；保存末尾 PART 的 KEY/MAP/PDT/不连续上下文 |
| 日期与 DATERANGE | 真实日历日期、重复 ID 更新、时间关系及 PDT 要求；移除毫秒截断与日期字符串长度限制 |
| URI | 拒绝非法字符/percent escape；合法 opaque URI 按 RFC 3986 检查，避免 iOS 15.5 Foundation 误拒绝 data: |
| 输出与重写 | render 抛错而非崩溃；不将 report 输出成绝对 URI；保留末尾广告 URI 和扩展属性重写 |

## 最终验证

原始结果在 [results/standards-strict](results/standards-strict)。

| 验证 | 结果及含义 |
|---|---|
| 全量 Swift + ASan + live + coverage | 68 项测试、9 个 suite 通过；包含 5 × 2,000 次变异；无 known issue |
| Release 性能门槛 | 大清单用例 0.332 秒通过，门槛 5 秒；ASan 不用于性能验收 |
| 固定规范 oracle | 51/51；每例固定接受/拒绝预期和规范章节，不用解析器结果生成预期 |
| 严格边界 | 11/11；溢出等危险输入在隔离进程中检查 |
| 属性生成 | 2,000 份有效清单 × 6 项检查，0 失败 |
| 广告 URI | 分片前、最后分片后两个位置都正确重写两个广告资源 URI |
| 73 份归档 | 18 接受且稳定往返；55 拒绝 |
| 归档独立违规检查 | 55/55 具有独立可确认的违规并正确拒绝：48 控制字符、5 PDT/PART 顺序、2 TARGETDURATION 问题 |
| 329 份外部静态输入 | 96 接受且稳定往返，233 拒绝；包含故意错误或缺父清单/URL 上下文的测试片段，拒绝数量不是规范认证指标 |
| iPhone 12 / iOS 15.5 原库解析 | 464 份输入，129 接受、335 拒绝；完整 JSON 与 Mac 逐项一致 |
| Apple 归档对照 | 48 次 original/render/rewrite 完成；拒绝清单返回 422，保存每项错误及工具 JSON |
| Apple 有效媒体验证 | AES/Range 各 original/render/rewrite 共 6 次退出码均为 0；Range 每次实际处理 6/6 分片 |
| AVPlayer 真机 | 19 个计划场景完整完成：12 播放通过、6 严格预期拒绝、1 原始 FairPlay 未通过播放验证 |

库源码覆盖率：行 92.95%（2190/2356）、函数 85.01%（414/487）、
区域 87.97%（1426/1621）；排除测试和探针。完整 coverage JSON 保存于结果目录。
计数按 Swift Testing 的 test 数量，参数化子例不是另外重复计数。

iOS 首轮发现 4 处差异：3 个 data: URI 相关结果和 BOM。
修复 Foundation 旧版本 URI 限制，并让探针使用 base64 原始 UTF-8/Data 入口后，
464 份结果一致。失败首轮保存在 `attempt-before-ios-portability-fix`。

## 播放与官方工具结果的解释

Apple 当前两个主清单引用的 38 个不同子清单都含 TAB，违反 bis §4.1。
归档也保留了这些原始字节。严格 render/rewrite 返回 422；不先去 TAB 再宣称
合法输入通过。原始 AVPlayer TS/fMP4 可以播放，这是容错播放证据。

公开 LL-HLS 的 PDT 出现在 parent 首个 PART 后，违反 bis §4.4.4.9，
严格重写拒绝；原始路径能播放。当前公开 FairPlay 清单含控制字符，严格路径拒绝。
原始 FairPlay 本轮取得 1 次证书、0 次许可证，出现 1 次 key cancellation，
没有首帧；不能报告本轮 FairPlay 解密验证成功。当前也没有合法公开 LL-HLS
媒体流经过严格路径播放成功的证据；其文本规则由有效 LL 规范回归覆盖。

12 路播放通过：原始 TS/fMP4、AES 原始/重写、Range 原始/重写、
滑动直播原始/重写、原始 LL、双语 tracks 原始/重写、单次 503 recovery。
通过播放检查包括首帧、推进超过 10 秒、暂停/恢复；适用 VOD 检查 seek。
双语 tracks 两路还通过音轨/字幕切换及切换后推进。

6 路预期拒绝：TS/fMP4 的 render/rewrite 四路、LL rewrite、
FairPlay rewrite。拒绝原因及 source URI 位于 `playback-rejections.jsonl`；
AVPlayer 的 HTTP 422 错误保留在完整设备 JSON 中。

官方工具的归档 render/rewrite 额外错误来自明确记录的 422：
控制字符、PDT/PART 顺序及两个负例。未因追求工具零错误而放宽解析器。
仍接受的 daterange/fairplay 归档结构和 delta 的原始问题三组一致。
AES 工具返回 advisory 111025、实际未解密处理分片，不能以退出 0 证明 AES
解密；AES 真机两路实际播放通过提供解密证据。Range 三组只有 advisory 135048。
首轮有效工具测试误用 `/start/.../original` 导致相对 URI 基址错误，
已修正为 `/fixture/...`，失败记录保存在 `attempt-invalid-original-route`。

## API 变化与集成状态

- 删除 ParseOptions.strict、substitutesVariables、ParseWarning 及 warnings；
  所有解析只有严格行为。
- AttributeList.parse、render 为 throwing API，调用处需要 try/错误处理。
- decimal-integer 对应公开模型字段改为 UInt64。
- 新增 imageVariant URI role；手工穷举 enum 的调用方需要更新。
- 自构模型输出生成所需最低版本；解析器不自动升级非法原始输入。
- 本轮没有修改 player 的业务集成、依赖锁定或 Git 分支，也未推送。
  本地提交不代表已发布到 player 依赖中。

## 证据与复跑

按 [README.md](README.md) 设置 standards-strict 工作/结果目录。
`standards.py` 是固定规范预期；`audit_sources.py` 是归档独立决定性违规检查；
`apple_valid.py` 要求测试 playback server 已运行。
结果目录包含原始 Swift/构建日志、覆盖率、语料结果、Mac/iOS 对照、官方工具、
真机结果、原始源快照和哈希、当前源码清单与补丁。
直播回放快照明确标记为事后请求，不冒充此前动态响应的逐字节副本。
测试完成后停止自己的 App、server、SSH tunnel/master、iproxy，并删除手机测试上传和 Probe。
