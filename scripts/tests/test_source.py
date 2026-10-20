#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Source checks that need neither firmware downloads nor build dependencies."""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
TARGETS = ("o1s", "t2s", "p3s", "r9s")


def run_bash(script, work_dir, **variables):
    environment = dict(os.environ, SRC_DIR=str(ROOT), WORK_DIR=str(work_dir))
    environment.update({key: str(value) for key, value in variables.items()})
    return subprocess.run(
        ["bash", "-e", "-c", script], cwd=ROOT, env=environment,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )


class SourceTests(unittest.TestCase):
    def run_smali(self, content, commands):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            decoded = root / "apktool/system/framework/test.jar/smali/Example.smali"
            decoded.parent.mkdir(parents=True)
            decoded.write_text(content)
            result = run_bash('''
source "$SRC_DIR/scripts/utils/smali_utils.sh"
DECODE_APK() { :; }
''' + commands, root, APKTOOL_DIR=root / "apktool")
            return result, decoded.read_text()

    @staticmethod
    def smali_fixture(value="a.b", prefix_value="a.b"):
        return f'''\
.class public LExample;
.super Ljava/lang/Object;

.method public static prefixvalue()Ljava/lang/String;
    .locals 1
    const-string v0, "{prefix_value}"
    return-object v0
.end method

.method public static value()Ljava/lang/String;
    .locals 1
    const-string v0, "{value}"
    return-object v0
.end method
'''

    def test_smali_replace_is_literal_scoped_and_repeatable(self):
        command = ("SMALI_PATCH system system/framework/test.jar smali/Example.smali "
                   "replace 'value()Ljava/lang/String;' 'a.b' 'a[b]&c'\n")
        result, content = self.run_smali(self.smali_fixture(), command + command)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(content.count('const-string v0, "a.b"'), 1)
        self.assertEqual(content.count('const-string v0, "a[b]&c"'), 1)

    def test_smali_replace_rejects_regex_near_matches(self):
        original = self.smali_fixture(value="axb")
        result, content = self.run_smali(original,
            "SMALI_PATCH system system/framework/test.jar smali/Example.smali "
            "replace 'value()Ljava/lang/String;' 'a.b' 'replacement'\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(content, original)

    def test_smali_replace_does_not_accept_another_methods_replacement(self):
        original = self.smali_fixture(value="unexpected", prefix_value="replacement")
        result, content = self.run_smali(original,
            "SMALI_PATCH system system/framework/test.jar smali/Example.smali "
            "replace 'value()Ljava/lang/String;' 'old' 'replacement'\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(content, original)

    def test_smali_requires_an_exact_method_declaration(self):
        original = self.smali_fixture().replace(' static value()', ' static othervalue()')
        original += '# Call site: LExample;->value()Ljava/lang/String;\n'
        result, content = self.run_smali(original,
            "SMALI_PATCH system system/framework/test.jar smali/Example.smali "
            "replace 'value()Ljava/lang/String;' 'a.b' 'replacement'\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('exactly one declaration', result.stderr)
        self.assertEqual(content, original)

    def test_smali_replaceall_remains_global(self):
        result, content = self.run_smali(self.smali_fixture(),
            "SMALI_PATCH system system/framework/test.jar smali/Example.smali "
            "replaceall 'a.b' 'replacement'\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(content.count('const-string v0, "replacement"'), 2)

    def test_smali_static_return_uses_a_local_register(self):
        original = ('.class public LExample;\n.super Ljava/lang/Object;\n'
                    '.method public static enabled()Z\n    .locals 1\n'
                    '    const/4 v0, 0x1\n    return v0\n.end method\n')
        result, content = self.run_smali(original,
            "SMALI_PATCH system system/framework/test.jar smali/Example.smali "
            "return 'enabled()Z' false\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('.locals 1', content)
        self.assertIn('const/4 v0, 0x0', content)
        self.assertIn('return v0', content)

    def test_floating_features_are_unique_and_preserve_other_tags(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            xml = root / "system/system/etc/floating_feature.xml"
            xml.parent.mkdir(parents=True)
            xml.write_text('''\
<?xml version="1.0" encoding="utf-8"?>
<SecFloatingFeatureSet>
    <CAMERA_SUPPORT_AI_HIGH_RESOLUTION>FALSE</CAMERA_SUPPORT_AI_HIGH_RESOLUTION>
    <CAMERA_SUPPORT_AI_HIGH_RESOLUTION>FALSE</CAMERA_SUPPORT_AI_HIGH_RESOLUTION>
    <CAMERA_SUPPORT_AI_HIGH_RESOLUTION_DRAFT_DOWNSCALE>KEEP</CAMERA_SUPPORT_AI_HIGH_RESOLUTION_DRAFT_DOWNSCALE>
    <UNCHANGED>KEEP</UNCHANGED>
</SecFloatingFeatureSet>
''')
            result = run_bash('''
source "$SRC_DIR/scripts/utils/module_utils.sh"
SET_FLOATING_FEATURE_CONFIG CAMERA_SUPPORT_AI_HIGH_RESOLUTION TRUE
SET_FLOATING_FEATURE_CONFIG CAMERA_SUPPORT_AI_HIGH_RESOLUTION TRUE
''', root)
            self.assertEqual(result.returncode, 0, result.stderr)
            document = ET.parse(xml).getroot()
            self.assertEqual(len(document.findall('CAMERA_SUPPORT_AI_HIGH_RESOLUTION')), 1)
            self.assertEqual(document.findtext('CAMERA_SUPPORT_AI_HIGH_RESOLUTION'), 'TRUE')
            self.assertEqual(document.findtext('CAMERA_SUPPORT_AI_HIGH_RESOLUTION_DRAFT_DOWNSCALE'), 'KEEP')
            self.assertEqual(document.findtext('UNCHANGED'), 'KEEP')
            result = run_bash('''
source "$SRC_DIR/scripts/utils/module_utils.sh"
SET_FLOATING_FEATURE_CONFIG CAMERA_SUPPORT_AI_HIGH_RESOLUTION --delete
''', root)
            self.assertEqual(result.returncode, 0, result.stderr)
            document = ET.parse(xml).getroot()
            self.assertIsNone(document.find('CAMERA_SUPPORT_AI_HIGH_RESOLUTION'))
            self.assertEqual(document.findtext('CAMERA_SUPPORT_AI_HIGH_RESOLUTION_DRAFT_DOWNSCALE'), 'KEEP')

    def test_shell_syntax(self):
        files = sorted(path for folder in ("scripts", "platform", "target", "unica")
                       for path in (ROOT / folder).rglob("*.sh") if path.is_file())
        files.append(ROOT / "buildenv.sh")
        for path in files:
            with self.subTest(file=str(path.relative_to(ROOT))):
                result = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_patch_syntax(self):
        files = sorted(path for folder in ("external/patches", "platform", "target", "unica")
                       for path in (ROOT / folder).rglob("*.patch"))
        for path in files:
            with self.subTest(file=str(path.relative_to(ROOT))):
                result = subprocess.run(
                    ["git", "apply", "--numstat", str(path)], cwd=ROOT,
                    capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_binary_prebuilts_are_not_normalized_as_text(self):
        paths = ("unica/mods/miracle/system/priv-app/Example/Example.apk.00",
                 "prebuilts/kernel/test/Image", "target/test/profiles/boot.prof.gz",
                 "target/test/boot.img", "prebuilts/test/archive.zip")
        for path in paths:
            with self.subTest(file=path):
                result = subprocess.run(["git", "check-attr", "text", "--", path],
                                        cwd=ROOT, capture_output=True, text=True, check=True)
                self.assertTrue(result.stdout.rstrip().endswith(": unset"), result.stdout)

    def test_pif_defaults_match_the_settings_version(self):
        patch = (ROOT / "unica/mods/pif/framework.jar/0001-Introduce-PlayIntegrityHooks.patch").read_text()
        version = re.search(r'PIF_VERSION:Ljava/lang/String; = "([0-9]+)"', patch).group(1)
        ui = (ROOT / "unica/mods/settings/SecSettings.apk/smali_classes3/"
              "io/mesalabs/unica/settings/pif/PIFUtils.smali").read_text()
        defaults = re.findall(r'"persist.sys.pif.version"\n\n    const-string v[0-9]+, "([0-9]+)"', ui)
        self.assertEqual(defaults, [version, version])
        for field, prop in (("FINGERPRINT", "fingerprint"), ("SECURITY_PATCH", "security_patch"),
                            ("DEVICE_INITIAL_SDK_INT", "first_api_level")):
            value = re.search(r'PIF_' + field + r':Ljava/lang/String; = "([^"]+)"', patch).group(1)
            default = re.search(r'"persist.sys.pif.' + prop + r'"\n\+\n\+    const-string v2, "([^"]+)"',
                                patch).group(1)
            self.assertEqual(default, value)

    def test_property_keys_are_literal(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            prop = work / "system/system/build.prop"
            prop.parent.mkdir(parents=True)
            prop.write_text("roXfoo=other\nro.foo=old\nro.foo.bar=child\nro.foobar=sibling\n")
            result = run_bash('''
source "$SRC_DIR/scripts/utils/common_utils.sh"
TARGET_OS_BUILD_SYSTEM_EXT_PARTITION=false
test "$(GET_PROP system ro.foo)" = old
test -z "$(GET_PROP system ro.fo)"
SET_PROP system ro.foo 'new=value'
test "$(GET_PROP system ro.foo)" = 'new=value'
SET_PROP system ro.foo --delete
test -z "$(GET_PROP system ro.foo)"
''', work)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(prop.read_text(), "roXfoo=other\nro.foo.bar=child\nro.foobar=sibling\n")

    def test_codec2_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            policy = work / "vendor/etc/seccomp_policy/samsung.software.media.c2-base-policy"
            policy.parent.mkdir(parents=True)
            policy.write_text("read: 1\nmremap: arg3 == 3\nwrite: 1\n")
            result = run_bash('''
LOG() { :; }; LOG_STEP_IN() { :; }; LOG_STEP_OUT() { :; }; LOGE() { echo "$*" >&2; }
source "$SRC_DIR/platform/exynos2100/patches/codec2/customize.sh"
source "$SRC_DIR/platform/exynos2100/patches/codec2/customize.sh"
''', work)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(policy.read_text(),
                             "read: 1\nmremap: arg3 == 3 || arg3 == MREMAP_MAYMOVE\nwrite: 1\n")

    def test_codec2_rejects_unknown_or_missing_policy(self):
        for content in (None, "mremap: arg3 == 0\n"):
            with self.subTest(content=content), tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                policy = work / "vendor/etc/seccomp_policy/samsung.software.media.c2-base-policy"
                if content is not None:
                    policy.parent.mkdir(parents=True)
                    policy.write_text(content)
                result = run_bash('''
LOG() { :; }; LOG_STEP_IN() { :; }; LOG_STEP_OUT() { :; }; LOGE() { echo "$*" >&2; }
source "$SRC_DIR/platform/exynos2100/patches/codec2/customize.sh"
''', work)
                self.assertNotEqual(result.returncode, 0)
                if content is not None:
                    self.assertEqual(policy.read_text(), content)
                else:
                    self.assertFalse(policy.exists())

    def test_prebuilt_update_repairs_chunks_and_symlinks(self):
        source = (ROOT / "scripts/internal/update_prebuilt_blobs.sh").read_text()
        functions = source.split("# ]", 1)[0]
        functions = re.sub(r'^source .*firmware_utils.sh.*$', '', functions, flags=re.MULTILINE)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prebuilt = root / "prebuilts/samsung/test/system/lib64"
            firmware = root / "fw/SM-TEST_EUX/system/system/lib64"
            prebuilt.mkdir(parents=True)
            firmware.mkdir(parents=True)
            (prebuilt / "large.so.00").write_text("old chunk")
            (prebuilt / "large.so.01").write_text("old chunk")
            (prebuilt / "large.so.notes").write_text("keep")
            (firmware / "large.so.notes").write_text("keep")
            (firmware / "large.so").write_text("small replacement")
            (prebuilt / "old.so").write_text("obsolete")
            (prebuilt / "model.so").symlink_to("old.so")
            (firmware / "model.so").symlink_to("new.so")
            (prebuilt / "absolute.so").symlink_to("/apex/old/lib.so")
            (firmware / "absolute.so").symlink_to("/apex/com.android.runtime/lib/bionic/libc.so")
            (firmware / "new.so").write_text("new model")
            (root / "fw/SM-TEST_EUX/.extracted").write_text("TEST_BUILD")
            result = run_bash(functions + '''
SRC_DIR="$FIXTURE_DIR"
FW_DIR="$FIXTURE_DIR/fw"
DEVICE=test; MODEL=SM-TEST; CSC=EUX
LOG() { :; }; LOGW() { :; }; LOGE() { echo "$*" >&2; }; EVAL() { eval "$1"; }
UPDATE_BLOBS
''', root, FIXTURE_DIR=root)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((prebuilt / "large.so").read_text(), "small replacement")
            self.assertFalse((prebuilt / "large.so.00").exists())
            self.assertFalse((prebuilt / "large.so.01").exists())
            self.assertTrue((prebuilt / "large.so.notes").is_file())
            self.assertFalse((prebuilt / "old.so").exists())
            self.assertEqual(os.readlink(prebuilt / "model.so"), "new.so")
            self.assertEqual((prebuilt / "model.so").read_text(), "new model")
            self.assertEqual(os.readlink(prebuilt / "absolute.so"),
                             "/apex/com.android.runtime/lib/bionic/libc.so")

    def test_bluetooth_apex_helpers_are_present(self):
        script = (ROOT / "unica/patches/bluetooth/customize.sh").read_text()
        for helper in ("BUILD_APK_IN_APEX", "DECODE_APEX", "DECODE_APK_IN_APEX",
                       "EXTRACT_PAYLOAD", "BUILD_PAYLOAD", "SIGN_PAYLOAD", "BUILD_APEX", "SIGN_APEX"):
            with self.subTest(helper=helper):
                self.assertRegex(script, re.compile(r'^' + helper + r'\(\)$', re.MULTILINE))

    @staticmethod
    def camera_helpers():
        return (ROOT / "unica/patches/camera/customize.sh").read_text().split("# ]", 1)[0]

    def test_camera_manifest_resolves_system_vendor_and_directory_models(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "system/system/cameradata").mkdir(parents=True)
            (root / "vendor/etc/portrait_data").mkdir(parents=True)
            (root / "system/system/cameradata/model with spaces.bin").write_bytes(b"model")
            (root / "vendor/etc/portrait_data/model.bin").write_bytes(b"model")
            manifest = root / "manifest.json"
            manifest.write_text('''{
                "system_model": "/system/cameradata/model with spaces.bin",
                "vendor_model": "/vendor/etc/portrait_data/model.bin",
                "model_directory": "/vendor/etc/portrait_data/"
            }''')
            result = run_bash(self.camera_helpers() + '''
ABORT() { echo "$*" >&2; return 1; }
VALIDATE_CAMERA_MODEL_MANIFEST "$WORK_DIR/manifest.json"
''', root)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_camera_manifest_rejects_corrupt_or_missing_models(self):
        cases = {
            "empty manifest": "",
            "invalid JSON": '{"model":',
            "missing system model": '{"model":"/system/cameradata/missing.bin"}',
            "missing vendor model": '{"model":"/vendor/etc/missing.bin"}',
            "missing model directory": '{"model":"/vendor/etc/missing/"}',
            "empty model": '{"model":"/system/cameradata/empty.bin"}',
        }
        for name, content in cases.items():
            with self.subTest(case=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / "system/system/cameradata").mkdir(parents=True)
                (root / "system/system/cameradata/empty.bin").touch()
                (root / "manifest.json").write_text(content)
                result = run_bash(self.camera_helpers() + '''
ABORT() { echo "$*" >&2; return 1; }
VALIDATE_CAMERA_MODEL_MANIFEST "$WORK_DIR/manifest.json"
''', root)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("camera", result.stderr.lower())

    def test_camera_tflite_requires_the_flatbuffer_identifier(self):
        cases = {
            "portable TFLite": (b"\x1c\x00\x00\x00TFL3model", True),
            "different format": (b"\x1c\x00\x00\x00DLC1model", False),
            "identifier at wrong offset": (b"TFL3model", False),
            "empty model": (b"", False),
        }
        for name, (content, valid) in cases.items():
            with self.subTest(case=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / "model.tflite").write_bytes(content)
                result = run_bash(self.camera_helpers() + '''
IS_PORTABLE_TFLITE "$WORK_DIR/model.tflite"
''', root)
                self.assertEqual(result.returncode == 0, valid, result.stderr)

    def test_camera_action_classifier_keeps_only_a_matching_target_runtime(self):
        script = (ROOT / "unica/patches/camera/customize.sh").read_text()
        block = script.split("# SEC_PRODUCT_FEATURE_CAMERA_CONFIG_ACTION_CLASSIFIER\n", 1)[1]
        block = block.split("# SEC_PRODUCT_FEATURE_CAMERA_CONFIG_GPPM_SOLUTIONS", 1)[0]
        cases = ("matched", "no legacy classifier", "different classifier",
                 "different OpenCV", "missing TensorFlow", "orphan TensorFlow")
        for case in cases:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                library = Path("system/system/lib64")
                target = root / "fw/SM-TARGET_EUX"
                current = root / "work"
                names = ("libVideoClassifier.camera.samsung.so", "libOpenCv.camera.samsung.so",
                         "libtensorflowLite2_11_0_dynamic_camera.so")
                for base in (target, current):
                    (base / library).mkdir(parents=True)
                (target / "vendor/etc/singletake/dynamic_viewing").mkdir(parents=True)
                (target / "vendor/etc/singletake/dynamic_viewing/model.tflite").write_bytes(b"model")
                for name in names:
                    (target / library / name).write_bytes(name.encode())
                for name in names[:2]:
                    (current / library / name).write_bytes(name.encode())
                if case == "no legacy classifier":
                    (current / library / names[0]).unlink()
                elif case == "different classifier":
                    (current / library / names[0]).write_bytes(b"unexpected")
                elif case == "different OpenCV":
                    (current / library / names[1]).write_bytes(b"unexpected")
                elif case == "missing TensorFlow":
                    (target / library / names[2]).unlink()
                elif case == "orphan TensorFlow":
                    (current / library / names[0]).unlink()
                    (current / library / names[2]).write_bytes(b"unexpected")
                result = run_bash(self.camera_helpers() + '''
ABORT() { echo "$*" >&2; return 1; }
LOG() { :; }
GET_FLOATING_FEATURE_CONFIG() { echo 1,0; }
ADD_TO_WORK_DIR() {
    mkdir -p "$WORK_DIR/$2/$(dirname "$3")"
    cp -a "$FW_DIR/$TARGET_FIRMWARE_PATH/$2/$3" "$WORK_DIR/$2/$3"
}
DELETE_FROM_WORK_DIR() { rm -f "$WORK_DIR/$1/$2"; }
''' + block, current, FW_DIR=root / "fw", SOURCE_FIRMWARE_PATH="SM-SOURCE_EUX",
                    TARGET_FIRMWARE_PATH="SM-TARGET_EUX", TARGET_FIRMWARE="SM-TARGET/EUX/12345678",
                    SOURCE_PLATFORM_SDK_VERSION=37)
                valid = case in ("matched", "no legacy classifier")
                self.assertEqual(result.returncode == 0, valid, result.stderr)
                if valid:
                    self.assertTrue((current / "vendor/etc/singletake/dynamic_viewing/model.tflite").is_file())
                    self.assertEqual((current / library / names[2]).exists(), case == "matched")
                else:
                    self.assertIn("classifier", result.stderr.lower())

    def test_build_cache_tracks_scripts_and_prebuilts(self):
        script = (ROOT / "scripts/make_rom.sh").read_text()
        function = re.search(r'^GET_WORK_DIR_HASH\(\)\n\{.*?^\}', script,
                             re.MULTILINE | re.DOTALL).group()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("unica", "platform/exynos2100", "target/o1s", "scripts", "prebuilts"):
                (root / name).mkdir(parents=True)
            result = run_bash(function + '''
SRC_DIR="$FIXTURE_DIR"; TARGET_PLATFORM=exynos2100; TARGET_CODENAME=o1s
GET_WORK_DIR_HASH
echo updated > "$SRC_DIR/scripts/build.sh"
GET_WORK_DIR_HASH
echo updated > "$SRC_DIR/prebuilts/lib.so"
GET_WORK_DIR_HASH
''', root, FIXTURE_DIR=root)
            self.assertEqual(result.returncode, 0, result.stderr)
            hashes = result.stdout.splitlines()
            self.assertEqual(len(hashes), 3)
            self.assertEqual(len(set(hashes)), 3)

    def test_platform_certificate_reaches_the_selected_sdk_patch(self):
        for sdk in (36, 37):
            with self.subTest(sdk=sdk), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / "security").mkdir()
                (root / "security/aosp_platform.x509.pem").write_text(
                    "-----BEGIN CERTIFICATE-----\nYQ==\n-----END CERTIFICATE-----\n")
                folder = root / "apktool/system/framework/services.jar/smali_classes2/com/android/server/pm"
                folder.mkdir(parents=True)
                name = "InstallPackageHelper" if sdk == 37 else "ScanPackageUtils"
                method = ("<init>(Lcom/android/server/pm/PackageManagerService;"
                          "Lcom/android/server/pm/AppDataHelper;Lcom/android/server/pm/RemovePackageHelper;"
                          "Lcom/android/server/pm/DeletePackageHelper;Lcom/android/server/pm/BroadcastHelper;)V"
                          if sdk == 37 else "signedWithCustomSignature([Landroid/content/pm/Signature;)Z")
                decoded = folder / (name + ".smali")
                decoded.write_text('.class public LExample;\n.super Ljava/lang/Object;\n'
                                   f'.method public {method}\n    .locals 1\n'
                                   '    const-string v0, "CONFIG_CUSTOM_PLATFORM_SIGNATURE"\n'
                                   '    return-void\n.end method\n')
                result = run_bash('''
source "$SRC_DIR/scripts/utils/module_utils.sh"
DECODE_APK() { :; }; APPLY_PATCH() { :; }
MODULE="$SRC_DIR/unica/patches/signature/customize.sh"
SRC_DIR="$FIXTURE_DIR"
source "$MODULE"
''', root, APKTOOL_DIR=root / "apktool", FIXTURE_DIR=root,
                    SOURCE_PLATFORM_SDK_VERSION=sdk, ROM_IS_OFFICIAL="false")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('const-string v0, "61"', decoded.read_text())
                self.assertNotIn("CONFIG_CUSTOM_PLATFORM_SIGNATURE", decoded.read_text())

    def test_engmode_client_is_backported_for_each_target(self):
        for target in TARGETS:
            with self.subTest(target=target), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                paths = {
                    "work/system/system/lib64/lib.engmode.samsung.so": "engmode-V1-ndk.so",
                    "work/vendor/lib64/vendor.samsung.hardware.security.engmode@1.0.so": "HIDL",
                    "fw/SM-TEST_EUX/system/system/lib64/lib.engmode.samsung.so": "legacy client",
                    "fw/SM-TEST_EUX/system/system/lib64/vendor.samsung.hardware.security.engmode@1.0.so": "HIDL",
                }
                for relative, content in paths.items():
                    path = root / relative
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(content)
                result = run_bash('''
LOG() { :; }; LOG_STEP_IN() { :; }; LOG_STEP_OUT() { :; }; ABORT() { echo "$*" >&2; return 1; }
DELETE_FROM_WORK_DIR() { :; }
ADD_TO_WORK_DIR() { printf '%s\n' "$3" >> "$FIXTURE_DIR/copied"; }
FW_DIR="$FIXTURE_DIR/fw"; TARGET_FIRMWARE=SM-TEST/EUX/12345678
source "$SRC_DIR/platform/exynos2100/patches/blobs/customize.sh"
''', root / "work", FIXTURE_DIR=root, TARGET_CODENAME=target)
                self.assertEqual(result.returncode, 0, result.stderr)
                copied = (root / "copied").read_text().splitlines()
                self.assertIn("system/lib64/lib.engmode.samsung.so", copied)
                self.assertIn("system/lib64/vendor.samsung.hardware.security.engmode@1.0.so", copied)

    def test_sensor_toggle_patch_applies_to_its_declared_preimage(self):
        path = ROOT / ("unica/mods/tweaks/smali/system_ext/priv-app/SystemUI/SystemUI.apk/"
                       "0003-Remove-confirm-dialog-on-sensors-QS-toggle.patch")
        patch = path.read_text()
        target = re.search(r'^--- a/(.*)$', patch, re.MULTILINE).group(1)
        hunks = list(re.finditer(r'^@@ -(\d+),(\d+) \+\d+,\d+ @@.*\n', patch, re.MULTILINE))
        self.assertTrue(hunks)
        original = []
        for index, hunk in enumerate(hunks):
            start, count = map(int, hunk.groups())
            end = hunks[index + 1].start() if index + 1 < len(hunks) else patch.index('\n-- \n') + 1
            old = [line[1:] for line in patch[hunk.end():end].splitlines(keepends=True)
                   if line.startswith((' ', '-'))]
            self.assertEqual(len(old), count)
            original.extend(['\n'] * max(0, start - 1 - len(original)))
            original[start - 1:start - 1 + count] = old
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            decoded = root / target
            decoded.parent.mkdir(parents=True)
            decoded.write_text(''.join(original))
            result = subprocess.run(['git', 'apply', str(path)], cwd=root,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            method = decoded.read_text().split('.method public final toggleTileState()V', 1)[1]
            method = method.split('.end method', 1)[0]
            self.assertNotIn('mDialog', method)
            self.assertIn('setSensorBlocked(IIZ)V', method)
            self.assertTrue(method.rstrip().endswith('return-void'))

    def test_sdk37_deknox_patch_references(self):
        folder = ROOT / "unica/mods/deknox"
        script = (folder / "customize-sdk37.sh").read_text()
        for patch in re.findall(r'\$MODPATH/([^"$\n]+\.patch)', script):
            with self.subTest(patch=patch):
                self.assertTrue((folder / patch).is_file(), patch)
        for apk in ("Traceur.apk", "knoxsdk.jar", "DeviceDiagnostics.apk", "ManagedProvisioning.apk",
                    "SecSettings.apk", "SecSettingsIntelligence.apk", "StorageManager.apk"):
            for feature, name in (("ddar", "DualDAR"), ("hdm", "HDM")):
                path = folder / feature / apk / f"0001-Nuke-Knox-{name}-SDK37.patch"
                with self.subTest(patch=str(path)):
                    self.assertTrue(path.is_file())


if __name__ == "__main__":
    unittest.main(verbosity=2)
