#!/bin/bash
############################################################################
#    Copyright (C) 2017-2020, by Vadim Peretokin  - <vperetokin@gmail.com> #
#    Copyright (C) 2017-2020 by Keneanung <kenenanung@googlemail.com>      #
#    Copyright (C) 2019, 2025 by Stephen Lyons - <slysven@virginmedia.com> #
#    Copyright (C) 2020 by Edru2                                           #
#                              - <60551052+Edru2@users.noreply.github.com> #
#                                                                          #
#    This program is free software; you can redistribute it and/or modify  #
#    it under the terms of the GNU General Public License as published by  #
#    the Free Software Foundation; either version 2 of the License, or     #
#    (at your option) any later version.                                   #
#                                                                          #
#    This program is distributed in the hope that it will be useful,       #
#    but WITHOUT ANY WARRANTY; without even the implied warranty of        #
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         #
#    GNU General Public License for more details.                          #
#                                                                          #
#    You should have received a copy of the GNU General Public License     #
#    along with this program; if not, write to the                         #
#    Free Software Foundation, Inc.,                                       #
#    59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.             #
############################################################################

# abort script if any command fails
set -e

RELEASE="false"
PTB="false"

if [ -n "${GITHUB_REPOSITORY}" ] ; then
  SOURCE_DIR=${GITHUB_WORKSPACE}
  BUILD_DIR=${BUILD_FOLDER}
fi

if [ -z "${SOURCE_DIR}" ]; then
  echo "SOURCE_DIR is not set, aborting.".
  exit 1
else
  echo "Working with source code in: '${SOURCE_DIR}'".
fi

# BUILD_DIR wil be ${SOURCE_DIR}/build if this script is run from
# build-and-make-installer.sh:
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
    LINUXDEPLOY_OUTPUT_VERSION="${OPTARG}"
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
  LINUXDEPLOY_OUTPUT_VERSION="${1}"
fi

# The environmental variable VERSION is used by the linuxdeploy process to
# identify the build - although we do now get warnings to use
# LINUXDEPLOY_OUTPUT_VERSION instead?
export LINUXDEPLOY_OUTPUT_VERSION

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
  if [[ ! -e linuxdeploy-plugin-checkrt.sh ]]; then
      # download prepackaged linuxdeploy-plugin-checkrt.sh - needed to allow an
      # AppImage build with a newer CRT to run on a system with an older one:
      echo "linuxdeploy-plugin-checkrt.sh not found - downloading it."
      wget -nv -O linuxdeploy-plugin-checkrt.sh https://github.com/darealshinji/linuxdeploy-plugin-checkrt/releases/download/continuous/linuxdeploy-plugin-checkrt.sh
      chmod +x linuxdeploy-plugin-checkrt.sh
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
  OUTPUT_NAME="Mudlet-${LINUXDEPLOY_OUTPUT_VERSION}"
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
echo "LINUXDEPLOY_OUTPUT_VERSION is: \"${LINUXDEPLOY_OUTPUT_VERSION}\""
echo "OUTPUT_NAME is: \"${OUTPUT_NAME}\""

# delete any previous appimage
rm -f Mudlet*.AppImage

# clean up the "${APP_DIR}"/ folder of any previous files:
rm -rf "${APP_DIR}"/

# make some directories we'll need:
# For the mudlet executable:
mkdir -p "${APP_DIR}"/usr/bin/
# For the libraries:
mkdir -p "${APP_DIR}"/usr/lib/
# For the lua files - not needed as the translations one will make it:
# mkdir -p "${APP_DIR}"/usr/share/applications/mudlet/lua
# For the lua code formatter files:
mkdir -p "${APP_DIR}"/usr/share/applications/mudlet/lcf
# For the lua translations
mkdir -p "${APP_DIR}"/usr/share/applications/mudlet/lua/translations
# For the dictionaries we ship as a fallback
mkdir -p "${APP_DIR}"/usr/share/hunspell


