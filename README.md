# common - プロジェクト基盤テンプレート

Google Cloud（Cloud Run, Firestore, Firebase Auth）上で運用するWebプロダクトのインフラ基盤を1コマンドで生成するテンプレート。

## 使い方

```bash
./scaffold.sh
```

対話式でプロジェクト名・GCPプロジェクトIDなどを入力すると、`/repos/<プロジェクト名>/` に基盤ファイルが生成されます。

## 構成

```
common/
├── scaffold.sh              # プロジェクト基盤生成CLI
├── templates/               # テンプレートファイル群
├── scripts/                 # GCP/GitHub セットアップスクリプト
└── docs/
    └── setup-guide.md       # 詳細なセットアップ手順
```

## 特徴

- **フレームワーク非依存**: Cloud Run / Cloud Build / MCP / GitHub連携の共通基盤のみ生成
- **冪等なセットアップ**: 全スクリプトは再実行しても問題なし
- **対話式**: 必要な情報を対話で収集し、テンプレート変数を自動置換

詳細は [docs/setup-guide.md](docs/setup-guide.md) を参照。個人プロジェクトを GitHub / pico / Linear へ登録する手順は [docs/pico-linear-registration.md](docs/pico-linear-registration.md) を参照。
