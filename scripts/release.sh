#!/bin/bash
# 发版脚本：改版本号 → 测试 → commit → tag → push（推送 tag 触发 GitHub CI 打包）。
# 用法: scripts/release.sh <x.y.z | patch | minor | major> ["提交信息"]
set -euo pipefail

cd "$(dirname "$0")/.."
PLIST="Resources/Info.plist"
BRANCH="main"
REMOTE="origin"
TEST_CMD="${RELEASE_TEST_CMD:-swift test}"

die() { echo "release: $*" >&2; exit 1; }

usage() {
    echo "用法: make release VERSION=<x.y.z|patch|minor|major> [MSG=\"提交信息\"]" >&2
    exit 1
}

# ---- 解析版本号 ----
[ $# -ge 1 ] || usage
INPUT="$1"
MSG="${2:-}"

latest_tag() {
    git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1
}

bump() { # bump <x.y.z> <patch|minor|major>
    local major minor patch
    IFS=. read -r major minor patch <<< "$1"
    case "$2" in
        major) echo "$((major + 1)).0.0" ;;
        minor) echo "$major.$((minor + 1)).0" ;;
        patch) echo "$major.$minor.$((patch + 1))" ;;
    esac
}

case "$INPUT" in
    patch|minor|major)
        LATEST="$(latest_tag || true)"
        [ -n "$LATEST" ] || die "没有可自增的历史 tag，请显式指定版本号"
        VERSION="$(bump "${LATEST#v}" "$INPUT")"
        ;;
    *)
        VERSION="${INPUT#v}"
        ;;
esac
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "版本号格式非法: $VERSION（应为 x.y.z）"
TAG="v$VERSION"

# ---- 前置校验 ----
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "不在 git 仓库内"
[ "$(git branch --show-current)" = "$BRANCH" ] || die "只能在 $BRANCH 分支发版，当前在 $(git branch --show-current)"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG 已存在"

echo "==> fetch $REMOTE"
git fetch "$REMOTE" "$BRANCH" --quiet
git merge-base --is-ancestor "$REMOTE/$BRANCH" HEAD || die "本地落后于 $REMOTE/$BRANCH，请先拉取/变基"

# ---- 测试（先测再改，失败不留半成品）----
echo "==> $TEST_CMD"
$TEST_CMD

# ---- 改版本号，失败则回滚 ----
restore_plist() { git restore "$PLIST" 2>/dev/null || true; }
trap 'restore_plist' EXIT

echo "==> $PLIST -> $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
                       -c "Set :CFBundleVersion $VERSION" "$PLIST"
make verify-version "TAG=$TAG"

# ---- commit + tag ----
[ -n "$MSG" ] || MSG="chore: 发布 $TAG"
git add -A
git commit -m "$MSG"
git tag "$TAG"
trap - EXIT

# ---- push（幂等，失败可手动重试）----
if ! git push "$REMOTE" "$BRANCH"; then
    die "push 分支失败，本地已生成 commit 和 tag $TAG，重试: git push $REMOTE $BRANCH && git push $REMOTE $TAG"
fi
if ! git push "$REMOTE" "$TAG"; then
    die "push tag 失败（CI 未触发），重试: git push $REMOTE $TAG"
fi

echo "✅ $TAG 已推送，GitHub CI 将自动打包发布"
