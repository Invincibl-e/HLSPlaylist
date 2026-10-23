# 标准对照实施记录

用户要求：仔细对照标准，按标准处理；不兼容不合规输入。
此文件记录实施规则，完成后的用户报告另存到 sibling player 的 verification。
审计起始基线为 fix/uri-rewriting-cocoapods / 716ea587；以下记录提交前的审计过程。
后续用户已授权本地提交，实际提交记录以 Git 历史为准。

## 规范依据

- RFC 8216：https://www.rfc-editor.org/rfc/rfc8216.html
- HLS 2nd Edition 草案固定版本 draft-pantos-hls-rfc8216bis-22（2026-05），
  https://datatracker.ietf.org/doc/html/draft-pantos-hls-rfc8216bis-22
- 已下载文本：`/tmp/hlsplaylist-standard-audit/rfc8216.txt`、
  `/tmp/hlsplaylist-standard-audit/bis.txt`。
- 第 4 节为清单语法、语义规则；bis 第 6.3.1 节规定前向兼容处理，
  第 8 节规定协议版本。媒体实际封装、编码、直播跨刷新一致性等需要媒体及
  多次响应，不能只靠单个文本解析器验证。不得将本库称为全部 RFC 的认证器。
- 已有 IMAGE-STREAM-INF 是扩展，不能因未出现在 RFC 正文就拒绝整个清单；
  未识别标签的忽略要求仍成立。其扩展专用要求需单独核实来源。

## 执行原则

1. 清单解析始终拒绝非法语法和已知字段/标签约束，不保留补零、丢数字属性或
   强行继续的宽松路径。移除 `ParseOptions.strict`、`ParseWarning` 和结果 warnings；
   `AttributeList.parse` 应成为 throwing 标准扫描接口，所有调用点同步修改。
2. 未识别标签、属性按规范忽略/保留。bis §6.3.1：未知 `REQ-` 属性需忽略整个
   标签；未知 enumerated-string 值也需忽略标签；被忽略 STREAM-INF 的后续 URI
   也要忽略。不能把这些前向兼容情形当非法输入拒绝。
3. 支持完整 decimal-integer：1–20 个 ASCII 数字，0…UInt64.max，无 +/-、空白、
   Unicode 数字。将对应模型字段和 AttributeValue.integer 改为 UInt64，勿钳位
   或丢失大于 Int.max 的合法值。索引、日期内部运算仍用 Int。
4. decimal-floating-point 用十进制位值形式，禁止 e/E、+、NaN/Inf；仅
   signed-decimal-floating-point 允许开头负号。模型仍使用有限 Double，输出
   formatDecimal 无指数并保留已存 Double 精度。FRAME-RATE 按规范三位小数。
5. 对程序构造/修改的模型，render 也应拒绝非法输出（throwing validation），
   不能靠 precondition 导致进程崩溃。需要同步迁移测试与探针。已解析清单的
   import/上下文不能在 render 中简单重新 parse 来伪造，验证模型自身约束。

## 文本与属性

- 第一行精确 #EXTM3U，不接受 BOM、前置空行、尾随空白或重复头。
- UTF-8、NFC、禁控制字符（CR/LF 除外）；换行为 LF 或 CRLF，拒绝孤立 CR。
- 空行可忽略；URI/标签不得有未允许的空白。标题及 quoted-string 内允许的
  空白按各自定义处理，不能全行 trim。
- 属性名仅 [A-Z0-9-]，无分隔符周围空白，拒绝空名、重复名、未闭引号、
  尾随垃圾/逗号。quoted-string 按 bis 默认非空，VALUE="" 是明确允许的例外。
- 各已知字段严格区分 quoted / unquoted / integer / float / resolution / hex /
  enumerated-string(-list)；未知扩展字段不强行按同名全局类型误解。
- resolution 两个完整 decimal-integer，以小写 x 分隔；不接受 ×、X、符号、
  多个分隔符。像素数排序防溢出，与模型的完整整数范围分开考虑。
- hex [0-9A-F]，0x/0X 前缀；IV 最长 128 bit，解析须左填零成 16 字节；
  不接受非法 hex 或超过 128 bit。SCTE35 不误用 IV 的长度上限。
- URI 引用需校验合法 RFC 3986 相对/绝对 URI（含合法 percent escape），
  不能以 Foundation 的隐式空格/Unicode 编码作为接受非法 URI 的依据。

## 标签与顺序