# copy the binary into the AppDir folders (they differ between qmake and cmake,
# so we use find to find the binary
find "${BUILD_DIR}"/ -iname mudlet -type f -exec cp '{}' "${APP_DIR}"/usr/bin \;
# get the lua files in:
cp -rf "${SOURCE_DIR}"/src/mudlet-lua/lua "${APP_DIR}"/usr/share/applications/mudlet
# get the lua code formatter files in:
cp -rf "${SOURCE_DIR}"/3rdparty/lcf "${APP_DIR}"/usr/share/applications/mudlet
# copy Lua translations, only copy if folder exists
if [ -d "${SOURCE_DIR}"/translations/lua ]; then
  cp -f "${SOURCE_DIR}"/translations/lua/translated/*.json "${APP_DIR}"/usr/share/applications/mudlet/lua/translations
  # We also need the untranslated table for en_US locale
  cp -f "${SOURCE_DIR}"/translations/lua/mudlet-lua.json "${APP_DIR}"/usr/share/applications/mudlet/lua/translations
  # Change to the directory to keep the symbolic link simple
  pushd "${APP_DIR}"/usr/share/applications/mudlet/lua/translations
  # Make a symbolic link so that mudlet-lua_en_US.json is a meaningful file reference
  ln -s ./mudlet-lua.json ./mudlet-lua_en_US.json
  # Return to where we were
  popd
fi

# and the dictionary files in case the user system doesn't have them (at a known
# place)
cp "${SOURCE_DIR}"/src/*.dic "${APP_DIR}"/usr/share/hunspell
cp "${SOURCE_DIR}"/src/*.aff "${APP_DIR}"/usr/share/hunspell

# and the .desktop and files used for icons so linuxdeploy can pilfer them
cp "${SOURCE_DIR}"/mudlet{.desktop,.png,.svg} "${APP_DIR}"/usr/share/applications/mudlet

# now copy Lua modules we need in
mkdir -p "${APP_DIR}"/usr/lib/luasql
mkdir -p "${APP_DIR}"/usr/lib/brimworks

for LIB in lfs rex_pcre luasql/sqlite3 brimworks/zip lua-utf8 yajl
do
  FOUND="false"
  for LIB_PATH in $(luarocks path --lr-cpath | tr ";" "\n")
  do
    CHANGED_PATH=${LIB_PATH/\?/${LIB}};
    echo "For \"${LIB}\" changing path from \"${LIB_PATH}\" to \"${CHANGED_PATH}\"."
    if [ -e "${CHANGED_PATH}" ]; then
      # For previous linuxdeployqt
      # cp -rL "${CHANGED_PATH}" "${BUILD_DIR}"/lib/${LIB}.so
      if cp -vrL "${CHANGED_PATH}" "${APP_DIR}/usr/lib/${LIB}.so"; then
        FOUND="true"
      fi
    fi
  done
  if [ "${FOUND}" == "false" ]; then
    echo "Missing dependency '${LIB}', aborting."
    exit 1
  fi
done

# Discord library
cp -v "${SOURCE_DIR}"/3rdparty/discord/rpc/lib/libdiscord-rpc.so "${APP_DIR}"/usr/lib/

# QMAKE is an extra detail (path and filename of the qmake to use) needed for
# the qt plugin - including selecting a Qt 6 make which should have been done
# by the caller of this script - this is to identify where to get the Qt plugins
# from:
QT_INSTALL_PLUGINS="$(${QMAKE} -query | grep QT_INSTALL_PLUGINS | cut -d: -f 2)"
echo "Using Qt plugins located at: '${QT_INSTALL_PLUGINS}'"
export QT_INSTALL_PLUGINS

# In case we need any:
EXTRA_QT_MODULES=""
echo "Using extra modules: \"${EXTRA_QT_MODULES}\""
export EXTRA_QT_MODULES

# Bundle libssl.so so Mudlet works on platforms that only distribute
# OpenSSL 1.1
cp -Lv /usr/lib/x86_64-linux-gnu/libssl.so* "${BUILD_DIR}"/lib/ 2>/dev/null || true
cp -Lv /lib/x86_64-linux-gnu/libssl.so* "${BUILD_DIR}"/lib/ 2>/dev/null || true
if [ -z "$(ls "${BUILD_DIR}"/lib/libssl.so* 2>/dev/null)" ]; then
  echo "No OpenSSL libraries to copy found. This might be a problem..."
  # exit 1
fi

echo "Generating AppImage"
# Note: the gstreamer plugin needs the patchelf utility!
./linuxdeploy.AppImage --appdir "${APP_DIR}" --plugin qt --plugin gstreamer --plugin checkrt --icon-file "${SOURCE_DIR}"/mudlet.svg --desktop-file "${SOURCE_DIR}"/mudlet.desktop --executable "${APP_DIR}"/usr/bin/mudlet --output appimage

# Unfortunately, until https://github.com/linuxdeploy/linuxdeploy-plugin-qt/issues/194
# is resolved we have to go through the ${APP_DIR}/usr/translations/ directory
# and combine the qtbase_xx(_YY).qm and qtmultimedia_xx(_YY).qm files into
# a single qt_xx(_YY).qm file with a:
# "lconvert -o ./qt_xx(_YY).qm qtbase_xx(_YY).qm qtmultimedia_xx(_YY).qm"
# The '_' in workarea needs to be accounted for in the cut fields to index
for baseFile in "${APP_DIR}"/usr/translations/qtbase_*.qm
do
    localeCode=$(echo "${baseFile}" | cut -d_ -f 2-)
    # remember localeCode includes the ".qm" extension
    if [ -f "${APP_DIR}"/usr/translations/qtmultimedia_${localeCode} ]; then
        # This locale DOES have a qtmultimedia_*.qm file so include it:
        lconvert -o "${APP_DIR}"/usr/translations/qt_${localeCode} "${APP_DIR}"/usr/translations/qtbase_${localeCode} "${APP_DIR}"/usr/translations/qtmultimedia_${localeCode}
    else
        # It doesn't so just convert/copy the base one:
        lconvert -o "${APP_DIR}"/usr/translations/qt_${localeCode} "${APP_DIR}"/usr/translations/qtbase_${localeCode}
    fi
done

# Remove the individual files
rm "${APP_DIR}"/usr/translations/qtbase_*.qm
rm "${APP_DIR}"/usr/translations/qtmultimedia_*.qm

# Remove some files from prior run that will be regenerated - and give us a
# warning if not removed
rm "${APP_DIR}"/AppRun
rm "${APP_DIR}"/AppRun.wrapped

# Rerun the base linuxdeploy (still with the checkrt plugin) to regenerate a new AppImage
./linuxdeploy.AppImage --appdir "${APP_DIR}" --plugin checkrt --output appimage

mv Mudlet*.AppImage "${OUTPUT_NAME}.AppImage"
