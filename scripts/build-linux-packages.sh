#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo 'usage: build-linux-packages.sh VERSION ARCH BUNDLE_DIRECTORY [all|deb|rpm]' >&2
  exit 2
fi

version="$1"
architecture="$2"
bundle_directory="$(realpath "$3")"
format="${4:-all}"
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_directory="$project_root/dist/linux-packages"
work_directory="$(mktemp -d)"
trap 'rm -rf "$work_directory"' EXIT
mkdir -p "$output_directory"

case "$architecture" in
  x64) deb_arch='amd64'; rpm_arch='x86_64' ;;
  arm64) deb_arch='arm64'; rpm_arch='aarch64' ;;
  *) echo "unsupported architecture: $architecture" >&2; exit 2 ;;
esac
case "$format" in all|deb|rpm) ;; *) echo "unsupported package format: $format" >&2; exit 2 ;; esac

rpm_version="${version%%-*}"
if [[ "$version" == *-* ]]; then
  rpm_release="0.${version#*-}.1"
else
  rpm_release='1'
fi

if [[ "$format" == 'all' || "$format" == 'deb' ]]; then
  debian_root="$work_directory/debian"
  mkdir -p "$debian_root/DEBIAN" "$debian_root/usr/bin" "$debian_root/usr/share/cowebs/catalog"
  sed -e "s/@VERSION@/$version/g" -e "s/@DEB_ARCH@/$deb_arch/g" "$project_root/packaging/debian/control" > "$debian_root/DEBIAN/control"
  install -m 0755 "$bundle_directory/cowebs" "$debian_root/usr/bin/cowebs"
  install -m 0644 "$bundle_directory/catalog/package-catalog.v3.json" "$debian_root/usr/share/cowebs/catalog/package-catalog.v3.json"
  install -m 0644 "$bundle_directory/catalog/profile-catalog.v3.json" "$debian_root/usr/share/cowebs/catalog/profile-catalog.v3.json"
  dpkg-deb --root-owner-group --build "$debian_root" "$output_directory/cowebs_${version}_${deb_arch}.deb"
fi

if [[ "$format" == 'all' || "$format" == 'rpm' ]]; then
  rpm_top="$work_directory/rpmbuild"
  mkdir -p "$rpm_top"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
  install -m 0755 "$bundle_directory/cowebs" "$rpm_top/SOURCES/cowebs"
  install -m 0644 "$bundle_directory/catalog/package-catalog.v3.json" "$rpm_top/SOURCES/package-catalog.v3.json"
  install -m 0644 "$bundle_directory/catalog/profile-catalog.v3.json" "$rpm_top/SOURCES/profile-catalog.v3.json"
  sed -e "s/@VERSION@/$rpm_version/g" -e "s/@RELEASE@/$rpm_release/g" -e "s/@RPM_ARCH@/$rpm_arch/g" "$project_root/packaging/rpm/cowebs.spec" > "$rpm_top/SPECS/cowebs.spec"
  rpmbuild --define "_topdir $rpm_top" -bb "$rpm_top/SPECS/cowebs.spec"
  find "$rpm_top/RPMS" -name '*.rpm' -exec cp {} "$output_directory/" \;
fi

echo "Built $format native package output in $output_directory"
