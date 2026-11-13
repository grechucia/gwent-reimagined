#!/bin/zsh
# Usage: ./native/build-ios.sh [--sim]   (--sim builds for the iOS Simulator, otherwise an unsigned .ipa for devices)
set -e
HERE=${0:A:h}
GAME=${HERE:h}
OUT=$HERE/build
MAC=$OUT/GwentReimagined.app
if [[ $1 == --sim ]]; then SDK=iphonesimulator; TARGET=arm64-apple-ios17.0-simulator; DIR=$OUT/ios-sim
else SDK=iphoneos; TARGET=arm64-apple-ios17.0; DIR=$OUT/ios; fi
APP=$DIR/GwentReimagined.app
print "» GwentReimagined: building iOS app ($SDK)"
[[ -d $MAC ]] || $HERE/build.sh
rm -rf $APP; mkdir -p $APP

print "» Compiling Swift"
xcrun --sdk $SDK swiftc -O -target $TARGET -framework UIKit -framework Metal -framework MetalKit \
  -framework CoreText -framework AVFoundation -framework GameController -swift-version 5 $HERE/Sources/*.swift -o $APP/GwentReimagined

print "» Copying game assets"
rsync -a $MAC/Contents/Resources/game $MAC/Contents/Resources/data $APP/
cp $GAME/LICENSE $GAME/NOTICE.md $APP/

print "» Icon"
XC=$OUT/ios-assets/Assets.xcassets; rm -rf $OUT/ios-assets; mkdir -p $XC/AppIcon.appiconset
sips -s format png -z 1024 1024 $HERE/Resources/icon.png --out $XC/AppIcon.appiconset/icon.png >/dev/null
print '{"info":{"version":1,"author":"xcode"}}' > $XC/Contents.json
print '{"images":[{"filename":"icon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"version":1,"author":"xcode"}}' > $XC/AppIcon.appiconset/Contents.json
xcrun actool $XC --compile $APP --platform $SDK --minimum-deployment-target 17.0 --app-icon AppIcon \
  --target-device iphone --target-device ipad --output-partial-info-plist $OUT/ios-assets/partial.plist >/dev/null

cat > $APP/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>GwentReimagined</string>
  <key>CFBundleDisplayName</key><string>Gwent</string>
  <key>CFBundleIdentifier</key><string>io.github.grechucia.gwentreimagined</string>
  <key>CFBundleExecutable</key><string>GwentReimagined</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>MinimumOSVersion</key><string>17.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
  <key>UIRequiredDeviceCapabilities</key><array><string>metal</string></array>
  <key>UILaunchScreen</key><dict><key>UIColorName</key><string></string></dict>
  <key>UIRequiresFullScreen</key><true/>
  <key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/></dict>
  <key>UIStatusBarHidden</key><true/>
  <key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
  <key>UISupportedInterfaceOrientations~ipad</key><array><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
  <key>UIFileSharingEnabled</key><true/>
  <key>LSSupportsOpeningDocumentsInPlace</key><true/>
  <key>CADisableMinimumFrameDurationOnPhone</key><true/>
  <key>GCSupportsControllerUserInteraction</key><true/>
  <key>GCSupportedGameControllers</key><array><dict><key>ProfileName</key><string>ExtendedGamepad</string></dict></array>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Merge $OUT/ios-assets/partial.plist" $APP/Info.plist >/dev/null
codesign --force --sign - $APP
print "✓ $APP ($(du -sh $APP | cut -f1))"

if [[ $SDK == iphoneos ]]; then
  print "» Packaging .ipa (unsigned, re-sign with your own certificate or a sideloading tool)"
  rm -rf $DIR/Payload; mkdir -p $DIR/Payload; cp -R $APP $DIR/Payload/
  (cd $DIR && rm -f GwentReimagined.ipa && zip -qry GwentReimagined.ipa Payload)
  rm -rf $DIR/Payload
  print "✓ $DIR/GwentReimagined.ipa ($(du -sh $DIR/GwentReimagined.ipa | cut -f1))"
fi
