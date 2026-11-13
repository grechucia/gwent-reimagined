#!/bin/zsh
set -e
HERE=${0:A:h}
GAME=${HERE:h}
OUT=$HERE/build
APP=$OUT/GwentReimagined.app
RES=$APP/Contents/Resources
print "» GwentReimagined: building macOS app (arm64, Metal)"
mkdir -p $OUT
rm -rf $APP; mkdir -p $APP/Contents/MacOS $RES/game $RES/data

print "» Exporting game data"
osascript -l JavaScript $HERE/tools/export-data.js $GAME $HERE/Resources/data >/dev/null
cp $HERE/Resources/data/*.json $RES/data/
cp $GAME/LICENSE $GAME/NOTICE.md $RES/

print "» Compiling Swift"
xcrun swiftc -O -target arm64-apple-macos14.0 -framework Cocoa -framework Metal -framework MetalKit \
  -framework CoreText -framework AVFoundation -framework GameController -swift-version 5 $HERE/Sources/*.swift -o $APP/Contents/MacOS/GwentReimagined

print "» Copying game assets"
mkdir -p $RES/game/img $RES/game/fonts
cp $GAME/img/board.jpg $GAME/img/start_bg.jpg $RES/game/img/
rsync -a --exclude '.DS_Store' $GAME/img/icons/ $RES/game/img/icons/
rsync -a $GAME/fonts/ $RES/game/fonts/
rsync -a --exclude '.DS_Store' $GAME/sfx/ $RES/game/sfx/
rsync -a --exclude '.DS_Store' $GAME/audio/ $RES/game/audio/
CACHE=$OUT/.img-cache/sm; mkdir -p $CACHE
todo=$OUT/.img-todo.txt; : > $todo
for f in $GAME/img/sm/*(.N); do c=$CACHE/${f:t}; [[ -f $c && ! $c -ot $f ]] || print -r -- ${f:t} >> $todo; done
if [[ -s $todo ]]; then
  print "  shrinking cards: $(wc -l < $todo | tr -d ' ') files"
  tr '\n' '\0' < $todo | xargs -0 -P 8 -n 1 $HERE/tools/shrink-one.sh $GAME/img/sm $CACHE
fi
rm -f $todo
rsync -a --delete $CACHE/ $RES/game/img/sm/

print "» Icon"
ICONSET=$OUT/AppIcon.iconset; rm -rf $ICONSET; mkdir -p $ICONSET
sips -s format png -z 1024 1024 $HERE/Resources/icon.png --out $OUT/icon1024.png >/dev/null
for s in 16 32 128 256 512; do
  sips -z $s $s $OUT/icon1024.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) $OUT/icon1024.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $ICONSET -o $RES/AppIcon.icns
rm -rf $ICONSET $OUT/icon1024.png

cat > $APP/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>GwentReimagined</string>
  <key>CFBundleDisplayName</key><string>GwentReimagined</string>
  <key>CFBundleIdentifier</key><string>io.github.grechucia.gwentreimagined</string>
  <key>CFBundleExecutable</key><string>GwentReimagined</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>pl</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.card-games</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Gra fanowska</string>
</dict></plist>
PLIST
codesign --force --deep --sign - $APP
touch $APP
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f $APP
print "✓ $APP ($(du -sh $APP | cut -f1))"
[[ $1 == --run ]] && open $APP
true
