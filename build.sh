#!/bin/bash
set -e

cd "$(dirname "$0")"

# FOX_ARCHS="arm64 x86_64" builds a universal binary (CI does this);
# unset it for a faster host-only development build.
ARCH_FLAGS=""
for arch in ${FOX_ARCHS:-}; do
    ARCH_FLAGS="$ARCH_FLAGS --arch $arch"
done

echo "Building FoxCapture${FOX_ARCHS:+ ($FOX_ARCHS)}..."
swift build -c release $ARCH_FLAGS

BIN_DIR=$(swift build -c release $ARCH_FLAGS --show-bin-path)

rm -rf build/FoxCapture.app
mkdir -p build/FoxCapture.app/Contents/{MacOS,Resources}
cp "$BIN_DIR/FoxCapture" build/FoxCapture.app/Contents/MacOS/
cp FoxCapture/Info.plist build/FoxCapture.app/Contents/
[ -f AppIcon.icns ] && cp AppIcon.icns build/FoxCapture.app/Contents/Resources/

# Sign with a stable identity so the Screen Recording permission grant
# survives rebuilds; ad-hoc signatures reset TCC on every build.
IDENTITY="${FOX_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' 'NR==1 {print $2}')}"
if [ -n "$IDENTITY" ]; then
    echo "Signing with identity: $IDENTITY"
    codesign --force --sign "$IDENTITY" build/FoxCapture.app
else
    echo "warning: no codesigning identity found; ad-hoc signing (permissions will reset on every rebuild)"
    codesign --force --sign - build/FoxCapture.app
fi

echo "Done! App is at build/FoxCapture.app"
