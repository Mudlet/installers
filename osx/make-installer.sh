#!/bin/bash

# abort script if any command fails
set -e

# set path to find macdeployqt
PATH=/usr/local/opt/qt5/bin:$PATH

cd source/build

# install installer dependencies
brew update
BREWS="sqlite3 lua@5.1 node wget"
for i in $BREWS; do
  brew outdated | grep -q $i && brew upgrade $i
done
for i in $BREWS; do
  brew list | grep -q $i || brew install $i
done
if [ ! -f "macdeployqtfix.py" ]; then
  wget https://raw.githubusercontent.com/aurelien-rainone/macdeployqtfix/master/macdeployqtfix.py
fi
echo "Need root permissions to install lua rocks..."
sudo luarocks-5.1 install LuaFileSystem
sudo luarocks-5.1 install lrexlib-pcre
sudo luarocks-5.1 install LuaSQL-SQLite3 SQLITE_DIR=/usr/local/opt/sqlite

npm install -g appdmg

# Bundle in Qt libraries
macdeployqt Mudlet.app

# fix unfinished deployment of macdeployqt
python macdeployqtfix.py Mudlet.app/Contents/MacOS/Mudlet /usr/local/Cellar/qt5/5.8.0_1/

# Bundle in dynamically loaded libraries
cp "/usr/local/lib/lua/5.1/lfs.so" Mudlet.app/Contents/MacOS
cp "/usr/local/lib/lua/5.1/rex_pcre.so" Mudlet.app/Contents/MacOS
# rex_pcre has to be adjusted to load libcpre from the same location
python macdeployqtfix.py Mudlet.app/Contents/MacOS/rex_pcre.so /usr/local/Cellar/qt5/5.8.0_1/
cp -r "/usr/local/lib/lua/5.1/luasql" Mudlet.app/Contents/MacOS

# Edit some nice plist entries, don't fail if entries already exist
/usr/libexec/PlistBuddy -c "Add CFBundleName string Mudlet" Mudlet.app/Contents/Info.plist || true
/usr/libexec/PlistBuddy -c "Add CFBundleDisplayName string Mudlet" Mudlet.app/Contents/Info.plist || true

# Generate final .dmg
cd ../..
rm -f ~/Desktop/Mudlet.dmg

# If you don't get a background image on Sierra, either upgrade
# or apply a workaround from https://github.com/LinusU/node-appdmg/issues/121
appdmg appdmg/mudlet-appdmg.json ~/Desktop/Mudlet.dmg
