#!/bin/bash

# abort script if any command fails
set -e
shopt -s expand_aliases

# enable temporary trace mode
set -x

# extract program name for message
pgm=$(basename "$0")

release=""
ptb=""

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

echo "release $release"
echo "ptb $ptb"
echo "1 ${1}"

# set path to find macdeployqt
PATH=/usr/local/opt/qt/bin:$PATH

cd source/build

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

# install installer dependencies
brew update
BREWS="sqlite3 lua@5.1 node wget luarocks"
for i in $BREWS; do
  brew outdated | grep -q "$i" && brew upgrade "$i"
done
for i in $BREWS; do
  brew list | grep -q "$i" || brew install "$i"
done
# create an alias to avoid the need to list the lua dir all the time
# we want to expand the subshell only once (it's only tmeporary anyways)
# shellcheck disable=2139
alias luarocks-5.1="luarocks --lua-dir='$(brew --prefix lua@5.1)'"
if [ ! -f "macdeployqtfix.py" ]; then
  wget https://raw.githubusercontent.com/aurelien-rainone/macdeployqtfix/master/macdeployqtfix.py
fi
luarocks-5.1 --local install LuaFileSystem
luarocks-5.1 --local install lrexlib-pcre
luarocks-5.1 --local install LuaSQL-SQLite3 SQLITE_DIR=/usr/local/opt/sqlite
luarocks-5.1 --local install luautf8
luarocks-5.1 --local install lua-yajl

# Ensure Homebrew's npm is used, instead of an outdated one
PATH=/usr/local/bin:$PATH
npm install -g appdmg

# copy in 3rd party framework first so there is the chance of things getting fixed if it doesn't exist
if [ ! -d "${app}/Contents/Frameworks/Sparkle.framework" ]; then
  cp -r "../3rdparty/cocoapods/Pods/Sparkle/Sparkle.framework" "${app}/Contents/Frameworks"
fi
# Bundle in Qt libraries
macdeployqt "${app}"

# fix unfinished deployment of macdeployqt
python macdeployqtfix.py "${app}/Contents/MacOS/Mudlet" "/usr/local/opt/qt/bin"

# Bundle in dynamically loaded libraries
cp "${HOME}/.luarocks/lib/lua/5.1/lfs.so" "${app}/Contents/MacOS"

cp "${HOME}/.luarocks/lib/lua/5.1/rex_pcre.so" "${app}/Contents/MacOS"
# rex_pcre has to be adjusted to load libpcre from the same location
python macdeployqtfix.py "${app}/Contents/MacOS/rex_pcre.so" "/usr/local/opt/qt/bin"

cp -r "${HOME}/.luarocks/lib/lua/5.1/luasql" "${app}/Contents/MacOS"
cp /usr/local/opt/sqlite/lib/libsqlite3.0.dylib  "${app}/Contents/Frameworks/"
# sqlite3 has to be adjusted to load libsqlite from the same location
python macdeployqtfix.py "${app}/Contents/Frameworks/libsqlite3.0.dylib" "/usr/local/opt/qt/bin"
# need to adjust sqlite3.lua manually as it is a level lower than expected...
install_name_tool -change "/usr/local/opt/sqlite/lib/libsqlite3.0.dylib" "@executable_path/../../Frameworks/libsqlite3.0.dylib" "${app}/Contents/MacOS/luasql/sqlite3.so"

cp "${HOME}/.luarocks/lib/lua/5.1/lua-utf8.so" "${app}/Contents/MacOS"

cp "../3rdparty/discord/rpc/lib/libdiscord-rpc.dylib" "${app}/Contents/Frameworks"

if [ -d "../3rdparty/lua_code_formatter" ]; then
  # we renamed lcf at some point
  LCF_NAME="lua_code_formatter"
else
  LCF_NAME="lcf"
fi
cp -r "../3rdparty/${LCF_NAME}" "${app}/Contents/MacOS"
if [ "${LCF_NAME}" != "lcf" ]; then
  mv "${app}/Contents/MacOS/${LCF_NAME}" "${app}/Contents/MacOS/lcf"
fi

cp "${HOME}/.luarocks/lib/lua/5.1/yajl.so" "${app}/Contents/MacOS"
# yajl has to be adjusted to load libyajl from the same location
python macdeployqtfix.py "${app}/Contents/MacOS/yajl.so" "/usr/local/opt/qt/bin"

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

echo "release ${release}"
echo "version ${version}"
echo "shortVersion ${shortVersion}"

/usr/libexec/PlistBuddy -c "Add CFBundleShortVersionString string ${shortVersion}" "${app}/Contents/Info.plist" || true
/usr/libexec/PlistBuddy -c "Add CFBundleVersion string ${version}" "${app}/Contents/Info.plist" || true

# Sparkle settings, see https://sparkle-project.org/documentation/customization/#infoplist-settings
if [ -z "${ptb}" ]; then
  /usr/libexec/PlistBuddy -c "Add SUFeedURL string https://feeds.dblsqd.com/MKMMR7HNSP65PquQQbiDIw/release/mac/x86_64/appcast" "${app}/Contents/Info.plist" || true
else
  /usr/libexec/PlistBuddy -c "Add SUFeedURL string https://feeds.dblsqd.com/MKMMR7HNSP65PquQQbiDIw/public-test-build/mac/x86_64/appcast" "${app}/Contents/Info.plist" || true
fi
/usr/libexec/PlistBuddy -c "Add SUEnableAutomaticChecks bool true" "${app}/Contents/Info.plist" || true
/usr/libexec/PlistBuddy -c "Add SUAllowsAutomaticUpdates bool true" "${app}/Contents/Info.plist" || true
/usr/libexec/PlistBuddy -c "Add SUAutomaticallyUpdate bool true" "${app}/Contents/Info.plist" || true

# Sign everything now that we're done modifying contents of the .app file
# Keychain is already setup in travis.osx.after_success.sh for us
if [ -n "$IDENTITY" ] && security find-identity | grep -q "$IDENTITY"; then
  codesign --deep -s "$IDENTITY" "${app}"
fi

# Generate final .dmg
cd ../../
rm -f ~/Desktop/[mM]udlet*.dmg

pwd
# Modify appdmg config file according to the app file to package
perl -pi -e "s|build/.*Mudlet.*\\.app|build/${app}|i" appdmg/mudlet-appdmg.json

# Last: build *.dmg file
appdmg appdmg/mudlet-appdmg.json "${HOME}/Desktop/$(basename "${app%.*}").dmg"
