#!/bin/bash -e
export RED_COLOR='\e[1;31m'
export GREEN_COLOR='\e[1;32m'
export YELLOW_COLOR='\e[1;33m'
export BLUE_COLOR='\e[1;34m'
export PINK_COLOR='\e[1;35m'
export SHAN='\e[1;33;5m'
export RES='\e[0m'

GROUP=
group() {
    endgroup
    echo "::group::  $1"
    GROUP=1
}
endgroup() {
    if [ -n "$GROUP" ]; then
        echo "::endgroup::"
    fi
    GROUP=
}

# check
if [ "$(whoami)" != "sbwml" ] && [ -z "$git_name" ] && [ -z "$git_password" ]; then
    echo -e "\n${RED_COLOR} Not authorized. Execute the following command to provide authorization information:${RES}\n"
    echo -e "${BLUE_COLOR} export git_name=your_username git_password=your_password${RES}\n"
    exit 1
fi

#####################################
#  NanoPi R4S OpenWrt Build Script  #
#####################################

# IP Location
ip_info=`curl -sk https://ip.cooluc.com`;
[ -n "$ip_info" ] && export isCN=`echo $ip_info | grep -Po 'country_code\":"\K[^"]+'` || export isCN=US

# script url
if [ "$isCN" = "CN" ]; then
    export mirror=https://init.cooluc.com
else
    export mirror=https://init2.cooluc.com
fi

# github actions - caddy server
if [ "$(whoami)" = "runner" ] && [ $git_name != "private" ]; then
    export mirror=http://127.0.0.1:8080
fi

# private gitea
export gitea="git.cooluc.com"

# github mirror
if [ "$isCN" = "CN" ]; then
    # There is currently no stable gh proxy
    export github="github.com"
    code_mirror="git.cooluc.com"
else
    export github="github.com"
    code_mirror="github.com"
fi

# Check root
if [ "$(id -u)" = "0" ]; then
    echo -e "${RED_COLOR}Building with root user is not supported.${RES}"
    exit 1
fi

# Start time
starttime=`date +'%Y-%m-%d %H:%M:%S'`
CURRENT_DATE=$(date +%s)

# Cpus
cores=`expr $(nproc --all) + 1`

# $CURL_BAR
if curl --help | grep progress-bar >/dev/null 2>&1; then
    CURL_BAR="--progress-bar";
fi

if [ -z "$1" ] || [ "$2" != "nanopi-r4s" -a "$2" != "nanopi-r5s" -a "$2" != "x86_64" -a "$2" != "netgear_r8500" -a "$2" != "armv8" ]; then
    echo -e "\n${RED_COLOR}Building type not specified.${RES}\n"
    echo -e "Usage:\n"
    echo -e "nanopi-r4s releases: ${GREEN_COLOR}bash build.sh rc2 nanopi-r4s${RES}"
    echo -e "nanopi-r4s snapshots: ${GREEN_COLOR}bash build.sh dev nanopi-r4s${RES}"
    echo -e "nanopi-r5s releases: ${GREEN_COLOR}bash build.sh rc2 nanopi-r5s${RES}"
    echo -e "nanopi-r5s snapshots: ${GREEN_COLOR}bash build.sh dev nanopi-r5s${RES}"
    echo -e "x86_64 releases: ${GREEN_COLOR}bash build.sh rc2 x86_64${RES}"
    echo -e "x86_64 snapshots: ${GREEN_COLOR}bash build.sh dev x86_64${RES}"
    echo -e "netgear-r8500 releases: ${GREEN_COLOR}bash build.sh rc2 netgear_r8500${RES}"
    echo -e "netgear-r8500 snapshots: ${GREEN_COLOR}bash build.sh dev netgear_r8500${RES}"
    echo -e "armsr-armv8 releases: ${GREEN_COLOR}bash build.sh rc2 armv8${RES}"
    echo -e "armsr-armv8 snapshots: ${GREEN_COLOR}bash build.sh dev armv8${RES}\n"
    exit 1
fi

# Source branch
if [ "$1" = "dev" ]; then
    export branch=openwrt-24.10
    export version=dev
elif [ "$1" = "rc2" ]; then
    latest_release="v$(curl -s $mirror/tags/v24)"
    export branch=$latest_release
    export version=rc2
fi

# lan
[ -n "$LAN" ] && export LAN=$LAN || export LAN=10.0.0.1

