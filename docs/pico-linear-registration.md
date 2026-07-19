# pico / Linear 登録フロー

新規プロジェクトを作るときは、GitHub・pico・Linear を同じ情報から連続して登録します。GitHub リポジトリが先、pico は台帳、Linear は実行管理です。

## 最短の使い方

プロジェクトを始めるときに Codex へ次を送ります。

```
新規プロジェクトを登録してください。
- 表示名: <プロジェクト名>
- GitHub リポジトリ名: <kebab-case-name>
- 概要: <1行>
- 目的: <1〜3文>
- ローカルパス: ~/repos/<kebab-case-name>
- 状態: 進行中
```

GitHub リポジトリ未作成の場合は、`./scaffold.sh` を使って先に基盤を作成します。

## Codex が実行する登録順

1. GitHub リポジトリの存在と URL を確認する。
2. `pico/projects/<slug>.md` をテンプレートから作成し、GitHub とローカルパスを記録する。
3. `pico/README.md` のプロジェクト一覧へ追記する。
4. Linear に同名の Project を作成し、概要・GitHub・pico のリンクを入れる。
5. 作成された Linear URL を `pico/projects/<slug>.md` に書き戻す。
6. GitHub / pico / Linear の3リンクを返して完了を報告する。

## 自動化の境界

pico は GitHub MCP で直接更新できます。Linear Project の作成は外部サービスへの書き込みなので、Codex が作成直前に確認を取ります。Linear API 連携を追加できるようになるまでは、この確認だけを残した半自動フローにします。

## プロジェクト記録テンプレート

テンプレートは [templates/pico-project.md.tmpl](../templates/pico-project.md.tmpl) にあります。
