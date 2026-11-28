#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

if [[ $# != 2 ]]; then
    echo "Usage: $0 <Android clang-r596125 directory> <output directory>" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_DIR="$SCRIPT_DIR/floppy"
TOOLCHAIN="$(realpath -e "$1")"
mkdir -p "$2"
OUT="$(realpath -e "$2")"
export PATH="$TOOLCHAIN/bin:$PATH"

VERSION="$("$TOOLCHAIN/bin/clang" --version)"
if [[ "$VERSION" != *"15682573"*"r596125"*"clang version 22.0.2"* ]]; then
    echo "This kernel uses Android clang-r596125 (build 15682573)." >&2
    exit 1
fi

REVISION=dc17ad08a8b4f7fcabd3f949d9c83ff11c5f80ee
UPSTREAM="${FLOPPY_SOURCE:-https://github.com/FlopKernel-Series/flop_exynos2100_kernel.git}"
if [[ -d "$UPSTREAM" ]]; then
    UPSTREAM="$(realpath -e "$UPSTREAM")"
fi

BUILD="$(mktemp -d "$OUT/.floppy.XXXXXXXX")"
trap 'rm -rf -- "$BUILD"' EXIT
git init -q "$BUILD/src"
cd "$BUILD/src"
git fetch --quiet --no-tags --depth=1 "$UPSTREAM" "$REVISION"
git checkout -q --detach "$REVISION"
git apply "$PATCH_DIR"/[0-9]*.patch

export SKIP_FIPS_CRYPTO_INTEGRITY=1
export SKIP_EXYNOS_FMP_INTEGRITY=1
export PLATFORM_VERSION=12
export ANDROID_MAJOR_VERSION=s
export TARGET_SOC=universal2100
export LOCALVERSION= KBUILD_BUILD_USER=MonsterROM KBUILD_BUILD_HOST=o1s KBUILD_BUILD_VERSION=1
KBUILD_BUILD_TIMESTAMP="$(date -u -d "@$(git show -s --format=%ct HEAD)" '+%Y-%m-%d %T UTC')"
export KBUILD_BUILD_TIMESTAMP

ARGS=(
    ARCH=arm64
    LLVM=1
    LLVM_IAS=1
    CC=clang
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_ARM32=arm-linux-gnueabi-
    O="$BUILD/obj"
)
make "${ARGS[@]}" exynos2100-unified_defconfig oneui95-o1s.config
make "${ARGS[@]}" olddefconfig
grep -Fxq 'CONFIG_FAKE_UNAME_5_15=y' "$BUILD/obj/.config"
grep -Fxq 'CONFIG_KSU_NEXT=y' "$BUILD/obj/.config"
make "${ARGS[@]}" -j"${JOBS:-$(nproc)}" Image modules dtbs

gzip -9nc "$BUILD/obj/arch/arm64/boot/Image" > "$BUILD/Image.gz"
make "${ARGS[@]}" \
    INSTALL_MOD_STRIP="--strip-debug --keep-section=.ARM.attributes" \
    INSTALL_MOD_PATH="$BUILD/mod_out" \
    modules_install

mkdir -p "$OUT/vendor/lib/modules"
find "$BUILD/mod_out" -type f -name '*.ko' -exec install -m 644 {} "$OUT/vendor/lib/modules/" \;
install -m 644 "$BUILD/obj/Module.symvers" "$BUILD/Image.gz" "$OUT/"
