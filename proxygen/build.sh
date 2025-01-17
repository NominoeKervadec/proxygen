#!/usr/bin/env bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.

## Run this script to build proxygen and run the tests. If you want to
## install proxygen to use in another C++ project on this machine, run
## the sibling file `reinstall.sh`.

# Obtain the base directory this script resides in.
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Useful constants
COLOR_RED="\033[0;31m"
COLOR_GREEN="\033[0;32m"
COLOR_OFF="\033[0m"

function detect_platform() {
  unameOut="$(uname -s)"
  case "${unameOut}" in
      Linux*)     PLATFORM=Linux;;
      Darwin*)    PLATFORM=Mac;;
      *)          PLATFORM="UNKNOWN:${unameOut}"
  esac
  echo -e "${COLOR_GREEN}Detected platform: $PLATFORM ${COLOR_OFF}"
}

function install_dependencies_linux() {
  sudo apt-get install -yq \
    git \
    cmake \
    m4 \
    g++ \
    flex \
    bison \
    libgflags-dev \
    libgoogle-glog-dev \
    libkrb5-dev \
    libsasl2-dev \
    libnuma-dev \
    pkg-config \
    libssl-dev \
    libcap-dev \
    gperf \
    libevent-dev \
    libtool \
    libboost-all-dev \
    libjemalloc-dev \
    libsnappy-dev \
    wget \
    unzip \
    libiberty-dev \
    liblz4-dev \
    liblzma-dev \
    make \
    zlib1g-dev \
    binutils-dev \
    libsodium-dev \
    libdouble-conversion-dev \
    nasm \
    autoconf \
    automake
}

function install_dependencies_mac() {
  # install the default dependencies from homebrew
  brew install -f            \
    cmake                    \
    m4                       \
    boost                    \
    double-conversion        \
    gflags                   \
    glog                     \
    gperf                    \
    libevent                 \
    lz4                      \
    snappy                   \
    xz                       \
    openssl                  \
    libsodium

  brew link                 \
    cmake                   \
    boost                   \
    double-conversion       \
    gflags                  \
    glog                    \
    gperf                   \
    libevent                \
    lz4                     \
    snappy                  \
    openssl                 \
    xz                      \
    libsodium
}

function install_dependencies() {
  echo -e "${COLOR_GREEN}[ INFO ] install dependencies ${COLOR_OFF}"
  if [ "$PLATFORM" = "Linux" ]; then
    install_dependencies_linux
  elif [ "$PLATFORM" = "Mac" ]; then
    install_dependencies_mac
  else
    echo -e "${COLOR_RED}[ ERROR ] Unknown platform: $PLATFORM ${COLOR_OFF}"
    exit 1
  fi
}

function synch_dependency_to_commit() {
  # Utility function to synch a dependency to a specific commit. Takes two arguments:
  #   - $1: folder of the dependency's git repository
  #   - $2: path to the text file containing the desired commit hash (facebook)
  #   - $3: path to the text file containing the desired commit hash (changes from broadpeak, if any)
  if [ "$FETCH_DEPENDENCIES" = false ] ; then
    return
  fi
  DEP_REV_FB=$(sed 's/Subproject commit //' "$2")
  if [[ "" != "$3" ]];  then
    DEP_REV=$(sed 's/Subproject commit //' "$3")
  else
    DEP_REV=$DEP_REV_FB
  fi
  pushd "$1"
  git fetch
  # Disable git warning about detached head when checking out a specific commit.
  git -c advice.detachedHead=false checkout "$DEP_REV"
  if [[ $DEP_REV != $DEP_REV_FB ]];  then
    # Check that broadpeak commit is more recent than fb
    git merge-base --is-ancestor $DEP_REV_FB $DEP_REV ||  ( echo "Broadpeak commit is outdated compared to facebook's" && exit )
  fi
  popd
}

