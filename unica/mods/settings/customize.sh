SETTINGS_SMALI_DIR="smali_classes4"
if [ "$SOURCE_PLATFORM_SDK_VERSION" = "37" ]; then
    SETTINGS_SMALI_DIR="smali_classes3"
fi

# Show battery regulatory info in Settings
# Requires SEM_BATTERY_PROPERTY_IC_AUTHENTICATION_RESULT support
if [ "$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_BATTERY_SUPPORT_BSOH_SETTINGS")" ]; then
    SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_BATTERY_SUPPORT_BSOH_SETTINGS" --delete
fi
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_SETTINGS_ENABLE_EU_BATTERY_REGULATORY" "TRUE"

SMALI_PATCH "system" "system/framework/framework.jar" \
    "smali/android/app/Instrumentation.smali" "replace" \
    'newApplication(Ljava/lang/Class;Landroid/content/Context;)Landroid/app/Application;' \
    'invoke-virtual {p0, p1}, Landroid/app/Application;->attach(Landroid/content/Context;)V' \
    '    invoke-virtual {p0, p1}, Landroid/app/Application;->attach(Landroid/content/Context;)V\n\n    invoke-static {p1}, Lio/mesalabs/unica/SamsungPropsHooks;->init(Landroid/content/Context;)V' \
    > /dev/null
SMALI_PATCH "system" "system/framework/framework.jar" \
    "smali/android/app/Instrumentation.smali" "replace" \
    'newApplication(Ljava/lang/ClassLoader;Ljava/lang/String;Landroid/content/Context;)Landroid/app/Application;' \
    'invoke-virtual {p0, p3}, Landroid/app/Application;->attach(Landroid/content/Context;)V' \
    '    invoke-virtual {p0, p3}, Landroid/app/Application;->attach(Landroid/content/Context;)V\n\n    invoke-static {p3}, Lio/mesalabs/unica/SamsungPropsHooks;->init(Landroid/content/Context;)V' \
    > /dev/null

DECODE_APK "system" "system/priv-app/SecSettings/SecSettings.apk"

# Disable stock OTA references
if [ ! -f "$WORK_DIR/system/system/priv-app/ChoiDujour/ChoiDujour.apk" ]; then
    if [ "$SOURCE_PLATFORM_SDK_VERSION" = "37" ]; then
        SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "smali_classes3/com/samsung/android/settings/homepage/TopLevelSoftwareUpdatePreferenceController.smali" "return" \
            "getAvailabilityStatus()I" "3"
    else
        SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "smali_classes3/com/samsung/android/settings/softwareupdate/SoftwareUpdateUtils.smali" "return" \
            'isOTAUpgradeAllowed(Landroid/content/Context;)Z' \
            'false'
    fi
fi

# SDK37 model/version changes are applied with its Settings interface patch below.
if [ "$SOURCE_PLATFORM_SDK_VERSION" != "37" ]; then
# Always show One UI minor version
SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
    "${SETTINGS_SMALI_DIR}/com/samsung/android/settings/deviceinfo/softwareinfo/OneUIVersionPreferenceController.smali" "replace" \
    'isDeviceWithMicroVersion()Z' \
    'move-result p0' \
    'const/4 p0, 0x1'

# Show real device model number
SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
    "${SETTINGS_SMALI_DIR}/com/samsung/android/settings/deviceinfo/aboutphone/ModelNameGetter.smali" "replace" \
    'getModelName()Ljava/lang/String;' \
    'ro.product.model' \
    'ro.boot.em.model'
fi

LOG_STEP_IN "- Adding UN1CA Settings"

