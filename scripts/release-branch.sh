#!/usr/bin/env bash
# Branch release: build linux-x64 + darwin-arm64 + windows-x64, tag, publish to fork.
# Usage: ./scripts/release-branch.sh [tag] [--dry-run] [--skip-build]
#   tag default: v<package.json version>-develop.<N> (next free N)
# Version is NEVER bumped — assets use bare x.y.z, tag is qualified.
# Installers (install.sh/install.ps1) are pointed at the new tag afterwards.
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi
set -euo pipefail

DRY=""; SKIP_BUILD=""
TAG_ARG=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --skip-build) SKIP_BUILD=1 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) TAG_ARG="$a" ;;
  esac
done

cd "$(dirname "$0")/.."
VERSION="$(bun -e "console.log(require('./package.json').version)")"
FORK="$(git remote get-url origin | sed -E 's|.*github.com[:/](.+)(\.git)?|\1|; s|\.git$||')"
CORE_VER="$(bun -e "console.log(require('./node_modules/@opentui/core/package.json').version)")"

# next free tag v<VERSION>-develop.<N>
if [[ -z "$TAG_ARG" ]]; then
  N=1
  while git rev-parse -q --verify "refs/tags/v${VERSION}-develop.${N}" >/dev/null      || git ls-remote --tags origin "v${VERSION}-develop.${N}" | grep -q .; do N=$((N+1)); done
  TAG="v${VERSION}-develop.${N}"
else
  TAG="$TAG_ARG"
fi
ASSETS=(soulforge-${VERSION}-darwin-arm64.tar.gz soulforge-${VERSION}-linux-x64.tar.gz soulforge-${VERSION}-windows-x64.zip)

if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null   || git ls-remote --tags origin "${TAG}" | grep -q .; then
  echo "tag ${TAG} already exists — pass another tag explicitly" >&2; exit 1
fi
if [[ -z "$DRY" && -n "$(git status --porcelain)" ]]; then
  echo "working tree dirty — commit or stash first" >&2; exit 1
fi
for c in bun gh curl tar python3; do command -v "$c" >/dev/null || { echo "need $c" >&2; exit 1; }; done

echo "  version : ${VERSION} (package.json, untouched)"
echo "  tag     : ${TAG}"
echo "  fork    : ${FORK}"
echo "  assets  : ${ASSETS[*]}"
if [[ -n "$DRY" ]]; then echo "  [dry-run] nothing built"; exit 0; fi

# cross-platform opentui libs (bun on linux skips darwin/win32 optionals)
ensure_otui() { # <triplet> <libfile>
  local dir="node_modules/@opentui/core-$1"
  [[ -f "$dir/$2" ]] && { echo "  otui $1 cached"; return; }
  echo "  fetching @opentui/core-$1@${CORE_VER}..."
  local t="$(mktemp -d)"; trap 'rm -rf "$t"' RETURN
  curl -fsSL --retry 3 "https://registry.npmjs.org/@opentui%2fcore-$1/-/core-$1-${CORE_VER}.tgz" -o "$t/o.tgz"
  tar xzf "$t/o.tgz" -C "$t"
  mkdir -p "$dir"; cp "$t/package/$2" "$dir/"
}
ensure_otui darwin-arm64 libopentui.dylib
ensure_otui win32-x64 opentui.dll