# platform
[ "$2" = "armv8" ] && export platform="armv8" toolchain_arch="aarch64_generic"
[ "$2" = "nanopi-r4s" ] && export platform="rk3399" toolchain_arch="aarch64_generic"
[ "$2" = "nanopi-r5s" ] && export platform="rk3568" toolchain_arch="aarch64_generic"
[ "$2" = "netgear_r8500" ] && export platform="bcm53xx" toolchain_arch="arm_cortex-a9"
[ "$2" = "x86_64" ] && export platform="x86_64" toolchain_arch="x86_64"

# gcc14 & 15
if [ "$USE_GCC13" = y ]; then
    export USE_GCC13=y gcc_version=13
elif [ "$USE_GCC14" = y ]; then
    export USE_GCC14=y gcc_version=14
elif [ "$USE_GCC15" = y ]; then
    export USE_GCC15=y gcc_version=15
else
    export USE_GCC14=y gcc_version=14
fi
[ "$ENABLE_MOLD" = y ] && export ENABLE_MOLD=y

# build.sh flags
export \
    ENABLE_BPF=$ENABLE_BPF \
    ENABLE_DPDK=$ENABLE_DPDK \
    ENABLE_GLIBC=$ENABLE_GLIBC \
    ENABLE_LRNG=$ENABLE_LRNG \
    KERNEL_CLANG_LTO=$KERNEL_CLANG_LTO \
    ROOT_PASSWORD=$ROOT_PASSWORD

# print version
echo -e "\r\n${GREEN_COLOR}Building $branch${RES}\r\n"
if [ "$platform" = "x86_64" ]; then
    echo -e "${GREEN_COLOR}Model: x86_64${RES}"
elif [ "$platform" = "armv8" ]; then
    echo -e "${GREEN_COLOR}Model: armsr/armv8${RES}"
    [ "$1" = "rc2" ] && model="armv8"
elif [ "$platform" = "bcm53xx" ]; then
    echo -e "${GREEN_COLOR}Model: netgear_r8500${RES}"
    [ "$LAN" = "10.0.0.1" ] && export LAN="192.168.1.1"
elif [ "$platform" = "rk3568" ]; then
    echo -e "${GREEN_COLOR}Model: nanopi-r5s/r5c${RES}"
    [ "$1" = "rc2" ] && model="nanopi-r5s"
else
    echo -e "${GREEN_COLOR}Model: nanopi-r4s${RES}"
    [ "$1" = "rc2" ] && model="nanopi-r4s"
