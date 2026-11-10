# rime-jit

Use words on the current screen as Rime candidates. An opt-in macOS menu bar app recognizes visible text locally. A Lua translator offers matching words inside Rime's candidate menu as you type.

This repository gives coding agents a working implementation to adapt to a user's Rime setup. The reference configuration uses macOS 14+, Squirrel, librime-lua, and 小鹤双拼 (Flypy). The encoder, segment tags, and schema patch depend on the input scheme.

| Visible text | Type | Candidate |
| --- | --- | --- |
| 重庆银行 | `isqkybhh` | 重庆银行 |
| Shell Click | `shellclick` | Shell Click |
| sample-creator-toolkit | `samplecrea` | sample-creator-toolkit |

English matching ignores case, spaces, dashes, underscores, and periods. Selection commits the original spelling. The reference translator offers up to two screen candidates labeled **屏**, with prefix matching from three letters.

## Give this to your agent

> Adapt https://github.com/Envl/rime-jit to my current Rime setup. Read AGENTS.md, identify my active schema and spelling rules, integrate screen candidates alongside my existing translators, and verify selection and commit in an isolated session before updating my configuration.

> 请参考 https://github.com/Envl/rime-jit 的 AGENTS.md，检查我当前的 Rime 方案、拼写规则和 Lua 插件，按我的配置接入屏幕候选词。先在隔离会话验证候选能选中并上屏，再更新本机配置。

The integration guide covers discovery, the Swift–Lua interface, testing, and rollback. [AGENTS.md](AGENTS.md)

## Reference implementation

- `Sources/ScreenReader.swift` captures changed frames from the display under the pointer when capture starts. Vision recognizes Chinese and English text.
- `Sources/WordIndex.swift` tokenizes OCR lines and maps Chinese phrases to Flypy keys. It combines word-level Mandarin readings with the Luna Pinyin pronunciation dictionary bundled in Squirrel. English labels retain their display text alongside a normalized lookup key.
- `Sources/Snapshot.swift` atomically publishes the current index. `Rime/screen_words.lua` reads it during translation, so OCR runs outside the keystroke path.

## Local development

On a Mac with the Swift compiler and macOS 14 SDK or newer, run `make build`. Run `make run` to open the menu bar app. The default build uses an available Apple Development identity, with ad hoc signing as a fallback. Use `make build SIGN_IDENTITY=-` for an ad hoc build from a clean checkout.

With Squirrel 1.1.2 in its standard system location, `make check` exercises Vision OCR, Flypy codes, punctuation-insensitive English prefixes, and selection and commit through Squirrel's librime and Lua plugin. The test fetches a pinned upstream Flypy schema and public C header, verifies their hashes, and deploys to a temporary Rime user directory. GitHub Actions checks compilation and the signature of an ad hoc build.

## Capture and local data

Choose **开始屏幕取词** from the menu bar and grant macOS Screen Recording permission to **RimeScreenWords**. The app processes frames in memory and writes recognized words and lookup keys to `~/Library/Caches/RimeScreenWords/words.tsv`. This plaintext file can contain visible personal text. Screen recognition and candidate lookup run locally.

Choose **暂停屏幕取词** to pause and remove the snapshot. Normal app exit also removes it. After an abnormal exit, the file can remain on disk, and the translator ignores it once its 12-second lease expires. Changes appear the next time Rime queries the translator.

## License

[MIT](LICENSE). Squirrel, librime, librime-lua, and Rime schemas are separate upstream projects with their own licenses.
