LOG "- Installing the One UI 9.5 kernel"

if [ ! -f "$MODPATH/Image.gz" ]; then
    ABORT "Missing o1s kernel Image.gz. Build it first via target/o1s/patches/kernel/source/rebuild.sh"
fi

mkdir -p "$TMP_DIR"
KERNEL_DIR="$(mktemp -d "$TMP_DIR/chiclet.XXXXXXXX")" || ABORT
EVAL "unpack_bootimg --boot_img \"$WORK_DIR/kernel/boot.img\" --out \"$KERNEL_DIR\" --format mkbootimg -0 > \"$KERNEL_DIR/args\"" || ABORT
EVAL "gzip -dc \"$MODPATH/Image.gz\" > \"$KERNEL_DIR/kernel\"" || ABORT
EVAL "xargs -0 -a \"$KERNEL_DIR/args\" mkbootimg --output \"$KERNEL_DIR/boot.img\"" || ABORT
EVAL "mv \"$KERNEL_DIR/boot.img\" \"$WORK_DIR/kernel/boot.img\"" || ABORT
EVAL "rm -rf \"$KERNEL_DIR\""

unset KERNEL_DIR

if [ -f "$MODPATH/KernelSU_Next.apk" ]; then
    LOG "- Installing KernelSU Next Manager"
    mkdir -p "$WORK_DIR/system/system/app/KernelSU_Next"
    EVAL "cp -a \"$MODPATH/KernelSU_Next.apk\" \"$WORK_DIR/system/system/app/KernelSU_Next/KernelSU_Next.apk\""
    SET_METADATA "system" "system/app/KernelSU_Next" 0 0 755 "u:object_r:system_file:s0"
    SET_METADATA "system" "system/app/KernelSU_Next/KernelSU_Next.apk" 0 0 644 "u:object_r:system_file:s0"
fi