fi
get_kernel_version=$(curl -s $mirror/tags/kernel-6.12)
kmod_hash=$(echo -e "$get_kernel_version" | awk -F'HASH-' '{print $2}' | awk '{print $1}' | tail -1 | md5sum | awk '{print $1}')
kmodpkg_name=$(echo $(echo -e "$get_kernel_version" | awk -F'HASH-' '{print $2}' | awk '{print $1}')~$(echo $kmod_hash)-r1)
echo -e "${GREEN_COLOR}Kernel: $kmodpkg_name ${RES}"
echo -e "${GREEN_COLOR}Date: $CURRENT_DATE${RES}\r\n"
echo -e "${GREEN_COLOR}SCRIPT_URL:${RES} ${BLUE_COLOR}$mirror${RES}\r\n"
echo -e "${GREEN_COLOR}GCC VERSION: $gcc_version${RES}"
[ -n "$LAN" ] && echo -e "${GREEN_COLOR}LAN: $LAN${RES}" || echo -e "${GREEN_COLOR}LAN: 10.0.0.1${RES}"
[ -n "$ROOT_PASSWORD" ] && echo -e "${GREEN_COLOR}Default Password:${RES} ${BLUE_COLOR}$ROOT_PASSWORD${RES}" || echo -e "${GREEN_COLOR}Default Password: (${RES}${YELLOW_COLOR}No password${RES}${GREEN_COLOR})${RES}"
[ "$ENABLE_GLIBC" = "y" ] && echo -e "${GREEN_COLOR}Standard C Library:${RES} ${BLUE_COLOR}glibc${RES}" || echo -e "${GREEN_COLOR}Standard C Library:${RES} ${BLUE_COLOR}musl${RES}"
[ "$ENABLE_OTA" = "y" ] && echo -e "${GREEN_COLOR}ENABLE_OTA: true${RES}" || echo -e "${GREEN_COLOR}ENABLE_OTA:${RES} ${YELLOW_COLOR}false${RES}"
[ "$ENABLE_DPDK" = "y" ] && echo -e "${GREEN_COLOR}ENABLE_DPDK: true${RES}" || echo -e "${GREEN_COLOR}ENABLE_DPDK:${RES} ${YELLOW_COLOR}false${RES}"
[ "$ENABLE_MOLD" = "y" ] && echo -e "${GREEN_COLOR}ENABLE_MOLD: true${RES}" || echo -e "${GREEN_COLOR}ENABLE_MOLD:${RES} ${YELLOW_COLOR}false${RES}"
[ "$ENABLE_BPF" = "y" ] && echo -e "${GREEN_COLOR}ENABLE_BPF: true${RES}" || echo -e "${GREEN_COLOR}ENABLE_BPF:${RES} ${RED_COLOR}false${RES}"
[ "$ENABLE_LTO" = "y" ] && echo -e "${GREEN_COLOR}ENABLE_LTO: true${RES}" || echo -e "${GREEN_COLOR}ENABLE_LTO:${RES} ${RED_COLOR}false${RES}"
[ "$ENABLE_LRNG" = "y" ] && echo -e "${GREEN_COLOR}ENABLE_LRNG: true${RES}" || echo -e "${GREEN_COLOR}ENABLE_LRNG:${RES} ${RED_COLOR}false${RES}"
[ "$ENABLE_LOCAL_KMOD" = "y" ] && echo -e "${GREEN_COLOR}ENABLE_LOCAL_KMOD: true${RES}" || echo -e "${GREEN_COLOR}ENABLE_LOCAL_KMOD: false${RES}"
[ "$BUILD_FAST" = "y" ] && echo -e "${GREEN_COLOR}BUILD_FAST: true${RES}" || echo -e "${GREEN_COLOR}BUILD_FAST:${RES} ${YELLOW_COLOR}false${RES}"
[ "$ENABLE_CCACHE" = "y" ] && echo -e "${GREEN_COLOR}ENABLE_CCACHE: true${RES}" || echo -e "${GREEN_COLOR}ENABLE_CCACHE:${RES} ${YELLOW_COLOR}false${RES}"
[ "$MINIMAL_BUILD" = "y" ] && echo -e "${GREEN_COLOR}MINIMAL_BUILD: true${RES}" || echo -e "${GREEN_COLOR}MINIMAL_BUILD: false${RES}"
[ "$KERNEL_CLANG_LTO" = "y" ] && echo -e "${GREEN_COLOR}KERNEL_CLANG_LTO: true${RES}\r\n" || echo -e "${GREEN_COLOR}KERNEL_CLANG_LTO:${RES} ${YELLOW_COLOR}false${RES}\r\n"

# clean old files
rm -rf openwrt master

# openwrt - releases
[ "$(whoami)" = "runner" ] && group "source code"
git clone --depth=1 https://$code_mirror/openwrt/openwrt -b $branch

# immortalwrt master
git clone https://$github/immortalwrt/packages master/immortalwrt_packages --depth=1
[ "$(whoami)" = "runner" ] && endgroup

if [ -d openwrt ]; then
    cd openwrt
    curl -Os $mirror/openwrt/patch/key.tar.gz && tar zxf key.tar.gz && rm -f key.tar.gz
else
    echo -e "${RED_COLOR}Failed to download source code${RES}"
    exit 1
fi

# tags
if [ "$1" = "rc2" ]; then
    git describe --abbrev=0 --tags > version.txt
else
    git branch | awk '{print $2}' > version.txt
fi

# feeds mirror
if [ "$1" = "rc2" ]; then
    packages="^$(grep packages feeds.conf.default | awk -F^ '{print $2}')"
    luci="^$(grep luci feeds.conf.default | awk -F^ '{print $2}')"
    routing="^$(grep routing feeds.conf.default | awk -F^ '{print $2}')"
    telephony="^$(grep telephony feeds.conf.default | awk -F^ '{print $2}')"
else
    packages=";$branch"
    luci=";$branch"
    routing=";$branch"
    telephony=";$branch"
fi
cat > feeds.conf <<EOF
src-git packages https://$code_mirror/openwrt/packages.git$packages
src-git luci https://$code_mirror/openwrt/luci.git$luci
src-git routing https://$code_mirror/openwrt/routing.git$routing
src-git telephony https://$code_mirror/openwrt/telephony.git$telephony
EOF

