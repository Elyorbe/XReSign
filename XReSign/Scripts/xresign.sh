# !/bin/bash

#
#  xresign.sh
#  XReSign
#
#  Copyright © 2017 xndrs. All rights reserved.
#

usage="Usage example:
$(basename "$0") -s path -c certificate [-p path] [-b identifier]

where:
-s  path to ipa file which you want to sign/resign
-c  signing certificate Common Name from Keychain
-p  path to mobile provisioning file (Optional)
-b  Bundle identifier (Optional)"


while getopts s:c:p:b: option
do
    case "${option}"
    in
      s) SOURCEIPA=${OPTARG}
         ;;
      c) DEVELOPER=${OPTARG}
         ;;
      p) MOBILEPROV=${OPTARG}
         ;;
      b) BUNDLEID=${OPTARG}
         ;;
     \?) echo "invalid option: -$OPTARG" >&2
         echo "$usage" >&2
         exit 1
         ;;
      :) echo "missing argument for -$OPTARG" >&2
         echo "$usage" >&2
         exit 1
         ;;
    esac
done


echo "Start resign the app..."

OUTDIR=$(dirname "${SOURCEIPA}")
TMPDIR="$OUTDIR/tmp"
APPDIR="$TMPDIR/app"


mkdir -p "$APPDIR"
unzip -qo "$SOURCEIPA" -d "$APPDIR"

APPLICATION=$(ls "$APPDIR/Payload/")


if [ -z "${MOBILEPROV}" ]; then
    echo "Sign process using existing provisioning profile from payload"
else
    echo "Coping provisioning profile into application payload"
    cp "$MOBILEPROV" "$APPDIR/Payload/$APPLICATION/embedded.mobileprovision"
fi

echo "Extract entitlements from mobileprovisioning"
security cms -D -i "$APPDIR/Payload/$APPLICATION/embedded.mobileprovision" > "$TMPDIR/provisioning.plist"
/usr/libexec/PlistBuddy -x -c 'Print:Entitlements' "$TMPDIR/provisioning.plist" > "$TMPDIR/entitlements.plist"


if [ -z "${BUNDLEID}" ]; then
    echo "Sign process using existing bundle identifier from payload"
else
    echo "Changing BundleID with : $BUNDLEID"
    /usr/libexec/PlistBuddy -c "Set:CFBundleIdentifier $BUNDLEID" "$APPDIR/Payload/$APPLICATION/Info.plist"
fi


echo "Get list of components and resign with certificate: $DEVELOPER"
find -d "$APPDIR" \( -name "*.app" -o -name "*.appex" -o -name "*.dylib" \) > "$TMPDIR/components.txt"


echo "Get list of frameworks"
framework_dirs=$(find -d "$APPDIR" \( -name "*.framework" \))

for framework_dir in ${framework_dirs[*]}
do
    echo "Signing framework $framework_dir"
    framework_parent_dir=$(dirname "$framework_dir")
    old_signature="$framework_dir/_CodeSignature"
    rm -rv $old_signature
    /usr/bin/codesign -d --entitlements - "$framework_dir" > "$framework_parent_dir/entitlements.plist"
    /usr/bin/codesign -f -s "$DEVELOPER" --entitlements "$framework_parent_dir/entitlements.plist" "$framework_dir"
    rm -rv "$framework_parent_dir/entitlements.plist"
done

var=$((0))
while IFS='' read -r line || [[ -n "$line" ]]; do
	if [[ ! -z "${BUNDLEID}" ]] && [[ "$line" == *".appex"* ]]; then
	   echo "Changing .appex BundleID with : $BUNDLEID.extra$var"
	   /usr/libexec/PlistBuddy -c "Set:CFBundleIdentifier $BUNDLEID.extra$var" "$line/Info.plist"
	   var=$((var+1))
	fi    
    /usr/bin/codesign --continue -f -s "$DEVELOPER" --entitlements "$TMPDIR/entitlements.plist" "$line"
done < "$TMPDIR/components.txt"


echo "Creating the signed ipa"
cd "$APPDIR"
filename=$(basename "$APPLICATION")
filename="${filename%.*}-xresign.ipa"
zip -qr "../$filename" *
cd ..
mv "$filename" "$OUTDIR"


echo "Clear temporary files"
rm -rf "$APPDIR"
rm "$TMPDIR/components.txt"
rm "$TMPDIR/provisioning.plist"
rm "$TMPDIR/entitlements.plist"

echo "XReSign FINISHED"
