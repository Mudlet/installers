#!/bin/bash

# abort script if any command fails
set -e

# extract program name for message
pgm=$(basename "$0")

# Retrieve latest source code, keep history as it's useful to edit sometimes
# if it's already there, keep it as is
if [ ! -d "source" ]; then
  # check command line option for commit-ish that should be checked out
  commitish="$1"
  if [ -z "$commitish" ]; then
    echo "No 'source' folder exists and no commit-ish given."
    echo "Usage: $pgm <commit-ish>"
    exit 2
  fi

  git clone --recursive https://github.com/Mudlet/Mudlet.git source

  # Switch to $commitish
  (cd source && git checkout "${commitish}")
fi

# set the commit ID so the build can reference it later
cd source
commit=$(git rev-parse --short HEAD)

# linux assumes compile time dependencies are installed to make this
# (hopefully) distribution independent

# Add commit information to version and extract version info itself
cd src/
# find out if we do a dev or a release build
dev=$(perl -lne 'print $1 if /^BUILD = (.*)$/' < src.pro)
if [ ! -z "${dev}" ]; then
  MUDLET_VERSION_BUILD="-dev-$commit"
  export MUDLET_VERSION_BUILD
fi
version=$(perl -lne 'print $1 if /^VERSION = (.+)/' < src.pro)
cd ..

mkdir -p build
cd build/

# Compile using all available cores
qmake ../src/src.pro
make -j "$(nproc)"

# now run the actual installer creation script
cd ../..
if [ ! -z "${dev}" ]; then
  ./make-installer.sh "${version}${MUDLET_VERSION_BUILD}"
else
  ./make-installer.sh -r "${version}"
fi
