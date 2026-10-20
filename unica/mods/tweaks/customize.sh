# Disable app compaction
# Guard the patch as the source firmware might have this already disabled
LOG "- Applying \"Disable app compaction\" to /system/system/framework/services.jar"
if [[ "$SOURCE_PLATFORM_SDK_VERSION" == "37" ]]; then
    DECODE_APK "system" "system/framework/services.jar"
    COMPACTION_SMALI="$APKTOOL_DIR/system/framework/services.jar/smali/com/android/server/am/CachedAppOptimizer.smali"
    COMPACTION_METHOD="$(sed -n '/^\.method.*updateUseCompaction()V/,/^\.end method/p' "$COMPACTION_SMALI" | sed '/^[[:space:]]*$/d; s/^[[:space:]]*//')"
    if ! grep -Fq '.field static final DEFAULT_USE_COMPACTION:Z = false' "$COMPACTION_SMALI" || \
            [[ "$COMPACTION_METHOD" != *$'const-string/jumbo v0, "use_compaction"\nconst/4 v1, 0x0\nconst-string/jumbo v2, "activity_manager"\ninvoke-static {v2, v0, v1}, Landroid/provider/DeviceConfig;->getBoolean(Ljava/lang/String;Ljava/lang/String;Z)Z'* ]] || \
            ! grep -Fq 'APPCOMPACTOR_ENABLE false' "$APKTOOL_DIR/system/framework/services.jar/smali/com/android/server/am/DynamicHiddenApp.smali"; then
        ABORT "Unrecognized app compaction defaults"
    fi
    unset COMPACTION_SMALI COMPACTION_METHOD
else
    APPLY_PATCH "system" "system/framework/services.jar" \
        "$MODPATH/appcompactor/services.jar/0001-Disable-app-compaction.patch" &> /dev/null || true
fi

# Disable FM Radio country restrictions
if [[ "$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_FMRADIO_CONFIG_CHIP_VENDOR")" != "0" ]]; then
    SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_FMRADIO_CONFIG_AVOID_REGION" --delete

    SMALI_PATCH "system" "system/framework/samsungfmradiolib.jar" \
        "smali/com/samsung/frameworks/fmradio/FMRadioImpl.smali" "return" \
        'isRadioNotSupportedInRegion()Z' \
        'false'
fi