function setup_fmt() {
  FMT_DIR=$DEPS_DIR/fmt
  FMT_BUILD_DIR=$DEPS_DIR/fmt/build/
  FMT_TAG=$(grep "subdir = " ../../build/fbcode_builder/manifests/fmt | cut -d "-" -f 2)
  if [ ! -d "$FMT_DIR" ] ; then
    echo -e "${COLOR_GREEN}[ INFO ] Cloning fmt repo ${COLOR_OFF}"
    git clone https://github.com/fmtlib/fmt.git  "$FMT_DIR"
  fi
  cd "$FMT_DIR"
  git fetch --tags
  git checkout "${FMT_TAG}"
  echo -e "${COLOR_GREEN}Building fmt ${COLOR_OFF}"
  mkdir -p "$FMT_BUILD_DIR"
  cd "$FMT_BUILD_DIR" || exit

  cmake                                           \
    -DCMAKE_PREFIX_PATH="$DEPS_PREFIX_DIR"               \
    -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX_DIR"            \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo             \
    "$MAYBE_OVERRIDE_CXX_FLAGS"                   \
    -DFMT_DOC=OFF                                 \
    -DFMT_TEST=OFF                                \
    "$FMT_DIR"
  make -j "$JOBS"
  make install
  echo -e "${COLOR_GREEN}fmt is installed ${COLOR_OFF}"
  cd "$BWD" || exit
}

function setup_googletest() {
  GTEST_DIR=$DEPS_DIR/googletest
  GTEST_BUILD_DIR=$DEPS_DIR/googletest/build/
  GTEST_TAG=$(grep "subdir = " ../../build/fbcode_builder/manifests/googletest | cut -d "-" -f 2,3)
  if [ ! -d "$GTEST_DIR" ] ; then
    echo -e "${COLOR_GREEN}[ INFO ] Cloning googletest repo ${COLOR_OFF}"
    git clone https://github.com/google/googletest.git  "$GTEST_DIR"
  fi
  cd "$GTEST_DIR"
  git fetch --tags
  git checkout "${GTEST_TAG}"
  echo -e "${COLOR_GREEN}Building googletest ${COLOR_OFF}"
  mkdir -p "$GTEST_BUILD_DIR"
  cd "$GTEST_BUILD_DIR" || exit

  cmake                                           \
    -DCMAKE_PREFIX_PATH="$DEPS_PREFIX_DIR"               \
    -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX_DIR"            \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo             \
    "$GTEST_DIR"
  make -j "$JOBS"
  make install
  echo -e "${COLOR_GREEN}googletest is installed ${COLOR_OFF}"
  cd "$BWD" || exit
}

function setup_zstd() {
  ZSTD_DIR=$DEPS_DIR/zstd
  ZSTD_BUILD_DIR=$DEPS_DIR/zstd/build/cmake/builddir
  ZSTD_INSTALL_DIR=$DEPS_DIR
  ZSTD_TAG=$(grep "subdir = " ../../build/fbcode_builder/manifests/zstd | cut -d "-" -f 2 | cut -d "/" -f 1)
  if [ ! -d "$ZSTD_DIR" ] ; then
    echo -e "${COLOR_GREEN}[ INFO ] Cloning zstd repo ${COLOR_OFF}"
    git clone https://github.com/facebook/zstd.git "$ZSTD_DIR"
  fi
  cd "$ZSTD_DIR"
  git fetch --tags
  git checkout "v${ZSTD_TAG}"
  echo -e "${COLOR_GREEN}Building Zstd ${COLOR_OFF}"
  mkdir -p "$ZSTD_BUILD_DIR"
  cd "$ZSTD_BUILD_DIR" || exit
  cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo           \
    -DBUILD_TESTS=OFF                               \
    -DCMAKE_PREFIX_PATH="$ZSTD_INSTALL_DIR"         \
    -DCMAKE_INSTALL_PREFIX="$ZSTD_INSTALL_DIR"      \
    ${CMAKE_EXTRA_ARGS[@]+"${CMAKE_EXTRA_ARGS[@]}"} \
    "$ZSTD_DIR/build/cmake/"
  make -j "$JOBS"
  make install
  echo -e "${COLOR_GREEN}Zstd is installed ${COLOR_OFF}"
  cd "$BWD" || exit
}