if [[ -z "$SKIP_BUILD" ]]; then
  bash scripts/bundle.sh x64 linux
  bash scripts/bundle.sh arm64 darwin

  # windows-x64 (bash port of bundle-windows.ps1; needs no pwsh/zip)
  STAGE="dist/bundle/soulforge-${VERSION}-windows-x64"
  rm -rf "$STAGE"; mkdir -p "$STAGE/deps/native/win32-x64" "$STAGE/deps/workers" "$STAGE/deps/wasm" "$STAGE/deps/opentui-assets"
  bun scripts/build.ts --compile --target=bun-windows-x64 --outfile="$STAGE/soulforge.exe"
  cp node_modules/@opentui/core-win32-x64/opentui.dll node_modules/ghostty-opentui/dist/win32-x64/ghostty-opentui.node "$STAGE/deps/native/win32-x64/"
  bun build src/core/workers/intelligence.worker.ts --outdir "$STAGE/deps/workers" --entry-naming "[name].[ext]" --target=bun --external "*.node" --external "*.wasm" --external "*.scm"
  bun build src/core/workers/io.worker.ts --outdir "$STAGE/deps/workers" --entry-naming "[name].[ext]" --target=bun --external "*.node" --external "*.wasm" --external "*.scm"
  for n in "src/index.tsx" "@opentui/core" "ghostty-opentui" "src/components/"; do
    grep -q "$n" "$STAGE/deps/workers/io.worker.js" && { echo "worker leak io->$n" >&2; exit 1; }
    grep -q "$n" "$STAGE/deps/workers/intelligence.worker.js" && { echo "worker leak intel->$n" >&2; exit 1; }
  done
  cp node_modules/web-tree-sitter/tree-sitter.wasm "$STAGE/deps/wasm/"
  cp node_modules/tree-sitter-wasms/out/*.wasm "$STAGE/deps/wasm/"
  bun build node_modules/@opentui/core/parser.worker.js --outdir "$STAGE/deps/opentui-assets" --target=bun --asset-naming="[name].[ext]"
  cp -r node_modules/@opentui/core/assets/* "$STAGE/deps/opentui-assets/"
  python3 - "$STAGE/deps/opentui-assets/parser.worker.js" <<'EOF'
import sys
p = sys.argv[1]; t = open(p).read()
t = t.replace('module2.exports = "./tree-sitter.wasm"', 'module2.exports = ((process.env.LOCALAPPDATA || __require("os").homedir() + "/AppData/Local") + "/SoulForge/wasm/tree-sitter.wasm")')
t = t.replace('var fs = require("fs")', 'var fs = __require("fs")').replace('var nodePath = require("path")', 'var nodePath = __require("path")').replace('require("url")', '__require("url")')
open(p, "w").write(t)
EOF
  cp src/core/editor/init.lua "$STAGE/deps/init.lua"
  cp LICENSE "$STAGE/LICENSE" 2>/dev/null || true
  python3 -c "import shutil; shutil.make_archive('dist/bundle/soulforge-${VERSION}-windows-x64','zip',root_dir='dist/bundle',base_dir='soulforge-${VERSION}-windows-x64')"
fi

for f in "${ASSETS[@]}"; do [[ -f "dist/bundle/$f" ]] || { echo "missing dist/bundle/$f" >&2; exit 1; }; done
./dist/bundle/soulforge-${VERSION}-linux-x64/soulforge --version
(cd dist/bundle && sha256sum "${ASSETS[@]}" > SHA256SUMS.txt && cat SHA256SUMS.txt)

PREV="$(git tag --list "v${VERSION}-develop.*" --sort=-v:refname | head -1)"
NOTES="$(mktemp)"; {
  echo "## Empryo — develop branch build \`${TAG}\`"
  echo ""; echo "Built from \`$(git branch --show-current)\` @ \`$(git rev-parse --short HEAD)\` (package.json ${VERSION})."
  if [[ -n "$PREV" ]]; then echo ""; echo "### Commits since ${PREV}"; git log --oneline "${PREV}..HEAD"; fi
} > "$NOTES"

git tag -a "$TAG" -m "Empryo develop branch build ${TAG}"
git push origin "$TAG"
# shellcheck disable=SC2086
gh release create "$TAG" -R "$FORK" --title "Empryo develop ${TAG}" --notes-file "$NOTES"   dist/bundle/soulforge-${VERSION}-darwin-arm64.tar.gz dist/bundle/soulforge-${VERSION}-linux-x64.tar.gz   dist/bundle/soulforge-${VERSION}-windows-x64.zip dist/bundle/SHA256SUMS.txt
rm -f "$NOTES"

# point branch installers at the new tag (defaults only)
python3 - "$TAG" "$VERSION" <<'EOF'
import re, sys
tag, ver = sys.argv[1], sys.argv[2]
p = open("install.sh").read()
p = re.sub(r'VERSION="\$\{EMPRYO_VERSION:-.*?\}"', 'VERSION="${EMPRYO_VERSION:-%s}"' % tag, p, count=1)
p = re.sub(r'ASSET_VER="\$\{EMPRYO_ASSET_VER:-.*?\}"', 'ASSET_VER="${EMPRYO_ASSET_VER:-%s}"' % ver, p, count=1)
open("install.sh", "w").write(p)
p = open("install.ps1").read()
p = re.sub(r'\$Version = "v[^"]*"', '$Version = "%s"' % tag, p)
p = re.sub(r'\$assetVer = "[^"]*"', '$assetVer = "%s"' % ver, p)
p = re.sub(r'\$env:EMPRYO_VERSION = "v[^"]*"', '$env:EMPRYO_VERSION = "%s"' % tag, p)
open("install.ps1", "w").write(p)
EOF
git add install.sh install.ps1 && git commit -m "chore(installer): point branch installers at ${TAG}" && git push origin "$(git branch --show-current)"

echo ""; echo "  done: https://github.com/${FORK}/releases/tag/${TAG}"
echo '  install: curl -fsSL https://raw.githubusercontent.com/'"${FORK}"'/'"$(git branch --show-current)"'/install.sh | bash'
