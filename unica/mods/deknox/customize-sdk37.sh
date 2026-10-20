# S26 keeps its native 64-bit ABI: vold, installd, sqlite and JNI libraries
# remain from the source firmware. Disable the unsupported Knox entry points
# in their matching Java code instead of importing an older device's binaries.
SET_PROP_IF_DIFF "vendor" "ro.security.fips.ux" "Disabled"

DELETE_FROM_WORK_DIR "system" "system/app/BlockchainBasicKit"
DELETE_FROM_WORK_DIR "system" "system/bin/dualdard"
DELETE_FROM_WORK_DIR "system" "system/bin/sdp_cryptod"
DELETE_FROM_WORK_DIR "system" "system/etc/init/dualdard.rc"
DELETE_FROM_WORK_DIR "system" "system/etc/init/kpp.init.rc"
DELETE_FROM_WORK_DIR "system" "system/etc/init/kss.init.rc"
DELETE_FROM_WORK_DIR "system" "system/etc/init/sdp_cryptod.rc"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.hdmapp.xml"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.kgclient.xml"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.knox.kfbp.xml"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.knox.knnr.xml"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.knox.mpos.xml"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.knox.pushmanager.xml"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.knox.sandbox.xml"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.knox.zt.framework.xml"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/signature-permissions-com.samsung.android.kgclient.xml"
DELETE_FROM_WORK_DIR "system" "system/etc/sysconfig/preinstalled-packages-com.samsung.android.coldwalletservice.xml"
DELETE_FROM_WORK_DIR "system" "system/priv-app/HdmApk"
DELETE_FROM_WORK_DIR "system" "system/priv-app/KnoxFrameBufferProvider"
DELETE_FROM_WORK_DIR "system" "system/priv-app/KnoxGuard"
DELETE_FROM_WORK_DIR "system" "system/priv-app/KnoxMposAgent"
DELETE_FROM_WORK_DIR "system" "system/priv-app/KnoxNeuralNetworkRuntime"
DELETE_FROM_WORK_DIR "system" "system/priv-app/KnoxPushManager"
DELETE_FROM_WORK_DIR "system" "system/priv-app/KnoxSandbox"
DELETE_FROM_WORK_DIR "system" "system/priv-app/KnoxZtFramework"

# SEC_PRODUCT_FEATURE_KNOX_SUPPORT_SDP
# SDK 37 removed SQLiteSdpHelper and the SDP feature flags. SdpManager and
# SdpManagerImpl already provide the unsupported API stubs in the S26 donor.
LOG "- Knox SDP is already removed in the SDK 37 framework"

# SEC_PRODUCT_FEATURE_KNOX_SUPPORT_DUAL_DAR
APPLY_PATCH "system" "system/framework/framework.jar" \
    "$MODPATH/ddar/framework.jar/0001-Nuke-Knox-DualDAR-SDK37.patch"
APPLY_PATCH "system" "system/framework/framework.jar" \
    "$MODPATH/ddar/framework.jar/0002-Nuke-MDF-SDK37.patch"
APPLY_PATCH "system" "system/framework/services.jar" \
    "$MODPATH/ddar/services.jar/0001-Nuke-Knox-DualDAR-SDK37.patch"
APPLY_PATCH "system" "system/priv-app/KnoxCore/KnoxCore.apk" \
    "$MODPATH/ddar/KnoxCore.apk/0001-Nuke-Knox-DualDAR-SDK37.patch"

