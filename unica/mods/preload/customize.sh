# Samsung Internet Browser
# https://play.google.com/store/apps/details?id=com.sec.android.app.sbrowser
LOG "- Downloading Samsung Internet app"
DOWNLOAD_FILE "$(GET_GALAXY_STORE_DOWNLOAD_URL "com.sec.android.app.sbrowser")" \
    "$WORK_DIR/system/system/preload/SBrowser/SBrowser.apk"


if [ -f "$SRC_DIR/target/$TARGET_CODENAME/patches/kernel/KernelSU_Next.apk" ]; then
    LOG "- Preloading KernelSU Next Manager"
    mkdir -p "$WORK_DIR/system/system/preload/KernelSU_Next"
    EVAL "cp -a "$SRC_DIR/target/$TARGET_CODENAME/patches/kernel/KernelSU_Next.apk" "$WORK_DIR/system/system/preload/KernelSU_Next/KernelSU_Next.apk""
    ALLOWED_PRELOAD="$WORK_DIR/system/system/etc/sysconfig/allowed-system-preload-apps.xml"
    if [ -f "$ALLOWED_PRELOAD" ] && ! grep -q "com.rifsxd.ksunext" "$ALLOWED_PRELOAD"; then
        EVAL "sed -i '/<\/config>/i \    <allowed-system-preload package=\"com.rifsxd.ksunext\"/>' "$ALLOWED_PRELOAD""
    fi
    unset ALLOWED_PRELOAD
fi

while IFS= read -r i; do
    i="${i//$WORK_DIR\/system\//}"

    if [ -d "$WORK_DIR/system/$i" ]; then
        SET_METADATA "system" "$i" 0 0 755 "u:object_r:system_file:s0"
    else
        SET_METADATA "system" "$i" 0 0 644 "u:object_r:system_file:s0"
    fi

    if [[ "$i" == *".apk" ]] && \
            ! grep -q "$i" "$WORK_DIR/system/system/etc/vpl_apks_count_list.txt"; then
        LOG "- Adding \"$i\" to /system/system/etc/vpl_apks_count_list.txt"
        EVAL "echo \"$i\" >> \"$WORK_DIR/system/system/etc/vpl_apks_count_list.txt\""
    fi
done <<< "$(find "$WORK_DIR/system/system/preload")"
