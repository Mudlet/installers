#!/bin/bash

# abort script if any command fails
set -e

RELEASE="false"
PTB="false"

if [ -n "${GITHUB_REPOSITORY}" ] ; then
  BUILD_DIR=${BUILD_FOLDER}
  SOURCE_DIR=${GITHUB_WORKSPACE}
fi

if [ -z "${SOURCE_DIR}" ]; then
  echo "SOURCE_DIR is not set, aborting.".
  exit 1
else
  echo "Working with source code in: '${SOURCE_DIR}'".
fi

if [ -z "${BUILD_DIR}" ]; then
  echo "BUILD_DIR is not set, aborting.".
  exit 1
else
  echo "Building in: '${BUILD_DIR}'.".
fi

APP_DIR="${SOURCE_DIR}/appDir"
export APP_DIR

# find out if we do a release build
while getopts ":pr:" option; do
  if [ "${option}" = "r" ]; then
    RELEASE="true"
    VERSION="${OPTARG}"
    shift $((OPTIND-1))
  elif [ "${option}" = "p" ]; then
    PTB="true"
    shift $((OPTIND-1))
  else
    echo "Unknown option -${option}"
    exit 1
  fi
done
if [ "${RELEASE}" != "true" ]; then
  VERSION="${1}"
fi

# The environmental variable VERSION is used by the linuxdeploy process to
# identify the build.
export VERSION

# setup linuxdeployqt binaries if not found
if [ "$(getconf LONG_BIT)" = "64" ]; then
  if [[ ! -e linuxdeploy.AppImage ]]; then
      # download prepackaged linuxdeploy
      echo "linuxdeploy not found - downloading it."
      wget -nv -O linuxdeploy.AppImage https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
      chmod +x linuxdeploy.AppImage
  fi
  if [[ ! -e linuxdeploy-plugin-qt.AppImage ]]; then
      # download prepackaged linuxdeploy-plugin-qt.
      echo "linuxdeploy-plugin-qt not found - downloading it."
      wget -nv -O linuxdeploy-plugin-qt.AppImage https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage
      chmod +x linuxdeploy-plugin-qt.AppImage
  fi

  if [[ ! -e linuxdeploy-plugin-gstreamer.sh ]]; then
      # download prepackaged linuxdeploy-plugin-gstreamer.
      echo "linuxdeploy-plugin-gstreamer not found - downloading it."
      wget -nv -O linuxdeploy-plugin-gstreamer.sh https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gstreamer/refs/heads/master/linuxdeploy-plugin-gstreamer.sh
      chmod +x linuxdeploy-plugin-gstreamer.sh
  fi
else
  echo "32bit Linux is no longer supported."
  exit 2
fi

if [ "${RELEASE}" != "true" ]; then
  OUTPUT_NAME="Mudlet-${VERSION}"
else
  if [ "${PTB}" == "true" ]; then
    OUTPUT_NAME="Mudlet PTB"
  else
    OUTPUT_NAME="Mudlet"
  fi
fi

# Report variables for checking:
echo "APP_DIR is: \"${APP_DIR}\""
echo "QMAKE is: \"${QMAKE}\""
echo "RELEASE is: \"${RELEASE}\""
echo "PTB is: \"${PTB}\""
echo "VERSION is: \"${VERSION}\""
echo "OUTPUT_NAME is: \"${OUTPUT_NAME}\""

# clean up the build/ folder
#rm -rf "${BUILD_DIR}"/
#mkdir -p "${BUILD_DIR}"

# delete previous appimage
rm -f Mudlet*.AppImage

