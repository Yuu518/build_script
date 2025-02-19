#!/bin/bash

# add nikki
git clone https://github.com/nikkinikki-org/OpenWrt-nikki.git package/new/nikki
if curl -s "https://$mirror/openwrt/24-config-common" | grep -q "^CONFIG_PACKAGE_luci-app-nikki=y"; then
    mkdir -p files/etc/nikki/run/ui
    curl -Lso files/etc/nikki/run/geoip.metadb https://$github/MetaCubeX/meta-rules-dat/releases/download/latest/geoip-lite.metadb
    curl -Lso files/etc/nikki/run/ASN.mmdb https://$github/Yuu518/geoip/raw/release/GeoLite2-ASN.mmdb
    curl -Lso metacubexd-gh-pages.tar.gz https://$github/MetaCubeX/metacubexd/archive/gh-pages.tar.gz
    tar zxf metacubexd-gh-pages.tar.gz
    rm metacubexd-gh-pages.tar.gz
    mv metacubexd-gh-pages files/etc/nikki/run/ui/metacubexd
fi

# add ddns-go
git clone https://$github/sirpdboy/luci-app-ddns-go package/new/ddns-go