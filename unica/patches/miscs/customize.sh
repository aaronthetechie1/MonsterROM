MISCS_MODULE_ROOT="$MODPATH"
MISCS_PLATFORM_SDK="${SOURCE_PLATFORM_SDK_VERSION:-$(GET_PROP "system" "ro.build.version.sdk")}"

SET_PROP_IF_DIFF "vendor" "ro.oem_unlock_supported" "0"

# Better device/model detection in CoreRune
SMALI_PATCH "system" "system/framework/framework.jar" \
    "smali_classes6/com/samsung/android/rune/CoreRune.smali" "replace" \
    '<clinit>()V' \
    'ro.product.model' \
    'ro.product.vendor.model'
SMALI_PATCH "system" "system/framework/framework.jar" \
    "smali_classes6/com/samsung/android/rune/CoreRune.smali" "replace" \
    '<clinit>()V' \
    'ro.product.device' \
    'ro.product.vendor.device'

DECODE_APK "system" "system/framework/services.jar"
if [[ "$SOURCE_PLATFORM_SDK_VERSION" == "37" ]] && \
        [ ! -f "$APKTOOL_DIR/system/framework/services.jar/smali/com/android/server/RescueParty.smali" ]; then
    if ! grep -Fq "com.android.server.crashrecovery.CrashRecoveryModule\$Lifecycle" \
            "$APKTOOL_DIR/system/framework/services.jar/smali/com/android/server/SystemServer.smali" || \
            ! unzip -p "$WORK_DIR/system/system/apex/com.google.android.crashrecovery_compressed.apex" \
                apex_manifest.pb 2> /dev/null | strings | grep -Fx 'com.android.crashrecovery' > /dev/null; then
        ABORT "Legacy RescueParty is absent and modular crash recovery could not be verified"
    fi
else
    # shellcheck disable=SC2016
    # Disable RescueParty
    SMALI_PATCH "system" "system/framework/services.jar" \
        "smali/com/android/server/RescueParty.smali" "return" \
        '-$$Nest$smisDisabled()Z' \
        'true'
fi

# Better model detection in FreecessController
SMALI_PATCH "system" "system/framework/services.jar" \
    "smali/com/android/server/am/FreecessController.smali" "replace" \
    '<clinit>()V' \
    'ro.product.model' \
    'ro.product.vendor.model'

