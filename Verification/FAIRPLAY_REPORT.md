# FairPlay 原始流失败排查与补测

2026-10-23，iPhone 12 / iOS 15.5，使用已授权实验手机和独立测试壳。
HLSPlaylist 库源码与完成标准审计时的 SHA-256 一致；本次修改测试壳及其 DRM 转发工具。
原始播放路径原样转发清单，没有经过库的 parse/render。

## 结论

已找到并复现一个能解释前次失败的原因：DRM 连接尝试等待过久，
使证书或许可证在取钥请求仍有效的时间内无法送达。
原测试壳在收到取钥回调后才下载证书，进一步占用了取钥窗口。
这不是许可证服务器明确拒绝授权，也没有证据说明是清单解析器造成原始播放失败。

前次完整 19 路执行没有分阶段时间日志，不能追溯证明那一次的全部内部状态；
但原始响应时间、独立地址连接测量、受控延迟复现，以及修改后的对照共同支持此原因。
本次成功不改写原 19 路记录。

## 证据

| 对照 | 实际观察 |
|---|---|
| 原 19 路中的 FairPlay original | 证书 1、许可证 0、SPC 取消 1、没有首帧；清单约 22:06:01 到达、首段约 22:06:04 到达，证书约 22:06:32 返回 |
| 原测试壳单独复跑 | 证书/许可证均 200，首帧、推进、暂停恢复、seek 全通过 |
| LL original → LL rewrite → FairPlay original | LL rewrite 按规范拒绝，之后 FairPlay 正常播放；未复现切换顺序导致失败 |
| 原按需取证书 + 本地人为延迟 35 秒 | 取钥回调约 23.22 秒再次触发；约 36.01 秒旧请求生成 SPC 返回 -11879；约 40.23 秒才清理，证明取消先于测试壳清理 |
| 预加载证书，默认 60 秒网络超时 + 同样延迟 | 证书准备阶段在约 60.79 秒明确超时，尚未启动取钥；这次也保留为失败证据 |
| 预加载证书，90 秒上限，旧 DRM 转发 + 同样延迟 | 证书准备约 65.71 秒完成；SPC 成功，但许可证等待约 30.83 秒，AVPlayer 报 -16833 / crypt key received slowly，未通过播放 |
| 预加载证书 + 修正 DRM 连接超时 + 同样延迟 | 证书准备约 38.72 秒完成；SPC 约 0.026 秒，许可证约 2.06 秒，首帧及全部播放检查通过 |
| 最终实现连续 5 次 | 5/5 完整播放检查通过；每次证书 1、许可证 1、取消 0，keyErrors 为空 |

独立 TCP 测量中，DRM 域名当时返回 `32.189.44.71` 与 `35.84.241.173`：
前者约 0.157 秒连通，后者在 3 秒截止时超时。该测量只描述当时当前网络，
不证明某地址永久不可用。域名地址及其顺序可能变化。

旧转发工具使用 `urllib.request.urlopen(..., timeout=30)`。
Python 的连接实现按解析出的地址逐个尝试，给每次连接应用同一超时。
失败连接等待会拖延后续地址尝试；本次旧工具实际记录一次证书获取耗时约 30.683 秒。
另一次 curl 连接建立耗时约 20.177 秒；该 curl 未带示例授权头、HTTP 返回 400，
因此只用作连接时序证据，不当作 DRM 授权测试。

Apple 将 [AVErrorContentKeyRequestCancelled](https://developer.apple.com/documentation/avfoundation/averror-swift.struct/code/contentkeyrequestcancelled)
定义为取消取钥请求。受控复现里，`AVContentKeyRequest.status` 当时仍显示 requesting，
但 SPC API 返回 -11879；不能仅靠 status 字段判断旧请求仍可用。
本次没有把取消计数当作播放成功：必须真的取得许可证并出现画面与播放推进。

## 修改

1. 测试壳在把资源加入取钥会话、启动播放之前下载并校验证书；
   下载有独立 90 秒上限。证书成功后存在该测试会话中，取钥直接使用；
   证书失败明确记录，避免继续等待不存在的许可证。
2. DRM 转发使用 Requests，连接超时 3 秒、读取超时 30 秒，
   将地址连接回退与响应读取的等待分别限定。媒体转发仍走原入口。
3. 增加证书、SPC、许可证、CKC、取钥成功与清理的阶段时间；
   保存 AVPlayer errorLog。日志只保存阶段、状态、时长、类型及字节长度，
   不保存 SPC/CKC 内容。
4. 测试构建支持 `--repeat`、`--certificate-delay`；
   `--on-demand-certificate` 用于复现旧测试壳流程，和清单严格解析无关。

测试服务器依赖 Requests。本次在任务专用 venv 中运行 Requests 2.32.5、
urllib3 1.26.20，以匹配现有 Python 3.9 / LibreSSL 2.8.3；
没有改全局 Python 环境中的包。

## 范围

本次证明原始公开 FairPlay 流可以在该设备上完成取钥与实际播放。
该公开清单仍包含 HLS 规范禁止的 TAB，严格 rewrite 路径仍应拒绝它。
本次没有通过放宽清单规则来获得播放成功，也未推送或修改 player 业务接入。
后续用户已授权本地提交，实际提交记录以 Git 历史为准。

受控 35 秒延迟仅发生在本地测试转发端，明确标注为故障注入；
没有伪造远端响应、许可证或解密结果。

## 复跑与记录

在 HLSPlaylist 工作树，设置独立工作和结果目录，运行测试 server、USB/SSH 通道，
再构建、部署测试壳：

```sh
python3 Verification/build_app.py --cases fairplay/original --repeat 5 --run fairplay-prefetch-repeat5-transport
python3 Verification/build_app.py --cases fairplay/original --certificate-delay 35 --run fairplay-delayed-prefetch-transport
```

原始记录保存在 `Verification/results/fairplay-investigation-20261023`，
包含各次完整执行 JSON、实时阶段 trace、DRM 时序、地址连接测量、源码与环境清单。
用户交付目录中的 evidence 保留这些原始记录及原 19 路记录的副本。
测试结束后停止并移除测试 App、上传、测试 server、自己的 SSH 通道和 iproxy。
