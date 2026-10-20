# SDK 37 passes the current ImageInfo and ExtraBundle directly from
# prepareFirstYuvProcessPicture to setCaptureInfo(ImageInfo, ExtraBundle).
# StrideInfo comes from that ImageInfo and ExtraCaptureInfo.Builder receives
# that bundle; the removed mLast* fields and processPicturePrepare callback
# are no longer part of this path. Keep the original fix for older cameras.
if [ "$SOURCE_PLATFORM_SDK_VERSION" -lt 37 ]; then
    APPLY_PATCH "system" "priv-app/SamsungCamera/SamsungCamera.apk" \
        "$MODPATH/SamsungCamera.apk/0001-Fix-ArcSsHdrNodeBase-NPE.patch"
else
    CAMERA_SOURCE_PATH="$(cut -d "/" -f 1 -s <<< "$SOURCE_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$SOURCE_FIRMWARE")"
    CAMERA_SOURCE_SHA="$(sha256sum "$FW_DIR/$CAMERA_SOURCE_PATH/system/system/priv-app/SamsungCamera/SamsungCamera.apk" | cut -d " " -f 1)"
    [ "$CAMERA_SOURCE_SHA" == "5b52171c35617f05d58948e456de7854ce7dc8e21105fa07ca03373698259fb0" ] || \
        ABORT "Unverified SamsungCamera ArcSsHdr capture-data contract; inspect this firmware before omitting the legacy NPE fix"
    LOG "- ArcSsHdr capture preparation already uses the current image and bundle (verified SDK 37 camera)"
    unset CAMERA_SOURCE_PATH CAMERA_SOURCE_SHA
fi

# Add camera libs
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libsame_source_hdr.arcsoft.so" 0 0 644 "u:object_r:system_lib_file:s0"
EVAL "echo \"libsame_source_hdr.arcsoft.so\" >> \"$WORK_DIR/system/system/etc/public.libraries-arcsoft.txt\""
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libsuperresolution_raw.arcsoft.so" 0 0 644 "u:object_r:system_lib_file:s0"
EVAL "echo \"libsuperresolution_raw.arcsoft.so\" >> \"$WORK_DIR/system/system/etc/public.libraries-arcsoft.txt\""
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libsuperresolutionraw_wrapper_v2.camera.samsung.so" 0 0 644 "u:object_r:system_lib_file:s0"
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libuwsuperresolution.arcsoft.so" 0 0 644 "u:object_r:system_lib_file:s0"
EVAL "echo \"libuwsuperresolution.arcsoft.so\" >> \"$WORK_DIR/system/system/etc/public.libraries-arcsoft.txt\""
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libuwsuperresolution_wrapper_v1.camera.samsung.so" 0 0 644 "u:object_r:system_lib_file:s0"
EVAL "echo \"libuwsuperresolution_wrapper_v1.camera.samsung.so\" >> \"$WORK_DIR/system/system/etc/public.libraries-camera.samsung.txt\""
