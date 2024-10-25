#!/bin/bash

# abort script if any command fails
set -e
shopt -s expand_aliases

# extract program name for message
pgm=$(basename "$0")

release=""
ptb=""

BUILD_DIR="source/build"
SOURCE_DIR="source"

# Set HOMEBREW_PREFIX, HOMEBREW_CELLAR, add correct paths to PATH
 eval "$(brew shellenv)"

# QT_ROOT_DIR set by install-qt action.
if [ -n "$QT_ROOT_DIR" ]; then
    QT_DIR="$QT_ROOT_DIR"
else
    # Check if QT_DIR is already set
    if [ -z "$QT_DIR" ]; then
        echo "QT_DIR not set."
        exit 1
    fi
fi

if [ -n "$GITHUB_REPOSITORY" ] ; then
  BUILD_DIR=$BUILD_FOLDER
  SOURCE_DIR=$GITHUB_WORKSPACE
fi

# find out if we do a release or ptb build
while getopts ":pr:" option; do
  if [ "${option}" = "r" ]; then
    release="${OPTARG}"
    shift $((OPTIND-1))
  elif [ "${option}" = "p" ]; then
    ptb="yep"
    shift $((OPTIND-1))
  else
    echo "Unknown option -${option}"
    exit 1
  fi
done

# Check if macdeployqt is in the path
if ! command -v macdeployqt &> /dev/null
then
    echo "Error: macdeployqt could not be found in the PATH."
    exit 1
fi

cd "${BUILD_DIR}"

# get the app to package
app=$(basename "${1}")

if [ -z "$app" ]; then
  echo "No Mudlet app folder to package given."
  echo "Usage: $pgm <Mudlet app folder to package>"
  exit 2
fi
app=$(find . -iname "${app}" -type d)
if [ -z "${app}" ]; then
  echo "error: couldn't determine location of the ./app folder"
  exit 1
fi

echo "Deploying ${app}"

# install installer dependencies, except on Github where they're preinstalled at this point
if [ -z "$GITHUB_REPOSITORY" ]; then
  luarocks-5.1 --local install LuaFileSystem
  luarocks-5.1 --local install lrexlib-pcre
  luarocks-5.1 --local install LuaSQL-SQLite3 SQLITE_DIR=${HOMEBREW_PREFIX}/opt/sqlite
  # Although it is called luautf8 here it builds a file called lua-utf8.so:
  luarocks-5.1 --local install luautf8
  luarocks-5.1 --local install lua-yajl
  # This is the Brimworks one (same as lua-yajl) note the hyphen, the one without
  # is the Kelper project one which has the, recently (2020), troublesome
  # dependency on zziplib (libzzip), however to avoid clashes in the field
  # it installs itself in brimworks subdirectory which must be accomodated
  # in where we put it and how we "require" it:
  luarocks-5.1 --local install lua-zip
fi

if [ ! -f "macdeployqtfix.py" ]; then
  wget https://raw.githubusercontent.com/arl/macdeployqtfix/master/macdeployqtfix.py
fi

npm install -g appdmg

# copy in 3rd party framework first so there is the chance of things getting fixed if it doesn't exist
if [ ! -d "${app}/Contents/Frameworks/Sparkle.framework" ]; then
  mkdir -p "${app}/Contents/Frameworks/Sparkle.framework"
  cp -R "${SOURCE_DIR}/3rdparty/cocoapods/Pods/Sparkle/Sparkle.framework" "${app}/Contents/Frameworks"
fi

# Bundle in Qt libraries
echo "Running macdeployqt"
macdeployqt "${app}" $( [ -n "$DEBUG" ] && echo "-verbose=3" )

# fix unfinished deployment of macdeployqt
echo "Running macdeployqtfix"
python macdeployqtfix.py "${app}/Contents/MacOS/Mudlet" "${QT_DIR}" $( [ -n "$DEBUG" ] && echo "--verbose" )

# Bundle in dynamically loaded libraries
# These will be manually fixed up because macdeployqtfix is not really designed to handle individual libraries.
echo "Bundling dynamic libraries"
cp -v "${HOME}/.luarocks/lib/lua/5.1/lfs.so" "${app}/Contents/MacOS"
cp -v "${HOME}/.luarocks/lib/lua/5.1/rex_pcre.so" "${app}/Contents/MacOS"
# rex_pcre has to be adjusted to load libpcre from the same location
install_name_tool -change "${HOMEBREW_PREFIX}/opt/pcre/lib/libpcre.1.dylib" "@executable_path/../Frameworks/libpcre.1.dylib" "${app}/Contents/MacOS/rex_pcre.so"

