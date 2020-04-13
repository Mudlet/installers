#!/bin/bash

# abort script if any command fails
set -e

release=""

# find out if we do a release build
while getopts ":r:" o; do
  if [ "${o}" = "r" ]; then
    release="${OPTARG}"
    version="${OPTARG}"
  else
    echo "Unknown option -${o}"
    exit 1
  fi
done
shift $((OPTIND-1))
if [ -z "${release}" ]; then
  version="${1}"
fi

# setup linuxdeployqt binary if not found
if [ "$(getconf LONG_BIT)" = "64" ]; then
  if [[ ! -e linuxdeployqt.AppImage ]]; then
      # download prepackaged linuxdeployqt. Doesn't seem to have a "latest" url yet
      echo "linuxdeployqt not found - downloading one."
      wget -O linuxdeployqt.AppImage https://github.com/probonopd/linuxdeployqt/releases/download/continuous/linuxdeployqt-continuous-x86_64.AppImage
      chmod +x linuxdeployqt.AppImage
  fi
else
  echo "32bit Linux is currently not supported."
  exit 2
fi

# clean up the build/ folder
rm -rf build/
mkdir build

# delete previous appimage as well since we need to regenerate it twice
rm -f Mudlet*.AppImage

# move the binary up to the build folder (they differ between qmake and cmake,
# so we use find to find the binary
find source/build/ -iname mudlet -type f -exec cp '{}' build/ \;
# get mudlet-lua in there as well so linuxdeployqt bundles it
cp -rf source/src/mudlet-lua build/
# and the dictionary files in case the user system doesn't have them (at a known
# place)
cp source/src/*.dic build/
cp source/src/*.aff build/
# and the .desktop file so linuxdeployqt can pilfer it for info
cp source/mudlet{.desktop,.png,.svg} build/


cp -r source/3rdparty/lcf build/

# now copy Lua modules we need in
# this should be improved not to be hardcoded
mkdir -p build/lib/luasql

cp source/3rdparty/discord/rpc/lib/libdiscord-rpc.so build/lib/

for lib in lfs rex_pcre luasql/sqlite3 zip lua-utf8 yajl
do
  found=0
  for path in $(lua -e "print(package.cpath)" | tr ";" "\n")
  do
    changed_path=${path/\?/${lib}};
    if [ -e "${changed_path}" ]; then
      cp -rL "${changed_path}" build/lib/${lib}.so
      found=1
    fi
  done
  if [ "${found}" -ne "1" ]; then
    echo "Missing dependency ${lib}, aborting."
    exit 1
  fi
done

# extract linuxdeployqt since some environments (like travis) don't allow FUSE
./linuxdeployqt.AppImage --appimage-extract

# a hack to get the Chinese input text plugin for Qt from the Ubuntu package into a location
# linuxdeployqt will understand
sudo cp /usr/lib/x86_64-linux-gnu/qt5/plugins/platforminputcontexts/libfcitxplatforminputcontextplugin.so \
        /opt/qt512/plugins/platforminputcontexts/libfcitxplatforminputcontextplugin.so || exit

# Bundle libssl.so so Mudlet works on platforms that only distribute
# OpenSSL 1.1
cp -L /usr/lib/x86_64-linux-gnu/libssl.so* \
      build/lib/
cp -L /lib/x86_64-linux-gnu/libssl.so* \
      build/lib/

echo "Generating AppImage"
./squashfs-root/AppRun ./build/mudlet -appimage \
  -executable=build/lib/rex_pcre.so -executable=build/lib/zip.so \
  -executable=build/lib/luasql/sqlite3.so -executable=build/lib/yajl.so \
  -executable=build/lib/libssl.so.1.1 \
  -executable=build/lib/libssl.so.1.0.0 \
  -extra-plugins=texttospeech/libqttexttospeech_flite.so,texttospeech/libqttexttospeech_speechd.so,platforminputcontexts/libcomposeplatforminputcontextplugin.so,platforminputcontexts/libibusplatforminputcontextplugin.so,platforminputcontexts/libfcitxplatforminputcontextplugin.so


# clean up extracted appimage
rm -rf squashfs-root/


if [ -z "${release}" ]; then
  output_name="Mudlet-${version}"
else
  output_name="Mudlet"
fi
mv Mudlet*.AppImage "$output_name.AppImage"
