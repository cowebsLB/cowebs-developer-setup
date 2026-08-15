#!/usr/bin/env sh
set -eu

VERSION='@VERSION@'
BASE_URL='@BASE_URL@'
X64_SHA256='@LINUX_X64_SHA256@'
ARM64_SHA256='@LINUX_ARM64_SHA256@'

case "$(uname -m)" in
  x86_64|amd64) architecture='x64'; expected_sha256="$X64_SHA256" ;;
  aarch64|arm64) architecture='arm64'; expected_sha256="$ARM64_SHA256" ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 2 ;;
esac

archive="cowebs-${VERSION}-linux-${architecture}.tar.gz"
url="${BASE_URL}/${archive}"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

curl --fail --location --proto '=https' --tlsv1.2 --output "$temporary_directory/$archive" "$url"
actual_sha256="$(sha256sum "$temporary_directory/$archive" | awk '{print $1}')"
if [ "$actual_sha256" != "$expected_sha256" ]; then
  echo "SHA-256 verification failed for $archive" >&2
  exit 1
fi

tar -xzf "$temporary_directory/$archive" -C "$temporary_directory"
install -d "$HOME/.local/bin" "$HOME/.local/share/cowebs/catalog"
install -m 0755 "$temporary_directory/cowebs" "$HOME/.local/bin/cowebs"
install -m 0644 "$temporary_directory/catalog/package-catalog.v3.json" "$HOME/.local/share/cowebs/catalog/package-catalog.v3.json"
install -m 0644 "$temporary_directory/catalog/profile-catalog.v3.json" "$HOME/.local/share/cowebs/catalog/profile-catalog.v3.json"

echo "Installed immutable COWebs CLI release $VERSION to $HOME/.local/bin/cowebs"
case ":${PATH:-}:" in
  *":$HOME/.local/bin:"*) ;;
  *)
    echo "Add $HOME/.local/bin to PATH, then start a new shell:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    ;;
esac