cp -r "${HOME}/.luarocks/lib/lua/5.1/luasql" "${app}/Contents/MacOS"
cp -v ${HOMEBREW_PREFIX}/opt/sqlite/lib/libsqlite3.0.dylib  "${app}/Contents/Frameworks/"
install_name_tool -id  "@executable_path/../Frameworks/libsqlite3.0.dylib" "${app}/Contents/Frameworks/libsqlite3.0.dylib" 
# need to adjust sqlite3.lua manually as it is a level lower than expected...
install_name_tool -change "${HOMEBREW_PREFIX}/opt/sqlite/lib/libsqlite3.0.dylib" "@executable_path/../../Frameworks/libsqlite3.0.dylib" "${app}/Contents/MacOS/luasql/sqlite3.so"

cp -v "${HOME}/.luarocks/lib/lua/5.1/lua-utf8.so" "${app}/Contents/MacOS"

# The lua-zip rock
mkdir "${app}/Contents/MacOS/brimworks"
cp -v "${HOME}/.luarocks/lib/lua/5.1/brimworks/zip.so" "${app}/Contents/MacOS/brimworks" 
install_name_tool -change "${HOMEBREW_PREFIX}/opt/libzip/lib/libzip.5.dylib" "@executable_path/../Frameworks/libzip.5.dylib" "${app}/Contents/MacOS/brimworks/zip.so"

cp -r "${SOURCE_DIR}/3rdparty/lcf" "${app}/Contents/MacOS"

cp -v "${HOME}/.luarocks/lib/lua/5.1/yajl.so" "${app}/Contents/MacOS"
# yajl has to be adjusted to load libyajl from the same location

if [ -n "$GITHUB_REPOSITORY" ] ; then
  cp -v "${VCPKG_ROOT}/packages/yajl_${TRIPLET}/lib/libyajl.2.dylib" "${app}/Contents/Frameworks/libyajl.2.dylib"
  install_name_tool -id "@executable_path/../Frameworks/libyajl.2.dylib" "${app}/Contents/Frameworks/libyajl.2.dylib"
  install_name_tool -change "${VCPKG_ROOT}/packages/yajl_${TRIPLET}/lib/libyajl.2.dylib" "@executable_path/../Frameworks/libyajl.2.dylib" "${app}/Contents/MacOS/yajl.so"
fi

cp -v "${SOURCE_DIR}/3rdparty/discord/rpc/lib/libdiscord-rpc.dylib" "${app}/Contents/Frameworks"

# End bundled libraries
echo "Done bundling libraries"

# Edit some nice plist entries, don't fail if entries already exist
if [ -z "${ptb}" ]; then
  /usr/libexec/PlistBuddy -c "Add CFBundleName string Mudlet" "${app}/Contents/Info.plist" || true
  /usr/libexec/PlistBuddy -c "Add CFBundleDisplayName string Mudlet" "${app}/Contents/Info.plist" || true
else
  /usr/libexec/PlistBuddy -c "Add CFBundleName string Mudlet PTB" "${app}/Contents/Info.plist" || true
  /usr/libexec/PlistBuddy -c "Add CFBundleDisplayName string Mudlet PTB" "${app}/Contents/Info.plist" || true
fi

if [ -z "${release}" ]; then
  stripped="${app#Mudlet-}"
  version="${stripped%.app}"
  shortVersion="${version%%-*}"
else
  version="${release}"
  shortVersion="${release}"
fi

/usr/libexec/PlistBuddy -c "Add CFBundleShortVersionString string ${shortVersion}" "${app}/Contents/Info.plist" || true
/usr/libexec/PlistBuddy -c "Add CFBundleVersion string ${version}" "${app}/Contents/Info.plist" || true

# Sparkle settings, see https://sparkle-project.org/documentation/customization/#infoplist-settings
if [ -z "${ptb}" ]; then
  /usr/libexec/PlistBuddy -c "Add SUFeedURL string https://feeds.dblsqd.com/MKMMR7HNSP65PquQQbiDIw/release/mac/${ARCH_DBLSQD}/appcast" "${app}/Contents/Info.plist" || true