# Init feeds
[ "$(whoami)" = "runner" ] && group "feeds update -a"
./scripts/feeds update -a
[ "$(whoami)" = "runner" ] && endgroup

[ "$(whoami)" = "runner" ] && group "feeds install -a"
./scripts/feeds install -a
[ "$(whoami)" = "runner" ] && endgroup

# loader dl
if [ -f ../dl.gz ]; then
    tar xf ../dl.gz -C .
fi

###############################################
echo -e "\n${GREEN_COLOR}Patching ...${RES}\n"

# scripts
curl -sO $mirror/openwrt/scripts/00-prepare_base.sh
curl -sO $mirror/openwrt/scripts/01-prepare_base-mainline.sh
curl -sO $mirror/openwrt/scripts/02-prepare_package.sh
curl -sO $mirror/openwrt/scripts/03-convert_translation.sh
curl -sO $mirror/openwrt/scripts/04-fix_kmod.sh
curl -sO $mirror/openwrt/scripts/05-fix-source.sh
curl -sO $mirror/openwrt/scripts/99_clean_build_cache.sh
if [ -n "$git_password" ] && [ -n "$private_url" ]; then
    curl -u openwrt:$git_password -sO "$private_url"
else
    curl -sO $mirror/openwrt/scripts/10-custom.sh
fi
chmod 0755 *sh
[ "$(whoami)" = "runner" ] && group "patching openwrt"
bash 00-prepare_base.sh
bash 01-prepare_base-mainline.sh
bash 02-prepare_package.sh
bash 04-fix_kmod.sh
bash 05-fix-source.sh
[ -f "10-custom.sh" ] && bash 10-custom.sh
find feeds -type f -name "*.orig" -exec rm -f {} \;
[ "$(whoami)" = "runner" ] && endgroup

rm -f 0*-*.sh 10-custom.sh
rm -rf ../master

# Load devices Config
if [ "$platform" = "x86_64" ]; then
    curl -s $mirror/openwrt/24-config-musl-x86 > .config
elif [ "$platform" = "bcm53xx" ]; then
    if [ "$MINIMAL_BUILD" = "y" ]; then
        curl -s $mirror/openwrt/24-config-musl-r8500-minimal > .config
    else
        curl -s $mirror/openwrt/24-config-musl-r8500 > .config
    fi
    sed -i '1i\# CONFIG_PACKAGE_kselftests-bpf is not set\n# CONFIG_PACKAGE_perf is not set\n' .config
elif [ "$platform" = "rk3568" ]; then
    curl -s $mirror/openwrt/24-config-musl-r5s > .config
elif [ "$platform" = "armv8" ]; then
    curl -s $mirror/openwrt/24-config-musl-armsr-armv8 > .config
else
    curl -s $mirror/openwrt/24-config-musl-r4s > .config
fi

# config-common
if [ "$MINIMAL_BUILD" = "y" ]; then
    [ "$platform" != "bcm53xx" ] && curl -s $mirror/openwrt/24-config-minimal-common >> .config
    echo 'VERSION_TYPE="minimal"' >> package/base-files/files/usr/lib/os-release
else
    [ "$platform" != "bcm53xx" ] && curl -s $mirror/openwrt/24-config-common >> .config
    [ "$platform" = "armv8" ] && sed -i '/DOCKER/Id' .config
fi

# ota
[ "$ENABLE_OTA" = "y" ] && [ "$version" = "rc2" ] && echo 'CONFIG_PACKAGE_luci-app-ota=y' >> .config

# bpf
[ "$ENABLE_BPF" = "y" ] && curl -s $mirror/openwrt/generic/config-bpf >> .config

# LTO
export ENABLE_LTO=$ENABLE_LTO
[ "$ENABLE_LTO" = "y" ] && curl -s $mirror/openwrt/generic/config-lto >> .config

# glibc
[ "$ENABLE_GLIBC" = "y" ] && {
    curl -s $mirror/openwrt/generic/config-glibc >> .config
    sed -i '/NaiveProxy/d' .config
}

# DPDK
[ "$ENABLE_DPDK" = "y" ] && {
    echo 'CONFIG_PACKAGE_dpdk-tools=y' >> .config
    echo 'CONFIG_PACKAGE_numactl=y' >> .config
}

