#!/usr/bin/env bash
# Empryo branch installer — macOS & Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/lguzzon-scratchbook/proxysoul-Empryo/develop/install.sh | bash
#
# Detects platform/arch, downloads the matching bundle tarball from the
# fork's GitHub release, verifies sha256, extracts, runs bundled install.sh.
#
# Env:
#   EMPRYO_VERSION=x.y.z-tag   pin release (default: latest develop tag)
#   EMPRYO_QUIET=1             non-interactive

if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi
set -euo pipefail

REPO="lguzzon-scratchbook/proxysoul-Empryo"
VERSION="${EMPRYO_VERSION:-v2.20.25-develop.1}"

case "$(uname -s)" in
  Darwin) PLAT="darwin" ;;
  Linux)  PLAT="linux" ;;
  *) echo "unsupported OS: $(uname -s) (need macOS or Linux)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64|aarch64)
    if [[ "$PLAT" == "darwin" ]]; then ARCH="arm64";
    else echo "linux arm64 build not shipped (need linux x64)" >&2; exit 1; fi ;;
  x86_64|amd64) ARCH="x64" ;;
  *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

ASSET="soulforge-${VERSION#v}-${PLAT}-${ARCH}.tar.gz"
BASE="https://github.com/${REPO}/releases/download/${VERSION}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

echo "  downloading ${ASSET} (${VERSION})..."
curl -fsSL --retry 3 "${BASE}/${ASSET}" -o "${ASSET}"
curl -fsSL --retry 3 "${BASE}/SHA256SUMS.txt" -o SHA256SUMS.txt

echo "  verifying checksum..."
if command -v sha256sum >/dev/null 2>&1; then
  grep "  ${ASSET}$" SHA256SUMS.txt | sha256sum -c - || exit 1
elif command -v shasum >/dev/null 2>&1; then
  grep "  ${ASSET}$" SHA256SUMS.txt | shasum -a 256 -c - || exit 1
else
  echo "  no sha256 tool found, skipping verify" >&2
fi

tar xzf "${ASSET}"
cd "${ASSET%.tar.gz}"
./install.sh ${EMPRYO_QUIET:+--quiet}
