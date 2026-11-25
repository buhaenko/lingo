#!/bin/zsh
# Builds Lingo.app (universal), Lingo.dmg and Lingo.zip into ./build.
#
#   scripts/build.sh 1.2.0
#
# Signing: ad-hoc with a stable identity by default (no Apple account needed).
#   SIGN_ID="Developer ID Application: …"  → hardened-runtime signature instead
#   NOTARY_PROFILE=<notarytool keychain profile> (with SIGN_ID) → notarise and staple the DMG
set -euo pipefail
cd "${0:A:h}/.."

NAME=Lingo
BUNDLE_ID=com.serhii.Lingo
MIN_MACOS=14.0
VERSION=${1:-0.0.0-dev}
BUILD=build
APP=$BUILD/$NAME.app

rm -rf $BUILD && mkdir -p $APP/Contents/{MacOS,Resources}

echo "▸ compiling $NAME $VERSION (arm64 + x86_64, macOS $MIN_MACOS+)"
for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macos$MIN_MACOS Sources/*.swift -o $BUILD/$NAME-$arch
done
lipo -create $BUILD/$NAME-arm64 $BUILD/$NAME-x86_64 -output $APP/Contents/MacOS/$NAME
rm $BUILD/$NAME-arm64 $BUILD/$NAME-x86_64
cp Resources/AppIcon.icns $APP/Contents/Resources/

cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$(date +%Y%m%d%H%M)</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Serhii Buhaienko · MIT License</string>
</dict></plist>
PLIST

if [[ -n "${SIGN_ID:-}" ]]; then
  echo "▸ signing: $SIGN_ID"
  codesign --force --options runtime --timestamp -s "$SIGN_ID" $APP
else
  echo "▸ signing: ad-hoc ($BUNDLE_ID)"
  codesign --force -s - --requirements "=designated => identifier \"$BUNDLE_ID\"" $APP
fi
codesign --verify --strict $APP

echo "▸ packaging"
stage=$(mktemp -d)
cp -R $APP $stage/ && ln -s /Applications $stage/Applications
hdiutil create -quiet -volname "$NAME" -srcfolder $stage -fs HFS+ -format UDZO -ov $BUILD/$NAME.dmg
rm -rf $stage
ditto -c -k --keepParent $APP $BUILD/$NAME.zip
if [[ -n "${SIGN_ID:-}" ]]; then
  codesign --force --timestamp -s "$SIGN_ID" $BUILD/$NAME.dmg
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit $BUILD/$NAME.dmg --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple $BUILD/$NAME.dmg
  fi
fi
(cd $BUILD && shasum -a 256 $NAME.dmg $NAME.zip > SHA256SUMS.txt)
echo "✓ $BUILD/$NAME.dmg · $BUILD/$NAME.zip"
