#!/bin/bash
set -euo pipefail

FFMPEG_VERSION="8.0"
FFMPEG_SHA256="b2751fccb6cc4c77708113cd78b561059b6fa904b24162fa0be2d60273d27b8e"
LAME_VERSION="3.100"
LAME_SHA256="ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"
IOS_MIN_VERSION="16.0"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build-ffmpeg"
FFMPEG_ARCHIVE="$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_SRC="$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}"
LAME_ARCHIVE="$BUILD_DIR/downloads/lame-${LAME_VERSION}.tar.gz"
LAME_SRC="$BUILD_DIR/lame-${LAME_VERSION}"
FRAMEWORK_DIR="$PROJECT_DIR/Frameworks"
LOG_DIR="$BUILD_DIR/logs"

LIBRARIES=(
    libavdevice
    libavfilter
    libavformat
    libavcodec
    libswresample
    libswscale
    libavutil
)

prepare_source() {
    mkdir -p "$BUILD_DIR" "$BUILD_DIR/downloads" "$LOG_DIR"

    if [ ! -f "$FFMPEG_ARCHIVE" ]; then
        curl --fail --location --retry 3 \
            --output "$FFMPEG_ARCHIVE" \
            "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
    fi

    printf '%s  %s\n' "$FFMPEG_SHA256" "$FFMPEG_ARCHIVE" | shasum -a 256 -c -

    if [ ! -x "$FFMPEG_SRC/configure" ]; then
        tar -xf "$FFMPEG_ARCHIVE" -C "$BUILD_DIR"
    fi

    if [ ! -f "$LAME_ARCHIVE" ]; then
        curl --fail --location --retry 3 \
            --output "$LAME_ARCHIVE" \
            "https://downloads.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz"
    fi

    printf '%s  %s\n' "$LAME_SHA256" "$LAME_ARCHIVE" | shasum -a 256 -c -

    if [ ! -x "$LAME_SRC/configure" ]; then
        tar -xf "$LAME_ARCHIVE" -C "$BUILD_DIR"
    fi
}

build_lame() {
    local platform="$1"
    local arch="$2"
    local prefix="$BUILD_DIR/output-lame-${platform}-${arch}"
    local sdk_path
    local compiler
    local target
    local deployment_flag
    local host_arch="$arch"
    local long_double_size="16"

    if [ "$arch" = "arm64" ]; then
        host_arch="aarch64"
        long_double_size="8"
    fi

    sdk_path="$(xcrun --sdk "$platform" --show-sdk-path)"
    compiler="$(xcrun --sdk "$platform" --find clang)"

    if [ "$platform" = "iphoneos" ]; then
        target="${arch}-apple-ios${IOS_MIN_VERSION}"
        deployment_flag="-mios-version-min=${IOS_MIN_VERSION}"
    else
        target="${arch}-apple-ios${IOS_MIN_VERSION}-simulator"
        deployment_flag="-mios-simulator-version-min=${IOS_MIN_VERSION}"
    fi

    if [ -f "$prefix/lib/libmp3lame.a" ]; then
        printf '\nReusing libmp3lame %s for %s %s.\n' "$LAME_VERSION" "$platform" "$arch"
        return
    fi

    printf '\nBuilding libmp3lame %s for %s %s...\n' "$LAME_VERSION" "$platform" "$arch"
    rm -rf "$prefix"
    cd "$LAME_SRC"
    make distclean >/dev/null 2>&1 || true

    CC="$compiler" \
    AR="$(xcrun --sdk "$platform" --find ar)" \
    RANLIB="$(xcrun --sdk "$platform" --find ranlib)" \
    CFLAGS="-target $target -arch $arch -isysroot $sdk_path $deployment_flag -O3 -fPIC" \
    LDFLAGS="-target $target -arch $arch -isysroot $sdk_path $deployment_flag" \
    ac_cv_sizeof_short=2 \
    ac_cv_sizeof_unsigned_short=2 \
    ac_cv_sizeof_int=4 \
    ac_cv_sizeof_unsigned_int=4 \
    ac_cv_sizeof_long=8 \
    ac_cv_sizeof_unsigned_long=8 \
    ac_cv_sizeof_long_long=8 \
    ac_cv_sizeof_unsigned_long_long=8 \
    ac_cv_sizeof_float=4 \
    ac_cv_sizeof_double=8 \
    ac_cv_sizeof_long_double="$long_double_size" \
    ac_cv_header_stdc=yes \
    ./configure \
        --prefix="$prefix" \
        --host="${host_arch}-apple-darwin" \
        --disable-shared \
        --enable-static \
        --disable-frontend \
        --disable-decoder \
        --disable-nasm \
        --with-pic \
        > "$LOG_DIR/${platform}-${arch}-lame-configure.log" 2>&1

    if ! make -C libmp3lame -j"$(sysctl -n hw.ncpu)" > "$LOG_DIR/${platform}-${arch}-lame-build.log" 2>&1; then
        tail -200 "$LOG_DIR/${platform}-${arch}-lame-build.log"
        return 1
    fi
    mkdir -p "$prefix/lib" "$prefix/include/lame"
    cp "$LAME_SRC/libmp3lame/.libs/libmp3lame.a" "$prefix/lib/libmp3lame.a"
    cp "$LAME_SRC/include/lame.h" "$prefix/include/lame/lame.h"
}