else
  /usr/libexec/PlistBuddy -c "Add SUFeedURL string https://feeds.dblsqd.com/MKMMR7HNSP65PquQQbiDIw/public-test-build/mac/${ARCH_DBLSQD}/appcast" "${app}/Contents/Info.plist" || true
fi
/usr/libexec/PlistBuddy -c "Add SUEnableAutomaticChecks bool true" "${app}/Contents/Info.plist" || true
/usr/libexec/PlistBuddy -c "Add SUAllowsAutomaticUpdates bool true" "${app}/Contents/Info.plist" || true
/usr/libexec/PlistBuddy -c "Add SUAutomaticallyUpdate bool true" "${app}/Contents/Info.plist" || true

# Enable HiDPI support
/usr/libexec/PlistBuddy -c "Add NSPrincipalClass string NSApplication" "${app}/Contents/Info.plist" || true
/usr/libexec/PlistBuddy -c "Add NSHighResolutionCapable string true" "${app}/Contents/Info.plist" || true


# Associate Mudlet with .mpackage files
/usr/libexec/PlistBuddy -c "Add CFBundleDocumentTypes array" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add CFBundleDocumentTypes:0 dict" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add CFBundleDocumentTypes:0:CFBundleTypeName string Mudlet Package" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add CFBundleDocumentTypes:0:CFBundleTypeRole string Editor" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add CFBundleDocumentTypes:0:LSItemContentTypes array" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add CFBundleDocumentTypes:0:LSItemContentTypes:0 string com.mudlet.mpackage" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add UTExportedTypeDeclarations array" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add UTExportedTypeDeclarations:0 dict" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add UTExportedTypeDeclarations:0:UTTypeIdentifier string com.mudlet.mpackage" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add UTExportedTypeDeclarations:0:UTTypeDescription string Mudlet Package" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add UTExportedTypeDeclarations:0:UTTypeConformsTo array" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add UTExportedTypeDeclarations:0:UTTypeConformsTo:0 string public.data" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add UTExportedTypeDeclarations:0:UTTypeConformsTo:1 string public.zip" "${app}/Contents/Info.plist"

# Sign everything now that we're done modifying contents of the .app file
# Keychain is already setup in travis.osx.after_success.sh for us
if [ -n "$IDENTITY" ] && security find-identity | grep -q "$IDENTITY"; then
  codesign --deep --force -o runtime --sign "$IDENTITY" "${app}/Contents/Frameworks/Sparkle.framework/Versions/A/Resources/Autoupdate.app"
  codesign --deep --force -o runtime --sign "$IDENTITY" "${app}"
  echo "Validating codesigning worked with codesign -vv --deep-verify:"
  codesign -vv --deep-verify "${app}"
fi

# Generate final .dmg
cd ../../
rm -f ~/Desktop/[mM]udlet*.dmg

# Modify appdmg config file according to the app file to package
perl -pi -e "s|../source/build/.*Mudlet.*\\.app|${BUILD_DIR}/${app}|i" "${BUILD_DIR}/../installers/osx/appdmg/mudlet-appdmg.json"
# Update icons to the correct type
if [ -z "${ptb}" ]; then
  perl -pi -e "s|../source/src/icons/.*\\.icns|${SOURCE_DIR}/src/icons/mudlet_ptb.icns|i" "${BUILD_DIR}/../installers/osx/appdmg/mudlet-appdmg.json"
else
  if [ -z "${release}" ]; then
    perl -pi -e "s|../source/src/icons/.*\\.icns|${SOURCE_DIR}/src/icons/mudlet_dev.icns|i" "${BUILD_DIR}/../installers/osx/appdmg/mudlet-appdmg.json"
  else
    perl -pi -e "s|../source/src/icons/.*\\.icns|${SOURCE_DIR}/src/icons/mudlet.icns|i" "${BUILD_DIR}/../installers/osx/appdmg/mudlet-appdmg.json"
  fi
fi

# Last: build *.dmg file
appdmg "${BUILD_DIR}/../installers/osx/appdmg/mudlet-appdmg.json" "${HOME}/Desktop/$(basename "${app%.*}").dmg"
