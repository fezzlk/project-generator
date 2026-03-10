# セットアップガイド

## 前提条件

以下のツールがインストール・認証済みであること:

- **gcloud CLI**: `gcloud auth login` 済み
- **gh CLI**: `gh auth login` 済み
- **firebase CLI**: `npm install -g firebase-tools && firebase login` 済み（Firebase使用時のみ）

## クイックスタート

```bash
cd ~/common
./scaffold.sh
```

対話形式でプロジェクト名・GCPプロジェクトIDなどを入力すると、基盤ファイルが生成されます。

## 生成されるファイル

| ファイル | 用途 |
|---------|------|
| `cloudbuild.yaml` | Cloud Build によるデプロイ定義 |
| `Dockerfile` | コンテナイメージ（要編集） |
| `docker-compose.yml` | ローカル開発環境 |
| `.mcp.json` | Claude Code MCP設定 |
| `CLAUDE.md` | Claude Code プロジェクトルール |
| `.gitignore` | Git除外設定 |
| `.github/workflows/ci.yml` | GitHub Actions CI |
| `.env.local.example` | 環境変数サンプル |

## 生成後にやること

### 1. Dockerfile の編集

生成された `Dockerfile` はプレースホルダーです。プロジェクトのスタックに合わせて編集してください。
ファイル内にNext.js / FastAPI / Flask の例がコメントで記載されています。

### 2. docker-compose.yml の調整

ホットリロードが効くようにコマンドを設定してください。

### 3. 環境変数の設定

```bash
cp .env.local.example .env.local
# .env.local を編集
```

### 4. Cloud Build の環境変数・シークレット

`cloudbuild.yaml` 内の TODO コメントを参考に、`--set-env-vars` や `--update-secrets` を設定してください。

Secret Manager にシークレットを追加:
```bash
echo -n "secret-value" | gcloud secrets create SECRET_NAME --data-file=-
```

### 5. CI の設定

`.github/workflows/ci.yml` にlint・testのステップを追加してください。

## ステップ構成と途中再開

scaffold.sh は11ステップのフラット構成です。`--from` オプションで途中から再開できます。

```
--- 基本 ---
 1. input                    対話式の入力収集・設定保存
 2. generate                 テンプレートからファイル生成
--- GitHub ---
 3. github                   GitHubリポジトリ作成
--- GCP ---
 4. gcp-set-project          GCPプロジェクト設定
 5. gcp-enable-apis          GCP APIの有効化
 6. gcp-artifact-registry    Artifact Registryリポジトリ作成
 7. gcp-service-account      Cloud Run用サービスアカウント作成
 8. gcp-sa-iam               サービスアカウントへのIAMロール付与
 9. gcp-cloudbuild-iam       Cloud BuildサービスアカウントへのIAMロール付与
--- Cloud Build ---
10. cloud-build-trigger      Cloud Buildトリガー作成
--- Firebase ---
11. firebase                 Firebaseセットアップ
```

### 途中から再開する

ステップ1の実行時に設定が `<生成先>/.scaffold-config` に自動保存されます。

```bash
# ステップ一覧を表示
./scaffold.sh --list

# ステップ6(Artifact Registry作成)から再開
./scaffold.sh --from 6

# ステップ名でも指定可能
./scaffold.sh --from gcp-artifact-registry

# 設定ファイルを明示指定（別ディレクトリから実行時）
./scaffold.sh --from 6 --config ~/repos/my-project/.scaffold-config
```

> `--config` を省略した場合、生成先ディレクトリを対話で聞いて `.scaffold-config` を自動検索します。

## トラブルシューティング

### セットアップが途中で失敗した

全ステップは冪等なので再実行しても安全です。失敗したステップ番号を `--from` で指定して再開してください。

```bash
# 例: API有効化まで成功、Artifact Registry作成から再開
./scaffold.sh --from gcp-artifact-registry
```

### Cloud Build トリガーが作成できない

GitHub 接続が必要です。GCPコンソール > Cloud Build > トリガー > リポジトリを接続 から設定してください。

### Cloud Run デプロイで権限エラー

IAMロール付与ステップから再実行してください。

```bash
./scaffold.sh --from gcp-sa-iam
```

### ローカルでdocker-compose upが失敗する

1. `.env.local` ファイルが存在するか確認
2. `Dockerfile` がプロジェクトのスタックに合わせて編集されているか確認
