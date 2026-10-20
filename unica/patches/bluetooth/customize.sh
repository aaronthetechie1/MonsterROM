if [ ! -f "$WORK_DIR/system/system/lib64/libbluetooth_jni.so" ]; then
    LOG_STEP_IN "- Extracting libbluetooth_jni.so from com.android.bt.apex"

    if [ -d "$TMP_DIR" ]; then
        EVAL "rm -rf \"$TMP_DIR\""
    fi
    mkdir -p "$TMP_DIR"

    EVAL "unzip -j \"$WORK_DIR/system/system/apex/com.android.bt.apex\" \"apex_payload.img\" -d \"$TMP_DIR\""

    if ! sudo -n true &> /dev/null; then
        LOG "\033[0;33m! Asking user for sudo password\033[0m"
        if ! sudo -v 2> /dev/null; then
            ABORT "Root permissions are required to unpack APEX image"
        fi
    fi

    mkdir -p "$TMP_DIR/tmp_out"
    EVAL "sudo mount -o ro \"$TMP_DIR/apex_payload.img\" \"$TMP_DIR/tmp_out\""
    EVAL "sudo cat \"$TMP_DIR/tmp_out/lib64/libbluetooth_jni.so\" > \"$WORK_DIR/system/system/lib64/libbluetooth_jni.so\""

    EVAL "sudo umount \"$TMP_DIR/tmp_out\""
    rm -rf "$TMP_DIR"

    SET_METADATA "system" "system/lib64/libbluetooth_jni.so" 0 0 644 "u:object_r:system_lib_file:s0"

# APK version folders are firmware inputs, not a device capability. Keep the
# original feature selection, but require one real Bluetooth APK in this APEX.
mapfile -t BLUETOOTH_APKS < <(find "$TMP_DIR/unknown/apex_payload/app" -type f -name "Bluetooth.apk" | LC_ALL=C sort)
if [ "${#BLUETOOTH_APKS[@]}" -ne 1 ]; then
    ABORT "Expected exactly one Bluetooth APK in the selected APEX, found ${#BLUETOOTH_APKS[@]}"
fi
BLUETOOTH_APK_REL="${BLUETOOTH_APKS[0]#$TMP_DIR/unknown/apex_payload/}"

# SEC_PRODUCT_FEATURE_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE
if $SOURCE_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE; then
    if ! $TARGET_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE; then
        DECODE_APK_IN_APEX "$TMP_DIR/unknown/apex_payload/$BLUETOOTH_APK_REL"
        LOG "- Applying \"Disable SUPPORT_A2DPSINK_PROFILE support\" to apex_payload/$BLUETOOTH_APK_REL"
        APPLY_PATCH "system" "system/$BLUETOOTH_APK_REL" \
            "$MODPATH/a2dp_sink/Bluetooth.apk/0001-Disable-SUPPORT_A2DPSINK_PROFILE-support.patch" \
            > /dev/null
        DECODE_APK_IN_APEX "$TMP_DIR/unknown/apex_payload/javalib/framework-bluetooth.jar"
        LOG "- Applying \"Disable SUPPORT_A2DPSINK_PROFILE support\" to apex_payload/javalib/framework-bluetooth.jar"
        APPLY_PATCH "system" "system/framework/framework-bluetooth.jar" \
            "$MODPATH/a2dp_sink/framework-bluetooth.jar/0001-Disable-SUPPORT_A2DPSINK_PROFILE-support.patch" \
            > /dev/null
    fi
else
    if $TARGET_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE" "TARGET_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE"
    fi
fi

# SEC_PRODUCT_FEATURE_BLUETOOTH_SUPPORT_A2DP_SBM
if ! $SOURCE_BLUETOOTH_SUPPORT_A2DP_SBM; then
    if $TARGET_BLUETOOTH_SUPPORT_A2DP_SBM; then
        DECODE_APK_IN_APEX "$TMP_DIR/unknown/apex_payload/$BLUETOOTH_APK_REL"
        LOG "- Applying \"Enable SUPPORT_A2DP_SBM support\" to apex_payload/$BLUETOOTH_APK_REL"
        APPLY_PATCH "system" "system/$BLUETOOTH_APK_REL" \
            "$MODPATH/sbm/Bluetooth.apk/0001-Enable-SUPPORT_A2DP_SBM-support.patch" \
            > /dev/null
    fi
