#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
DEFAULT_REGION="asia-northeast1"
DEFAULT_OUTPUT_BASE="${HOME}/repos"

# --- ヘルパー ---
info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
success() { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

render_template() {
  local template="$1"
  local output="$2"
  sed \
    -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
    -e "s|{{PROJECT_ID}}|${PROJECT_ID}|g" \
    -e "s|{{SERVICE_NAME}}|${SERVICE_NAME}|g" \
    -e "s|{{REPO_NAME}}|${REPO_NAME}|g" \
    -e "s|{{REGION}}|${REGION}|g" \
    -e "s|{{HOME}}|${HOME}|g" \
    "$template" > "$output"
}

read_input() {
  local prompt="$1"
  local default="${2:-}"
  local var_name="$3"
  if [[ -n "$default" ]]; then
    read -rp "${prompt} [${default}]: " value
    eval "${var_name}=\${value:-${default}}"
  else
    read -rp "${prompt}: " value
    while [[ -z "$value" ]]; do
      read -rp "${prompt} (必須): " value
    done
    eval "${var_name}=\${value}"
  fi
}

confirm() {
  local prompt="$1"
  local default="${2:-n}"
  local yn
  if [[ "$default" == "y" ]]; then
    read -rp "${prompt} [Y/n]: " yn
    yn="${yn:-y}"
  else
    read -rp "${prompt} [y/N]: " yn
    yn="${yn:-n}"
  fi
  [[ "$yn" =~ ^[Yy] ]]
}

# ============================================================
# ステップ定義（フラット構成）
# ============================================================
STEPS=(
  "input"
  "generate"
  "github"
  "gcp-set-project"
  "gcp-enable-apis"
  "gcp-artifact-registry"
  "gcp-service-account"
  "gcp-sa-iam"
  "gcp-cloudbuild-iam"
  "cloud-build-trigger"
  "firebase"
)

STEP_DESCRIPTIONS=(
  "対話式の入力収集・設定保存"
  "テンプレートからファイル生成"
  "GitHubリポジトリ作成"
  "GCPプロジェクト設定 (gcloud config set project)"
  "GCP APIの有効化"
  "Artifact Registryリポジトリ作成"
  "Cloud Run用サービスアカウント作成"
  "サービスアカウントへのIAMロール付与"
  "Cloud BuildサービスアカウントへのIAMロール付与"
  "Cloud Buildトリガー作成"
  "Firebaseセットアップ"
)

show_steps() {
  echo ""
  echo "ステップ一覧:"
  echo ""
  local prev_group=""
  for i in "${!STEPS[@]}"; do
    local num=$((i + 1))
    local name="${STEPS[$i]}"
    local desc="${STEP_DESCRIPTIONS[$i]}"
    local group=""
    case "$name" in
      input|generate) group="基本" ;;
      github)         group="GitHub" ;;
      gcp-*)          group="GCP" ;;
      cloud-build-*)  group="Cloud Build" ;;
      firebase)       group="Firebase" ;;
    esac
    if [[ "$group" != "$prev_group" ]]; then
      echo "  --- ${group} ---"
      prev_group="$group"
    fi
    printf "  %2d. %-24s %s\n" "$num" "$name" "$desc"
  done
  echo ""
}

show_help() {
  echo ""
  echo "プロジェクト基盤ジェネレータ"
  echo ""
  echo "Google Cloud (Cloud Run / Firestore / Firebase Auth) 上で運用する"
  echo "Webプロダクトのインフラ基盤を対話式で生成します。"
  echo ""
  echo "使い方:"
  echo "  ./scaffold.sh [オプション]"
  echo ""
  echo "オプション:"
  echo "  --from <ステップ>    指定したステップから再開（番号 or 名前）"
  echo "  --config <パス>      設定ファイルを指定（省略時は対話で検索）"
  echo "  --list               ステップ一覧を表示"
  echo "  --help, -h           このヘルプを表示"
  echo ""
  echo "前提条件:"
  echo "  - gcloud CLI   : gcloud auth login 済み"
  echo "  - gh CLI        : gh auth login 済み"
  echo "  - firebase CLI  : firebase login 済み（Firebase使用時のみ）"
  echo ""
  echo "使用例:"
  echo "  ./scaffold.sh                                  # 全ステップ実行"
  echo "  ./scaffold.sh --from 4                         # ステップ4から再開"
  echo "  ./scaffold.sh --from gcp-enable-apis           # ステップ名で指定"
  echo "  ./scaffold.sh --from 4 --config path/to/config # 設定ファイル指定"
  echo ""
  show_steps
}

