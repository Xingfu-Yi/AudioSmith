# Audio Smith Skills

Audio Smith uses standard, single-file Skills. Each Skill is a directory containing one required `SKILL.md`; no companion JSON is needed.

## Where Skills live

| Kind | Location | Purpose |
|---|---|---|
| Bundled fallback | `AudioSmith/Resources/Skills/aigc/SKILL.md` | Reviewed AIGC starter shipped inside the app bundle |
| Repository examples | `Examples/Skills/<name>/SKILL.md` | Copyable templates that are not shipped in the app |
| User-installed | `~/Library/Application Support/AudioSmith/Skills/<name>/SKILL.md` | Local Skills discovered when the app reloads |

The application ships one starter: `aigc`. On first launch it copies that file to `~/Library/Application Support/AudioSmith/Skills/aigc/SKILL.md`, selects it by default, and lets the user inspect or edit it. A valid user Skill with the same identifier overrides the bundled fallback and is never overwritten by later rescans.

In Audio Smith, open **System Settings → 术语 Skill → 打开 Skills 文件夹** to reveal the user directory. Copy the entire Skill directory into it. Audio Smith scans the directory before every dictation, so edits take effect on the next request without a reload button or application restart.

For example:

```text
~/Library/Application Support/AudioSmith/Skills/
└── aigc/
    └── SKILL.md
```

## File format

```markdown
---
name: my-domain
description: Improve dictation for a specialist domain.
---

# My Domain

## 使用说明

- 结合完整上下文修正发音相近的术语，不要强行替换。

## 专有名词与读法

| 规范写法 | 读法或常见误识别 |
|---|---|
| Qwen-Image-Edit | 千问 Image Edit |
| Qwen | 千问 |
| token | 偷啃；托肯 |
```

- The directory name and frontmatter `name` must match.
- `name` uses lowercase letters, digits and hyphens and is at most 64 characters.
- `description` explains when the Skill is useful.
- The first level-one heading is the display name shown in Audio Smith.
- Every Markdown body section except the pronunciation dictionary is retained as bounded Professional-mode guidance.
- Under `## 专有名词与读法`, each two-column Markdown row maps a canonical spelling to semicolon-separated spoken forms or common ASR errors.
- The legacy list form ``- `Preferred spelling`: `spoken form` `` remains accepted for existing Skills, but tables are recommended because they are more compact and consistent.
- Body text is inert data and cannot execute code, tools, scripts, or linked resources.

English `## Pronunciation dictionary` and the legacy headings `## Vocabulary` / `## 词汇` / `## 术语` are also accepted.

## Runtime behavior

1. Pressing the selected push-to-talk key starts one dictation request (`Fn` by default).
2. Audio Smith rescans the built-in and fixed user Skills directories.
3. It resolves every checked Skill and creates one deterministic, immutable combined snapshot.
4. ASR never receives the Skill. Professional mode supplies the bounded guidance and pronunciation dictionary to its one whole-transcript refinement call. Fast mode ignores the snapshot.
5. Changes saved during a recording are picked up on the next dictation request.

System Settings shows every discovered Skill as a checkbox. The bundled product experience starts with one editable AIGC Skill; advanced users may still add and combine custom Skills. The app sorts selections by identifier, deduplicates preferred terms, and activates at most 300 terms in one Professional request. The checked state remains visible but inactive in Fast mode.

## Safety and limits

- Audio Smith never sends Skills to ASR and never executes scripts, tools, or linked resources from a Skill.
- `SKILL.md` must be UTF-8 and no larger than 256KB.
- A Skill may contain at most 200 parsed pronunciation entries.
- Each selected Skill contributes at most 4,000 context characters; the final combined model prompt is capped at 8,000 characters.
- The combined request contains at most 300 unique preferred terms.
- Spoken forms are contextual hints for the Professional refiner and are never unconditional final string replacements. Still avoid overly broad entries that provide no useful acoustic signal.
- Do not include private transcripts, patient data, credentials or copyrighted terminology collections without permission.

The repository example is available at `Examples/Skills/medical-dictation/SKILL.md`. The editable starter source is maintained at `AudioSmith/Resources/Skills/aigc/SKILL.md`.