build_ffmpeg() {
    local platform="$1"
    local arch="$2"
    local prefix="$BUILD_DIR/output-${platform}-${arch}"
    local sdk_path
    local compiler
    local target
    local deployment_flag
    local x86_assembler_option=""
    local lame_prefix="$BUILD_DIR/output-lame-${platform}-${arch}"
    local lame_relative_prefix="../output-lame-${platform}-${arch}"
    local output_relative_prefix="../output-${platform}-${arch}"

    sdk_path="$(xcrun --sdk "$platform" --show-sdk-path)"
    compiler="$(xcrun --sdk "$platform" --find clang)"

    if [ "$platform" = "iphoneos" ]; then
        target="${arch}-apple-ios${IOS_MIN_VERSION}"
        deployment_flag="-mios-version-min=${IOS_MIN_VERSION}"
    else
        target="${arch}-apple-ios${IOS_MIN_VERSION}-simulator"
        deployment_flag="-mios-simulator-version-min=${IOS_MIN_VERSION}"
    fi

    if [ "$arch" = "x86_64" ]; then
        # FFmpeg 8 HEVC assembly requires newer NASM macro semantics than the
        # locally available yasm. Keep every component, but use the portable
        # implementation for the Intel-only simulator slice.
        x86_assembler_option="--disable-x86asm"
    fi

    printf '\nConfiguring FFmpeg %s for %s %s...\n' "$FFMPEG_VERSION" "$platform" "$arch"
    rm -rf "$prefix"
    cd "$FFMPEG_SRC"
    make distclean >/dev/null 2>&1 || true

    ./configure \
        --prefix="$output_relative_prefix" \
        --enable-cross-compile \
        --target-os=darwin \
        --arch="$arch" \
        --cc="$compiler" \
        --sysroot="$sdk_path" \
        --pkg-config=/usr/bin/false \
        --extra-cflags="-target $target -arch $arch -isysroot $sdk_path $deployment_flag -fPIC -I$lame_relative_prefix/include" \
        --extra-ldflags="-target $target -arch $arch -isysroot $sdk_path $deployment_flag -L$lame_relative_prefix/lib" \
        --enable-static \
        --disable-shared \
        --disable-programs \
        --disable-doc \
        --disable-debug \
        --disable-stripping \
        --enable-pic \
        --enable-optimizations \
        --enable-asm \
        --enable-inline-asm \
        --enable-runtime-cpudetect \
        --enable-gray \
        --enable-pthreads \
        --enable-network \
        --enable-securetransport \
        --enable-videotoolbox \
        --enable-audiotoolbox \
        --enable-avfoundation \
        --enable-coreimage \
        --enable-zlib \
        --enable-bzlib \
        --disable-lzma \
        --enable-iconv \
        --enable-libmp3lame \
        $x86_assembler_option \
        2>&1 | tee "$LOG_DIR/${platform}-${arch}-configure.log"

    cp config.h "$LOG_DIR/${platform}-${arch}-config.h"
    cp config_components.h "$LOG_DIR/${platform}-${arch}-components.h"
    printf 'Compiling %s %s...\n' "$platform" "$arch"
    if ! make -j"$(sysctl -n hw.ncpu)" > "$LOG_DIR/${platform}-${arch}-build.log" 2>&1; then
        tail -200 "$LOG_DIR/${platform}-${arch}-build.log"
        return 1
    fi
    make install >> "$LOG_DIR/${platform}-${arch}-build.log" 2>&1
    printf 'Completed %s %s.\n' "$platform" "$arch"
}

merge_libraries() {
    local prefix="$1"
    local lame_prefix="$2"
    local output="$3"
    local archives=()
    local library

    for library in "${LIBRARIES[@]}"; do
        archives+=("$prefix/lib/${library}.a")
    done
    if [ -f "$lame_prefix/lib/libmp3lame.a" ]; then
        archives+=("$lame_prefix/lib/libmp3lame.a")
    fi

    libtool -static -o "$output" "${archives[@]}"
}