else
    if ! $TARGET_BLUETOOTH_SUPPORT_A2DP_SBM; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_BLUETOOTH_SUPPORT_A2DP_SBM" "TARGET_BLUETOOTH_SUPPORT_A2DP_SBM"
    fi
fi

# SEC_PRODUCT_FEATURE_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF
if ! $SOURCE_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF; then
    if $TARGET_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF; then
        DECODE_APK_IN_APEX "$TMP_DIR/unknown/apex_payload/$BLUETOOTH_APK_REL"
        LOG "- Applying \"Enable SUPPORT_HEAD_SAR_BACKOFF support\" to apex_payload/$BLUETOOTH_APK_REL"
        APPLY_PATCH "system" "system/$BLUETOOTH_APK_REL" \
            "$MODPATH/head_sar/Bluetooth.apk/0001-Enable-SUPPORT_HEAD_SAR_BACKOFF-support.patch" \
            > /dev/null
    fi
else
    if ! $TARGET_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF" "TARGET_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF"
    fi
fi

# SEC_PRODUCT_FEATURE_BLUETOOTH_SUPPORT_XLNA_CONTROL
if $SOURCE_BLUETOOTH_SUPPORT_XLNA_CONTROL; then
    if ! $TARGET_BLUETOOTH_SUPPORT_XLNA_CONTROL; then
        DECODE_APK_IN_APEX "$TMP_DIR/unknown/apex_payload/$BLUETOOTH_APK_REL"
        LOG "- Applying \"Disable SUPPORT_XLNA_CONTROL support\" to apex_payload/$BLUETOOTH_APK_REL"
        APPLY_PATCH "system" "system/$BLUETOOTH_APK_REL" \
            "$MODPATH/xlna/Bluetooth.apk/0001-Disable-SUPPORT_XLNA_CONTROL-support.patch" \
            > /dev/null
    fi
else
    if $TARGET_BLUETOOTH_SUPPORT_XLNA_CONTROL; then
        DECODE_APK_IN_APEX "$TMP_DIR/unknown/apex_payload/$BLUETOOTH_APK_REL"
        LOG "- Applying \"Enable SUPPORT_XLNA_CONTROL support\" to apex_payload/$BLUETOOTH_APK_REL"
        APPLY_PATCH "system" "system/$BLUETOOTH_APK_REL" \
            "$MODPATH/xlna/Bluetooth.apk/0001-Enable-SUPPORT_XLNA_CONTROL-support.patch" \
            > /dev/null
    fi
fi

# Disable VaultKeeper support
# Before: [tbnz w8, #0, #0xXXXXXX]
# After: [b #0xXXXXXX]
VAULTKEEPER_FROM="28f7773948050037"
VAULTKEEPER_TO="28f777392a000014"
if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
    # The singleton flag moved in SDK 37. ELF relocation/disassembly confirms
    # the same branch skips VaultKeeperManager::getInstance initialization.
    VAULTKEEPER_FROM="8856523948050037"
    VAULTKEEPER_TO="885652392a000014"
fi
LOG "- Patching \"$VAULTKEEPER_FROM\" to \"$VAULTKEEPER_TO\" in apex_payload/lib64/libbluetooth_jni.so"
HEX_PATCH "$TMP_DIR/unknown/apex_payload/lib64/libbluetooth_jni.so" \
    "$VAULTKEEPER_FROM" "$VAULTKEEPER_TO" > /dev/null

BUILD_APK_IN_APEX "$TMP_DIR/unknown/apex_payload/$BLUETOOTH_APK_REL"
BUILD_APK_IN_APEX "$TMP_DIR/unknown/apex_payload/javalib/framework-bluetooth.jar"
BUILD_PAYLOAD
SIGN_PAYLOAD
BUILD_APEX "$WORK_DIR/system/system/apex/com.android.bt.apex"
SIGN_APEX "$WORK_DIR/system/system/apex/com.android.bt.apex"

rm -rf "$TMP_DIR"

unset SOURCE_FIRMWARE_PATH BLUETOOTH_APKS BLUETOOTH_APK_REL VAULTKEEPER_FROM VAULTKEEPER_TO
unset -f BUILD_APK_IN_APEX BUILD_APEX BUILD_PAYLOAD \
    DECODE_APEX DECODE_APK_IN_APEX EXTRACT_PAYLOAD \
    LOG_MISSING_PATCHES SIGN_APEX SIGN_PAYLOAD
