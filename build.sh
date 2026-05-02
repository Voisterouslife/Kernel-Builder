#!/bin/bash
set -e

if [ -z "$DEFCONFIG" ] || [ -z "$CLANG_VERSION" ] || [ -z "$KERNEL_IMAGE_NAME" ] || [ -z "$ANYKERNEL_REPO" ] || [ -z "$ZIP_PREFIX" ]; then
    echo "Error: Missing required environment variables."
    exit 1
fi

TARGET_DEFCONFIG=$DEFCONFIG
LOCALVERSION_BASE=$LOCALVERSION
AK3_REPO=$ANYKERNEL_REPO
OUT_ZIP_PREFIX=$ZIP_PREFIX
TARGET_CLANG_VER=$CLANG_VERSION

TOOLCHAIN=$(realpath "$GITHUB_WORKSPACE/prebuilts")
export PATH="$TOOLCHAIN/build-tools/linux-x86/bin:$TOOLCHAIN/build-tools/path/linux-x86:$TOOLCHAIN/clang/host/linux-x86/$TARGET_CLANG_VER/bin:$TOOLCHAIN/clang-tools/linux-x86/bin:$TOOLCHAIN/kernel-build-tools/linux-x86/bin:$PATH"

export USE_CCACHE=1
export CCACHE_EXEC=$(which ccache)
export O=out
export ARCH=arm64
export CC='ccache clang'
export LLVM=1
export LLVM_IAS=1

rm -rf out

make O=out $TARGET_DEFCONFIG || exit 1

scripts/config --file out/.config \
  -d UH \
  -d RKP \
  -d KDP \
  -d SECURITY_DEFEX \
  -d INTEGRITY \
  -d FIVE \
  -d TRIM_UNUSED_KSYMS

make O=out -j$(nproc) LOCALVERSION="${LOCALVERSION_BASE}" || exit 1

cd out

if [ ! -d AnyKernel3 ]; then
  git clone --depth=1 "${AK3_REPO}" AnyKernel3
else
  cd AnyKernel3 && git pull && cd ..
fi

cp arch/arm64/boot/${KERNEL_IMAGE_NAME} AnyKernel3/${KERNEL_IMAGE_NAME}
cd AnyKernel3
mv ${KERNEL_IMAGE_NAME} zImage

kernel_release=$(cat ../include/config/kernel.release)
final_name="${OUT_ZIP_PREFIX}_${kernel_release}_$(date '+%Y%m%d')"

zip -r9 "../${final_name}.zip" . -x "*.zip"

cd tools
chmod +x libmagiskboot.so || true

if [ "$IS_BOOT_LZ4" == "true" ]; then
    if [ ! -f boot.img.lz4 ]; then
        echo "Error: boot.img.lz4 not found."
        exit 1
    fi
    lz4 -d boot.img.lz4 boot.img
else
    if [ ! -f boot.img ]; then
        echo "Error: boot.img not found."
        exit 1
    fi
fi

./libmagiskboot.so unpack boot.img
cp ../zImage ./kernel 
./libmagiskboot.so repack boot.img new-boot.img

if [ ! -f new-boot.img ]; then
  echo "Error: repack failed."
  exit 1
fi

mv new-boot.img "../../${final_name}.img"
cd ../..

exit 0