install_headers() {
    local source_headers="$1"
    local target_headers="$PROJECT_DIR/Sources/CFFmpeg/include"
    local backup_dir

    backup_dir="$(mktemp -d)"
    cp "$target_headers/shim.h" "$backup_dir/shim.h"
    cp "$target_headers/module.modulemap" "$backup_dir/module.modulemap"
    rm -rf "$target_headers"
    mkdir -p "$target_headers"
    cp -R "$source_headers/"* "$target_headers/"
    cp "$backup_dir/shim.h" "$target_headers/shim.h"
    cp "$backup_dir/module.modulemap" "$target_headers/module.modulemap"
    rm "$backup_dir/shim.h" "$backup_dir/module.modulemap"
    rmdir "$backup_dir"
}

write_capability_manifest() {
    local components="$LOG_DIR/iphoneos-arm64-components.h"
    local manifest="$PROJECT_DIR/FFmpegCapabilities.txt"

    awk '
        /^#define CONFIG_.*_DECODER 1$/ { decoder++ }
        /^#define CONFIG_.*_ENCODER 1$/ { encoder++ }
        /^#define CONFIG_.*_DEMUXER 1$/ { demuxer++ }
        /^#define CONFIG_.*_MUXER 1$/ { muxer++ }
        /^#define CONFIG_.*_FILTER 1$/ { filter++ }
        /^#define CONFIG_.*_PROTOCOL 1$/ { protocol++ }
        /^#define CONFIG_.*_BSF 1$/ { bsf++ }
        /^#define CONFIG_.*_INDEV 1$/ { indev++ }
        /^#define CONFIG_.*_OUTDEV 1$/ { outdev++ }
        END {
            print "FFmpeg 8.0 full iOS static build"
            print "decoders=" decoder + 0
            print "encoders=" encoder + 0
            print "demuxers=" demuxer + 0
            print "muxers=" muxer + 0
            print "filters=" filter + 0
            print "protocols=" protocol + 0
            print "bitstream_filters=" bsf + 0
            print "input_devices=" indev + 0
            print "output_devices=" outdev + 0
            print "videotoolbox=enabled"
            print "audiotoolbox=enabled"
            print "avfoundation=enabled"
            print "securetransport=enabled"
            print "libmp3lame=enabled"
            print "lzma=disabled (not exposed by the public iOS SDK headers)"
            print "license=LGPL-2.1-or-later"
        }
    ' "$components" > "$manifest"
}

prepare_source

BUILD_TARGETS="${FFMPEG_BUILD_TARGETS:-iphoneos:arm64 iphonesimulator:arm64 iphonesimulator:x86_64}"
for build_target in $BUILD_TARGETS; do
    build_lame "${build_target%%:*}" "${build_target##*:}"
    build_ffmpeg "${build_target%%:*}" "${build_target##*:}"
done

DEVICE_PREFIX="$BUILD_DIR/output-iphoneos-arm64"
SIM_ARM64_PREFIX="$BUILD_DIR/output-iphonesimulator-arm64"
SIM_X86_PREFIX="$BUILD_DIR/output-iphonesimulator-x86_64"
DEVICE_LAME_PREFIX="$BUILD_DIR/output-lame-iphoneos-arm64"
SIM_ARM64_LAME_PREFIX="$BUILD_DIR/output-lame-iphonesimulator-arm64"
SIM_X86_LAME_PREFIX="$BUILD_DIR/output-lame-iphonesimulator-x86_64"
MERGED_DIR="$BUILD_DIR/merged"

rm -rf "$MERGED_DIR"
mkdir -p "$MERGED_DIR/device" "$MERGED_DIR/simulator-arm64" "$MERGED_DIR/simulator-x86_64" "$MERGED_DIR/simulator"

merge_libraries "$DEVICE_PREFIX" "$DEVICE_LAME_PREFIX" "$MERGED_DIR/device/libFFmpegAll.a"
merge_libraries "$SIM_ARM64_PREFIX" "$SIM_ARM64_LAME_PREFIX" "$MERGED_DIR/simulator-arm64/libFFmpegAll.a"
merge_libraries "$SIM_X86_PREFIX" "$SIM_X86_LAME_PREFIX" "$MERGED_DIR/simulator-x86_64/libFFmpegAll.a"

lipo -create \
    "$MERGED_DIR/simulator-arm64/libFFmpegAll.a" \
    "$MERGED_DIR/simulator-x86_64/libFFmpegAll.a" \
    -output "$MERGED_DIR/simulator/libFFmpegAll.a"

rm -rf "$FRAMEWORK_DIR/FFmpegLibs.xcframework"
xcodebuild -create-xcframework \
    -library "$MERGED_DIR/device/libFFmpegAll.a" \
    -headers "$DEVICE_PREFIX/include" \
    -library "$MERGED_DIR/simulator/libFFmpegAll.a" \
    -headers "$SIM_ARM64_PREFIX/include" \
    -output "$FRAMEWORK_DIR/FFmpegLibs.xcframework"

install_headers "$DEVICE_PREFIX/include"
write_capability_manifest

printf '\nFull FFmpeg iOS XCFramework created at:\n%s\n' "$FRAMEWORK_DIR/FFmpegLibs.xcframework"
