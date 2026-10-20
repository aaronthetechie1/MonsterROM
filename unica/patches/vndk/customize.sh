RUNTIME_VNDK_PROFILE=""
if [ -f "$SRC_DIR/platform/$TARGET_PLATFORM/patches/runtime/component.sh" ]; then
    source "$SRC_DIR/platform/$TARGET_PLATFORM/patches/runtime/component.sh"
    REGISTER_RUNTIME_COMPONENT "vndk" || return 1
    RUNTIME_VNDK_PROFILE="$RUNTIME_COMPONENT_PROFILE"
fi

if [[ "$SOURCE_BOARD_API_LEVEL" == "$TARGET_BOARD_API_LEVEL" ]] && [ "$RUNTIME_VNDK_PROFILE" != "s21" ]; then
    LOG "\033[0;33m! Nothing to do\033[0m"
    unset RUNTIME_VNDK_PROFILE
    return 0
fi

# [
ADD_TARGET_VNDK_APEX() {
    local TARGET_FW_PATH="$FW_DIR/$(cut -d "/" -f 1 <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 <<< "$TARGET_FIRMWARE")"
    if [ -f "$TARGET_FW_PATH/system_ext/apex/com.android.vndk.v$TARGET_BOARD_API_LEVEL.apex" ] || \
       [ -f "$TARGET_FW_PATH/system/system/system_ext/apex/com.android.vndk.v$TARGET_BOARD_API_LEVEL.apex" ]; then
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system_ext" "apex/com.android.vndk.v$TARGET_BOARD_API_LEVEL.apex" 0 0 644 "u:object_r:system_file:s0"
        return 0
    fi
    case "$TARGET_BOARD_API_LEVEL" in
        "30")
            if [ "$SOURCE_PLATFORM_SDK_VERSION" -ge "37" ] && \
                    [ "$TARGET_CODENAME" = "t2s" ]; then
                # Keep the exact G996 VNDK snapshot paired with its vendor,
                # including the 32-bit libraries required by legacy HALs.
                ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system_ext" \
                    "apex/com.android.vndk.v30.apex" 0 0 644 \
                    "u:object_r:system_file:s0"
            else
                ADD_TO_WORK_DIR "a73xqxx" "system_ext" \
                    "apex/com.android.vndk.v30.apex" 0 0 644 \
                    "u:object_r:system_file:s0"
            fi
            ;;
        "31")
            ADD_TO_WORK_DIR "b0qxxx" "system_ext" "apex/com.android.vndk.v31.apex" 0 0 644 "u:object_r:system_file:s0"
            ;;
        "32")
            ADD_TO_WORK_DIR "b4qxxx" "system_ext" "apex/com.android.vndk.v32.apex" 0 0 644 "u:object_r:system_file:s0"
            ;;
        "33")
            ADD_TO_WORK_DIR "dm1qxxx" "system_ext" "apex/com.android.vndk.v33.apex" 0 0 644 "u:object_r:system_file:s0"
            ;;
        "34")
            ADD_TO_WORK_DIR "gta9pxxx" "system_ext" "apex/com.android.vndk.v34.apex" 0 0 644 "u:object_r:system_file:s0"
            ;;
        *)
            ABORT "No APEX blob available for VNDK $TARGET_BOARD_API_LEVEL"
            ;;
    esac
}
# ]

if $TARGET_OS_BUILD_SYSTEM_EXT_PARTITION; then
    SYS_EXT_DIR="$WORK_DIR/system_ext"
else
    SYS_EXT_DIR="$WORK_DIR/system/system/system_ext"
fi

if [ "$RUNTIME_VNDK_PROFILE" = "s21" ]; then
    # This remains VNDK's one owner. The post-BUILD_APKS finalizer verifies
    # the complete bundled providers before retiring the standalone APEX.
    LOG "- Queuing VNDK30 providers for the runtime APEX"
    SET_PROP "system_ext" "ro.vndk.version" "$TARGET_BOARD_API_LEVEL" || return 1
    python3 - "$SYS_EXT_DIR/etc/vintf/manifest.xml" "$TARGET_BOARD_API_LEVEL" <<'PY' || return 1
