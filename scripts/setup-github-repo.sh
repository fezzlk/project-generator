#!/usr/bin/env bash
set -euo pipefail

# GitHubリポジトリ作成＆初期push（冪等）
# Usage: setup-github-repo.sh <REPO_NAME> <PROJECT_DIR>

REPO_NAME="${1:?REPO_NAME is required}"
PROJECT_DIR="${2:?PROJECT_DIR is required}"

info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
success() { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }

# gh CLI 確認
if ! command -v gh &>/dev/null; then
  echo "Error: gh CLI がインストールされていません"
  echo "  brew install gh && gh auth login"
  exit 1
fi

info "GitHubリポジトリを作成中: ${REPO_NAME}"

# リポジトリ作成（既存チェック）
if gh repo view "${REPO_NAME}" &>/dev/null; then
  warn "リポジトリ ${REPO_NAME} は既に存在します（スキップ）"
else
  gh repo create "${REPO_NAME}" --private --source="${PROJECT_DIR}"
  success "リポジトリ ${REPO_NAME} を作成しました"
fi

# git初期化＆初回push
cd "${PROJECT_DIR}"

if [[ ! -d .git ]]; then
  git init
  git add -A
  git commit -m "Initial scaffold from common template"
  success "初回コミット作成"
fi

# リモート設定
GITHUB_OWNER=$(gh api user --jq '.login')
REMOTE_URL="https://github.com/${GITHUB_OWNER}/${REPO_NAME}.git"

if git remote get-url origin &>/dev/null; then
  warn "リモート origin は既に設定されています"
else
  git remote add origin "${REMOTE_URL}"
  success "リモート origin を設定: ${REMOTE_URL}"
fi

# push
info "mainブランチをpush中..."
git branch -M main
git push -u origin main
success "push完了"

echo ""
success "GitHubリポジトリのセットアップが完了しました"
info "  https://github.com/${GITHUB_OWNER}/${REPO_NAME}"
