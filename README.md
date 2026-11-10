# rime-jit

把屏幕上看到的词加入 Rime 候选栏。开启取词后，macOS 菜单栏应用在本机识别屏幕文字；打字时，Rime 的 Lua 翻译器按输入码查词，选中即可上屏。

本仓库供编码 agent 适配用户现有的 Rime 配置。参考实现使用 macOS 14 及以上版本、鼠须管、librime-lua 和小鹤双拼。换用其他输入方案时，需要核对编码规则、分段标签和方案补丁。

## 让 agent 接入

把下面这段话发给你的 agent：

> 请阅读 https://github.com/Envl/rime-jit 的 AGENTS.md，检查我当前使用的 Rime 方案、拼写规则和 Lua 插件，在现有翻译器列表中加入屏幕候选词。先用临时配置验证中文和英文候选都能选中并上屏，再更新本机配置。

配置检查、Swift 与 Lua 之间的词表格式、验证及回退步骤见 [agent 适配指南](AGENTS.md)。

## 输入效果

| 屏幕文字 | 输入 | 上屏结果 |
| --- | --- | --- |
| 重庆银行 | `isqkybhh` | 重庆银行 |
| Shell Click | `shellclick` | Shell Click |
| sample-creator-toolkit | `samplecrea` | sample-creator-toolkit |

同一行的中文、英文和中英混排短语都可以省略空格输入；上屏保留 OCR 识别出的空格，包括连续空格和全角空格。中文按词组读音生成小鹤双拼码。英文匹配时忽略大小写、空格、连字符、下划线和点号，上屏保留原文。输入三个字母即可按前缀匹配，每次最多补两个候选。

- **屏**：词在屏幕上可见时可以联想，离屏后保留五分钟。完整匹配优先于前缀匹配；同等匹配下，当前可见的词优先，其余按最近出现时间排序。
- **记**：主动选中并上屏的词按输入方案长期保存。即使用前缀选词，保存的也是完整编码。暂停取词或重启鼠须管后仍可联想。仅浏览或高亮候选不会触发保存。

## 开始、暂停与清除数据

在菜单栏选择「开始屏幕取词」，并在 macOS 系统设置中授予 **RimeScreenWords** 屏幕录制权限。程序同时从所有扩展显示器和内建屏幕取词，自动跟随显示器的接入与断开；镜像画面只取一次，在内存中处理画面，文字识别和候选查询都在本机完成。

| 本地文件 | 内容与清除方式 |
| --- | --- |
| `~/Library/Caches/RimeScreenWords/words.tsv` | 当前和最近五分钟的屏幕词及编码。「暂停屏幕取词」或正常退出会删除文件。异常退出可能留下文件，翻译器会在快照的 12 秒有效期结束后忽略它。 |
| Rime 用户目录下的 `rime-jit-selected-<schema_id>.tsv` | 当前方案中主动选用过的词。要清除长期记忆，先退出输入法，删除对应方案的文件，再重新打开输入法。 |

两个文件均为明文，可能包含屏幕上出现的个人信息。

## 实现与验证

- [屏幕识别](Sources/ScreenReader.swift) 使用 ScreenCaptureKit 获取变化的画面，交给 Vision 识别中英文。
- [分词与编码](Sources/WordIndex.swift) 结合系统提供的词组读音和鼠须管自带的朙月拼音字典生成双拼码。英文词条同时保存原文和用于匹配的编码。
- [词表快照](Sources/Snapshot.swift) 以原子替换方式更新索引。[Lua 翻译器](Rime/screen_words.lua) 在 Rime 下次查询候选时读取更新，按键处理无需等待 OCR。

在装有 Swift 编译器和 macOS 14 或更新版本 SDK 的 Mac 上使用以下命令：

| 命令 | 用途 |
| --- | --- |
| `make build` | 构建并签名菜单栏应用。默认使用可用的 Apple Development 身份，找不到时使用 ad hoc 签名。全新检出后可用 `make build SIGN_IDENTITY=-` 指定 ad hoc 签名。 |
| `make run` | 构建并打开菜单栏应用。 |
| `make check` | 在标准系统位置装有鼠须管 1.1.2 的 Mac 上，用独立的 librime 会话验证 OCR、双拼编码、跨分隔符匹配、候选上屏、五分钟过期和重启后的记忆召回。 |

测试会下载固定版本的小鹤方案和 librime C 头文件，校验哈希后在临时 Rime 用户目录中部署。GitHub Actions 负责检查 macOS 构建和 ad hoc 签名。

## 许可证

本项目采用 [MIT 许可证](LICENSE)。鼠须管、librime、librime-lua 及各输入方案沿用各自的许可证。
