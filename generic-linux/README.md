The OS X installer generation
=============================

The directory
-------------

This directory contains all files needed to create the generic linux APpImage. It is home to two helper scripts `build-and-make-installer.sh`, which runs the full build and generation process, as well as `make-installer.sh`, which is the isolated generation process.

Prerequisites
-------------

The script expects all dependencies to be installed (for a current list have a look at the `.travis.yml` and `CI/travis.linux.install.sh` of the main project). It will only download the `linuxdeployqt.AppImage` it uses.

How to generate the installer
-----------------------------

### Building and generating in one step ###

Usage:
```bash
$ ./build-and-make-installer.sh [<commit-ish>]
```

Example:
```bash
$ ./build-and-make-installer.sh development
```

The script `build-and-make-installer.sh` installs build dependencies, clones  the git repository of Mudlet, checks the specified `commit-ish`out of the repository and starts building Mudlet. This may take a while. After the build is done, it hands control to the `make-installer.sh` script automatically.

If an `source` subdirectory exists, `commit-ish` is optional. If it exists, the currently checked out branch is used to build, otherwise the Mudlet sources will be cloned into the `source` subdirectory and `commit-ish` will be checked out.

### Generating the installer only ###

Usage:
```bash
$ ./make-installer.sh [-r] <version>
```

Examples:
```bash
$ ./make-installer.sh dev-01923abc
$ ./make-installer.sh -r 3.0.0
```

Prerequisites:

- A pre-build `mudlet` binary in `./source/build/`, e.g. the output of the Travis build process or the result of the `build-and-make-installer.sh` before it hands control to this script.

The script `make-installer.sh` copies the runtime dependencies as well as Qt required dynamically linked libraries into the `./build` directory, adapts search pathes and finally bundles it all up into a single `.AppImage` according to the passed version.

The optional argument `-r` sets a release version. This will make the output AppImage to be named `Mudlet.AppImage` as opposed to development versions, where the binary is called `Mudlet-<version>.AppImage`.
