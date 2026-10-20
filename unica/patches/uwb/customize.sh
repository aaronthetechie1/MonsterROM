SOURCE_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$SOURCE_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$SOURCE_FIRMWARE")"
TARGET_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")"

SOURCE_HAS_UWB="$(test -f "$FW_DIR/$SOURCE_FIRMWARE_PATH/vendor/etc/permissions/android.hardware.uwb.xml" && echo "true" || echo "false")"
TARGET_HAS_UWB="$(test -f "$FW_DIR/$TARGET_FIRMWARE_PATH/vendor/etc/permissions/android.hardware.uwb.xml" && echo "true" || echo "false")"

if ! $SOURCE_HAS_UWB; then
    if $TARGET_HAS_UWB; then
        SET_PROP "product" "ro.boot.uwbcountrycode" "ff"

        ADD_TO_WORK_DIR "b0qxxx" "product" \
            "overlay/UwbRROverlay.apk" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/app/UwbTest/UwbTest.apk" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/etc/init/init.system.uwb.rc" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/etc/permissions/com.samsung.android.uwb_extras.xml" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/etc/permissions/org.carconnectivity.android.digitalkey.timesync.xml" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/etc/permissions/privapp-permissions-com.samsung.android.dcktimesync.xml" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/etc/permissions/privapp-permissions-com.sec.android.app.uwbtest.xml" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" \
            "system/etc/libuwb-cal.conf" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" \
            "system/etc/pp_model.tflite" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/framework/com.samsung.android.uwb_extras.jar" 0 0 644 "u:object_r:system_file:s0"
        # Only the Samsung extras belong on the boot classpath. In particular,
        # do not replace Android 17's framework list with the Android 16 list.
        UWB_CLASSPATH_REFERENCE="$SRC_DIR/prebuilts/samsung/$([[ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" == "qssi" ]] && echo "b0qxxx" || echo "b0sxxx")/system/etc/classpaths/bootclasspath.pb"
        # Repair work directories produced by the old whole-file import, only
        # when their descriptor is still byte-for-byte that known prebuilt.
        if [[ "$SOURCE_PLATFORM_SDK_VERSION" -ge 37 ]] && cmp -s \
                "$WORK_DIR/system/system/etc/classpaths/bootclasspath.pb" "$UWB_CLASSPATH_REFERENCE"; then
            ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" \
                "system/etc/classpaths/bootclasspath.pb" 0 0 644 "u:object_r:system_file:s0"
        fi
        python3 "$SRC_DIR/scripts/utils/classpaths_utils.py" \
            --work-dir "$WORK_DIR" --reference "$UWB_CLASSPATH_REFERENCE" \
            --jar /system/framework/com.samsung.android.uwb_extras.jar \
            --sdk "$SOURCE_PLATFORM_SDK_VERSION" || ABORT "Unable to preserve the current UWB boot classpath"
        unset UWB_CLASSPATH_REFERENCE
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/framework/semuwb-service.jar" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/lib/libtflite_uwb_jni.so" 0 0 644 "u:object_r:system_lib_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/lib64/libtflite_uwb_jni.so" 0 0 644 "u:object_r:system_lib_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system_ext" \
            "framework/org.carconnectivity.android.digitalkey.timesync.jar" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system_ext" \
            "priv-app/DckTimeSyncService/DckTimeSyncService.apk" 0 0 644 "u:object_r:system_file:s0"
    else
        LOG "\033[0;33m! Nothing to do\033[0m"
    fi
else
    if ! $TARGET_HAS_UWB; then
        ABORT "Missing patch for condition (SOURCE_HAS_UWB: [$SOURCE_HAS_UWB], TARGET_HAS_UWB: [$TARGET_HAS_UWB]). Aborting"
    fi
fi

unset SOURCE_FIRMWARE_PATH TARGET_FIRMWARE_PATH SOURCE_HAS_UWB TARGET_HAS_UWB
