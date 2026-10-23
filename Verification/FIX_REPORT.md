# HLSPlaylist 修复与复测

**历史报告。当前行为及验证以 [STANDARDS_REPORT.md](STANDARDS_REPORT.md) 为准。**
后续标准审计已移除宽松接口，render 改为抛错，整数模型使用 UInt64，
不再兼容下文提到的非法数值、空格/Unicode URI 等输入。
下面的源码哈希、接受数量和播放成功记录只对应当时实现，不代表当前严格修复结果。

修复位于 `/Users/bytedance/Project/HLSPlaylist` 当前
`fix/uri-rewriting-cocoapods` 工作树，基于
`716ea58772b7ab2a274880d0d4ec33bdc68be4d4`。没有切换分支、提交或推送。
综合复测证据在 `results/repaired-716-final/`；测试使用独立的新构建目录。
之后按用户“符合标准”的要求复查数值格式，发现 FRAME-RATE 的三位小数
是规范要求，已纠正先前将其视为精度缺陷的结论。该补充修正的证据独立保存在
`results/standard-decimals/`；下方 413 份真机和 19 路播放记录对应补充修正前的源码，
不改写这些记录的源码哈希。

补充修正后重新构建：51 项 Swift 测试（含 Apple 实时清单、ASan 和 10,000 次
变异）通过，73 份归档及 327 份接受的外部输入稳定往返，11 个严格边界和
2,000 份随机属性用例通过。新增 FRAME-RATE 回归检查 29.970、59.940、
23.976、60.000 及向上舍入 29.971；本次没有重复真机播放。

规范依据：[RFC 8216 的 EXTINF](https://www.rfc-editor.org/rfc/rfc8216.html#section-4.3.2.1)
要求累计时长具有足够精度，未要求任意精度小数原文保真；
[FRAME-RATE](https://www.rfc-editor.org/rfc/rfc8216.html#section-4.3.4.2)
要求四舍五入到三位小数，当前 HLS bis 草案保持相同规定。

## 已修复

| 问题 | 修复后的行为 |
|---|---|
| IMAGE-STREAM-INF 的 URI 未重写 | 增加 `imageVariants` 和 `URIRole.imageVariant`，支持只有图片流的主清单 |
| 最后一个分片之后的 interstitial URI 未重写 | 分片内与末尾 DATERANGE 共用重写逻辑，覆盖 X-ASSET-URI 和 X-ASSET-LIST |
| PRELOAD-HINT、RENDITION-REPORT 丢扩展属性 | `otherAttributes` 保留未知属性，KEY preload 的 METHOD 也保留 |
| 时长被截成六位 | 使用 Double 最短往返表示，展开指数，不丢可表示精度 |
| 将 FRAME-RATE 误改为任意精度 | 按 RFC 8216 §4.3.4.2 和当前 HLS bis 草案恢复三位小数，使用固定 locale 保证小数点 |
| 极大 TARGETDURATION 计算直播偏移时溢出 | 先转 Double 再乘 3，避免整数乘法陷阱 |
| strict 接受非法时长、引号与重复属性 | 属性扫描暴露诊断；非法或非有限数值、缺失/重复/非整数 TARGETDURATION 在 strict 下拒绝 |
| 变量定义的 VALUE 引用前一个变量不稳定 | 按定义顺序展开 VALUE，再存储规范化定义 |
| URI 先引用、后定义导致 render 改变含义 | 后续定义直接报 undefinedVariable，保留第一次非法引用的行号 |
| iOS 15.5 的 Unicode 属性行未识别 | 属性标签匹配使用 String，避免旧运行时对 Substring 哈希的差异 |
| 新旧 Foundation 对含空格/Unicode 的 URI 解析不同 | resolvingURIs 显式编码 RFC 3986 以外字符，保留已有 `%` 转义和签名参数 |

`mapURIs` 仍将原始 URI 交给调用方；`resolvingURIs` 才做 URL 解析。
探针在代理重写前调用实际库的 `resolvingURIs`，没有替换库的解析逻辑。

## 最终复测

| 验证 | 结果 |
|---|---|
| 全量 Swift Testing、Apple 实时清单、ASan、覆盖率 | 50 项测试通过，0 个 known issue；含 5 × 2,000 次变异 |
| 归档语料 | 73/73 接受，全部稳定往返 |
| 外部静态输入 | 329 份中 327 份接受并稳定往返，2 份预期负例拒绝 |
| 严格边界探针 | 11/11 达到预期，无退出陷阱 |
| 随机属性生成 | 2,000 份 × 6 项检查，0 失败 |
| 广告 URI 位置 | 分片前、最后一个分片后均正确重写两个资源 URI |
| iPhone 12 / iOS 15.5 直接运行库 | 413 份完整 JSON 与 Mac 逐项一致，405 接受、8 份预期拒绝 |
| Apple mediastreamvalidator | 48 次 original/render/rewrite 对照完成；有效输入没有新增失败 |
| AVPlayer 真机播放 | 19/19 场景通过，complete=true；包含 TS/fMP4、AES 换钥、Range、直播、LL-HLS、FairPlay、双语轨道/字幕和单次 503 恢复 |

库源码覆盖率为行 92.59%、函数 88.66%、区域 91.19%；统计排除了测试和探针源码。
每路检查真实首帧、推进超过 10 秒、暂停与恢复；VOD 检查 seek，多语言场景
检查两个不同音轨与字幕选项切换、选择结果及切换后的推进。
FairPlay 原始与重写两路各成功获取 1 次证书和 1 次许可证；
两路 keyErrors 均为空，keyCancellations 均为 0。

外部负例分别为缺损 EXTM3U 头和 hls.js `m3u8-parser.ts:3176` 的前向变量引用。
413 份真机输入包含 73 份归档、329 份外部输入及 11 个严格边界；
8 份拒绝由两份外部负例和六份严格边界负例组成。

Apple 的公开 LL-HLS 快照在三种模式下都有相同的原始问题；
不会把这些问题归为修复新增错误。负例 `negative_duplicate_target` 在宽松
render 后被规范化，工具通过；`negative_missing_target` 在三种模式均失败，
render/rewrite 额外出现 `622045`。这不代表非法输入获得了严格验证：
strict 下两者都被本库拒绝。解析器仍是播放清单解析器，不是完整的 RFC
制作规范检查器。

## 行为与兼容性

- `AttributeList.parse` 保留原有宽松接口，清单解析器在 strict 下消费扫描诊断。
- 宽松解析对非法时长警告并置零，对非法数字属性警告并移除；重复目标时长警告。
- 没有后续定义的未定义变量仍按原宽松行为保留并警告；前向定义在两种模式都拒绝，
  以免 render 将定义前移后悄悄改变 URI。
- 新增 `URIRole.imageVariant`，调用方如穷举该 enum，需要增加对应分支。
- 本轮修复 HLSPlaylist 库；播放器 Dart 接入的后续迁移不包含在这份验收内。

## 复跑与证据

见 [README.md](README.md)。最终日志、覆盖率统计、源码哈希和工作树补丁保存于
`results/repaired-716-final/`。修复前 `results/fix-716ea58` 和第一轮
`results/repaired-716` 保留；第一轮扩展真机对照发现差异后才追加了 Unicode
和 URL 编码修复。

真机脚本重传 Probe 时先删除旧文件，重新创建 inode，避免系统缓存旧代码签名
造成重编译后的可执行文件被终止。测试完成后关闭测试 App、代理和 SSH 通道，
删除手机临时测试文件。