# ============================================================
# 引数パース
# ============================================================
FROM_STEP=""
CONFIG_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)  FROM_STEP="$2"; shift 2 ;;
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --list)  show_steps; exit 0 ;;
    --help|-h) show_help; exit 0 ;;
    *) shift ;;
  esac
done

resolve_step_number() {
  local input="$1"
  if [[ "$input" =~ ^[0-9]+$ ]]; then
    echo "$input"
    return
  fi
  for i in "${!STEPS[@]}"; do
    if [[ "${STEPS[$i]}" == "$input" ]]; then
      echo "$((i + 1))"
      return
    fi
  done
  error "不明なステップ: ${input}"
  show_steps
  exit 1
}

START_STEP=1
if [[ -n "$FROM_STEP" ]]; then
  START_STEP=$(resolve_step_number "$FROM_STEP")
fi

should_run() {
  local step_num=$1
  [[ $step_num -ge $START_STEP ]]
}

# ============================================================
# 設定の保存・読み込み
# ============================================================
save_config() {
  local config_path="$1"
  mkdir -p "$(dirname "$config_path")"
  cat > "$config_path" << CONF
PROJECT_NAME="${PROJECT_NAME}"
PROJECT_ID="${PROJECT_ID}"
SERVICE_NAME="${SERVICE_NAME}"
REPO_NAME="${REPO_NAME}"
REGION="${REGION}"
OUTPUT_DIR="${OUTPUT_DIR}"
USE_FIREBASE_AUTH="${USE_FIREBASE_AUTH}"
USE_FIRESTORE="${USE_FIRESTORE}"
CONF
  success "設定を保存: ${config_path}"
}

load_config() {
  local config_path="$1"
  if [[ ! -f "$config_path" ]]; then
    error "設定ファイルが見つかりません: ${config_path}"
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$config_path"
  info "設定を読み込み: ${config_path}"
}

# ============================================================
# メイン処理
# ============================================================
echo ""
echo "=============================="
echo "  プロジェクト基盤ジェネレータ"
echo "=============================="

if [[ $START_STEP -gt 1 ]]; then
  echo ""
  info "ステップ ${START_STEP} (${STEPS[$((START_STEP - 1))]}) から再開"
fi
echo ""

# ----------------------------------------------------------
# 1. input: 対話式入力 or 設定読み込み
# ----------------------------------------------------------
if should_run 1; then
  if [[ -n "$CONFIG_FILE" ]]; then
    load_config "$CONFIG_FILE"
  else
    read_input "プロジェクト名" "" PROJECT_NAME
    read_input "GCPプロジェクトID" "${PROJECT_NAME}" PROJECT_ID
    SERVICE_NAME="${PROJECT_NAME}"
    read_input "Cloud Runサービス名" "${SERVICE_NAME}" SERVICE_NAME
    read_input "Artifact Registryリポジトリ名" "${PROJECT_NAME}" REPO_NAME
    read_input "リージョン" "${DEFAULT_REGION}" REGION
    read_input "生成先ディレクトリ" "${DEFAULT_OUTPUT_BASE}/${PROJECT_NAME}" OUTPUT_DIR

    USE_FIREBASE_AUTH="n"
    USE_FIRESTORE="n"
    if confirm "Firebase Auth を使用しますか？"; then
      USE_FIREBASE_AUTH="y"
    fi
    if confirm "Firestore を使用しますか？"; then
      USE_FIRESTORE="y"
    fi
  fi

  echo ""
  info "=== 設定確認 ==="
  info "プロジェクト名:    ${PROJECT_NAME}"
  info "GCPプロジェクトID: ${PROJECT_ID}"
  info "サービス名:        ${SERVICE_NAME}"
  info "ARリポジトリ名:    ${REPO_NAME}"
  info "リージョン:        ${REGION}"
  info "生成先:            ${OUTPUT_DIR}"
  info "Firebase Auth:     ${USE_FIREBASE_AUTH}"
  info "Firestore:         ${USE_FIRESTORE}"
  echo ""

  if ! confirm "この内容で生成しますか？" "y"; then
    echo "中止しました。"
    exit 0
  fi

  mkdir -p "${OUTPUT_DIR}"
  save_config "${OUTPUT_DIR}/.scaffold-config"
