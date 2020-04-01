#!/bin/bash
#
# Copyright 2020 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Generate Android.bp for AOSP blob self-extractors.
#
# For example, a blob package may contain:
#   ./vendor
#   └── qcom
#       └── coral
#           └── proprietary
#               ├── lib64
#               |   ├── libfoo.so
#               |   └── libbar.so
#               ├── libfoo.so
#               └── libbar.so
#
# Generate prebuilt modules for these blobs:
# $ export SYSTEM_EXT_SPECIFIC=true # If installing prebuilts to system_ext/ partition
# $ export OWNER=qcom # Owner is relevant if PRODUCT_RESTRICT_VENDOR_FILES is set
# $ ./generate-android-bp-for-blobs.sh ./vendor/qcom/coral/proprietary > Android.bp.txt
# $ mv Android.bp.txt ${ANDROID_BUILD_TOP}/device/google/coral/self-extractors/qcom/staging/
#
# You may need to review the contents of Android.bp.txt as some of the blobs may
# have unsatisfied dependencies. Add `check_elf_files: false` to bypass this
# kind of build errors.

set -e

readonly PREBUILT_DIR="$1"

readonly elf_files=$(
  for file in $(find "$PREBUILT_DIR" -type f); do
    if readelf -h "$file" 2>/dev/null 1>&2; then
      basename "$file"
    fi
  done | sort | uniq | xargs
)

echo "// Copyright (C) $(date +%Y) The Android Open Source Project"
echo "//"
echo "// Licensed under the Apache License, Version 2.0 (the \"License\");"
echo "// you may not use this file except in compliance with the License."
echo "// You may obtain a copy of the License at"
echo "//"
echo "//      http://www.apache.org/licenses/LICENSE-2.0"
echo "//"
echo "// Unless required by applicable law or agreed to in writing, software"
echo "// distributed under the License is distributed on an \"AS IS\" BASIS,"
echo "// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied."
echo "// See the License for the specific language governing permissions and"
echo "// limitations under the License."
echo ""
echo "soong_namespace {"
echo "}"

for file in $elf_files; do
  file32=$(find "$PREBUILT_DIR" -type f -name "$file" | grep -v 'lib64' | head)
  file64=$(find "$PREBUILT_DIR" -type f -name "$file" | grep 'lib64' | head)
  if [[ -n "$file32" ]] && [[ -n "$file64" ]]; then
    multilib="both"
  elif [[ -n "$file32" ]]; then
    multilib="32"
  else
    multilib="64"
  fi

echo ""
echo "cc_prebuilt_library_shared {"
echo "    name: \"${file%.so}\","
echo "    arch: {"

  if [[ -f "$file32" ]]; then
  NEEDED=$(readelf -d "$file32" | sed -n -E 's/^.*\(NEEDED\).*\[(.+)\]$/\1/p' | xargs)
echo "        arm: {"
echo "            srcs: [\"$(realpath --relative-to="$PREBUILT_DIR" "$file32")\"],"
    if [[ -n "$NEEDED" ]]; then
echo "            shared_libs: ["
      for entry in $NEEDED; do
echo "                \"${entry%.so}\","
      done
echo "            ],"
    fi
echo "        },"
  fi

  if [[ -f "$file64" ]]; then
  NEEDED=$(readelf -d "$file64" | sed -n -E 's/^.*\(NEEDED\).*\[(.+)\]$/\1/p' | xargs)
echo "        arm64: {"
echo "            srcs: [\"$(realpath --relative-to="$PREBUILT_DIR" "$file64")\"],"
    if [[ -n "$NEEDED" ]]; then
echo "            shared_libs: ["
      for entry in $NEEDED; do
echo "                \"${entry%.so}\","
      done
echo "            ],"
    fi
echo "        },"
  fi

echo "    },"
echo "    compile_multilib: \"$multilib\","
  if [[ -n "$SYSTEM_EXT_SPECIFIC" ]]; then
echo "    system_ext_specific: true,"
  fi
  if [[ -n "$OWNER" ]]; then
echo "    owner: \"${OWNER}\","
  fi
echo "    strip: {"
echo "        none: true,"
echo "    },"
echo "}"

done