# mold
[ "$ENABLE_MOLD" = "y" ] && echo 'CONFIG_USE_MOLD=y' >> .config

# kernel - CLANG + LTO; Allow CONFIG_KERNEL_CC=clang / clang-18 / clang-xx
if [ "$KERNEL_CLANG_LTO" = "y" ]; then
    echo '# Kernel - CLANG LTO' >> .config
    if [ "$USE_GCC15" = "y" ] && [ "$ENABLE_CCACHE" = "y" ]; then
        echo 'CONFIG_KERNEL_CC="ccache clang"' >> .config
    else
        echo 'CONFIG_KERNEL_CC="clang"' >> .config
    fi
    echo 'CONFIG_EXTRA_OPTIMIZATION=""' >> .config
    echo '# CONFIG_PACKAGE_kselftests-bpf is not set' >> .config
fi

# kernel - enable LRNG
if [ "$ENABLE_LRNG" = "y" ]; then
    echo -e "\n# Kernel - LRNG" >> .config
    echo "CONFIG_KERNEL_LRNG=y" >> .config
    echo "# CONFIG_PACKAGE_urandom-seed is not set" >> .config
    echo "# CONFIG_PACKAGE_urngd is not set" >> .config
fi

# local kmod
if [ "$ENABLE_LOCAL_KMOD" = "y" ]; then
    echo -e "\n# local kmod" >> .config
    echo "CONFIG_TARGET_ROOTFS_LOCAL_PACKAGES=y" >> .config
fi

# gcc15 patches
[ "$(whoami)" = "runner" ] && group "patching toolchain"
curl -s $mirror/openwrt/patch/generic-24.10/202-toolchain-gcc-add-support-for-GCC-15.patch | patch -p1

# gcc config
echo -e "\n# gcc ${gcc_version}" >> .config
echo -e "CONFIG_DEVEL=y" >> .config
echo -e "CONFIG_TOOLCHAINOPTS=y" >> .config
echo -e "CONFIG_GCC_USE_VERSION_${gcc_version}=y\n" >> .config
[ "$(whoami)" = "runner" ] && endgroup

# uhttpd
[ "$ENABLE_UHTTPD" = "y" ] && sed -i '/nginx/d' .config && echo 'CONFIG_PACKAGE_ariang=y' >> .config

# not all kmod
[ "$NO_KMOD" = "y" ] && sed -i '/CONFIG_ALL_KMODS=y/d; /CONFIG_ALL_NONSHARED=y/d' .config

# build wwan pkgs for openwrt_core
[ "$OPENWRT_CORE" = "y" ] && curl -s $mirror/openwrt/generic/config-wwan >> .config

# ccache
if [ "$USE_GCC15" = "y" ] && [ "$ENABLE_CCACHE" = "y" ]; then
    echo "CONFIG_CCACHE=y" >> .config
    [ "$(whoami)" = "runner" ] && echo "CONFIG_CCACHE_DIR=\"/builder/.ccache\"" >> .config
    [ "$(whoami)" = "sbwml" ] && echo "CONFIG_CCACHE_DIR=\"/home/sbwml/.ccache\"" >> .config
    tools_suffix="_ccache"
fi

# Toolchain Cache
if [ "$BUILD_FAST" = "y" ]; then
    [ "$ENABLE_GLIBC" = "y" ] && LIBC=glibc || LIBC=musl
    [ "$isCN" = "CN" ] && github_proxy="ghp.ci/" || github_proxy=""
    echo -e "\n${GREEN_COLOR}Download Toolchain ...${RES}"
    PLATFORM_ID=""
    [ -f /etc/os-release ] && source /etc/os-release
    if [ "$PLATFORM_ID" = "platform:el9" ]; then
        TOOLCHAIN_URL="http://127.0.0.1:8080"
    else
        TOOLCHAIN_URL=https://"$github_proxy"github.com/sbwml/openwrt_caches/releases/download/openwrt-24.10
    fi
    curl -L ${TOOLCHAIN_URL}/toolchain_${LIBC}_${toolchain_arch}_gcc-${gcc_version}${tools_suffix}.tar.zst -o toolchain.tar.zst $CURL_BAR
    echo -e "\n${GREEN_COLOR}Process Toolchain ...${RES}"
    tar -I "zstd" -xf toolchain.tar.zst
    rm -f toolchain.tar.zst
    mkdir bin
    find ./staging_dir/ -name '*' -exec touch {} \; >/dev/null 2>&1
    find ./tmp/ -name '*' -exec touch {} \; >/dev/null 2>&1