else
  # ステップ2以降から開始 → 設定ファイル必須
  if [[ -n "$CONFIG_FILE" ]]; then
    load_config "$CONFIG_FILE"
  else
    read_input "プロジェクト名 or 生成先ディレクトリ" "" OUTPUT_DIR
    SCAFFOLD_CONFIG=""

    # 入力値からconfig探索: そのまま → DEFAULT_OUTPUT_BASE配下 の順
    CANDIDATES=(
      "${OUTPUT_DIR}/.scaffold-config"
      "${DEFAULT_OUTPUT_BASE}/${OUTPUT_DIR}/.scaffold-config"
    )
    for candidate in "${CANDIDATES[@]}"; do
      if [[ -f "$candidate" ]]; then
        SCAFFOLD_CONFIG="$candidate"
        break
      fi
    done

    if [[ -n "$SCAFFOLD_CONFIG" ]]; then
      load_config "$SCAFFOLD_CONFIG"
    else
      error "設定ファイルが見つかりません"
      info "  検索パス:"
      for candidate in "${CANDIDATES[@]}"; do
        info "    - ${candidate}"
      done
      info "  --config で直接指定するか、ステップ1から実行してください"
      exit 1
    fi
  fi
  echo ""
  info "=== 読み込んだ設定 ==="
  info "プロジェクト名:    ${PROJECT_NAME}"
  info "GCPプロジェクトID: ${PROJECT_ID}"
  info "サービス名:        ${SERVICE_NAME}"
  info "ARリポジトリ名:    ${REPO_NAME}"
  info "リージョン:        ${REGION}"
  info "生成先:            ${OUTPUT_DIR}"
  info "Firebase Auth:     ${USE_FIREBASE_AUTH}"
  info "Firestore:         ${USE_FIRESTORE}"
  echo ""
fi

# 共通変数
SA_NAME="${SERVICE_NAME}-run"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# ----------------------------------------------------------
# 2. generate: テンプレートからファイル生成
# ----------------------------------------------------------
if should_run 2; then
  info "[2/11] テンプレートからファイル生成"
  mkdir -p "${OUTPUT_DIR}/.github/workflows"

  render_template "${TEMPLATES_DIR}/cloudbuild.yaml.tmpl" "${OUTPUT_DIR}/cloudbuild.yaml"
  render_template "${TEMPLATES_DIR}/Dockerfile.tmpl" "${OUTPUT_DIR}/Dockerfile"
  render_template "${TEMPLATES_DIR}/docker-compose.yml.tmpl" "${OUTPUT_DIR}/docker-compose.yml"
  render_template "${TEMPLATES_DIR}/.mcp.json.tmpl" "${OUTPUT_DIR}/.mcp.json"
  render_template "${TEMPLATES_DIR}/CLAUDE.md.tmpl" "${OUTPUT_DIR}/CLAUDE.md"
  render_template "${TEMPLATES_DIR}/.gitignore.tmpl" "${OUTPUT_DIR}/.gitignore"
  render_template "${TEMPLATES_DIR}/.github/workflows/ci.yml.tmpl" "${OUTPUT_DIR}/.github/workflows/ci.yml"

  if [[ ! -f "${OUTPUT_DIR}/.env.local.example" ]]; then
    cat > "${OUTPUT_DIR}/.env.local.example" << 'EOF'
# ローカル開発用環境変数
# このファイルをコピーして .env.local を作成してください
# cp .env.local.example .env.local
PORT=8080
EOF
  fi

  success "ファイル生成完了: ${OUTPUT_DIR}"
  echo ""
fi

# ----------------------------------------------------------
# 3. github: GitHubリポジトリ作成
# ----------------------------------------------------------
if should_run 3; then
  info "[3/11] GitHubリポジトリ作成"
  if confirm "  実行しますか？"; then
    bash "${SCRIPTS_DIR}/setup-github-repo.sh" "${PROJECT_NAME}" "${OUTPUT_DIR}"
  else
    warn "スキップ"
  fi
  echo ""
fi

# ----------------------------------------------------------
# 4. gcp-set-project: GCPプロジェクト設定
# ----------------------------------------------------------
if should_run 4; then
  info "[4/11] GCPプロジェクト設定: ${PROJECT_ID}"
  gcloud config set project "${PROJECT_ID}"
  success "プロジェクト設定完了"
  echo ""
fi

# ----------------------------------------------------------
# 5. gcp-enable-apis: API有効化
# ----------------------------------------------------------
if should_run 5; then
  info "[5/11] GCP APIを有効化中..."
  APIS=(
    run.googleapis.com
    artifactregistry.googleapis.com
    cloudbuild.googleapis.com
    secretmanager.googleapis.com
  )
  if [[ "${USE_FIRESTORE}" == "y" ]]; then
    APIS+=(firestore.googleapis.com)
  fi
  for api in "${APIS[@]}"; do
    info "  ${api}"
    gcloud services enable "${api}" --quiet 2>/dev/null || true
  done
  success "API有効化完了"
  echo ""
