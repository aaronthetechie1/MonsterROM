BLOCKLIST_PATCH_SUFFIX=""
if [ "$SOURCE_PLATFORM_SDK_VERSION" = "37" ]; then
    BLOCKLIST_PATCH_SUFFIX=""
fi

DELETE_FROM_WORK_DIR "system" "system/etc/ldu_blocklist.xml"

APPLY_PATCH "system" "system/framework/services.jar" \
    "$MODPATH/services.jar/0001-Allow-custom-PackageBlockListPolicy$BLOCKLIST_PATCH_SUFFIX.patch"
SMALI_PATCH "system" "system/framework/services.jar" \
    "smali_classes2/com/samsung/android/server/pm/install/PackageBlockListPolicy\$1.smali" 'remove'

unset BLOCKLIST_PATCH_SUFFIX