# These APKs embed their own Knox SDK. Apply each original feature contract to
# every copy, including the SDK 37 multidex moves in Settings and SystemUI.
while read -r PARTITION ARCHIVE SMALI_DIR; do
    APK_NAME="${ARCHIVE##*/}"
    APPLY_PATCH "$PARTITION" "$ARCHIVE" \
        "$MODPATH/ddar/$APK_NAME/0001-Nuke-Knox-DualDAR-SDK37.patch"
    APPLY_PATCH "$PARTITION" "$ARCHIVE" \
        "$MODPATH/hdm/$APK_NAME/0001-Nuke-Knox-HDM-SDK37.patch"
    SMALI_PATCH "$PARTITION" "$ARCHIVE" \
        "$SMALI_DIR/com/samsung/android/knox/integrity/EnhancedAttestationPolicy.smali" "return" \
        'isBldpEventSupported()Z' 'false'
    SMALI_PATCH "$PARTITION" "$ARCHIVE" \
        "$SMALI_DIR/com/samsung/android/knox/integrity/EnhancedAttestationPolicy.smali" "return" \
        'isMposSupported()Z' 'false'
done <<'EOF'
system system/app/Traceur/Traceur.apk smali
system system/framework/knoxsdk.jar smali
system system/priv-app/DeviceDiagnostics/DeviceDiagnostics.apk smali
system system/priv-app/ManagedProvisioning/ManagedProvisioning.apk smali
system system/priv-app/SecSettings/SecSettings.apk smali_classes3
system system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk smali_classes2
system_ext priv-app/StorageManager/StorageManager.apk smali
EOF
unset PARTITION ARCHIVE SMALI_DIR APK_NAME

# SEC_PRODUCT_FEATURE_KNOX_SUPPORT_HDM
APPLY_PATCH "system" "system/framework/services.jar" \
    "$MODPATH/hdm/services.jar/0001-Nuke-Knox-HDM-SDK37.patch"

# SEC_PRODUCT_FEATURE_KNOX_SUPPORT_BLDP / SUPPORT_MPOS
SMALI_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
    "smali_classes5/com/samsung/android/knox/integrity/EnhancedAttestationPolicy.smali" "return" \
    'isBldpEventSupported()Z' 'false'
SMALI_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
    "smali_classes5/com/samsung/android/knox/integrity/EnhancedAttestationPolicy.smali" "return" \
    'isMposSupported()Z' 'false'
APPLY_PATCH "system" "system/framework/services.jar" \
    "$MODPATH/mpos/services.jar/0001-Nuke-MPOS-SDK37.patch"

# SEC_PRODUCT_FEATURE_KNOX_SUPPORT_KNOXGUARD
APPLY_PATCH "system" "system/framework/services.jar" \
    "$MODPATH/knoxguard/services.jar/0001-Disable-KnoxGuard-SDK37.patch"

# SEC_PRODUCT_FEATURE_SECURITY_SUPPORT_KNOX_MATRIX_AI_PRIVACY
APPLY_PATCH "system" "system/framework/framework.jar" \
    "$MODPATH/kmxai/framework.jar/0001-Nuke-Knox-Matrix-AI-Privacy-SDK37.patch"

# SEC_PRODUCT_FEATURE_FRAMEWORK_SUPPORT_BLOCKCHAIN_SERVICE
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_FRAMEWORK_SUPPORT_BLOCKCHAIN_SERVICE" --delete
SMALI_PATCH "system" "system/framework/framework.jar" \
    "smali_classes6/com/samsung/android/ProductPackagesRune.smali" "replaceall" \
    "SERVICE_SAMSUNG_BLOCKCHAIN:Z = true" \
    "SERVICE_SAMSUNG_BLOCKCHAIN:Z = false"
if [[ "$TARGET_SECURITY_CONFIG_ESE_CHIP_VENDOR" == "none" ]] && [[ "$TARGET_SECURITY_CONFIG_ESE_COS_NAME" == "none" ]]; then
    APPLY_PATCH "system" "system/framework/services.jar" \
        "$MODPATH/ese+blockchain/services.jar/0001-Nuke-BlockchainTZService-SDK37.patch"
else
    APPLY_PATCH "system" "system/framework/services.jar" \
        "$MODPATH/blockchain/services.jar/0001-Nuke-BlockchainTZService-SDK37.patch"
fi