fi

# ----------------------------------------------------------
# 6. gcp-artifact-registry: ARリポジトリ作成
# ----------------------------------------------------------
if should_run 6; then
  info "[6/11] Artifact Registryリポジトリ作成"
  if gcloud artifacts repositories describe "${REPO_NAME}" \
      --location="${REGION}" --format="value(name)" 2>/dev/null; then
    warn "リポジトリ ${REPO_NAME} は既に存在します（スキップ）"
  else
    gcloud artifacts repositories create "${REPO_NAME}" \
      --repository-format=docker \
      --location="${REGION}" \
      --description="Docker repository for ${SERVICE_NAME}"
    success "リポジトリ ${REPO_NAME} を作成しました"
  fi
  echo ""
fi

# ----------------------------------------------------------
# 7. gcp-service-account: サービスアカウント作成
# ----------------------------------------------------------
if should_run 7; then
  info "[7/11] サービスアカウント作成: ${SA_NAME}"
  if gcloud iam service-accounts describe "${SA_EMAIL}" 2>/dev/null; then
    warn "サービスアカウント ${SA_NAME} は既に存在します（スキップ）"
  else
    gcloud iam service-accounts create "${SA_NAME}" \
      --display-name="Cloud Run service account for ${SERVICE_NAME}"
    success "サービスアカウント ${SA_NAME} を作成しました"
  fi
  echo ""
fi

# ----------------------------------------------------------
# 8. gcp-sa-iam: SAへのIAMロール付与
# ----------------------------------------------------------
if should_run 8; then
  info "[8/11] サービスアカウントにIAMロール付与"
  ROLES=(
    roles/datastore.user
    roles/secretmanager.secretAccessor
    roles/storage.objectViewer
  )
  for role in "${ROLES[@]}"; do
    info "  ${role}"
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="serviceAccount:${SA_EMAIL}" \
      --role="${role}" \
      --condition=None \
      --quiet 2>/dev/null || true
  done
  success "IAMロール付与完了"
  echo ""
fi

# ----------------------------------------------------------
# 9. gcp-cloudbuild-iam: Cloud Build SAへのIAMロール付与
# ----------------------------------------------------------
if should_run 9; then
  info "[9/11] Cloud Buildサービスアカウントに権限付与"
  PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
  CB_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

  CB_ROLES=(
    roles/run.admin
    roles/iam.serviceAccountUser
    roles/artifactregistry.writer
  )
  for role in "${CB_ROLES[@]}"; do
    info "  ${role} → ${CB_SA}"
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="serviceAccount:${CB_SA}" \
      --role="${role}" \
      --condition=None \
      --quiet 2>/dev/null || true
  done
  success "Cloud Build権限付与完了"
  echo ""
fi

# ----------------------------------------------------------
# 10. cloud-build-trigger: Cloud Buildトリガー作成
# ----------------------------------------------------------
if should_run 10; then
  info "[10/11] Cloud Buildトリガー作成"
  if confirm "  実行しますか？"; then
    bash "${SCRIPTS_DIR}/setup-cloud-build-trigger.sh" \
      "${PROJECT_ID}" "${PROJECT_NAME}" "${REPO_NAME}"
  else
    warn "スキップ"
  fi
  echo ""
fi

# ----------------------------------------------------------
# 11. firebase: Firebaseセットアップ
# ----------------------------------------------------------
if should_run 11; then
  if [[ "${USE_FIREBASE_AUTH}" == "y" || "${USE_FIRESTORE}" == "y" ]]; then
    info "[11/11] Firebaseセットアップ"
    if confirm "  実行しますか？"; then
      bash "${SCRIPTS_DIR}/setup-firebase.sh" \
        "${PROJECT_ID}" "${USE_FIREBASE_AUTH}" "${USE_FIRESTORE}" "${REGION}"
    else
      warn "スキップ"
    fi
    echo ""
  fi
fi

# ============================================================
# 完了
# ============================================================
echo ""
success "セットアップが完了しました！"
echo ""
info "次のステップ:"
info "  1. cd ${OUTPUT_DIR}"
info "  2. Dockerfile をプロジェクトのスタックに合わせて編集"
info "  3. docker-compose.yml のホットリロード設定を調整"
info "  4. git push origin main でデプロイ"
echo ""
info "途中から再開する場合:"
info "  ./scaffold.sh --from <ステップ番号 or 名前>"
info "  ./scaffold.sh --list  # ステップ一覧を表示"
