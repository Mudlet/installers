#!/bin/bash

# abort script if any command fails
set -e

START_DIRECTORY=$(pwd)

# setup linuxdeployqt binary if not found
if [[ ! -e linuxdeployqt.AppImage ]]; then
  if [ "$(getconf LONG_BIT)" = "64" ]
  then
      # download prepackaged linuxdeployqt. Doesn't seem to have a "latest" url yet
      echo "linuxdeployqt not found - downloading one."
      wget -O linuxdeployqt.AppImage https://github.com/probonopd/linuxdeployqt/releases/download/continuous/linuxdeployqt-continuous-x86_64.AppImage
      chmod +x linuxdeployqt.AppImage
  else
    echo "linuxdeployqt not found - making one."
    rm -rf patchelf/ linuxdeployqt/
    sudo rm -f /usr/local/bin/appimagetool

    git clone --depth=1 https://github.com/NixOS/patchelf.git
    cd patchelf
    bash ./bootstrap.sh
    ./configure
    make -j "$(nproc)"
    sudo make install

    cd "${START_DIRECTORY}"
    sudo wget -c "https://github.com/probonopd/AppImageKit/releases/download/continuous/appimagetool-i686.AppImage" -O /usr/local/bin/appimagetool
    sudo chmod a+x /usr/local/bin/appimagetool

    git clone --depth=50 https://github.com/probonopd/linuxdeployqt.git
    cd linuxdeployqt/
    # build currently broken, use latest that works
    git checkout c21b17174de603e6be14ef719c20101d1ccfb87e
    qmake linuxdeployqt.pro
    make -j "$(nproc)"

    mkdir -p linuxdeployqt.AppDir/usr/bin/
    cp /usr/local/bin/patchelf linuxdeployqt.AppDir/usr/bin/
    cp /usr/local/bin/appimagetool linuxdeployqt.AppDir/usr/bin/
    find linuxdeployqt.AppDir/
    export VERSION=continuous
    cp ./linuxdeployqt/linuxdeployqt linuxdeployqt.AppDir/usr/bin/
    ./linuxdeployqt/linuxdeployqt linuxdeployqt.AppDir/linuxdeployqt.desktop -appimage
    cp linuxdeployqt-continuous-Intel_80386.AppImage "${START_DIRECTORY}/linuxdeployqt.AppImage"
  fi
fi

# Retrieve latest source code, keep history as it's useful to edit sometimes
if [ ! -d "source" ]; then
  git clone https://github.com/Mudlet/Mudlet.git source
fi

# In case Mudlet source already exists, update it
cd "${START_DIRECTORY}"
cd source/
git pull

# Switch to release banrch
git fetch
git checkout release_30

cd src/

# Compile using all available cores
qmake
make -j "$(nproc)"

# go up to the root folder and clean up the build/ folder
cd ../../
rm -rf build/
mkdir build

# delete previous appimage as well since we need to regenerate it twice
rm -f Mudlet*.AppImage

# move the binary up to the build folder
cp source/src/mudlet build/
# get mudlet-lua in there as well so linuxdeployqt bundles it
cp -rf source/src/mudlet-lua build/
# and the .desktop file so linuxdeployqt can pilfer it for info
cp source/mudlet{.desktop,.png,.svg} build/

# first go at generation
echo "Generating AppImage for the first time"
./linuxdeployqt.AppImage ./build/mudlet -appimage

# now copy Lua modules we need in
# this should be improved not to be hardcoded
if [ "$(getconf LONG_BIT)" = "64" ]
    then
    cp /usr/lib/x86_64-linux-gnu/lua/5.1/lfs.so      ./build/lib
    cp /usr/lib/x86_64-linux-gnu/lua/5.1/rex_pcre.so ./build/lib
    mkdir ./build/lib/luasql
    cp /usr/lib/x86_64-linux-gnu/lua/5.1/luasql/sqlite3.so ./build/lib/luasql
    cp /usr/lib/x86_64-linux-gnu/lua/5.1/zip.so      ./build/lib
else
  cp /usr/lib/i386-linux-gnu/lua/5.1/lfs.so      ./build/lib
  cp /usr/lib/i386-linux-gnu/lua/5.1/rex_pcre.so ./build/lib
  mkdir ./build/lib/luasql
  cp /usr/lib/i386-linux-gnu/lua/5.1/luasql/sqlite3.so ./build/lib/luasql
  cp /usr/lib/i386-linux-gnu/lua/5.1/zip.so      ./build/lib
fi

echo "Regenerating AppImage to include Lua C modules"
# and regenerate (https://github.com/probonopd/linuxdeployqt/issues/67#issuecomment-279211530)
./linuxdeployqt.AppImage ./build/mudlet -appimage
