# Device-local packaging pins are not part of the generated runtime config.
source "$SRC_DIR/target/$TARGET_CODENAME/config.sh" || return 1

REPOSITORY="https://github.com/UN1CA/proprietary_vendor_samsung_exynos2100/releases/download"
TARS=(
    # t2sxxx (eur_open)
    "G996BXXSJHZC2_XEO_OXM/BL_G996BXXSJHZC2_G996BXXSJHZC2_MQB107295216_REV01_user_low_ship_MULTI_CERT.tar.md5"
    "G996BXXSJHZC2_XEO_OXM/CP_G996BXXSJHZA6_CP32677257_MQB105755316_REV01_user_low_ship_MULTI_CERT.tar.md5"
    # t2sksx (kor_single)
    "G996NKSSCHZA9_KOO_OKR/BL_G996NKSSCHZA9_G996NKSSCHZA9_MQB107175103_REV01_user_low_ship_MULTI_CERT.tar.md5"
    "G996NKSSCHZA9_KOO_OKR/CP_G996NKOSCHZA5_CP32602497_MQB105441439_REV01_user_low_ship_MULTI_CERT.tar.md5"
)

if ${TARGET_FIRMWARE_LOCAL_ONLY:-false}; then
    # Use the same pinned Odin archives as the selected target firmware.
    # Do not fetch another release asset (or an unselected model variant).
    TARGET_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")"
    TARS=("$TARGET_ODIN_BL_ARCHIVE" "$TARGET_ODIN_CP_ARCHIVE")
    for i in "${TARS[@]}"; do
        case "$i" in
            BL_*) EXPECTED_HASH="$TARGET_ODIN_BL_SHA256" ;;
            CP_*) EXPECTED_HASH="$TARGET_ODIN_CP_SHA256" ;;
            *) LOGE "Invalid local target firmware archive: $i"; return 1 ;;
        esac
        FILE_PATH="$ODIN_DIR/$TARGET_FIRMWARE_PATH/$i"
        if [ ! -f "$FILE_PATH" ] || [ "$(sha256sum "$FILE_PATH" | cut -d " " -f 1)" != "$EXPECTED_HASH" ]; then
            LOGE "Missing or mismatched local target firmware archive: $i"
            return 1
        fi
        LOG "- Adding $i from out/odin/$TARGET_FIRMWARE_PATH"
        EVAL "cp -a \"$FILE_PATH\" \"$TMP_DIR/$i\"" || return 1
    done
    unset EXPECTED_HASH FILE_PATH
else
    for i in "${TARS[@]}"; do
        LOG "- Downloading $(basename "$i")"
        DOWNLOAD_FILE "$REPOSITORY/$i" "$TMP_DIR/$(basename "$i")" || return 1
    done
fi

while IFS= read -r f; do
    FILE_NAME="$(basename "$f")"
    LOG "- Verifying $FILE_NAME"

    FILE_NAME="${FILE_NAME%.md5}"

    # Samsung stores the output of `md5sum` at the very end of the file
    LENGTH="32" # Length of MD5 hash
    LENGTH="$((LENGTH + 2))" # 2 whitespace chars
    LENGTH="$((LENGTH + ${#FILE_NAME}))" # File name without .md5 extension
    LENGTH="$((LENGTH + 1))" # 1 newline char

    STORED_HASH="$(tail -c "$LENGTH" "$f" | cut -d " " -f 1 -s)"
    if [ ! "$STORED_HASH" ] || [[ "${#STORED_HASH}" != "32" ]]; then
        LOG "\033[0;31m! Expected hash could not be parsed\033[0m"
        return 1
    fi

    CALCULATED_HASH="$(head -c-$LENGTH "$f" | md5sum | cut -d " " -f 1 -s)"

    if [[ "$STORED_HASH" != "$CALCULATED_HASH" ]]; then
        LOG "\033[0;31m! File is damaged\033[0m"
        return 1
    fi

    FILE_NAME="$(basename "$f")"
    LOG "- Extracting $FILE_NAME"

    MODEL="$(cut -c4-8 <<< "$FILE_NAME" | sed "s/^/SM-/")"

    if [ ! -d "$TMP_DIR/firmware/$MODEL" ]; then
        EVAL "mkdir -p \"$TMP_DIR/firmware/$MODEL\"" || return 1
    fi

    EVAL "cd \"$TMP_DIR/firmware/$MODEL\"; tar -xf \"$f\"" || return 1
    EVAL "rm -f \"$f\"" || return 1

    if [ -f "$TMP_DIR/firmware/$MODEL/modem_debug.bin.lz4" ]; then
        LOG "- Deleting firmware/$MODEL/modem_debug.bin.lz4"
        EVAL "rm -f \"$TMP_DIR/firmware/$MODEL/modem_debug.bin.lz4\"" || return 1
    fi

    unset FILE_NAME LENGTH STORED_HASH CALCULATED_HASH MODEL
done < <(find "$TMP_DIR" -type f -name "*.md5")

while IFS= read -r f; do
    LOG "- Decompressing ${f#"$TMP_DIR"/}"
    EVAL "lz4 -d --rm \"$f\" \"${f%.lz4}\"" || return 1
done < <(find "$TMP_DIR" -type f -name "*.lz4")

while IFS= read -r f; do
    LOG "- Patching ${f#"$TMP_DIR"/}"
    # https://android.googlesource.com/platform/system/core/+/refs/tags/android-15.0.0_r1/fastboot/fastboot.cpp#1129
    EVAL "printf \"\x03\" | dd of=\"$f\" bs=1 seek=123 count=1 conv=notrunc" || return 1
done < <(find "$TMP_DIR" -type f -name "vbmeta.img")

unset REPOSITORY TARS
