#!/bin/bash
# 发版脚本：更新说明 → 改版本号 → 测试 → commit → tag → push（推送 tag 触发 GitHub CI 打包）。
# 用法: scripts/release.sh <x.y.z | patch | minor | major> ["提交信息"]
# 更新说明（GitHub Release 正文）按优先级取其一：
#   NOTES_FILE=<路径>   用该文件内容
#   NOTES="..."         用这段文本
#   docs/release-notes/vX.Y.Z.md 已存在则直接用它（推荐：发版前手写）
#   都没有              从上一个 tag 的提交记录起草一份，随版本一起提交（随后再改写）
set -euo pipefail

cd "$(dirname "$0")/.."
PLIST="Resources/Info.plist"
NOTES_DIR="docs/release-notes"
BRANCH="main"
REMOTE="origin"
TEST_CMD="${RELEASE_TEST_CMD:-swift test}"

die() { echo "release: $*" >&2; exit 1; }

usage() {
    echo "用法: make release VERSION=<x.y.z|patch|minor|major> [MSG=\"提交信息\"] [NOTES=\"更新说明\" | NOTES_FILE=<路径>]" >&2
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

# ---- 更新说明 ----
NOTES_PATH="$NOTES_DIR/$TAG.md"
PREV_TAG="$(git describe --tags --abbrev=0 HEAD 2>/dev/null || true)"
mkdir -p "$NOTES_DIR"

if [ -n "${NOTES_FILE:-}" ]; then
    [ -f "$NOTES_FILE" ] || die "NOTES_FILE 不存在: $NOTES_FILE"
    cp "$NOTES_FILE" "$NOTES_PATH"
    NOTES_SOURCE="NOTES_FILE"
elif [ -n "${NOTES:-}" ]; then
    printf '%s\n' "$NOTES" > "$NOTES_PATH"
    NOTES_SOURCE="NOTES"
elif [ -f "$NOTES_PATH" ]; then
    NOTES_SOURCE="已有文件"
else
    {
        echo "## 更新内容"
        echo
        if [ -n "$PREV_TAG" ]; then
            git log --no-merges --pretty='- %s' "$PREV_TAG..HEAD"
        else
            git log --no-merges --pretty='- %s' HEAD
        fi
        echo
        echo "<!-- 自动草稿：发布前请改写为面向用户的说明，删除本行 -->"
    } > "$NOTES_PATH"
    NOTES_SOURCE="自动草稿"
fi
[ -s "$NOTES_PATH" ] || die "$NOTES_PATH 内容为空"
echo "==> $NOTES_PATH ($NOTES_SOURCE${PREV_TAG:+，相比 $PREV_TAG})"
if [ "$NOTES_SOURCE" = "自动草稿" ]; then
    echo "    注意：说明由提交记录起草，建议改写后重新执行本次 make release" >&2
fi

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