function setup_folly() {
  FOLLY_DIR=$DEPS_DIR/folly
  FOLLY_BUILD_DIR=$DEPS_BUILD_DIR/folly/build/

  if [ ! -d "$FOLLY_DIR" ] ; then
    echo -e "${COLOR_GREEN}[ INFO ] Cloning folly repo ${COLOR_OFF}"
    git clone git@git.broadpeak.rd:Broadpeak/folly.git "$FOLLY_DIR"
  fi
  # We're using a custom fork
  synch_dependency_to_commit "$FOLLY_DIR" "$BASE_DIR"/../build/deps/github_hashes/facebook/folly-rev.txt  "$BASE_DIR"/../build/deps/bpk_hashes/folly-rev.txt 
  if [ "$PLATFORM" = "Mac" ]; then
    # Homebrew installs OpenSSL in a non-default location on MacOS >= Mojave
    # 10.14 because MacOS has its own SSL implementation.  If we find the
    # typical Homebrew OpenSSL dir, load OPENSSL_ROOT_DIR so that cmake
    # will find the Homebrew version.
    dir=/usr/local/opt/openssl
    if [ -d $dir ]; then
        export OPENSSL_ROOT_DIR=$dir
    fi
  fi
  echo -e "${COLOR_GREEN}Building Folly ${COLOR_OFF}"
  mkdir -p "$FOLLY_BUILD_DIR"
  cd "$FOLLY_BUILD_DIR" || exit
  MAYBE_DISABLE_JEMALLOC=""
  if [ "$NO_JEMALLOC" == true ] ; then
    MAYBE_DISABLE_JEMALLOC="-DFOLLY_USE_JEMALLOC=0"
  fi

  MAYBE_USE_STATIC_DEPS=""
  MAYBE_USE_STATIC_BOOST=""
  MAYBE_BUILD_SHARED_LIBS=""
  if [ "$BUILD_FOR_FUZZING" == true ] ; then
    MAYBE_USE_STATIC_DEPS="-DUSE_STATIC_DEPS_ON_UNIX=ON"
    MAYBE_USE_STATIC_BOOST="-DBOOST_LINK_STATIC=ON"
    MAYBE_BUILD_SHARED_LIBS="-DBUILD_SHARED_LIBS=OFF"
  fi
  if [ "$BOOST_ROOT" != "" ]; then
   MAYBE_USE_STATIC_BOOST="-DBOOST_LINK_STATIC=ON"
  fi
  cmake                                           \
    -DCMAKE_PREFIX_PATH="$DEPS_PREFIX_DIR"               \
    -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX_DIR"            \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo             \
    -DBUILD_TESTS=OFF                             \
    "$MAYBE_USE_STATIC_DEPS"                      \
    "$MAYBE_USE_STATIC_BOOST"                     \
    "$MAYBE_BUILD_SHARED_LIBS"                    \
    "$MAYBE_OVERRIDE_CXX_FLAGS"                   \
    $MAYBE_DISABLE_JEMALLOC                       \
    "$FOLLY_DIR"
  make -j "$JOBS"
  make install
  echo -e "${COLOR_GREEN}Folly is installed ${COLOR_OFF}"
  cd "$BWD" || exit
}

