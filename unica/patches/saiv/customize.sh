SOURCE_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$SOURCE_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$SOURCE_FIRMWARE")"
TARGET_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")"

DELETE_FROM_WORK_DIR "system" "system/saiv"
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/saiv" 0 0 755 "u:object_r:system_file:s0"

# SEC_PRODUCT_FEATURE_VISION_CONFIG_FACE_RECOGNITION_SOLUTION
SOURCE_VISION_CONFIG_FACE_RECOGNITION_SOLUTION="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_GALLERY_CONFIG_FACE_CLUSTER_VERSION")"
TARGET_VISION_CONFIG_FACE_RECOGNITION_SOLUTION="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_GALLERY_CONFIG_FACE_CLUSTER_VERSION")"
if [[ "$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_GALLERY_CONFIG_FACE_CLUSTER_VERSION")" == "$SOURCE_VISION_CONFIG_FACE_RECOGNITION_SOLUTION" ]]; then
    if [[ "$TARGET_VISION_CONFIG_FACE_RECOGNITION_SOLUTION" != "$SOURCE_VISION_CONFIG_FACE_RECOGNITION_SOLUTION" ]] || \
            [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
        if [ -d "$WORK_DIR/system/system/saiv/face/cluster_pb" ]; then
            DELETE_FROM_WORK_DIR "system" "system/saiv/face/cluster_pb"
        fi
        ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "system/saiv/face/cluster_pb" 0 0 755 "u:object_r:system_file:s0"
    fi
fi

# SEC_PRODUCT_FEATURE_SAIV_CONFIG_MIDAS
if [ ! -f "$WORK_DIR/vendor/etc/midas/moire_detection/moire_detection.tflite" ]; then
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "etc/midas/moire_detection/moire_detection.tflite" 0 0 644 "u:object_r:vendor_configs_file:s0"
fi
if [ ! "$(find "$WORK_DIR/vendor/etc/midas" -maxdepth 1 -type f -name "SRIBMQA_aiFiQA*" 2> /dev/null)" ]; then
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "etc/midas/SRIBMQA_aiFiQA_V100_FP32.tflite" 0 0 644 "u:object_r:vendor_configs_file:s0"
fi
if [ ! -f "$WORK_DIR/vendor/etc/midas/SRIBMQA_aiIQA_V100_FP32.tflite" ]; then
    if [ -f "$FW_DIR/$SOURCE_FIRMWARE_PATH/vendor/etc/midas/SRIBMQA_aiIQA_V100_FP32.tflite" ]; then
        ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "etc/midas/SRIBMQA_aiIQA_V100_FP32.tflite" 0 0 644 "u:object_r:vendor_configs_file:s0"
    else
        # The donor retains AIiqa V100 but omits its model. This original A34
        # graph uses the same 448x448 RGB normalization, five float outputs,
        # tensor-index binding and native postprocessing. Do not substitute
        # the different FiQA graph, weights or a renamed model.
        if [ "$SOURCE_PLATFORM_SDK_VERSION" -ne 37 ] || \
                [ "$(sha256sum "$WORK_DIR/system/system/lib64/libsrib_MQA.camera.samsung.so" | cut -d ' ' -f 1)" != "0a57613edc1d6faa51609f22924da78fc57f8fdba449b51e3318e98f3dabf974" ] || \
                [ "$(sha256sum "$SRC_DIR/prebuilts/samsung/a34xxx/vendor/etc/midas/SRIBMQA_aiIQA_V100_FP32.tflite" | cut -d ' ' -f 1)" != "deece2e2b296eac7433fc7760134cb0581439f3af56d22d3f0a1281e1eddac85" ]; then
            ABORT "Missing donor IQA model; the original V100 fallback requires the checked SDK-37 AIiqa consumer"
            return 1
        fi
        if ! python3 - "$WORK_DIR/vendor/etc/midas/midas_config.json" <<'PY'
import json, sys
with open(sys.argv[1]) as config:
    entries = [entry for entry in json.load(config)['detection'] if entry['type'] == 'iqa-score']
if len(entries) != 1:
    raise SystemExit('Expected one IQA configuration')
entry, = entries
if entry['inference_dim'] != [448, 448] or entry['nChannel'] != 3:
    raise SystemExit('IQA input contract changed')
model, = entry['dnn_model_info']
expected = {'version': 'default', 'inference_type': 'TFLITE', 'compute_unit': 'XNNPACK',
            'model_format': 'TENSORFLOWLITE', 'exec_type': 'FLOAT32',
            'input_node': ['input'], 'output_node': ['output']}
if any(model.get(key) != value for key, value in expected.items()):
    raise SystemExit('IQA runtime contract changed')
if model['compatible_models'] != [{'id': 'adreno,amd',
        'model_file': ['SRIBMQA_aiIQA_V100_FP32.tflite'], 'models_list': []}]:
    raise SystemExit('Different IQA model selected')
PY
        then
            ABORT "Original IQA V100 fallback does not match the current Midas configuration"
            return 1
        fi
        ADD_TO_WORK_DIR "a34xxx" "vendor" "etc/midas/SRIBMQA_aiIQA_V100_FP32.tflite" 0 0 644 "u:object_r:vendor_configs_file:s0"
    fi
fi
if [ "$(find "$WORK_DIR/vendor/etc/midas" -maxdepth 1 -type f -name "*UPSCALER_*_LITE*" 2> /dev/null)" ]; then
    # Ensure AI_UPSCALE LITE models are loaded if available
    if ! sed -n "/\"midasSR_devices\"/,/]/p" "$WORK_DIR/vendor/etc/midas/midas_config.json" | grep -q "\"$(GET_PROP "ro.product.device")\""; then
        LOG "- Patching /vendor/etc/midas/midas_config.json"
        EVAL "sed -i \"/\\\"midasSR_devices\\\"[^[]*\\[/a\\\\    \\\"$(GET_PROP "ro.product.device")\\\",\" \"$WORK_DIR/vendor/etc/midas/midas_config.json\""
    fi
fi

# SEC_PRODUCT_FEATURE_GALLERY_CONFIG_IMAGE_TAGGER_VERSION
SOURCE_GALLERY_CONFIG_IMAGE_TAGGER_VERSION="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_GALLERY_CONFIG_IMAGE_TAGGER_VERSION")"
TARGET_GALLERY_CONFIG_IMAGE_TAGGER_VERSION="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_GALLERY_CONFIG_IMAGE_TAGGER_VERSION")"
if [[ "$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_GALLERY_CONFIG_IMAGE_TAGGER_VERSION")" == "$SOURCE_GALLERY_CONFIG_IMAGE_TAGGER_VERSION" ]]; then
    if [[ "$TARGET_GALLERY_CONFIG_IMAGE_TAGGER_VERSION" != "$SOURCE_GALLERY_CONFIG_IMAGE_TAGGER_VERSION" ]] || \
            [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
        if [ "$SOURCE_PLATFORM_SDK_VERSION" -ge "37" ]; then
            # MediaSearch's current encoder opens its own packaged image/tag,
            # document and landmark models, not the retired external AIG set.
            for MODEL in enc_image enc_text dec_tag dec_document dec_landmark dec_brand dec_intent; do
                unzip -Z1 "$WORK_DIR/system/system/priv-app/MediaSearch/MediaSearch.apk" \
                    | grep -Fx "assets/model/$MODEL.tflite" > /dev/null \
                    || ABORT "Missing current MediaSearch model: $MODEL"
            done
            unset MODEL
        else
        if [ -d "$WORK_DIR/system/system/saiv/image_understanding/db/aig" ]; then
            DELETE_FROM_WORK_DIR "system" "system/saiv/image_understanding/db/aig"
        fi
        ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "system/saiv/image_understanding/db/aig" 0 0 755 "u:object_r:system_file:s0"
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/aig_classifier" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/aig_classifier"
        fi
        ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "saiv/image_understanding/db/aig_classifier" 0 2000 755 "u:object_r:vendor_snap_file:s0"
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/aig_detector" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/aig_detector"
        fi
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/aig_document_classifier" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/aig_document_classifier"
        fi
        ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "saiv/image_understanding/db/aig_document_classifier" 0 2000 755 "u:object_r:vendor_snap_file:s0"
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/aig_document_detector" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/aig_document_detector"
        fi
        ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "saiv/image_understanding/db/aig_document_detector" 0 2000 755 "u:object_r:vendor_snap_file:s0"
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/srr_interaction" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/srr_interaction"
        fi
        fi
    fi
fi

# Photo Editor "oneUI-full-release"/"genAI-full-release" flavor models
if [ -f "$WORK_DIR/system/system/priv-app/PhotoEditor_Full/PhotoEditor_Full.apk" ] || \
        [ -f "$WORK_DIR/system/system/priv-app/PhotoEditor_AIFull/PhotoEditor_AIFull.apk" ]; then
    if [ ! -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/hs_segmenter" ] || \
            [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
        if [ -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/hs_segmenter" ]; then
            DELETE_FROM_WORK_DIR "vendor" "etc/saiv/image_understanding/db/hs_segmenter"
        fi
        # Keep the descriptor/model set together: current Photo Editor selects
        # versioned HumanSeg/BGPclassifier descriptors instead of hs_segmenter.info.
        ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "etc/saiv/image_understanding/db/hs_segmenter" 0 0 755 "u:object_r:vendor_configs_file:s0"
    fi
else
    if [ -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/hs_segmenter" ]; then
        DELETE_FROM_WORK_DIR "vendor" "etc/saiv/image_understanding/db/hs_segmenter"
    fi
fi

# SEC_PRODUCT_FEATURE_GALLERY_CONFIG_PET_CLUSTER_VERSION
SOURCE_GALLERY_CONFIG_PET_CLUSTER_VERSION="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_GALLERY_CONFIG_PET_CLUSTER_VERSION")"
TARGET_GALLERY_CONFIG_PET_CLUSTER_VERSION="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_GALLERY_CONFIG_PET_CLUSTER_VERSION")"
if [[ "$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_GALLERY_CONFIG_PET_CLUSTER_VERSION")" == "$SOURCE_GALLERY_CONFIG_PET_CLUSTER_VERSION" ]]; then
    if [[ "$SOURCE_GALLERY_CONFIG_PET_CLUSTER_VERSION" != "None" ]]; then
        if [[ "$TARGET_GALLERY_CONFIG_PET_CLUSTER_VERSION" != "$SOURCE_GALLERY_CONFIG_PET_CLUSTER_VERSION" ]] || \
                [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
            if [ "$SOURCE_PLATFORM_SDK_VERSION" -ge "37" ]; then
                # FaceService's config.yaml runs pet detection/extraction through
                # the matching cluster_pb set imported above, using XNNPACK.
                [ -f "$WORK_DIR/system/system/priv-app/FaceService/FaceService.apk" ] \
                    || ABORT "Missing current FaceService pet model consumer"
                for MODEL in faceservice_bd faceservice_fd pet_face_keypoint_mps fe pet_body_embedding_mps; do
                    [ -f "$WORK_DIR/system/system/saiv/face/cluster_pb/$MODEL.tflite" ] \
                        || ABORT "Missing current FaceService pet model: $MODEL"
                done
                unset MODEL
            else
            if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/pet_detector" ]; then
                DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/pet_detector"
            fi
            ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "saiv/image_understanding/db/pet_detector" 0 2000 755 "u:object_r:vendor_snap_file:s0"
            if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/pet_mypetsearch" ]; then
                DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/pet_mypetsearch"
            fi
            ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "saiv/image_understanding/db/pet_mypetsearch" 0 2000 755 "u:object_r:vendor_snap_file:s0"
            fi
        fi
    else
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/pet_detector" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/pet_detector"
        fi
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/pet_mypetsearch" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/pet_mypetsearch"
        fi
    fi
fi

# SEC_PRODUCT_FEATURE_VISION_CONFIG_BIXBYVISION_VERSION
if [ -f "$WORK_DIR/system/system/priv-app/BixbyVisionFramework3.5/BixbyVisionFramework3.5.apk" ]; then
    if [ ! -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/slens_classifier" ] || \
            [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
        if [ -d "$WORK_DIR/system/system/saiv/image_understanding/db/slens_classifier" ]; then
            DELETE_FROM_WORK_DIR "system" "system/saiv/image_understanding/db/slens_classifier"
        fi
        ADD_TO_WORK_DIR "pa2qxxx" "system" "system/saiv/image_understanding/db/slens_classifier/slens_classifier_cnn.sni" 0 0 644 "u:object_r:system_file:s0"
        if [ -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/slens_classifier" ]; then
            DELETE_FROM_WORK_DIR "vendor" "etc/saiv/image_understanding/db/slens_classifier"
        fi
        ADD_TO_WORK_DIR "pa2qxxx" "vendor" "etc/saiv/image_understanding/db/slens_classifier/slens_classifier_cnn.tflite" 0 0 644 "u:object_r:vendor_configs_file:s0"
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/slens_classifier" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/slens_classifier"
        fi
    fi
    if [ ! -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/slens_detector" ] || \
            [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
        if [ -d "$WORK_DIR/system/system/saiv/image_understanding/db/slens_detector" ]; then
            DELETE_FROM_WORK_DIR "system" "system/saiv/image_understanding/db/slens_detector"
        fi
        ADD_TO_WORK_DIR "pa2qxxx" "system" "system/saiv/image_understanding/db/slens_detector/slens_detector_cnn.sni" 0 0 644 "u:object_r:system_file:s0"
        if [ -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/slens_detector" ]; then
            DELETE_FROM_WORK_DIR "vendor" "etc/saiv/image_understanding/db/slens_detector"
        fi
        ADD_TO_WORK_DIR "pa2qxxx" "vendor" "etc/saiv/image_understanding/db/slens_detector/slens_detector_cnn.tflite" 0 0 644 "u:object_r:vendor_configs_file:s0"
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/slens_detector" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/slens_detector"
        fi
    fi
else
    if [ -d "$WORK_DIR/system/system/saiv/image_understanding/db/slens_classifier" ]; then
        DELETE_FROM_WORK_DIR "system" "system/saiv/image_understanding/db/slens_classifier"
    fi
    if [ -d "$WORK_DIR/system/system/saiv/image_understanding/db/slens_detector" ]; then
        DELETE_FROM_WORK_DIR "system" "system/saiv/image_understanding/db/slens_detector"
    fi
    if [ -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/slens_classifier" ]; then
        DELETE_FROM_WORK_DIR "vendor" "etc/saiv/image_understanding/db/slens_classifier"
    fi
    if [ -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/slens_detector" ]; then
        DELETE_FROM_WORK_DIR "vendor" "etc/saiv/image_understanding/db/slens_detector"
    fi
    if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/slens_classifier" ]; then
        DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/slens_classifier"
    fi
    if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/slens_detector" ]; then
        DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/slens_detector"
    fi
fi

# SEC_PRODUCT_FEATURE_CAMERA_CONFIG_DOCUMENT_DEWARP_VERSION
SOURCE_CAMERA_CONFIG_DOCUMENT_DEWARP_VERSION="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_CAMERA_DOCUMENTSCAN_SOLUTIONS")"
TARGET_CAMERA_CONFIG_DOCUMENT_DEWARP_VERSION="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_CAMERA_DOCUMENTSCAN_SOLUTIONS")"
if [[ "$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_CAMERA_DOCUMENTSCAN_SOLUTIONS")" == "$SOURCE_CAMERA_CONFIG_DOCUMENT_DEWARP_VERSION" ]]; then
    if [[ "$SOURCE_CAMERA_CONFIG_DOCUMENT_DEWARP_VERSION" == *"AI_DEWARPING"* ]]; then
        if [[ "$TARGET_CAMERA_CONFIG_DOCUMENT_DEWARP_VERSION" != *"AI_DEWARPING"* ]] || \
                [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
            if [ "$SOURCE_PLATFORM_SDK_VERSION" -ge "37" ]; then
                # libDeepDocRectify reads this descriptor and its versioned
                # model directly. Keep the donor's backend/precision unchanged.
                ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" \
                    "vendor" "etc/saiv/image_understanding/db/doc_rectifier" 0 0 755 "u:object_r:vendor_configs_file:s0"
            else
            ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" \
                "system" "system/saiv/image_understanding/db/smartscan_rectifier/deep_dewarp_cnn.sni" 0 0 644 "u:object_r:system_file:s0"
            ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" \
                "vendor" "saiv/image_understanding/db/smartscan_rectifier/deep_dewarp_cnn.onnx" 0 0 644 "u:object_r:vendor_snap_file:s0"
            fi
        fi
    else
        if [ -d "$WORK_DIR/system/system/saiv/image_understanding/db/smartscan_rectifier" ]; then
            DELETE_FROM_WORK_DIR "system" "system/saiv/image_understanding/db/smartscan_rectifier"
        fi
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/smartscan_rectifier" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/smartscan_rectifier"
        fi
    fi
fi

# SEC_PRODUCT_FEATURE_VISION_CONFIG_SMART_CROPPING_SOLUTION
if [ "$SOURCE_PLATFORM_SDK_VERSION" -ge "37" ]; then
    # The current ImageCropper uses the system model with its original name;
    # neither the old Caffe saliency pair nor the vendor detector path is used.
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "system/saiv/imageCropper" 0 0 755 "u:object_r:system_file:s0"
else
if [ ! -d "$WORK_DIR/system/system/saiv/smartcropping_2.0" ] || \
        [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
    if [ -d "$WORK_DIR/system/system/saiv/smartcropping_2.0" ]; then
        DELETE_FROM_WORK_DIR "system" "system/saiv/smartcropping_2.0"
    fi
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "system/saiv/smartcropping_2.0/db/smartcrop_saliency_deploy.prototxt" 0 0 644 "u:object_r:system_file:s0"
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "system/saiv/smartcropping_2.0/db/smartcrop_saliency_train" 0 0 644 "u:object_r:system_file:s0"
fi
if [ ! -d "$WORK_DIR/vendor/saiv/image_understanding/db/sce_detector" ] || \
        [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
    if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/sce_detector" ]; then
        DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/sce_detector"
    fi
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "saiv/image_understanding/db/sce_detector/sce_detector_cnn.tflite" 0 0 644 "u:object_r:vendor_snap_file:s0"
fi
fi

# SEC_PRODUCT_FEATURE_CAMERA_CONFIG_STRIDE_OCR_VERSION
if [ -d "$WORK_DIR/system/system/saiv/textrecognition" ]; then
    DELETE_FROM_WORK_DIR "system" "system/saiv/textrecognition"
fi
ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "system/saiv/textrecognition" 0 0 755 "u:object_r:system_file:s0"

# SEC_PRODUCT_FEATURE_CAMERA_CONFIG_VENDOR_LIB_INFO:=*smart_scan.samsung.v2*
if [ -f "$WORK_DIR/system/system/lib64/libSmartScan.camera.samsung.so" ]; then
    if [ "$TARGET_PLATFORM" != "exynos2100" ] && { [ ! -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/SS_segmenter" ] || \
            [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; }; then
        if [ -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/SS_segmenter" ]; then
            DELETE_FROM_WORK_DIR "vendor" "etc/saiv/image_understanding/db/SS_segmenter"
        fi
        ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "etc/saiv/image_understanding/db/SS_segmenter" 0 2000 755 "u:object_r:vendor_configs_file:s0"
    fi
fi

unset SOURCE_FIRMWARE_PATH TARGET_FIRMWARE_PATH \
    SOURCE_VISION_CONFIG_FACE_RECOGNITION_SOLUTION TARGET_VISION_CONFIG_FACE_RECOGNITION_SOLUTION \
    SOURCE_GALLERY_CONFIG_IMAGE_TAGGER_VERSION TARGET_GALLERY_CONFIG_IMAGE_TAGGER_VERSION \
    SOURCE_GALLERY_CONFIG_PET_CLUSTER_VERSION TARGET_GALLERY_CONFIG_PET_CLUSTER_VERSION \
    SOURCE_CAMERA_CONFIG_DOCUMENT_DEWARP_VERSION TARGET_CAMERA_CONFIG_DOCUMENT_DEWARP_VERSION
