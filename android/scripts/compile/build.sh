#!/usr/bin/env bash
# Build ijkplayer.aar from source.
# v0.2 path — v0.1 uses download-prebuilt.sh.
#
# Prereqs: NDK r26b (26.1.10909125), git, bash, python3, yasm, make.
# Override NDK path via: NDK_HOME=/path/to/ndk ./build.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBS_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)/libs"
BUILD_DIR="${SCRIPT_DIR}/.build"
IJK_DIR="${BUILD_DIR}/ijkplayer"

IJK_REPO="https://github.com/debugly/ijkplayer"
IJK_TAG="k0.8.9-beta-260402150035"
MODULE_SRC="${SCRIPT_DIR}/modules/module-lite-hevc.sh"

: "${NDK_HOME:=/Users/luckin/Library/Android/sdk/ndk/26.1.10909125}"
export ANDROID_NDK="${NDK_HOME}"
export NDK_HOME

echo "[build] NDK_HOME=${NDK_HOME}"
if [[ ! -d "${NDK_HOME}" ]]; then
  echo "[build] ERROR: NDK_HOME does not exist: ${NDK_HOME}" >&2
  echo "[build]   install NDK r26b (26.1.10909125) via Android Studio SDK Manager," >&2
  echo "[build]   or set NDK_HOME to an alternate location." >&2
  exit 1
fi

mkdir -p "${BUILD_DIR}" "${LIBS_DIR}"

echo "[build] step 1/6 clone ijkplayer @ ${IJK_TAG}"
if [[ ! -d "${IJK_DIR}/.git" ]]; then
  git clone --depth 1 --branch "${IJK_TAG}" "${IJK_REPO}" "${IJK_DIR}"
else
  echo "[build] ijkplayer already cloned, fetching tag."
  git -C "${IJK_DIR}" fetch --depth 1 origin "refs/tags/${IJK_TAG}:refs/tags/${IJK_TAG}"
  git -C "${IJK_DIR}" checkout "${IJK_TAG}"
fi
echo "[build] step 1/6 done"

echo "[build] step 2/6 copy module-lite-hevc.sh into ijkplayer config"
mkdir -p "${IJK_DIR}/config"
cp "${MODULE_SRC}" "${IJK_DIR}/config/module.sh"
cp "${MODULE_SRC}" "${IJK_DIR}/config/module-lite-hevc.sh"
echo "[build] step 2/6 done"

echo "[build] step 3/6 run init-android.sh (pulls FFmpeg + openssl sources)"
pushd "${IJK_DIR}" >/dev/null
./init-android.sh
popd >/dev/null
echo "[build] step 3/6 done"

echo "[build] step 4/6 run init-android-openssl.sh (if present)"
pushd "${IJK_DIR}" >/dev/null
if [[ -x ./init-android-openssl.sh ]]; then
  ./init-android-openssl.sh
else
  echo "[build] init-android-openssl.sh not found, skipping."
fi
popd >/dev/null
echo "[build] step 4/6 done"

echo "[build] step 5/6 compile ijk (arm64-v8a + armv7a)"
pushd "${IJK_DIR}/android/contrib" >/dev/null
./compile-openssl.sh clean || true
./compile-openssl.sh all
./compile-ffmpeg.sh clean || true
./compile-ffmpeg.sh all
popd >/dev/null

pushd "${IJK_DIR}/android" >/dev/null
./compile-ijk.sh all
popd >/dev/null
echo "[build] step 5/6 done"

echo "[build] step 6/6 assemble .aar and copy into ${LIBS_DIR}"
pushd "${IJK_DIR}/android/ijkplayer" >/dev/null
./gradlew :ijkplayer-arm64:assembleRelease :ijkplayer-armv7a:assembleRelease :ijkplayer-java:assembleRelease
popd >/dev/null

# TODO: the debugly fork typically ships a combined cmake aar under
#   android/ijkplayer/ijkplayer-cmake/build/outputs/aar/ijkplayer-cmake-release.aar
# Confirm path on first real run.
CANDIDATE="${IJK_DIR}/android/ijkplayer/ijkplayer-cmake/build/outputs/aar/ijkplayer-cmake-release.aar"
if [[ ! -f "${CANDIDATE}" ]]; then
  CANDIDATE="$(find "${IJK_DIR}/android" -name 'ijkplayer-cmake-release.aar' -print -quit || true)"
fi
if [[ -z "${CANDIDATE}" || ! -f "${CANDIDATE}" ]]; then
  echo "[build] ERROR: could not locate built .aar under ${IJK_DIR}/android" >&2
  exit 1
fi

cp "${CANDIDATE}" "${LIBS_DIR}/ijkplayer.aar"

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "${LIBS_DIR}/ijkplayer.aar"
else
  sha256sum "${LIBS_DIR}/ijkplayer.aar"
fi

echo "[build] step 6/6 done"
echo "[build] OK -> ${LIBS_DIR}/ijkplayer.aar"