fi

# init openwrt config
rm -rf tmp/*
if [ "$BUILD" = "n" ]; then
    exit 0
else
    make defconfig
fi

# Compile
if [ "$BUILD_TOOLCHAIN" = "y" ]; then
    echo -e "\r\n${GREEN_COLOR}Building Toolchain ...${RES}\r\n"
    make -j$cores toolchain/compile || make -j$cores toolchain/compile V=s || exit 1
    mkdir -p toolchain-cache
    [ "$ENABLE_GLIBC" = "y" ] && LIBC=glibc || LIBC=musl
    tar -I "zstd -19 -T$(nproc --all)" -cf toolchain-cache/toolchain_${LIBC}_${toolchain_arch}_gcc-${gcc_version}${tools_suffix}.tar.zst ./{build_dir,dl,staging_dir,tmp}
    echo -e "\n${GREEN_COLOR} Build success! ${RES}"
    exit 0
else
    echo -e "\r\n${GREEN_COLOR}Building OpenWrt ...${RES}\r\n"
    sed -i "/BUILD_DATE/d" package/base-files/files/usr/lib/os-release
    sed -i "/BUILD_ID/aBUILD_DATE=\"$CURRENT_DATE\"" package/base-files/files/usr/lib/os-release
    make -j$cores IGNORE_ERRORS="n m"
fi

# Compile time
endtime=`date +'%Y-%m-%d %H:%M:%S'`
start_seconds=$(date --date="$starttime" +%s);
end_seconds=$(date --date="$endtime" +%s);
SEC=$((end_seconds-start_seconds));

if [ -f bin/targets/*/*/sha256sums ]; then
    echo -e "${GREEN_COLOR} Build success! ${RES}"
    echo -e " Build time: $(( SEC / 3600 ))h,$(( (SEC % 3600) / 60 ))m,$(( (SEC % 3600) % 60 ))s"
else
    echo -e "\n${RED_COLOR} Build error... ${RES}"
    echo -e " Build time: $(( SEC / 3600 ))h,$(( (SEC % 3600) / 60 ))m,$(( (SEC % 3600) % 60 ))s"
    echo
    exit 1
fi

if [ "$platform" = "x86_64" ]; then
    if [ "$NO_KMOD" != "y" ]; then
        cp -a bin/targets/x86/*/packages $kmodpkg_name
        rm -f $kmodpkg_name/Packages*
        cp -a bin/packages/x86_64/base/rtl88*a-firmware*.ipk $kmodpkg_name/
        cp -a bin/packages/x86_64/base/natflow*.ipk $kmodpkg_name/
        [ "$OPENWRT_CORE" = "y" ] && {
            cp -a bin/packages/x86_64/base/*3ginfo*.ipk $kmodpkg_name/
            cp -a bin/packages/x86_64/base/*modemband*.ipk $kmodpkg_name/
            cp -a bin/packages/x86_64/base/*sms-tool*.ipk $kmodpkg_name/
            cp -a bin/packages/x86_64/base/*quectel*.ipk $kmodpkg_name/
        }
        [ "$ENABLE_DPDK" = "y" ] && {
            cp -a bin/packages/x86_64/base/*dpdk*.ipk $kmodpkg_name/ || true
            cp -a bin/packages/x86_64/base/*numa*.ipk $kmodpkg_name/ || true
        }
        bash kmod-sign $kmodpkg_name
        tar zcf x86_64-$kmodpkg_name.tar.gz $kmodpkg_name
        rm -rf $kmodpkg_name
    fi
    # OTA json
    if [ "$1" = "rc2" ]; then
        mkdir -p ota
        if [ "$MINIMAL_BUILD" = "y" ]; then
            OTA_URL="https://x86.cooluc.com/d/minimal/openwrt-24.10"
        else
            OTA_URL="https://github.com/sbwml/builder/releases/download"
        fi
        VERSION=$(sed 's/v//g' version.txt)
        SHA256=$(sha256sum bin/targets/x86/64*/*-generic-squashfs-combined-efi.img.gz | awk '{print $1}')
        cat > ota/fw.json <<EOF
{
  "x86_64": [
    {
      "build_date": "$CURRENT_DATE",
      "sha256sum": "$SHA256",
      "url": "$OTA_URL/v$VERSION/openwrt-$VERSION-x86-64-generic-squashfs-combined-efi.img.gz"
    }
  ]
}
EOF
    fi
    # Backup download cache
    if [ "$isCN" = "CN" ] && [ "$1" = "rc2" ]; then
        rm -rf dl/geo* dl/go-mod-cache
        tar cf ../dl.gz dl
    fi
    exit 0
