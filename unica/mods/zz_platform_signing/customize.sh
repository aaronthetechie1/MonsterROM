if [[ "$TARGET_CODENAME" != "t2s" && "$TARGET_CODENAME" != "o1s" ]]; then
    return 0
fi

STOCK_PLATFORM_APK="$FW_DIR/SM-S947B_EUX/system/system/framework/framework-res.apk"
SIGNER_CLASSES="$(mktemp -d "$OUT_DIR/platform-signer.XXXXXX")"
javac -classpath "$TOOLS_DIR/bin/signapk.jar" -d "$SIGNER_CLASSES" "$SRC_DIR/security/monsterrom/PlatformSigner.java"
"$SRC_DIR/security/monsterrom/prepare-apex-keys.sh"
for MODULE in com.android.bt com.android.nfcservices com.android.uwb com.android.webapp com.android.wifi; do
    COUNT=1
    [[ "$MODULE" == "com.android.wifi" ]] && COUNT=3
    "$SRC_DIR/security/monsterrom/resign-apex.sh" "$MODULE" "$SIGNER_CLASSES" "$COUNT"
    if [ ! -f "$WORK_DIR/system/system/apex/$MODULE.apex" ]; then
        ABORT "APEX resigning did not produce /system/system/apex/$MODULE.apex"
    fi
    if ! unzip -t "$WORK_DIR/system/system/apex/$MODULE.apex" > /dev/null; then
        ABORT "APEX archive validation failed for /system/system/apex/$MODULE.apex"
    fi
    SET_METADATA "system" "system/apex/$MODULE.apex" 0 0 644 "u:object_r:system_file:s0"
    if [ -f "$WORK_DIR/system/system/apex/$MODULE.capex" ]; then
        DELETE_FROM_WORK_DIR "system" "system/apex/$MODULE.capex"
    fi
    if [ -e "$WORK_DIR/system/system/apex/$MODULE.capex" ]; then
        ABORT "Stale compressed APEX remained after resigning $MODULE"
    fi
done
unset MODULE COUNT

if find "$WORK_DIR/system/system/apex" -maxdepth 1 -type f -name '*.capex' -print -quit | grep -q .; then
    ABORT "A compressed APEX remained in the final t2s system tree"
fi

java -Xmx1g -classpath "$SIGNER_CLASSES:$TOOLS_DIR/bin/signapk.jar" PlatformSigner \
    "$STOCK_PLATFORM_APK" "$SRC_DIR/security/aosp_platform.x509.pem" "$SRC_DIR/security/aosp_platform.pk8" "$WORK_DIR"
rm "$SIGNER_CLASSES/PlatformSigner.class"
rmdir "$SIGNER_CLASSES"
unset SIGNER_CLASSES STOCK_PLATFORM_APK


if [ -f "$WORK_DIR/system/system/priv-app/SamsungAccount/SamsungAccount.apk" ]; then
    LOG "- Patching SamsungAccount to report stock platform signature to Samsung servers"
    DECODE_APK "system" "system/priv-app/SamsungAccount/SamsungAccount.apk"
    python3 - "$FW_DIR/SM-S947B_EUX/system/system/framework/framework-res.apk" "$APKTOOL_DIR/system/priv-app/SamsungAccount/SamsungAccount.apk" << 'EOF'
import subprocess, sys, zipfile
from pathlib import Path

stock_apk, sa_dir = sys.argv[1], Path(sys.argv[2])
with zipfile.ZipFile(stock_apk) as z:
    rsa_name = [n for n in z.namelist() if n.startswith("META-INF/") and n.endswith((".RSA", ".EC", ".DSA"))][0]
    rsa_bytes = z.read(rsa_name)
p1 = subprocess.run(["openssl", "pkcs7", "-inform", "DER", "-print_certs"], input=rsa_bytes, capture_output=True, check=True)
p2 = subprocess.run(["openssl", "x509", "-outform", "DER"], input=p1.stdout, capture_output=True, check=True)
cert_hex = p2.stdout.hex()

helper = next(sa_dir.glob("smali*/com/samsung/android/samsungaccount/utils/signature/SignatureInfoHelper.smali"))
src = helper.read_text()
new_method = """.method public static d(Landroid/content/Context;Ljava/lang/String;)[Landroid/content/pm/Signature;
    .locals 5

    const/4 v0, 0x0

    :try_start_0
    invoke-virtual {p0}, Landroid/content/Context;->getPackageManager()Landroid/content/pm/PackageManager;

    move-result-object p0

    const/high16 v1, 0x8000000

    invoke-virtual {p0, p1, v1}, Landroid/content/pm/PackageManager;->getPackageInfo(Ljava/lang/String;I)Landroid/content/pm/PackageInfo;

    move-result-object p1

    iget-object p1, p1, Landroid/content/pm/PackageInfo;->signingInfo:Landroid/content/pm/SigningInfo;

    if-eqz p1, :cond_1

    invoke-virtual {p1}, Landroid/content/pm/SigningInfo;->getApkContentsSigners()[Landroid/content/pm/Signature;

    move-result-object p1

    if-eqz p1, :cond_0

    array-length v2, p1

    if-lez v2, :cond_0

    const-string v2, "android"

    invoke-virtual {p0, v2, v1}, Landroid/content/pm/PackageManager;->getPackageInfo(Ljava/lang/String;I)Landroid/content/pm/PackageInfo;

    move-result-object p0

    iget-object p0, p0, Landroid/content/pm/PackageInfo;->signingInfo:Landroid/content/pm/SigningInfo;

    if-eqz p0, :cond_0

    invoke-virtual {p0}, Landroid/content/pm/SigningInfo;->getApkContentsSigners()[Landroid/content/pm/Signature;

    move-result-object p0

    if-eqz p0, :cond_0

    array-length v1, p0

    if-lez v1, :cond_0

    const/4 v1, 0x0

    aget-object v2, p1, v1

    aget-object p0, p0, v1

    invoke-virtual {v2, p0}, Landroid/content/pm/Signature;->equals(Ljava/lang/Object;)Z

    move-result p0

    if-eqz p0, :cond_0

    const/4 p0, 0x1

    new-array p0, p0, [Landroid/content/pm/Signature;

    new-instance v2, Landroid/content/pm/Signature;

    const-string v3, "__CERT_HEX__"

    invoke-direct {v2, v3}, Landroid/content/pm/Signature;-><init>(Ljava/lang/String;)V

    aput-object v2, p0, v1
    :try_end_0
    .catch Landroid/content/pm/PackageManager$NameNotFoundException; {:try_start_0 .. :try_end_0} :catch_0

    return-object p0

    :cond_0
    return-object p1

    :catch_0
    move-exception p0

    goto :goto_0

    :cond_1
    return-object v0

    :goto_0
    invoke-virtual {p0}, Ljava/lang/Throwable;->getMessage()Ljava/lang/String;

    move-result-object p0

    const-string p1, "getSignatures - cannot find package : "

    const-string v1, "SignatureInfoHelper"

    invoke-static {p1, p0, v1}, Lfc3;->n(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V

    return-object v0
.end method""".replace("__CERT_HEX__", cert_hex)

import re
pattern = re.compile(r"^\.method public static d\(Landroid/content/Context;Ljava/lang/String;\)\[Landroid/content/pm/Signature;.*?^\.end method", re.M | re.S)
assert pattern.search(src), "SignatureInfoHelper.d not found"
helper.write_text(pattern.sub(new_method, src, count=1))
EOF
fi

source "$MODPATH/fsverity/customize.sh"
