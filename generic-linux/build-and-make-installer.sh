#!/bin/bash

# abort script if any command fails
set -e

# extract program name for message
PGM=$(basename "$0")

# Where to put the Mudlet source code:
if [ -z "${SOURCE_DIR}" ]; then
  SOURCE_DIR="$(pwd)/work_area"
  export SOURCE_DIR
fi

echo "Working in: '${SOURCE_DIR}'"
# Used within this script AND the make-installer one and needed in the latter
# to force a Qt6 build rather than Qt5:
QMAKE="$(which qmake6)"
export QMAKE
# Retrieve latest source code, keep history as it's useful to edit sometimes
# if it's already there, keep it as is
if [ ! -d "${SOURCE_DIR}" ]; then
  # check command line option for commit-ish that should be checked out
  COMMITISH="$1"
  if [ -z "${COMMITISH}" ]; then
    echo "No 'source' folder exists and no commit-ish given."
    echo "Usage: ${PGM} <commit-ish>"
    exit 2
  fi

  git clone https://github.com/Mudlet/Mudlet.git "${SOURCE_DIR}"

  # Switch to ${COMMITISH}
  (cd "${SOURCE_DIR}" && git checkout "${COMMITISH}")
fi

# set the commit ID so the build can reference it later
# This path/location is effectively hard coded into this AND the
# make-installer.sh script:
cd "${SOURCE_DIR}"
COMMIT=$(git rev-parse --short HEAD)

# linux assumes compile time dependencies are installed to make this
# (hopefully) distribution independent

# Add commit information to version and extract version info itself
cd "${SOURCE_DIR}"/src/
# find out if we do a dev or a release build
DEV=$(perl -lne 'print $1 if /^BUILD = (.*)$/' < mudlet.pro)
if [ -n "${DEV}" ]; then
  MUDLET_VERSION_BUILD="-dev-${COMMIT}"
  export MUDLET_VERSION_BUILD
fi

VERSION=$(perl -lne 'print $1 if /^VERSION = (.+)/' < mudlet.pro)

cd ..

BUILD_DIR="${SOURCE_DIR}"/build
export BUILD_DIR

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Compile using all available cores
"${QMAKE}" "${SOURCE_DIR}"/src/mudlet.pro
make -j "$(nproc)"

# now run the actual installer creation script
cd ../..
if [ -n "${DEV}" ]; then
  ./make-installer.sh "${VERSION}${MUDLET_VERSION_BUILD}"
else
  ./make-installer.sh -r "${VERSION}"
fi