elif [ "$platform" = "armv8" ]; then
    if [ "$NO_KMOD" != "y" ]; then
        cp -a bin/targets/armsr/armv8*/packages $kmodpkg_name
        rm -f $kmodpkg_name/Packages*
        cp -a bin/packages/aarch64_generic/base/rtl88*a-firmware*.ipk $kmodpkg_name/
        cp -a bin/packages/aarch64_generic/base/natflow*.ipk $kmodpkg_name/
        [ "$OPENWRT_CORE" = "y" ] && {
            cp -a bin/packages/aarch64_generic/base/*3ginfo*.ipk $kmodpkg_name/
            cp -a bin/packages/aarch64_generic/base/*modemband*.ipk $kmodpkg_name/
            cp -a bin/packages/aarch64_generic/base/*sms-tool*.ipk $kmodpkg_name/
            cp -a bin/packages/aarch64_generic/base/*quectel*.ipk $kmodpkg_name/
        }
        [ "$ENABLE_DPDK" = "y" ] && {
            cp -a bin/packages/aarch64_generic/base/*dpdk*.ipk $kmodpkg_name/ || true
            cp -a bin/packages/aarch64_generic/base/*numa*.ipk $kmodpkg_name/ || true
        }
        bash kmod-sign $kmodpkg_name
        tar zcf armv8-$kmodpkg_name.tar.gz $kmodpkg_name
        rm -rf $kmodpkg_name
    fi
    # OTA json
    if [ "$1" = "rc2" ]; then
        mkdir -p ota
        VERSION=$(sed 's/v//g' version.txt)
        SHA256=$(sha256sum bin/targets/armsr/armv8*/*-generic-squashfs-combined-efi.img.gz | awk '{print $1}')
        cat > ota/fw.json <<EOF
{
  "armsr,armv8": [
    {
      "build_date": "$CURRENT_DATE",
      "sha256sum": "$SHA256",
      "url": "https://github.com/sbwml/builder/releases/download/v$VERSION/openwrt-$VERSION-armsr-armv8-generic-squashfs-combined-efi.img.gz"
    }
  ]
}
EOF
    fi
    exit 0