# move the binary up to the build folder (they differ between qmake and cmake,
# so we use find to find the binary
#find "${BUILD_DIR}"/ -iname mudlet -type f -exec cp '{}' "${BUILD_DIR}"/ \;
# get mudlet-lua in there as well so linuxdeployqt bundles it
cp -rf "${SOURCE_DIR}"/src/mudlet-lua "${BUILD_DIR}"/
# copy Lua translations
# only copy if folder exists
mkdir -p "${BUILD_DIR}"/translations/lua
[ -d "${SOURCE_DIR}"/translations/lua ] && cp -rf "${SOURCE_DIR}"/translations/lua "${BUILD_DIR}"/translations/
# and the dictionary files in case the user system doesn't have them (at a known
# place)
cp "$SOURCE_DIR"/src/*.dic "${BUILD_DIR}"/
cp "$SOURCE_DIR"/src/*.aff "${BUILD_DIR}"/
# and the .desktop file so linuxdeployqt can pilfer it for info
cp "$SOURCE_DIR"/mudlet{.desktop,.png,.svg} "${BUILD_DIR}"/


cp -r "$SOURCE_DIR"/3rdparty/lcf "${BUILD_DIR}"/

# now copy Lua modules we need in
# this should be improved not to be hardcoded
mkdir -p "${BUILD_DIR}"/lib/luasql
mkdir -p "${BUILD_DIR}"/lib/brimworks

cp "${SOURCE_DIR}"/3rdparty/discord/rpc/lib/libdiscord-rpc.so "${BUILD_DIR}"/lib/

for LIB in lfs rex_pcre luasql/sqlite3 brimworks/zip lua-utf8 yajl
do
  FOUND="false"
  for LIB_PATH in $(luarocks path --lr-cpath | tr ";" "\n")
  do
    CHANGED_PATH=${LIB_PATH/\?/${LIB}};
    if [ -e "${CHANGED_PATH}" ]; then
      cp -rL "${CHANGED_PATH}" "${BUILD_DIR}"/lib/${LIB}.so
      FOUND="true"
    fi
  done
  if [ "${FOUND}" == "false" ]; then
    echo "Missing dependency '${LIB}', aborting."
    exit 1
  fi
done

# extract linuxdeployqt since some environments (like travis) don't allow FUSE
#./linuxdeploy.AppImage --appimage-extract


# QMAKE is an extra detail (path and filename of the qmake to use) needed for
# the qt plugin - including selecting a Qt 6 make which should have been done
# by the caller of this script - this is to identify where to get the Qt plugins
# from:
QT_INSTALL_PLUGINS="$(${QMAKE} -query | grep QT_INSTALL_PLUGINS | cut -d: -f 2)"
echo "Using Qt plugins located at: '${QT_INSTALL_PLUGINS}'"
export QT_INSTALL_PLUGINS

# In case we need any:
EXTRA_QT_MODULES=""
echo "Using extra modules: ${EXTRA_QT_MODULES}"
export EXTRA_QT_MODULES

# Bundle libssl.so so Mudlet works on platforms that only distribute
# OpenSSL 1.1
cp -L /usr/lib/x86_64-linux-gnu/libssl.so* "${BUILD_DIR}"/lib/ 2>/dev/null || true
cp -L /lib/x86_64-linux-gnu/libssl.so* "${BUILD_DIR}"/lib/ 2>/dev/null || true
if [ -z "$(ls "${BUILD_DIR}"/lib/libssl.so*)" ]; then
  echo "No OpenSSL libraries to copy found. Aborting..."
  exit 1
fi

echo "Generating AppImage"

# Leaving out --plugin gstreamer  for the moment
./linuxdeploy.AppImage --appdir "${APP_DIR}" --plugin qt --output appimage --icon-file "${BUILD_DIR}"/mudlet.svg --desktop-file "${BUILD_DIR}"/mudlet.desktop --executable "${BUILD_DIR}"/mudlet

#./squashfs-root/AppRun ./build/mudlet -appimage \
#  -executable=build/lib/rex_pcre.so -executable=build/lib/zip.so \
#  -executable=build/lib/luasql/sqlite3.so -executable=build/lib/yajl.so \
#  -executable=build/lib/libssl.so.1.1 \
#  -executable=build/lib/libssl.so.1.0.0 \
#  -extra-plugins=texttospeech/libqttexttospeech_flite.so,texttospeech/libqttexttospeech_speechd.so,platforminputcontexts/libcomposeplatforminputcontextplugin.so,platforminputcontexts/libibusplatforminputcontextplugin.so,platforminputcontexts/libfcitxplatforminputcontextplugin.so

# clean up extracted appimage
#rm -rf squashfs-root/

mv Mudlet*.AppImage "${OUTPUT_NAME}.AppImage"
