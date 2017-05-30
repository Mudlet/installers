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
# git fetch
# git checkout release_30

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
    cp /usr/lib/x86_64-linux-gnu/lua/5.1/lfs.so                            ./build/lib
    cp /usr/lib/x86_64-linux-gnu/lua/5.1/rex_pcre.so                       ./build/lib
    mkdir                                                                  ./build/lib/luasql
    cp /usr/lib/x86_64-linux-gnu/lua/5.1/luasql/sqlite3.so                 ./build/lib/luasql
    cp /usr/lib/x86_64-linux-gnu/lua/5.1/zip.so                            ./build/lib
    # patch zip.so so it loads libzzip
    patchelf --set-rpath "$ORIGIN" ./build/lib/zip.so
    cp /usr/lib/x86_64-linux-gnu/libzzip-0.so.13                           ./build/lib
    # mp3 support for sounds 
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstflump3dec.so         ./build/lib
    cp /lib/x86_64-linux-gnu/libz.so.1                                     ./build/lib
    cp /lib/x86_64-linux-gnu/libpcre.so.3                                  ./build/lib
     
    # gstreamer bulk include. This needs to have the video stuff pruned... 
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstadder.so             ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstalsa.so              ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstapp.so               ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstaudioconvert.so      ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstaudiorate.so         ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstaudioresample.so     ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstaudiotestsrc.so      ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstcdparanoia.so        ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstcoreelements.so      ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstcoreelements.so      ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstcoreindexers.so      ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstdecodebin.so         ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstdecodebin2.so        ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstencodebin.so         ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstffmpegcolorspace.so  ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstflump3dec.so         ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstgdp.so               ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstgio.so               ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstlibvisual.so         ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstnice010.so           ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstogg.so               ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstpango.so             ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstplaybin.so           ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstplaybin.so           ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstpulse.so             ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstsubparse.so          ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgsttcp.so               ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgsttheora.so            ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgsttypefindfunctions.so ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstvideorate.so         ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstvideoscale.so        ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstvideotestsrc.so      ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstvolume.so            ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstvorbis.so            ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstximagesink.so        ./build/lib
    # cp /usr/lib/x86_64-linux-gnu/gstreamer-0.10/libgstxvimagesink.so       ./build/lib
else
  cp /usr/lib/i386-linux-gnu/lua/5.1/lfs.so                            ./build/lib
  cp /usr/lib/i386-linux-gnu/lua/5.1/rex_pcre.so                       ./build/lib
  mkdir                                                                ./build/lib/luasql
  cp /usr/lib/i386-linux-gnu/lua/5.1/luasql/sqlite3.so                 ./build/lib/luasql
  cp /usr/lib/i386-linux-gnu/lua/5.1/zip.so                            ./build/lib
  # patch zip.so so it loads libzzip
  patchelf --set-rpath "$ORIGIN" ./build/lib/zip.so
  cp /usr/lib/i386-linux-gnu/libzzip-0.so.13                           ./build/lib
  # mp3 support for sounds 
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstflump3dec.so         ./build/lib
  cp /lib/i386-linux-gnu/libz.so.1                                     ./build/lib
  cp /lib/i386-linux-gnu/libpcre.so.3                                  ./build/lib
   
  # gstreamer bulk include. This needs to have the video stuff pruned. ..
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstadder.so             ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstalsa.so              ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstapp.so               ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstaudioconvert.so      ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstaudiorate.so         ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstaudioresample.so     ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstaudiotestsrc.so      ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstcdparanoia.so        ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstcoreelements.so      ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstcoreelements.so      ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstcoreindexers.so      ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstdecodebin.so         ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstdecodebin2.so        ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstencodebin.so         ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstffmpegcolorspace.so  ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstflump3dec.so         ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstgdp.so               ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstgio.so               ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstlibvisual.so         ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstnice010.so           ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstogg.so               ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstpango.so             ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstplaybin.so           ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstplaybin.so           ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstpulse.so             ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstsubparse.so          ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgsttcp.so               ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgsttheora.so            ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgsttypefindfunctions.so ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstvideorate.so         ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstvideoscale.so        ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstvideotestsrc.so      ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstvolume.so            ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstvorbis.so            ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstximagesink.so        ./build/lib
  # cp /usr/lib/i386-linux-gnu/gstreamer-0.10/libgstxvimagesink.so       ./build/lib 
fi

echo "Regenerating AppImage to include Lua C and GStreamer modules"
# and regenerate (https://github.com/probonopd/linuxdeployqt/issues/67#issuecomment-279211530)
./linuxdeployqt.AppImage ./build/mudlet -appimage
