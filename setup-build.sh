#!/bin/bash

#
# Installs dependencies, builds VeriFast, and runs tests.
# Suitable for home use and for continuous integration.
#

set -e # Stop as soon as a command fails.
set -x # Print what is being executed.

. ./config.sh

dl_and_unzip() {
  url="$1"
  filename=$(basename "$url")
  hash="$2"
  sha="$3"
  filter="$4"
  curl -Lf -o "/tmp/$filename" "$url"
  echo "$hash  /tmp/$filename" | shasum -a "$sha" -c || exit 1
  sudo tar "x"$filter"f" "/tmp/$filename"
}

dl_and_unzip_vfdeps() {
  url="$1"
  hash="$2"
  dl_and_unzip $url $hash 256 j
}

dl_and_unzip_llvm-clang() {
  platform="$1"
  hash="$2"
  dl_and_unzip "https://github.com/verifast/vf-llvm-clang-build/releases/download/v3/vf-llvm-clang-build-$VF_LLVM_CLANG_BUILD_VERSION-$platform.tar.gz" $hash 256 z
}

script_dir=$(pwd)
  dl_and_unzip_vfdeps https://github.com/docprofsky/vfdeps/releases/download/26.10rc1/$VFDEPS_NAME-linux.txz b9b8747c52be764784c6aba79b81c5c76e41e30e0a4bfee1927d41b50e4d32e9

if [ $(uname -s) = "Linux" ]; then
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends \
       git wget ca-certificates m4 \
       patch unzip libgtk2.0-dev \
       valac \
       cmake build-essential ninja-build \
       coq \
       software-properties-common # For add-apt-repository
  if ! sudo apt-get install -y --no-install-recommends libgtksourceview2.0-dev; then
    # libgtksourceview2.0-dev is not in recent Ubuntu releases, so add focal (20.04 LTS) repo
    sudo add-apt-repository -y "deb http://mirrors.kernel.org/ubuntu/ focal universe"
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends libgtksourceview2.0-dev
  fi

  if ! rustup show home; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s - -y
  fi
  $HOME/.cargo/bin/cargo install --locked --git https://github.com/btj/capnpc-ocaml-decoder

  cd /
  dl_and_unzip_llvm-clang Linux 7bc39ea82589679a10a4d03cbd7e1d032fffb644774aff60a46bdf973171ef7a
  . "$script_dir/install-vfdeps.sh"

  cd $script_dir/src/cxx_frontend/ast_exporter
  ls -la "/tmp" || echo error
  ls -la "/tmp/${VFDEPS_NAME}" || echo error
  ls -la "/tmp/${VFDEPS_NAME}/lib" || echo error
  ls -la "/tmp/${VFDEPS_NAME}/lib/cmake" || echo error
  ls -la "/tmp/${VFDEPS_NAME}/lib/cmake/CapnProto" || echo error
  cmake -S . -B build -G Ninja -DLLVM_INSTALL_DIR=/tmp/vf-llvm-clang-build-$VF_LLVM_CLANG_BUILD_VERSION -DVFDEPS=/tmp/$VFDEPS_NAME -DCMAKE_BUILD_TYPE=Release || (echo cmake failed; cat build/CMakeCache.txt; exit 1)

  sudo apt-get install -y --no-install-recommends libcoq-iris || echo "Skipping libcoq-iris installation; may not be available for your Ubuntu version."

elif [ $(uname -s) = "Darwin" ]; then

  if [ -z "$GITHUB_ACTIONS" ]; then
      # No need to update when running in GitHub Actions; their brew is updated weekly.
      brew update
  fi

  function brewinstall {
      if brew list $1 1>/dev/null 2>/dev/null; then
	  true;
      else
	  brew install $1;
      fi
  }  
  brewinstall wget
  brewinstall gtk+
  # brewinstall gtksourceview
  brewinstall oras
  if [ "$(uname -p)" = arm ]; then
    oras pull ghcr.io/homebrew/core/gtksourceview:2.10.5_7@sha256:0511545c79d16ff872f2bbc931abcdd5c1b4f3d70b71064f7d59989f68c8c073
    HOMEBREW_DEVELOPER=1 HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 brew install ./gtksourceview--2.10.5_7.arm64_monterey.bottle.tar.gz
  else
    exit 1 # Vfdeps isn't building on x86_64 macOS right now.
    oras pull ghcr.io/homebrew/core/gtksourceview:2.10.5_7@sha256:368413983346081e277782a5df7ac4b9e9ad1adce149fa7028fa6d99e809b7ae
    HOMEBREW_DEVELOPER=1 HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 brew install ./gtksourceview--2.10.5_7.monterey.bottle.tar.gz
  fi
  brewinstall vala
  brewinstall cmake
  brewinstall ninja
  export PKG_CONFIG_PATH=/opt/X11/lib/pkgconfig
  sudo mkdir /usr/local/$VFDEPS_NAME
  sudo mkdir /usr/local/vf-llvm-clang-build-$VF_LLVM_CLANG_BUILD_VERSION

  if ! rustup show home; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s - -y
  fi
  $HOME/.cargo/bin/cargo install --locked --git https://github.com/btj/capnpc-ocaml-decoder

  cd /usr/local
  if [ "$(uname -p)" = arm ]; then
    dl_and_unzip_llvm-clang MacOS-aarch64 aabb08b2d0f8226161fa7cec60746670c7e1ab4c69cedfdd76a47c52b329bc09
    dl_and_unzip_vfdeps https://github.com/docprofsky/vfdeps/releases/download/26.10rc1/$VFDEPS_NAME-macos-aarch64.txz b002f0931aaffdec195869e597ea54e17f19e069697086f6bf45a5252ed5704c
  else
    dl_and_unzip_llvm-clang MacOS 92d595ac8c92a2c28ca13a152463c52c12fc900d32d283558a885a29e8f250a5
    dl_and_unzip_vfdeps https://github.com/verifast/vfdeps/releases/download/25.01/$VFDEPS_NAME-macos.txz 99d9eceb2f4e483a61d84015db5251c99d4ce3932535b4b4e4d37a23d0a0146d
  fi

  cd $script_dir/src/cxx_frontend/ast_exporter
  cmake -S . -B build -G Ninja -DLLVM_INSTALL_DIR=/usr/local/vf-llvm-clang-build-$VF_LLVM_CLANG_BUILD_VERSION -DVFDEPS=/usr/local/$VFDEPS_NAME -DCMAKE_BUILD_TYPE=Release
  
else
  echo "Your OS is not supported by this script."
  exit 1
  
fi
