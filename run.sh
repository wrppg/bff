#!/usr/bin/env bash
### this script should be after checkout
set -e -o pipefail
set -x
APP_NAME=$(awk -F '/' '{print $2}' <<< "$1")

curl -sSLf -o app_record.txt https://raw.githubusercontent.com/wrppg/bff/refs/heads/main/app_record.txt

SELECT_REC=$(awk '/'"${APP_NAME}"'/ {print $0}' app_record.txt)
FLAV=$(awk '{print $NF}' <<< "${SELECT_REC}" | awk -F ':' '{print $2}')
echo "FLAV=${FLAV}" >> $GITHUB_ENV

### 1. Change versionCode To Max INT
BUILD_GRADLE=$(find app -maxdepth 1 \( -name 'build.gradle' -or -name 'build.gradle.kts' \) -print -quit)
[ -z "${BUILD_GRADLE}" ] && "❌ No BUILD_GRADLE." && exit 99

## Do this because some use ```versionName = versionCode.toString()``` ###
VER_CODE=$(awk '/^\s*versionCode( |=)/ {print $NF; exit}' $BUILD_GRADLE)
sed -E "/^\s*versionName/s/versionCode\.toString\(\)/\"${VER_CODE}\"/" -i $BUILD_GRADLE
##
sed -E '/^\s*versionCode( |=)/s/[0-9]+$/2147483647/' -i $BUILD_GRADLE

### 2. patch package name
OLD_APP_ID=$(awk -F '"' '/applicationId( |=)/ {print $2; exit}' $BUILD_GRADLE)
APP_NAME="${APP_NAME// /}"
NEW_APP_ID="bff.${APP_NAME,,}"

[ -z "${OLD_APP_ID}" ] && echo "❌ No OLD_APP_ID" && exit 99
[ -z "${APP_NAME}" ] && echo "❌ No APP_NAME" && exit 99

sed -E "/applicationId( |=)/s|${OLD_APP_ID}|${NEW_APP_ID}|" -i $BUILD_GRADLE

## Patch shortcuts package name
if [ -f app/src/main/res/xml*/shortcuts.xml ]; then
	sed "s/android:targetPackage=\"${OLD_APP_ID}\"/android:targetPackage=\"${NEW_APP_ID}\"/" -i app/src/main/res/xml*/shortcuts.xml
fi

echo "APP_NAME=${APP_NAME}" >> $GITHUB_ENV
echo "VER_CODE=${VER_CODE}" >> $GITHUB_ENV

### 3. patch permission name
## Find Permissions
PERM=$(find app -type f -name 'AndroidManifest.xml' -exec yq --xml-attribute-prefix "+@" -p=xml -o=json {} \; \
| jq -r '.manifest.permission | (if type=="array" then . else [.] end)[]["+@android:name"] | select(length > 0)' | sort -u)

## Build permsission pettern
PERM_EXPR=$(tr '\n' '|' <<< "${PERM}" | sed -E 's,\|$,,')
PERM_EXPR=$(sed -E -e '/^[[:space:]]+$/d' -e '/^$/d' -e '/\$\{.*\}/d' <<< "${PERM_EXPR}") # Ignore placeholder app id name

## Patch permission / uses-permission in XML
if ! [ -z "${PERM_EXPR}" ]; then
	# find app/ -type f -name '*.xml' -exec sed -E "s/${PERM_EXPR}/${NEW_APP_ID}/g" -i {} +
	find app/ -type f -name '*.xml' -exec sed -E "s/(${PERM_EXPR})/_\1/g" -i {} +
fi


### 4. patch source
git clone https://github.com/wrppg/bff.git bff
PATCH_FILE=$(find bff/ -type f -iname "patch-${APP_NAME}.y*ml" -print -quit)
# case "$1" in
# 	*Inure*)
# 		PATCH_FILE=$(find bff/ -type f -iname 'patch-Inure.y*ml' -print -quit)
# 		;;
# 	*Netguard*)
# 		PATCH_FILE=$(find bff/ -type f -iname 'patch-Netguard.y*ml' -print -quit)
# 		;;
# 	*) unset PATCH_FILE ;;
# esac

if ! [ -z "${PATCH_FILE}" ]; then
	curl -Lf https://github.com/ast-grep/ast-grep/releases/download/0.39.4/app-x86_64-unknown-linux-gnu.zip -o ast-grep.zip
	[ $? -ne 0 ] && echo "❌ Error when downloading ast-grep." && exit 99
	unzip ast-grep.zip
	chmod +x ./ast-grep ./sg
	./ast-grep scan --rule "${PATCH_FILE}" --update-all app
fi

### 5. Extra setup
function RootActivityLauncher_Extra_Setup {
	# API_LEVEL=$((curl -sLf https://raw.githubusercontent.com/zacharee/RootActivityLauncher/refs/heads/master/app/build.gradle.kts \
	# 	|| curl -sLf https://raw.githubusercontent.com/zacharee/RootActivityLauncher/refs/heads/master/app/build.gradle) \
	# 	| awk '/^\s*compileSdk( |=)/ {print $NF; exit}')
	
 	API_LEVEL=$(awk '/^\s*compileSdk( |=)/ {print $NF; exit}' \
  	$(find app -maxdepth 1 \( -name 'build.gradle' -or -name 'build.gradle.kts' \) -print -quit))
	
 	[[ "${API_LEVEL}" =~ ^[0-9]+$ ]] || { echo '❌ Invalid API_LEVEL'; exit 99; }

	TARGET_DIR="$ANDROID_SDK_ROOT/platforms/android-${API_LEVEL}"

	mkdir -p "$TARGET_DIR" || { echo "Failed to create directory $TARGET_DIR"; exit 99; }

	## Download the modified android.jar from Reginer/aosp-android-jar
	curl -sSLf -o "$TARGET_DIR/android.jar" "https://github.com/Reginer/aosp-android-jar/raw/refs/heads/main/android-${API_LEVEL}/android.jar"
	[[ $? -ne 0 ]] && exit 99
	echo "android.jar downloaded successfully."
}

function NativeAlphaForAndroid_Extra_Setup {
	cp app/src/main/AndroidManifest.xml app/src/main/AndroidManifest_original.xml
}

function NetGuard_Extra_Setup {
	set +x
	echo "${KEYSTORE}" | base64 -d > keystore.jks
 	cp keystore.jks app/keystore.jks
	echo "storeFile=keystore.jks" >> keystore.properties
	echo "storePassword=${SIGNING_STORE_PASSWORD}" >> keystore.properties
	echo "keyAlias=${SIGNING_KEY_ALIAS}" >> keystore.properties
	echo "keyPassword=${SIGNING_KEY_PASSWORD}" >> keystore.properties
 	set -x
}

## Run extra setup
${APP_NAME}_Extra_Setup || echo '✅ No extra Setup for this app.'

# case "$1" in
#     *RootActivityLauncher*)
#         RootActivityLauncher_Extra_Setup
#         ;;
#     *NativeAlphaForAndroid*)
#         NativeAlphaForAndroid_Extra_Setup
#         ;;
#     *NetGuard*)
#         NetGuard_Extra_Setup
#         ;;
#     *) echo '✅ No extra Setup for this app.' ;;
# esac

### X. Continue next workflow step...
