#!/usr/bin/env bash
# Pull debugly/ijkplayer prebuilt .aar into android/localmaven/ so the plugin's
# Gradle build can resolve it as a proper maven artifact.
# See VERSIONS.lock for the pinned version / sha256.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Pinned maven coordinates. Must match android/build.gradle.
GROUP_PATH="tv/danmaku/ijk"
ARTIFACT="ijkplayer"
VERSION="0.8.9-beta-260402150035"

MAVEN_DIR="${ANDROID_DIR}/localmaven/${GROUP_PATH}/${ARTIFACT}/${VERSION}"
TARGET="${MAVEN_DIR}/${ARTIFACT}-${VERSION}.aar"
POM="${MAVEN_DIR}/${ARTIFACT}-${VERSION}.pom"

PREBUILT_URL="https://github.com/debugly/ijkplayer/releases/download/${VERSION}/ijkplayer-cmake-release.aar"
EXPECTED_SHA256="f325911be7f6b9288a58bfe5872d7860b2066982b630f6462492f56efec5f163"

mkdir -p "${MAVEN_DIR}"

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

if [[ -f "${TARGET}" ]]; then
  actual="$(sha256_of "${TARGET}")"
  if [[ "${actual}" == "${EXPECTED_SHA256}" ]]; then
    echo "[download-prebuilt] ijkplayer.aar already present with matching sha256, skipping."
    echo "[download-prebuilt] sha256: ${actual}"
    exit 0
  fi
  echo "[download-prebuilt] existing ijkplayer.aar sha256 mismatch (${actual}), re-downloading."
fi

echo "[download-prebuilt] downloading ${PREBUILT_URL}"
tmp="${TARGET}.tmp.$$"
curl -L --fail --retry 3 --retry-delay 2 -o "${tmp}" "${PREBUILT_URL}"
mv "${tmp}" "${TARGET}"

actual="$(sha256_of "${TARGET}")"
echo "[download-prebuilt] sha256: ${actual}"
echo "[download-prebuilt] expected: ${EXPECTED_SHA256}"

if [[ "${actual}" != "${EXPECTED_SHA256}" ]]; then
  echo "[download-prebuilt] ERROR: sha256 mismatch" >&2
  rm -f "${TARGET}"
  exit 1
fi

# Companion .pom so the maven repo layout is valid. Always rewrite so edits to
# VERSION propagate without manual cleanup.
cat > "${POM}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
    <modelVersion>4.0.0</modelVersion>
    <groupId>tv.danmaku.ijk</groupId>
    <artifactId>${ARTIFACT}</artifactId>
    <version>${VERSION}</version>
    <packaging>aar</packaging>
    <description>Prebuilt AAR from debugly/ijkplayer, vendored for niuma_player.</description>
</project>
EOF

echo "[download-prebuilt] OK -> ${TARGET}"
