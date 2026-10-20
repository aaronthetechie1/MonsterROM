#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -e -o pipefail

cd "$(dirname "$0")/../.."

for target in o1s t2s p3s r9s; do
    (
        source ./buildenv.sh "$target" > /dev/null
        test "$TARGET_CODENAME" = "$target"
        test "$TARGET_PLATFORM" = exynos2100
        test "$SOURCE_PLATFORM_SDK_VERSION" = 37
        test "$TARGET_BOARD_API_LEVEL" = 30
        test "$TARGET_USE_DYNAMIC_PARTITIONS" = true
        test "$TARGET_GROUP_BASIC_SIZE" -lt "$TARGET_SUPER_PARTITION_SIZE"
        test "$TARGET_OS_SINGLE_SYSTEM_IMAGE" = essi
        if [ "$target" = t2s ]; then
            test "$TARGET_ASSERT_MODEL" = SM-G996B:SM-G996N
        fi
    )
    echo "$target: configuration passed"
done

python3 scripts/tests/test_source.py