- shared singleton：VERSION、INDEPENDENT-SEGMENTS、START；媒体 singleton：
  TARGETDURATION、MEDIA-SEQUENCE、DISCONTINUITY-SEQUENCE、ENDLIST、
  PLAYLIST-TYPE、I-FRAMES-ONLY、PART-INF、SERVER-CONTROL；SKIP 唯一。
- 标记标签不能带冒号/值，带参数标签须有冒号；重复 EXTINF 或悬空必要 URI
  拒绝。主/媒体混合拒绝，包括 DATERANGE 等媒体 metadata。
- TARGETDURATION 至少 1，必需；版本 <=5 约束实际最大时长，>=6 约束四舍五入
  后时长。media/discontinuity sequence 必须在第一分片前；discontinuity sequence
  还必须在首个 DISCONTINUITY 前。序列递增不能 wrap 产生负数/零。
- BYTERANGE n[@o] 严格解析；无 offset 需要前一个分片有范围并指向相同资源。
  MAP BYTERANGE 的 offset 在 bis 为必需。PART 隐式范围的前序须属于同一 parent。
- DISCONTINUITY、KEY、MAP、PROGRAM-DATE-TIME 必须在 parent 的首个 PART 之前。
  重写/序列化不能丢末尾 PART 所需的 key、map、discontinuity、PDT 上下文
  （当前模型在 trailingParts 处丢上下文，需修复）。

## 字段约束

- STREAM-INF / I-FRAME：BANDWIDTH 必需；I-FRAME URI 必需，禁止 FRAME-RATE、
  AUDIO、SUBTITLES、CLOSED-CAPTIONS。MEDIA：TYPE/GROUP-ID/NAME 必需；
  SUBTITLES URI 必需；CLOSED-CAPTIONS 禁 URI、必 INSTREAM-ID。
- DEFAULT=YES 则 AUTOSELECT 若出现必须 YES；FORCED 仅 SUBTITLES；
  同组 NAME 唯一、最多一个 DEFAULT；variant 的 group 引用必须存在；
  CLOSED-CAPTIONS=NONE 的全体 variant 约束。bis non-CC INSTREAM-ID 为 v13
  功能，不能机械套 RFC 老规则拒绝。
- SESSION-DATA DATA-ID 必需，VALUE/URI 二选一，同 DATA-ID/LANGUAGE 唯一。
  SESSION-KEY 禁 NONE，重复相同 key 禁止。
- KEY METHOD 必需；NONE 禁其他属性；未知方法按规范忽略/不解密，不默认 NONE。
  SAMPLE-AES-CTR 和 AES-256-GCM 禁 IV；AES-128 MAP 加密需要明确 IV；
  KEYFORMATVERSIONS 为正整数 slash 列表。
- DEFINE 三种声明 NAME/IMPORT/QUERYPARAM 互斥且恰一，NAME 必 VALUE；
  名称只 [a-zA-Z0-9_-] 且不空、不重复；IMPORT 仅媒体、需要父清单上下文；
  query 值解码后禁引号/控制字符。bis-22 §4.3 明确允许在 URI 行、quoted
  属性值、hexadecimal-sequence 属性值中替换；不能替换
  EXTINF 标题、注释或 unquoted 数字；仅用前面已定义的值，替换结果不再递归
  替换。VALUE 自身为 quoted-string，引用前面变量仍须先展开。
- DATERANGE ID 必需；START-DATE 可在同 ID 后续更新省略；
  同 ID 重复属性必须一致，需合并解释；END-ON-NEXT 必 CLASS，禁 DURATION/
  END-DATE；end >= start，end=start+duration，清单必须有至少一个 PDT。
  CUE 禁 PRE 与 POST 同时出现；X- 属性只 quoted/hex/signed decimal。
  日历日期须真实存在，不能把 2 月 30 日静默进位；时区偏移要校验。
- LL：PART 必 URI/DURATION；PART-INF 必 PART-TARGET，存在 PART 则必 PART-INF；
  存在 PART-INF 则必 PART-HOLD-BACK，至少 2×partTarget（3×为 SHOULD）。
  CAN-SKIP-UNTIL 至少 6×target，HOLD-BACK 至少 3×target，
  CAN-SKIP-DATERANGES 需 CAN-SKIP-UNTIL；PART 时长 <=partTarget，85% 下界
  按 INDEPENDENT/GAP/后接 GAP/parent final 的例外处理。
- PRELOAD TYPE 未识别（包括 KEY）按 bis §6.3.9 MUST ignore，不能把 Shaka 的
  KEY preload 当核心 HLS 合规功能；可保留原文但不跟随/重写其 URI。
  ENDLIST 禁 PRELOAD。建议重复 TYPE 是 SHOULD，不能当硬错误。
