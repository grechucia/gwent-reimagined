#!/bin/zsh
# Builds android/build/GwentReimagined.apk without Gradle: aapt2 -> javac -> d8 -> zipalign -> apksigner.
# Usage: ./android/build-android.sh [--install]   (--install also installs the APK on a running emulator/device)
set -e
HERE=${0:A:h}
GAME=${HERE:h}
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
BT=$SDK/build-tools/36.0.0
JAR=$SDK/platforms/android-36/android.jar
OUT=$HERE/build
MAC=$GAME/native/build/GwentReimagined.app/Contents/Resources
print "» GwentReimagined: building Android APK"
mkdir -p $OUT
[[ -d $MAC ]] || $GAME/native/build.sh

print "» Assets"
mkdir -p $OUT/assets
rsync -a --delete $MAC/game/ $OUT/assets/game/
rsync -a --delete $GAME/native/Resources/data/ $OUT/assets/data/
cp $GAME/LICENSE $GAME/NOTICE.md $OUT/assets/

print "» Resources"
rm -rf $OUT/gen $OUT/classes $OUT/dex; mkdir -p $OUT/gen $OUT/classes $OUT/dex
$BT/aapt2 compile --dir $HERE/res -o $OUT/res.zip
$BT/aapt2 link -o $OUT/base.apk -I $JAR --manifest $HERE/AndroidManifest.xml -A $OUT/assets $OUT/res.zip \
  --java $OUT/gen -0 mp3 -0 ogg -0 jpg -0 png -0 ttf -0 json

print "» Compiling Java"
javac -nowarn -encoding UTF-8 --release 17 -classpath $JAR -d $OUT/classes $(find $HERE/src $OUT/gen -name '*.java')
$BT/d8 --release --lib $JAR --min-api 26 --output $OUT/dex $(find $OUT/classes -name '*.class')

print "» Packaging"
cp $OUT/base.apk $OUT/unsigned.apk
(cd $OUT/dex && zip -q $OUT/unsigned.apk classes.dex)
$BT/zipalign -f -p 4 $OUT/unsigned.apk $OUT/aligned.apk
if [[ ! -f $OUT/debug.keystore ]]; then
  keytool -genkeypair -keystore $OUT/debug.keystore -storepass android -keypass android -alias gwent \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Gwent Reimagined" >/dev/null 2>&1
fi
$BT/apksigner sign --ks $OUT/debug.keystore --ks-pass pass:android --key-pass pass:android --out $OUT/GwentReimagined.apk $OUT/aligned.apk
rm -f $OUT/unsigned.apk $OUT/aligned.apk $OUT/base.apk
print "✓ $OUT/GwentReimagined.apk ($(du -sh $OUT/GwentReimagined.apk | cut -f1))"
if [[ $1 == --install ]]; then $SDK/platform-tools/adb install -r $OUT/GwentReimagined.apk; fi
