# agent-kit の導入

生成したプロジェクトで Codex と Claude Code の共通ルールを使う場合は、基盤生成後に agent-kit を導入します。

```sh
git clone https://github.com/fezzlk/agent-kit.git ~/repos/agent-kit
~/repos/agent-kit/scripts/sync-project.sh /path/to/generated-project
```

これにより、次のファイルが生成されます。

- `AGENTS.md` — Codex 向けの共有ルール
- `CLAUDE.md` — Claude Code 向けの共有ルール
- `.ai/project-rules.md` — このプロジェクト固有の追記場所
- `.agent-kit.lock` — 採用した agent-kit の版を固定するファイル

生成後は `AGENTS.md` と `CLAUDE.md` を直接編集せず、共通内容は agent-kit 側、固有内容は `.ai/project-rules.md` に記録します。