function setup_ippcrypto() {
  IPPCRYPTO_DIR=$DEPS_DIR/ippcrypto
  IPPCRYPTO_BUILD_DIR=$DEPS_BUILD_DIR/ippcrypto/build/

  if [ ! -d "$IPPCRYPTO_DIR" ] ; then
    echo -e "${COLOR_GREEN}[ INFO ] Cloning ippcrypto repo ${COLOR_OFF}"
    git clone --recursive https://github.com/intel/ipp-crypto.git  "$IPPCRYPTO_DIR"
  fi
  cd "$IPPCRYPTO_DIR" || exit
  if [ "$FETCH_DEPENDENCIES" == true ] ; then
    git fetch --tags
    git checkout ippcp_2021.6
  fi
  echo -e "${COLOR_GREEN}Building ippcrypto ${COLOR_OFF}"
  mkdir -p "$IPPCRYPTO_BUILD_DIR"
  cd "$IPPCRYPTO_BUILD_DIR" || exit
  if [ -e $DEPS_DIR/lib/libcrypto_mb.a ]; then
    # IPPCPP Make rebuilds everything unconditonally, so bypass early reinstallation
    #return;
    echo $DEPS_DIR/lib/libcrypto_mb.a already exists, skipping build
  else
    cmake                                           \
      -DCMAKE_PREFIX_PATH="$DEPS_DIR"               \
      -DCMAKE_INSTALL_PREFIX="$DEPS_DIR"            \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo             \
      -DARCH=intel64                                \
      -DMERGED_BLD:BOOL=on                          \
      "$IPPCRYPTO_DIR"

    make -j "$JOBS" all
  fi
  mkdir -p "$DEPS_PREFIX_DIR/lib/"
  cp -r .build/RELEASE/lib/*.so* .build/RELEASE/lib/*.a "$DEPS_PREFIX_DIR/lib"
  cp -r sources/ippcp/*.so* sources/ippcp/*.a "$DEPS_PREFIX_DIR/lib"
  cp -r .build/RELEASE/include/* "$DEPS_PREFIX_DIR/include"
  mkdir -p "$DEPS_PREFIX_DIR/lib/cmake/ippcp"
  cp -r .build/RELEASE/cmake/* "$DEPS_PREFIX_DIR/lib/cmake/ippcp"
  cp -r .build/RELEASE/pkgconfig/* "$DEPS_PREFIX_DIR/lib/pkgconfig"

  echo -e "${COLOR_GREEN}ippcrypto is installed ${COLOR_OFF}"
  cd "$BWD" || exit
}

function setup_isa_l_crypto() {
  ISA_L_CRYPTO_DIR=$DEPS_DIR/isa_l_crypto

  if [ ! -d "$ISA_L_CRYPTO_DIR" ] ; then
    echo -e "${COLOR_GREEN}[ INFO ] Cloning isa_l_crypto repo ${COLOR_OFF}"
    git clone --recursive git@git.broadpeak.rd:Broadpeak/isa_l_crypto.git  "$ISA_L_CRYPTO_DIR"
  fi
  cd "$ISA_L_CRYPTO_DIR" || exit
  # We're using a custom fork with added variants
  synch_dependency_to_commit "$ISA_L_CRYPTO_DIR" "$BASE_DIR"/../build/deps/bpk_hashes/isa_l_crypto-rev.txt  "$BASE_DIR"/../build/deps/bpk_hashes/isa_l_crypto-rev.txt 
  echo -e "${COLOR_GREEN}Building isa_l_crypto ${COLOR_OFF}"
  if [ -e $DEPS_DIR/lib/libisal_crypto.a ]; then
    # ISA_L_CRYPTO Make rebuilds everything unconditonally, so bypass early reinstallation
    #return;
    echo $DEPS_DIR/lib/libisal_crypto.a exists, skipping build
  else
    ./autogen.sh
    ./configure --prefix="$DEPS_PREFIX_DIR" \
                       --libdir="$DEPS_PREFIX_DIR/lib"
    make -j "$JOBS"
    make install
  fi

  echo -e "${COLOR_GREEN}isa_l_crypto is installed ${COLOR_OFF}"
  cd "$BWD" || exit
}

function setup_fizz() {
  FIZZ_DIR=$DEPS_DIR/fizz
  FIZZ_BUILD_DIR=$DEPS_BUILD_DIR/fizz/build/
  if [ ! -d "$FIZZ_DIR" ] ; then
    echo -e "${COLOR_GREEN}[ INFO ] Cloning fizz repo ${COLOR_OFF}"
    git clone git@git.broadpeak.rd:Broadpeak/fizz.git "$FIZZ_DIR"
  fi
  # We're using a custom fork with added variants
  synch_dependency_to_commit "$FIZZ_DIR" "$BASE_DIR"/../build/deps/github_hashes/facebookincubator/fizz-rev.txt "$BASE_DIR"/../build/deps/bpk_hashes/fizz-rev.txt 
  echo -e "${COLOR_GREEN}Building Fizz ${COLOR_OFF}"
  mkdir -p "$FIZZ_BUILD_DIR"
  cd "$FIZZ_BUILD_DIR" || exit

  MAYBE_USE_STATIC_DEPS=""
  MAYBE_USE_SODIUM_STATIC_LIBS=""
  MAYBE_BUILD_SHARED_LIBS=""
  if [ "$BUILD_FOR_FUZZING" == true ] ; then
    MAYBE_USE_STATIC_DEPS="-DUSE_STATIC_DEPS_ON_UNIX=ON"
    MAYBE_USE_SODIUM_STATIC_LIBS="-Dsodium_USE_STATIC_LIBS=ON"
    MAYBE_BUILD_SHARED_LIBS="-DBUILD_SHARED_LIBS=OFF"
  fi

  cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo       \
    -DCMAKE_PREFIX_PATH="$DEPS_PREFIX_DIR"             \
    -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX_DIR"          \
    -DBUILD_TESTS=ON                            \
    "$MAYBE_USE_STATIC_DEPS"                    \
    "$MAYBE_BUILD_SHARED_LIBS"                  \
    "$MAYBE_OVERRIDE_CXX_FLAGS"                 \
    "$MAYBE_USE_SODIUM_STATIC_LIBS"             \
    "$FIZZ_DIR/fizz"
  make -j "$JOBS"
  make install
  echo -e "${COLOR_GREEN}Fizz is installed ${COLOR_OFF}"
  cd "$BWD" || exit
}

function setup_wangle() {
  WANGLE_DIR=$DEPS_DIR/wangle
  WANGLE_BUILD_DIR=$DEPS_BUILD_DIR/wangle/build/
  if [ ! -d "$WANGLE_DIR" ] ; then
    echo -e "${COLOR_GREEN}[ INFO ] Cloning wangle repo ${COLOR_OFF}"
    git clone https://github.com/facebook/wangle "$WANGLE_DIR"
  fi
  synch_dependency_to_commit "$WANGLE_DIR" "$BASE_DIR"/../build/deps/github_hashes/facebook/wangle-rev.txt
  echo -e "${COLOR_GREEN}Building Wangle ${COLOR_OFF}"
  mkdir -p "$WANGLE_BUILD_DIR"
  cd "$WANGLE_BUILD_DIR" || exit

  MAYBE_USE_STATIC_DEPS=""
  MAYBE_BUILD_SHARED_LIBS=""
  if [ "$BUILD_FOR_FUZZING" == true ] ; then
    MAYBE_USE_STATIC_DEPS="-DUSE_STATIC_DEPS_ON_UNIX=ON"
    MAYBE_BUILD_SHARED_LIBS="-DBUILD_SHARED_LIBS=OFF"
  fi

  cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo       \
    -DCMAKE_PREFIX_PATH="$DEPS_PREFIX_DIR"             \
    -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX_DIR"          \
    -DBUILD_TESTS=OFF                           \
    "$MAYBE_USE_STATIC_DEPS"                    \
    "$MAYBE_BUILD_SHARED_LIBS"                  \
    "$MAYBE_OVERRIDE_CXX_FLAGS"                 \
    "$WANGLE_DIR/wangle"
  make -j "$JOBS"
  make install
  echo -e "${COLOR_GREEN}Wangle is installed ${COLOR_OFF}"
  cd "$BWD" || exit
}

function setup_mvfst() {
  MVFST_DIR=$DEPS_DIR/mvfst
  MVFST_BUILD_DIR=$DEPS_BUILD_DIR/mvfst/build/
  if [ ! -d "$MVFST_DIR" ] ; then
    echo -e "${COLOR_GREEN}[ INFO ] Cloning mvfst repo ${COLOR_OFF}"
    git clone git@git.broadpeak.rd:Broadpeak/mvfst.git "$MVFST_DIR"
  fi
  synch_dependency_to_commit "$MVFST_DIR" "$BASE_DIR"/../build/deps/github_hashes/facebookincubator/mvfst-rev.txt  "$BASE_DIR"/../build/deps/bpk_hashes/mvfst-rev.txt 
  echo -e "${COLOR_GREEN}Building Mvfst ${COLOR_OFF}"
  mkdir -p "$MVFST_BUILD_DIR"
  cd "$MVFST_BUILD_DIR" || exit

  MAYBE_USE_STATIC_DEPS=""
  MAYBE_BUILD_SHARED_LIBS=""
  if [ "$BUILD_FOR_FUZZING" == true ] ; then
    MAYBE_USE_STATIC_DEPS="-DUSE_STATIC_DEPS_ON_UNIX=ON"
    MAYBE_BUILD_SHARED_LIBS="-DBUILD_SHARED_LIBS=OFF"
  fi


  cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo       \
    -DCMAKE_PREFIX_PATH="$DEPS_PREFIX_DIR"             \
    -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX_DIR"          \
    -DBUILD_TESTS=OFF                           \
    "$MAYBE_USE_STATIC_DEPS"                    \
    "$MAYBE_BUILD_SHARED_LIBS"                  \
    "$MAYBE_OVERRIDE_CXX_FLAGS"                 \
    "$MVFST_DIR"
  make -j "$JOBS"
  make install
  echo -e "${COLOR_GREEN}Mvfst is installed ${COLOR_OFF}"
  cd "$BWD" || exit
}

# Parse args
JOBS=8
WITH_QUIC=false
INSTALL_DEPENDENCIES=true
FETCH_DEPENDENCIES=true
DO_NOT_BUILD_PROXYGEN=false
PREFIX=""
COMPILER_FLAGS=""
USAGE="./build.sh [-j num_jobs] [-q|--with-quic] [-m|--no-jemalloc] [--no-install-dependencies] [-p|--prefix] [-x|--compiler-flags] [--no-fetch-dependencies]"
while [ "$1" != "" ]; do
  case $1 in
    -j | --jobs ) shift
                  JOBS=$1
                  ;;
    -q | --with-quic )
                  WITH_QUIC=true
                  ;;
    -m | --no-jemalloc )
                  NO_JEMALLOC=true
                  ;;
    --no-install-dependencies )
                  INSTALL_DEPENDENCIES=false
          ;;
    --no-fetch-dependencies )
                  FETCH_DEPENDENCIES=false
          ;;
    --build-for-fuzzing )
                  BUILD_FOR_FUZZING=true
      ;;
    -t | --no-tests )
                  NO_BUILD_TESTS=true
      ;;
    --dependencies-only-do-not-build-proxygen )
                  DO_NOT_BUILD_PROXYGEN=true
      ;;
    -p | --prefix )
                  shift
                  PREFIX=$1
      ;;
     --deps-build-dir )
                  shift
                  DEPS_BUILD_DIR=$1
      ;;
      --deps-prefix-dir )
                  shift
                  DEPS_PREFIX_DIR=$1
     ;;
    -x | --compiler-flags )
                  shift
                  COMPILER_FLAGS=$1
      ;;
    * )           echo $USAGE
                  exit 1
esac
shift
done

detect_platform

if [ "$INSTALL_DEPENDENCIES" == true ] ; then
  install_dependencies
fi

MAYBE_OVERRIDE_CXX_FLAGS=""
if [ -n "$COMPILER_FLAGS" ] ; then
  MAYBE_OVERRIDE_CXX_FLAGS="-DCMAKE_CXX_FLAGS=$COMPILER_FLAGS"
fi

BUILD_DIR=_build
mkdir -p $BUILD_DIR

set -e nounset
trap 'cd $BASE_DIR' EXIT
cd $BUILD_DIR || exit
BWD=$(pwd)
DEPS_DIR=$BWD/deps
mkdir -p "$DEPS_DIR"
: "${DEPS_BUILD_DIR:=$DEPS_DIR}""
: "${DEPS_PREFIX_DIR:=$DEPS_DIR}''

# Must execute from the directory containing this script
cd "$(dirname "$0")"

#setup_fmt
setup_googletest
setup_zstd
setup_folly
setup_ippcrypto
setup_isa_l_crypto
setup_fizz
setup_wangle
MAYBE_BUILD_QUIC=""
if [ "$WITH_QUIC" == true ] ; then
  setup_mvfst
  MAYBE_BUILD_QUIC="-DBUILD_QUIC=On"
fi

MAYBE_BUILD_FUZZERS=""
MAYBE_USE_STATIC_DEPS=""
MAYBE_LIB_FUZZING_ENGINE=""
MAYBE_BUILD_SHARED_LIBS=""
MAYBE_BUILD_TESTS="-DBUILD_TESTS=ON"
if [ "$NO_BUILD_TESTS" == true ] ; then
  MAYBE_BUILD_TESTS="-DBUILD_TESTS=OFF"
fi
if [ "$BUILD_FOR_FUZZING" == true ] ; then
  MAYBE_BUILD_FUZZERS="-DBUILD_FUZZERS=ON"
  MAYBE_USE_STATIC_DEPS="-DUSE_STATIC_DEPS_ON_UNIX=ON"
  MAYBE_LIB_FUZZING_ENGINE="-DLIB_FUZZING_ENGINE='$LIB_FUZZING_ENGINE'"
  MAYBE_BUILD_SHARED_LIBS="-DBUILD_SHARED_LIBS=OFF"
fi

if [ -z "$PREFIX" ]; then
  PREFIX=$BWD
fi

if [ "$DO_NOT_BUILD_PROXYGEN" == true ]; then
  exit
fi

# Build proxygen with cmake
cd "$BWD" || exit
cmake                                     \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo       \
  -DCMAKE_PREFIX_PATH="$DEPS_PREFIX_DIR"         \
  -DCMAKE_INSTALL_PREFIX="$PREFIX"        \
  "$MAYBE_BUILD_QUIC"                     \
  "$MAYBE_BUILD_TESTS"                    \
  "$MAYBE_BUILD_FUZZERS"                  \
  "$MAYBE_BUILD_SHARED_LIBS"              \
  "$MAYBE_OVERRIDE_CXX_FLAGS"             \
  "$MAYBE_USE_STATIC_DEPS"                \
  "$MAYBE_LIB_FUZZING_ENGINE"             \
  ../..

make -j "$JOBS"
echo -e "${COLOR_GREEN}Proxygen build is complete. To run unit test: \
  cd _build/ && make test ${COLOR_OFF}"