- RENDITION-REPORT URI 必须相对；LAST-MSN / LAST-PART 可按本清单末尾隐式
  省略，不能机械要求存在；对其他 rendition 是否含 PART 无上下文则不臆断。
  generic mapURIs/resolvingURIs 和代理探针不能把 report 最终写成绝对 URI。

## 协议版本与输出

bis §8：IV >=2；浮点 EXTINF >=3；BYTERANGE/I-FRAMES-ONLY >=4；
SAMPLE-AES/KEYFORMAT/VERSIONS/MAP >=5；非 I-FRAMES 的 MAP >=6；
SERVICE CC >=7；变量替换 >=8；SKIP >=9；跳 DATERANGE 的 SKIP >=10；
DEFINE QUERYPARAM >=11；REQ- 属性 >=12；非 CC INSTREAM-ID >=13。
解析不能自动升级缺失/不足的输入版本。模型构造的 render 可显式生成所需版本，
但不能伪造合法解析。旧 PROGRAM-ID/ALLOW-CACHE 按对应版本及忽略规则处理。

## 验证迁移

- 原有 lenient 测试改为拒绝测试，不保留兼容路径以维持旧计数。
- 修正本库正例：LL CAN-SKIP-UNTIL=12 对 target4 非法（需至少24）；
  含小数 EXTINF 的无 VERSION 输入、无 PDT 的 DATERANGE 等补足规范字段。
- 73 归档及 329 外部输入重新分类：缺上下文/缺字段/故意错误样本应该拒绝，
  不能把“接受得更多”作为成功指标。为有效样本保留独立字段与重写 oracle，
  为拒绝样本固定规范规则及错误，不只用 parser 自己来生成预期。
- property generator 正例带足够 VERSION，并让 master/group/MAP/LL/DRM fixtures
  满足约束；补 64-bit 极值、符号、指数、控制/NFC、REQ-/未知 enum 忽略、
  relative report、隐式范围、LL 时间边界、版本、重复/必需/互斥的负例。
- 全量 Swift ASan/live/coverage，新的 corpus/property/boundary 结果目录；
  Apple original/render/rewrite 对照需记录拒绝非法输入（422）与通过有效输入，
  不再使用强行规范化非法源清单的宽松代理；新 source manifest。
- 真实 iOS 优化构建解析对照与有效流真机播放；测试 App 及脚本的 render/parse
  错误处理同步。关闭临时服务，保留用户已有代理与 iproxy8090。
- 审计执行阶段不切分支、不提交、不推送、不修改播放器集成。后续用户授权本地提交；
  不推送、不修改播放器集成的范围仍保持。报告/支持文件最终放 player；
  实现、测试及审计记录放 HLSPlaylist。

## 正文复核修正及已确认事实

- bis-22 §4.3 除 URI 和 quoted-string 外还列出 hexadecimal-sequence；
  `IV=0x{$iv}` 等十六进制属性已纳入替换。EXTINF 标题和 unquoted 数字不替换。
- bis-22 §4.4.4.6 的 PDT 时区属于 SHOULD，省略时区按 UTC；
  不能把没有时区作为硬错误。日历日期和偏移范围仍须验证。
- MAP 的加密配置取决于它被声明时的 KEY；不是使用分片当前 KEY 来判断。
  模型已保存 MAP 的声明配置，输出会在 MAP 前设置对应 KEY，再恢复分片 KEY。
- Foundation `String(data:encoding:)` 和 JSONSerialization 的 NSString 桥接会
  消除开头的 BOM。库的 Data 入口先检查原始字节，探针使用 JSONDecoder。
- Apple 当前两个公开主清单的 38 个不同子清单中存在 `EXTINF:...,\t`：
  该 TAB 是 §4.1 禁用控制字符。实时测试保留字节并按独立控制字符检查预期拒绝，
  不使用去 TAB 的输出冒充原始输入通过。
- 性能用例的 5 秒阈值仅在显式 `HLS_PERFORMANCE_TESTS=1` 的 Release 构建验收；
  ASan 用于功能和内存检查。所有失败尝试均保留，不改写为通过日志。
- 新结果专用目录：`Verification/results/standards-strict`；
  新工作目录：`/tmp/hlsplaylist-validation/standards-strict`。
  `standards.py` 固定独立规范正/负例；语料 round-trip 测试仅说明接受输入的保真，
  不把 parser 自己的接受/拒绝作为外部语料的规范认证 oracle。