# Dynamically patch SecSettings
# - Add missing/non-xml files in place
# - Patch existing files
#   - Use the first line of the file to tell sed how to apply the rest of the content
#   - Exception made for files under *res/values* where the "resources" tag gets nuked
while IFS= read -r f; do
    f="${f//$MODPATH\/SecSettings.apk\//}"

    case "$f" in
        smali_classes3/*) [ "$SOURCE_PLATFORM_SDK_VERSION" = "37" ] || continue ;;
        smali_classes4/*) [ "$SOURCE_PLATFORM_SDK_VERSION" != "37" ] || continue ;;
    esac

    if [ ! -f "$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk/$f" ] || \
            [[ "$f" != *".xml" ]]; then
        LOG "- Adding \"$f\" to /system/system/priv-app/SecSettings.apk"
        EVAL "mkdir -p \"$(dirname "$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk/$f")\""
        EVAL "cp -a \"$MODPATH/SecSettings.apk/${f//\$/\\$}\" \"$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk/${f//\$/\\$}\""
    else
        LOG "- Patching \"$f\" in /system/system/priv-app/SecSettings.apk"
        if [[ "$f" == *"res/values"* ]]; then
            PATCH_INST="/<\/resources>/i"
            CONTENT="$(sed -e "/?xml/d" -e "/resources>/d" "$MODPATH/SecSettings.apk/$f")"
        else
            PATCH_INST="$(head -n 1 "$MODPATH/SecSettings.apk/$f")"
            CONTENT="$(tail -n +2 "$MODPATH/SecSettings.apk/$f")"
        fi
        CONTENT="$(sed -e "s/\"/\\\\\"/g" -e "s/\\$/\\\\$/g" -e "s/ /\\\ /g" -e "s/\\\\n/\\\\\\\\\n/g" <<< "$CONTENT")"
        CONTENT="$(sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g' <<< "$CONTENT")"
        EVAL "sed -i \"$PATCH_INST $CONTENT\" \"$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk/$f\""
    fi
done < <(find "$MODPATH/SecSettings.apk" -type f)

if [ "$SOURCE_PLATFORM_SDK_VERSION" = "37" ]; then
    APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "$MODPATH/search/SecSettings.apk/0001-Register-UN1CA-Settings-search-providers.patch"
    APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "$MODPATH/search/SecSettings.apk/0002-Adapt-Android17-UN1CA-settings.patch"
    APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "$MODPATH/search/SecSettings.apk/0004-Adapt-Android17-preference-interfaces.patch"
else
    # Add UN1CA Settings SearchIndexableData registrations
    LOG "- Patching \"smali/com/android/settingslib/search/SearchIndexableResourcesMobile.smali\" in /system/system/priv-app/SecSettings.apk"
    SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "smali/com/android/settingslib/search/SearchIndexableResourcesMobile.smali" "replaceall" \
        '.class public final Lcom/android/settingslib/search/SearchIndexableResourcesMobile;' \
        '.class public Lcom/android/settingslib/search/SearchIndexableResourcesMobile;' \
        > /dev/null
    LOG "- Patching \"smali/com/android/settings/search/SearchFeatureProviderImpl\$\$ExternalSyntheticLambda0.smali\" in /system/system/priv-app/SecSettings.apk"
    SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "smali/com/android/settings/search/SearchFeatureProviderImpl\$\$ExternalSyntheticLambda0.smali" "replace" \
        'invoke()Ljava/lang/Object;' \
        'new-instance p0, Lcom/android/settingslib/search/SearchIndexableResourcesMobile;' \
        'new-instance p0, Lio/mesalabs/unica/search/UnicaSearchIndexableResources;' \
        > /dev/null
    SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "smali/com/android/settings/search/SearchFeatureProviderImpl\$\$ExternalSyntheticLambda0.smali" "replace" \
        'invoke()Ljava/lang/Object;' \
        'invoke-direct {p0}, Lcom/android/settingslib/search/SearchIndexableResourcesBase;-><init>()V' \
        'invoke-direct {p0}, Lio/mesalabs/unica/search/UnicaSearchIndexableResources;-><init>()V' \
        > /dev/null

fi

SETTINGS_COLLECTOR_LOCALS=36
if [ "$SOURCE_PLATFORM_SDK_VERSION" = "37" ]; then
    SETTINGS_COLLECTOR_LOCALS=37
fi
DECODE_APK "system" "system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk"
LOG "- Patching \"smali_classes2/com/samsung/android/settings/intelligence/search/categorizing/TopLevelKeysCollector.smali\" in /system/system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk"
SMALI_PATCH "system" "system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk" \
    "smali_classes2/com/samsung/android/settings/intelligence/search/categorizing/TopLevelKeysCollector.smali" "replace" \
    '<init>(Landroid/content/Context;)V' \
    ".locals $SETTINGS_COLLECTOR_LOCALS" \
    ".locals $((SETTINGS_COLLECTOR_LOCALS + 1))" \
    > /dev/null
SMALI_PATCH "system" "system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk" \
    "smali_classes2/com/samsung/android/settings/intelligence/search/categorizing/TopLevelKeysCollector.smali" "replace" \
    '<init>(Landroid/content/Context;)V' \
    "filled-new-array/range {v1 .. v$((SETTINGS_COLLECTOR_LOCALS - 1))}, [Ljava/lang/String;" \
    "    const-string v${SETTINGS_COLLECTOR_LOCALS}, \"top_level_unica\"\n\n    filled-new-array/range {v1 .. v${SETTINGS_COLLECTOR_LOCALS}}, [Ljava/lang/String;" \
    > /dev/null

# Show Vulkan renderer toggle if required
if [[ "$(GET_PROP "ro.hwui.use_vulkan")" != "true" ]]; then
    SET_PROP "system" "persist.sys.unica.vulkan" "false"
fi

unset PATCH_INST CONTENT SETTINGS_SMALI_DIR SETTINGS_COLLECTOR_LOCALS

LOG_STEP_OUT
