LOG_STEP_IN "- Adding OK Google Hotword Enrollment blobs"
DELETE_FROM_WORK_DIR "product" "priv-app/HotwordEnrollmentXGoogleEx6_WIDEBAND_LARGE"
DELETE_FROM_WORK_DIR "product" "priv-app/HotwordEnrollmentYGoogleEx6_WIDEBAND_LARGE"
ADD_TO_WORK_DIR "r9sxxx" "product" "priv-app/HotwordEnrollmentOKGoogleEx3CORTEXM4/HotwordEnrollmentOKGoogleEx3CORTEXM4.apk" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "r9sxxx" "product" "priv-app/HotwordEnrollmentXGoogleEx3CORTEXM4/HotwordEnrollmentXGoogleEx3CORTEXM4.apk" 0 0 644 "u:object_r:system_file:s0"
LOG_STEP_OUT

if [[ "$TARGET_CODENAME" == "r9s" ]]; then
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/init/rscmgr_s21fe.rc" 0 0 644 "u:object_r:system_file:s0"
fi

ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/permissions/android.hardware.sensor.hifi_sensors.xml" 0 0 644 "u:object_r:system_file:s0"

if [[ "$TARGET_CODENAME" != "r9s" ]]; then
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/permissions/privapp-permissions-com.samsung.android.app.ledbackcover.xml" 0 0 644 "u:object_r:system_file:s0"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/priv-app/LedBackCoverAppUnbound/LedBackCoverAppUnbound.apk" 0 0 644 "u:object_r:system_file:s0"
fi

LOG_STEP_IN "- Adding 32-bit WFD blobs"
ADD_TO_WORK_DIR "r9sxxx" "system" "system/bin/remotedisplay" 0 2000 755 "u:object_r:remotedisplay_exec:s0"

LOG_STEP_IN "- Adding HIDL face biometrics libs"
ADD_TO_WORK_DIR "r9sxxx" "system" "system/lib/android.hardware.biometrics.face@1.0.so" 0 0 644 "u:object_r:system_lib_file:s0"
ADD_TO_WORK_DIR "r9sxxx" "system" "system/lib/vendor.samsung.hardware.biometrics.face@2.0.so" 0 0 644 "u:object_r:system_lib_file:s0"
ADD_TO_WORK_DIR "r9sxxx" "system" "system/lib/vendor.samsung.hardware.biometrics.face@3.0.so" 0 0 644 "u:object_r:system_lib_file:s0"
LOG_STEP_OUT

LOG_STEP_IN "- Adding keymaster 4.0 libs"
ADD_TO_WORK_DIR "r9sxxx" "system" "system/lib/android.hardware.keymaster@3.0.so" 0 0 644 "u:object_r:system_lib_file:s0"
ADD_TO_WORK_DIR "r9sxxx" "system" "system/lib/android.hardware.keymaster@4.0.so" 0 0 644 "u:object_r:system_lib_file:s0"
ADD_TO_WORK_DIR "r9sxxx" "system" "system/lib/android.hardware.keymaster@4.1.so" 0 0 644 "u:object_r:system_lib_file:s0"
DELETE_FROM_WORK_DIR "system" "system/lib/android.hardware.security.keymint-V1-ndk.so"
DELETE_FROM_WORK_DIR "system" "system/lib/android.hardware.security.secureclock-V1-ndk.so"
ADD_TO_WORK_DIR "r9sxxx" "system" "system/lib/lib_nativeJni.dk.samsung.so" 0 0 644 "u:object_r:system_lib_file:s0"
ADD_TO_WORK_DIR "r9sxxx" "system" "system/lib/libdk_native_keymaster.so" 0 0 644 "u:object_r:system_lib_file:s0"
DELETE_FROM_WORK_DIR "system" "system/lib/libdk_native_keymint.so"
ADD_TO_WORK_DIR "r9sxxx" "system" "system/lib/libkeymaster4_1support.so" 0 0 644 "u:object_r:system_lib_file:s0"
ADD_TO_WORK_DIR "r9sxxx" "system" "system/lib/libkeymaster4support.so" 0 0 644 "u:object_r:system_lib_file:s0"
DELETE_FROM_WORK_DIR "system" "system/lib/vendor.samsung.hardware.keymint-V1-ndk.so"
DELETE_FROM_WORK_DIR "system" "system/lib64/android.hardware.security.keymint-V1-ndk.so"
ADD_TO_WORK_DIR "r9sxxx" "system" "system/lib64/lib_nativeJni.dk.samsung.so" 0 0 644 "u:object_r:system_lib_file:s0"
DELETE_FROM_WORK_DIR "system" "system/lib64/libdk_native_keymint.so"
ADD_TO_WORK_DIR "r9sxxx" "system" "system/lib64/libdk_native_keymaster.so" 0 0 644 "u:object_r:system_lib_file:s0"
DELETE_FROM_WORK_DIR "system" "system/lib64/vendor.samsung.hardware.keymint-V1-ndk.so"
LOG_STEP_OUT

_BACKPORT_HIDL_ENGMODE_CLIENT()
{
    local TARGET_FIRMWARE_DIR="$FW_DIR/$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")"
    local CURRENT_MANAGER="$WORK_DIR/system/system/lib64/lib.engmode.samsung.so"
    local LEGACY_MANAGER="$TARGET_FIRMWARE_DIR/system/system/lib64/lib.engmode.samsung.so"
    local LEGACY_INTERFACE="$TARGET_FIRMWARE_DIR/system/system/lib64/vendor.samsung.hardware.security.engmode@1.0.so"
    local VENDOR_INTERFACE="$WORK_DIR/vendor/lib64/vendor.samsung.hardware.security.engmode@1.0.so"

    [ -f "$CURRENT_MANAGER" ] || return 0

    if ! strings "$CURRENT_MANAGER" | grep -qF "engmode-V1-ndk.so"; then
        return 0
    fi
    if [ ! -f "$VENDOR_INTERFACE" ]; then
        LOG "- Skipping HIDL EngMode client backport: vendor HIDL service is absent"
        return 0
    fi
    if [ ! -f "$LEGACY_MANAGER" ] || [ ! -f "$LEGACY_INTERFACE" ]; then
        ABORT "Target HIDL EngMode client libraries are missing"
    fi

    # The source JNI bridge uses the stable EngMode C ABI exposed by this client.
    LOG "- Backporting HIDL EngMode client for the legacy vendor HAL"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/lib.engmode.samsung.so" \
        0 0 644 "u:object_r:system_lib_file:s0"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" \
        "system/lib64/vendor.samsung.hardware.security.engmode@1.0.so" \
        0 0 644 "u:object_r:system_lib_file:s0"
}

