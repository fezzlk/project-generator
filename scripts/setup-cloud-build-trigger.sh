#!/usr/bin/env bash
set -euo pipefail

# Cloud Build GitHubトリガー作成（冪等）
# Usage: setup-cloud-build-trigger.sh <PROJECT_ID> <GITHUB_REPO_NAME> <TRIGGER_NAME>

PROJECT_ID="${1:?PROJECT_ID is required}"
GITHUB_REPO_NAME="${2:?GITHUB_REPO_NAME is required}"
TRIGGER_NAME="${3:-${GITHUB_REPO_NAME}-deploy}"

info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
success() { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }

# GitHubオーナー取得
GITHUB_OWNER=$(gh api user --jq '.login' 2>/dev/null) || {
  echo "Error: gh CLI でGitHubユーザーを取得できませんでした"
  echo "  gh auth login を実行してください"
  exit 1
}

info "Cloud Buildトリガーを作成中..."
info "  プロジェクト: ${PROJECT_ID}"
info "  リポジトリ:   ${GITHUB_OWNER}/${GITHUB_REPO_NAME}"
info "  トリガー名:   ${TRIGGER_NAME}"

gcloud config set project "${PROJECT_ID}"

# 既存トリガーの確認
if gcloud builds triggers describe "${TRIGGER_NAME}" \
    --region=global --format="value(name)" 2>/dev/null; then
  warn "トリガー ${TRIGGER_NAME} は既に存在します（スキップ）"
else
  # GitHub接続の確認
  info "GitHub接続を確認中..."
  info "注意: Cloud Buildの GitHub接続が未設定の場合は、"
  info "  GCPコンソールから手動で接続を設定してください:"
  info "  https://console.cloud.google.com/cloud-build/triggers;region=global/connect?project=${PROJECT_ID}"
  echo ""

  # トリガー作成
  gcloud builds triggers create github \
    --name="${TRIGGER_NAME}" \
    --repo-name="${GITHUB_REPO_NAME}" \
    --repo-owner="${GITHUB_OWNER}" \
    --branch-pattern="^main$" \
    --build-config="cloudbuild.yaml" \
    --region=global \
    2>/dev/null && {
    success "トリガー ${TRIGGER_NAME} を作成しました"
  } || {
    warn "トリガーの自動作成に失敗しました"
    info "GCPコンソールから手動で作成してください:"
    info "  https://console.cloud.google.com/cloud-build/triggers?project=${PROJECT_ID}"
    info ""
    info "設定値:"
    info "  名前: ${TRIGGER_NAME}"
    info "  リポジトリ: ${GITHUB_OWNER}/${GITHUB_REPO_NAME}"
    info "  ブランチ: ^main$"
    info "  構成ファイル: cloudbuild.yaml"
  }
fi

echo ""
success "Cloud Buildトリガー設定が完了しました"
