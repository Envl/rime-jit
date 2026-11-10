# Integrating rime-jit

Use this implementation to add screen-derived candidates to the user's chosen Rime schema. The tested path is macOS Squirrel 1.1.2, librime 1.16.0 with Lua, and the upstream `double_pinyin_flypy` schema. Keep the user's current frontend, schema, dictionaries, and shortcuts as the starting point.

## 1. Discover the target

Identify the frontend and version, the actual user and shared data directories, and the active schema ID. A schema list can contain several enabled options. If you cannot establish which one is active, ask which scheme the user wants to extend.

Read the schema source, its custom patch, and the effective compiled schema. Check `speller/alphabet`, `speller/algebra`, the segment tags used for ordinary input, `engine/translators`, and `engine/filters`. Check whether the frontend bundles and loads librime-lua. Treat the build directory as generated output.

## 2. Map the lookup keys

The reference helper produces Flypy keys from word-level Mandarin readings, plus lowercase compact keys for English labels. For a Flypy variant, check the actual key map, zero initials, delimiters, and alternate spellings. For full pinyin, another double-pinyin layout, or a shape-based scheme, adapt the encoder to the scheme's keys. Verify a real example against the user's mapping.

The Lua translator currently handles the `abc` segment tag and lowercase Latin input with optional Rime delimiters. It normalizes Flypy's alternate `jv/qv/xv/yv` spellings. Revisit these conditions if the target uses other tags, alphabets, or segmentation. Preserve original candidate text and the segment's start and end offsets.

On other platforms, supply a capture and OCR producer appropriate for that frontend. The included producer uses macOS ScreenCaptureKit, Vision, and the standard system Squirrel dictionary path.

## 3. Connect producer and translator

Both sides must resolve the same local snapshot path. The reference uses `~/Library/Caches/RimeScreenWords/words.tsv`. This UTF-8 format contains a header followed by up to 2,000 rows:

```text
<expiry as Unix seconds><TAB><version>
<lookup key><TAB><original candidate text>
```

Use a new version when the rows change, atomically replace the file, and renew expiry while capture is active. Use ASCII letters or digits for compact keys and keep control characters out of candidate text. The translator also accepts underscores in stored keys. On stop, clear the snapshot. Keep captured text out of logs, fixtures, issue reports, and Rime sync folders.

Copy the Lua module into the target's user Lua module directory and register it once with the active schema. For the reference configuration with no conflicting patch key:

```yaml
patch:
  "engine/translators/@next": lua_translator@*screen_words
```

If the user already customizes the translator sequence, append to their effective sequence and verify the deployed order. Preserve existing entries, including other Lua modules and filters. Check for an existing module of the same name before copying. Record the exact changes for rollback.

`scripts/install.rb` implements the reference patch for `double_pinyin_flypy`. Set `RIME_USER_DIR` to exercise it against a staged user directory. `make install-rime` applies that helper and requests a local Squirrel redeploy. Use it only when these paths, schema assumptions, and the intended live change have been verified.

## 4. Verify the adapted setup

1. Run `make build` and `make check` on a compatible Mac to establish the reference behavior.
2. Stage the target schema, its dependencies and existing patches in a temporary Rime directory. Apply the integration there. Confirm the compiled schema contains the translator once and retains the original translators and filters.
3. Use synthetic text in the snapshot. In an isolated librime session with matching module paths, type a known Chinese code and an English prefix across a separator. Assert the candidate is selectable and commits the exact original text. The reference harness in `Tests/session.c` demonstrates this. Check ordinary candidates when capture is paused.
4. Apply the verified changes to the user's intended schema, redeploy through their frontend, and run the helper. Have the user enable capture on the desired display and try a visible phrase in a text field. Record whether validation covered the library, the actual frontend, or both.

To undo the integration, stop the helper, remove the translator entry and the Lua module added for it, then redeploy. If a previously existing module was adapted, restore its previous contents.
