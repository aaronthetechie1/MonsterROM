# SDK-37 removed the API-30 compatibility files. Restore the target's last
# shipped public mappings, not a guessed API number or a permissive policy.
# The complete current platform/target policy is compiled below before use.
RESTORE_SDK37_SEPOLICY_MAPPING()
{
    local TARGET_MODEL="${TARGET_FIRMWARE%%/*}"
    local TARGET_CSC="${TARGET_FIRMWARE#*/}"
    TARGET_CSC="${TARGET_CSC%%/*}"
    local TARGET_FW_PATH="$FW_DIR/${TARGET_MODEL}_${TARGET_CSC}"
    local TARGET_SYS_EXT="$TARGET_FW_PATH/system_ext"
    [ -d "$TARGET_SYS_EXT" ] || TARGET_SYS_EXT="$TARGET_FW_PATH/system/system/system_ext"
    local PARTITION DESTINATION SOURCE FILE
    for PARTITION in system system_ext product; do
        case "$PARTITION" in
            system)
                DESTINATION="$WORK_DIR/system/system/etc/selinux"
                SOURCE="$TARGET_FW_PATH/system/system/etc/selinux"
                ;;
            system_ext)
                DESTINATION="$WORK_DIR/$(GET_SYSTEM_EXT)/etc/selinux"
                SOURCE="$TARGET_SYS_EXT/etc/selinux"
                ;;
            product)
                DESTINATION="$WORK_DIR/product/etc/selinux"
                SOURCE="$TARGET_FW_PATH/product/etc/selinux"
                ;;
        esac
        if [ ! -f "$DESTINATION/mapping/$CIL_NAME.cil" ] && \
                [ -f "$SOURCE/mapping/$CIL_NAME.cil" ]; then
            FILE="etc/selinux/mapping/$CIL_NAME.cil"
            [[ "$PARTITION" == "system" ]] && FILE="system/$FILE"
            ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "$PARTITION" "$FILE" 0 0 644 "u:object_r:system_file:s0"
            if [ -f "$SOURCE/mapping/$CIL_NAME.compat.cil" ]; then
                FILE="etc/selinux/mapping/$CIL_NAME.compat.cil"
                [[ "$PARTITION" == "system" ]] && FILE="system/$FILE"
                ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "$PARTITION" "$FILE" 0 0 644 "u:object_r:system_file:s0"
            fi
        fi
        # The target's last shipped API30 mapping predates current public type
        # splits. Its API31 mapping is the common reference, not a replacement
        # for API30: preserve the older aliases and all their legacy members.
        if [ "$CIL_NAME" = "30.0" ] && [ -f "$SOURCE/mapping/$CIL_NAME.cil" ]; then
            [ -f "$SOURCE/mapping/31.0.cil" ] && \
                [ -f "$DESTINATION/mapping/31.0.cil" ] || \
                ABORT "Missing API31 reference for $PARTITION mapping evolution"
            python3 "$MODPATH/evolve-mapping.py" \
                "$SOURCE/mapping/$CIL_NAME.cil" "$SOURCE/mapping/31.0.cil" \
                "$DESTINATION/mapping/31.0.cil" "$DESTINATION/mapping/$CIL_NAME.cil" || \
                ABORT "Unsupported $PARTITION public SELinux mapping evolution"
        fi
    done
    [ -f "$WORK_DIR/system/system/etc/selinux/mapping/$CIL_NAME.cil" ] || \
        ABORT "No platform SELinux mapping for target policy $CIL_NAME"
    [ -f "$WORK_DIR/$(GET_SYSTEM_EXT)/etc/selinux/mapping/$CIL_NAME.cil" ] || \
        ABORT "No system_ext SELinux mapping for target policy $CIL_NAME"
}

CHECK_SDK37_SEPOLICY()
{
    command -v secilc >/dev/null || ABORT "SDK-37 policy compatibility requires the host secilc compiler"
    # S21 FE vendor owns this USB subtree. The new platform declaration
    # conflicts with that device label; preserve its existing hardware grants.
    # Do not merge sysfs types or give those grants to unrelated USB nodes.
    python3 - "$WORK_DIR" <<'PY' || ABORT "Unsupported USB sysfs label ownership"
import pathlib, sys
root = pathlib.Path(sys.argv[1])
vendor = (root / 'vendor/etc/selinux/vendor_sepolicy.cil').read_text()
owner = '(genfscon sysfs /bus/usb/devices (u object_r sysfs_ss_writable ((s0) (s0))))'
path = root / 'system/system/etc/selinux/plat_sepolicy.cil'
platform = path.read_text()
conflict = '(genfscon sysfs "/bus/usb/devices" (u object_r sysfs_usb ((s0) (s0))))'
if owner in vendor.splitlines() and conflict in platform.splitlines():
    if vendor.splitlines().count(owner) != 1 or platform.splitlines().count(conflict) != 1:
        raise SystemExit('Non-unique USB sysfs ownership contract')
    path.write_text(platform.replace(conflict + '\n', '', 1))
    print('Preserved target vendor USB sysfs label ownership')
PY
    local FILE DIRECTORY CHECK_DIR
    local -a POLICY_FILES=()
    for FILE in \
            "$WORK_DIR/system/system/etc/selinux/plat_sepolicy.cil" \
            "$WORK_DIR/vendor/etc/selinux/plat_pub_versioned.cil" \
            "$WORK_DIR/vendor/etc/selinux/vendor_sepolicy.cil"; do
        [ -f "$FILE" ] || ABORT "Missing required SELinux input: $FILE"
        POLICY_FILES+=("$FILE")
    done
    for FILE in \
            "$WORK_DIR/$(GET_SYSTEM_EXT)/etc/selinux/system_ext_sepolicy.cil" \
            "$WORK_DIR/product/etc/selinux/product_sepolicy.cil" \
            "$WORK_DIR/odm/etc/selinux/odm_sepolicy.cil"; do
        [ ! -f "$FILE" ] || POLICY_FILES+=("$FILE")
    done
    for DIRECTORY in \
            "$WORK_DIR/system/system/etc/selinux" \
            "$WORK_DIR/$(GET_SYSTEM_EXT)/etc/selinux" \
            "$WORK_DIR/product/etc/selinux"; do
        for FILE in "$DIRECTORY/mapping/$CIL_NAME.cil" "$DIRECTORY/mapping/$CIL_NAME.compat.cil"; do
            [ ! -f "$FILE" ] || POLICY_FILES+=("$FILE")
        done
    done
    # Earlier APEX modules may clean the shared temporary directory.
    mkdir -p "$TMP_DIR" || return 1
    CHECK_DIR="$(mktemp -d "$TMP_DIR/sepolicy-sdk37.XXXXXX")" || return 1
    # Android init compiles these shipped CIL inputs with multiple declarations,
    # MLS, generated-attribute expansion and shipping neverallow checks disabled.
    # The S21 vendor/ODM policy targets the kernel's policy format 30.
    secilc -m -M true -G -N -c 30 -o "$CHECK_DIR/policy" -f "$CHECK_DIR/contexts" \
        "${POLICY_FILES[@]}" || ABORT "SDK-37 platform/target SELinux policy cannot be linked"
    LOG "- Current platform and target SELinux policy linked successfully"
}