import pathlib, re, sys, xml.etree.ElementTree as ET
path = pathlib.Path(sys.argv[1])
source = path.read_text()
assert ET.fromstring(source).tag == 'manifest'
blocks = list(re.finditer(r'<vendor-ndk>.*?</vendor-ndk>', source, re.S))
assert len(blocks) <= 1, 'Multiple vendor-ndk blocks require review'
if blocks:
    block = blocks[0]
    changed, count = re.subn(r'<version>[^<]*</version>', '<version>' + sys.argv[2] + '</version>', block.group())
    assert count == 1, 'Unexpected vendor-ndk version contract'
    source = source[:block.start()] + changed + source[block.end():]
else:
    source, count = re.subn(r'</manifest>\s*$', '    <vendor-ndk>\n        <version>' + sys.argv[2] + '</version>\n    </vendor-ndk>\n</manifest>\n', source)
    assert count == 1
if source != path.read_text():
    path.write_text(source)
PY
    unset SYS_EXT_DIR RUNTIME_VNDK_PROFILE
    unset -f ADD_TARGET_VNDK_APEX
    return 0
fi

if [ "$SOURCE_BOARD_API_LEVEL" -gt "34" ] && [ "$TARGET_BOARD_API_LEVEL" -gt "34" ]; then
    :
elif [ "$SOURCE_BOARD_API_LEVEL" -gt "34" ] && [ "$TARGET_BOARD_API_LEVEL" -le "34" ]; then
    ADD_TARGET_VNDK_APEX
    SET_PROP "system_ext" "ro.vndk.version" "$TARGET_BOARD_API_LEVEL"
    LOG "- Patching ${SYS_EXT_DIR//$WORK_DIR/}/etc/vintf/manifest.xml"
    EVAL "sed -i \"\\\$d\" \"$SYS_EXT_DIR/etc/vintf/manifest.xml\""
    {
        echo "    <vendor-ndk>"
        echo "        <version>$TARGET_BOARD_API_LEVEL</version>"
        echo "    </vendor-ndk>"
        echo "</manifest>"
    } >> "$SYS_EXT_DIR/etc/vintf/manifest.xml"
elif [ "$SOURCE_BOARD_API_LEVEL" -le "34" ] && [ "$TARGET_BOARD_API_LEVEL" -gt "34" ]; then
    DELETE_FROM_WORK_DIR "system_ext" "apex/com.android.vndk.v$SOURCE_BOARD_API_LEVEL.apex"
    LOG "- Patching ${SYS_EXT_DIR//$WORK_DIR/}/etc/vintf/manifest.xml"
    EVAL "sed -i -e \"/vendor-ndk/d\" -e \"/version>/d\" \"$SYS_EXT_DIR/etc/vintf/manifest.xml\""
elif [ ! -f "$SYS_EXT_DIR/apex/com.android.vndk.v$TARGET_BOARD_API_LEVEL.apex" ]; then
    DELETE_FROM_WORK_DIR "system_ext" "apex/com.android.vndk.v$SOURCE_BOARD_API_LEVEL.apex"
    ADD_TARGET_VNDK_APEX
    SET_PROP "system_ext" "ro.vndk.version" "$TARGET_BOARD_API_LEVEL"
    LOG "- Patching ${SYS_EXT_DIR//$WORK_DIR/}/etc/vintf/manifest.xml"
    EVAL "sed -i \"s/version>$SOURCE_BOARD_API_LEVEL/version>$TARGET_BOARD_API_LEVEL/g\" \"$SYS_EXT_DIR/etc/vintf/manifest.xml\""
fi

unset SYS_EXT_DIR RUNTIME_VNDK_PROFILE
unset -f ADD_TARGET_VNDK_APEX