elif [ "$platform" = "bcm53xx" ]; then
    if [ "$NO_KMOD" != "y" ]; then
        cp -a bin/targets/bcm53xx/generic/packages $kmodpkg_name
        rm -f $kmodpkg_name/Packages*
        cp -a bin/packages/arm_cortex-a9/base/rtl88*a-firmware*.ipk $kmodpkg_name/
        cp -a bin/packages/arm_cortex-a9/base/natflow*.ipk $kmodpkg_name/
        [ "$OPENWRT_CORE" = "y" ] && {
            cp -a bin/packages/arm_cortex-a9/base/*3ginfo*.ipk $kmodpkg_name/
            cp -a bin/packages/arm_cortex-a9/base/*modemband*.ipk $kmodpkg_name/
            cp -a bin/packages/arm_cortex-a9/base/*sms-tool*.ipk $kmodpkg_name/
            cp -a bin/packages/arm_cortex-a9/base/*quectel*.ipk $kmodpkg_name/
        }
        bash kmod-sign $kmodpkg_name
        tar zcf bcm53xx-$kmodpkg_name.tar.gz $kmodpkg_name
        rm -rf $kmodpkg_name
    fi
    # OTA json
    if [ "$1" = "rc2" ]; then
        mkdir -p ota
        if [ "$MINIMAL_BUILD" = "y" ]; then
            OTA_URL="https://r8500.cooluc.com/d/minimal/openwrt-24.10"
        else
            OTA_URL="https://github.com/sbwml/builder/releases/download"
        fi
        VERSION=$(sed 's/v//g' version.txt)
        SHA256=$(sha256sum bin/targets/bcm53xx/generic/*-bcm53xx-generic-netgear_r8500-squashfs.chk | awk '{print $1}')
        cat > ota/fw.json <<EOF
{
  "netgear,r8500": [
    {
      "build_date": "$CURRENT_DATE",
      "sha256sum": "$SHA256",
      "url": "$OTA_URL/v$VERSION/openwrt-$VERSION-bcm53xx-generic-netgear_r8500-squashfs.chk"
    }
  ]
}
EOF
    fi
    exit 0
else
    if [ "$NO_KMOD" != "y" ] && [ "$platform" != "rk3399" ]; then
        cp -a bin/targets/rockchip/armv8*/packages $kmodpkg_name
        rm -f $kmodpkg_name/Packages*
        cp -a bin/packages/aarch64_generic/base/rtl88*a-firmware*.ipk $kmodpkg_name/
        cp -a bin/packages/aarch64_generic/base/natflow*.ipk $kmodpkg_name/
        [ "$OPENWRT_CORE" = "y" ] && {
            cp -a bin/packages/aarch64_generic/base/*3ginfo*.ipk $kmodpkg_name/
            cp -a bin/packages/aarch64_generic/base/*modemband*.ipk $kmodpkg_name/
            cp -a bin/packages/aarch64_generic/base/*sms-tool*.ipk $kmodpkg_name/
            cp -a bin/packages/aarch64_generic/base/*quectel*.ipk $kmodpkg_name/
        }
        [ "$ENABLE_DPDK" = "y" ] && {
            cp -a bin/packages/aarch64_generic/base/*dpdk*.ipk $kmodpkg_name/ || true
            cp -a bin/packages/aarch64_generic/base/*numa*.ipk $kmodpkg_name/ || true
        }
        bash kmod-sign $kmodpkg_name
        tar zcf aarch64-$kmodpkg_name.tar.gz $kmodpkg_name
        rm -rf $kmodpkg_name
    fi
    # OTA json
    if [ "$1" = "rc2" ]; then
        mkdir -p ota
        OTA_URL="https://github.com/sbwml/builder/releases/download"
        VERSION=$(sed 's/v//g' version.txt)
        if [ "$model" = "nanopi-r4s" ]; then
            [ "$MINIMAL_BUILD" = "y" ] && OTA_URL="https://r4s.cooluc.com/d/minimal/openwrt-24.10"
            SHA256=$(sha256sum bin/targets/rockchip/armv8*/*-squashfs-sysupgrade.img.gz | awk '{print $1}')
            cat > ota/fw.json <<EOF
{
  "friendlyarm,nanopi-r4s": [
    {
      "build_date": "$CURRENT_DATE",
      "sha256sum": "$SHA256",
      "url": "$OTA_URL/v$VERSION/openwrt-$VERSION-rockchip-armv8-friendlyarm_nanopi-r4s-squashfs-sysupgrade.img.gz"
    }
  ]
}
EOF
        elif [ "$model" = "nanopi-r5s" ]; then
            [ "$MINIMAL_BUILD" = "y" ] && OTA_URL="https://r5s.cooluc.com/d/minimal/openwrt-24.10"
            SHA256_R5C=$(sha256sum bin/targets/rockchip/armv8*/*-r5c-squashfs-sysupgrade.img.gz | awk '{print $1}')
            SHA256_R5S=$(sha256sum bin/targets/rockchip/armv8*/*-r5s-squashfs-sysupgrade.img.gz | awk '{print $1}')
            cat > ota/fw.json <<EOF
{
  "friendlyarm,nanopi-r5c": [
    {
      "build_date": "$CURRENT_DATE",
      "sha256sum": "$SHA256_R5C",
      "url": "$OTA_URL/v$VERSION/openwrt-$VERSION-rockchip-armv8-friendlyarm_nanopi-r5c-squashfs-sysupgrade.img.gz"
    }
  ],
  "friendlyarm,nanopi-r5s": [
    {
      "build_date": "$CURRENT_DATE",
      "sha256sum": "$SHA256_R5S",
      "url": "$OTA_URL/v$VERSION/openwrt-$VERSION-rockchip-armv8-friendlyarm_nanopi-r5s-squashfs-sysupgrade.img.gz"
    }
  ]
}
EOF
        fi
    fi
    # Backup download cache
    if [ "$isCN" = "CN" ] && [ "$version" = "rc2" ]; then
        rm -rf dl/geo* dl/go-mod-cache
        tar -cf ../dl.gz dl
    fi
    exit 0
fi

# 很少有人会告诉你为什么要这样做，而是会要求你必须要这样做。
