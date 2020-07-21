#! /bin/bash

set -xe

mkdir /app
mkdir /build

export APPLICATION_NAME="${APPLICATION_NAME:-Nextcloud}"
export APPLICATION_ICON_NAME="${APPLICATION_NAME:-Nextcloud}"
export APPLICATION_SHORTNAME="${APPLICATION_SHORTNAME:-Nextcloud}"
export WITH_PROVIDERS="${WITH_PROVIDERS:-ON}"
export BUILD_UPDATER="${BUILD_UPDATER:-ON}"
export APPLICATION_SERVER_URL="${APPLICATION_SERVER_URL:-}"
export OEM_THEME_DIR="${OEM_THEME_DIR:-}"
export CMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-RELEASE}"
export NO_SHIBBOLETH=${NO_SHIBBOLETH:-1}

#Set Qt-5.12
export QT_BASE_DIR=/opt/qt5.12.8
export QTDIR=$QT_BASE_DIR
export PATH=$QT_BASE_DIR/bin:$PATH
export LD_LIBRARY_PATH=$QT_BASE_DIR/lib/x86_64-linux-gnu:$QT_BASE_DIR/lib:$LD_LIBRARY_PATH
export PKG_CONFIG_PATH=$QT_BASE_DIR/lib/pkgconfig:$PKG_CONFIG_PATH

#Set APPID for .desktop file processing
export LINUX_APPLICATION_ID=${LINUX_APPLICATION_ID:-com.nextcloud.desktopclient.nextcloud}

#set defaults
export SUFFIX=${DRONE_PULL_REQUEST:=master}
if [ $SUFFIX != "master" ]; then
    SUFFIX="PR-$SUFFIX"
fi

#QtKeyChain master
cd /build
git clone https://github.com/frankosterfeld/qtkeychain.git
cd qtkeychain
git checkout master
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr ../
make -j4
make DESTDIR=/app install

#Build client
cd /build
mkdir build-client
cd build-client
cmake \
    -Wno-dev \
    -D CMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-RELEASE}" \
    -D CMAKE_INSTALL_PREFIX=/usr \
    -D BUILD_UPDATER=OFF \
    -D QTKEYCHAIN_LIBRARY=/app/usr/lib/x86_64-linux-gnu/libqt5keychain.so \
    -D QTKEYCHAIN_INCLUDE_DIR=/app/usr/include/qt5keychain/ \
    -D NO_SHIBBOLETH=${NO_SHIBBOLETH} \
    -D OEM_THEME_DIR="${OEM_THEME_DIR}" \
    -D APPLICATION_ICON_NAME="${APPLICATION_ICON_NAME}" \
    -D APPLICATION_NAME="${APPLICATION_NAME}" \
    -D APPLICATION_SHORTNAME="${APPLICATION_SHORTNAME}" \
    -D APPLICATION_SERVER_URL="${APPLICATION_SERVER_URL}" \
    -D WITH_PROVIDERS="${WITH_PROVIDERS}" \
    -D MIRALL_VERSION_SUFFIX=PR-${DRONE_PULL_REQUEST} \
    -D MIRALL_VERSION_BUILD=${DONE_BUILD_NUMBER} \
    ${DRONE_WORKSPACE}

make -j4
make DESTDIR=/app install

# Move stuff around
cd /app

mv ./usr/lib/x86_64-linux-gnu/${APPLICATION_SHORTNAME}/* ./usr/lib/x86_64-linux-gnu/
mv ./usr/lib/x86_64-linux-gnu/* ./usr/lib/
rm -rf ./usr/lib/${APPLICATION_SHORTNAME}
rm -rf ./usr/lib/cmake
rm -rf ./usr/include
rm -rf ./usr/mkspecs
rm -rf ./usr/lib/x86_64-linux-gnu/

# Don't bundle ${APPLICATION_SHORTNAME}cmd as we don't run it anyway
rm -rf ./usr/bin/${APPLICATION_SHORTNAME}cmd

# Don't bundle the explorer extentions as we can't do anything with them in the AppImage
rm -rf ./usr/share/caja-python/
rm -rf ./usr/share/nautilus-python/
rm -rf ./usr/share/nemo-python/

# Move sync exclude to right location
mv "./etc/${APPLICATION_SHORTNAME}/sync-exclude.lst" ./usr/bin/
rm -rf ./etc

DESKTOP_FILE=/app/usr/share/applications/${LINUX_APPLICATION_ID}.desktop
sed -i -e 's|Icon=nextcloud|Icon=Nextcloud|g' ${DESKTOP_FILE} # Bug in desktop file?
cp ./usr/share/icons/hicolor/512x512/apps/Nextcloud.png . # Workaround for linuxeployqt bug, FIXME


# Because distros need to get their shit together
cp -R /lib/x86_64-linux-gnu/libssl.so* ./usr/lib/
cp -R /lib/x86_64-linux-gnu/libcrypto.so* ./usr/lib/
cp -P /usr/local/lib/libssl.so* ./usr/lib/
cp -P /usr/local/lib/libcrypto.so* ./usr/lib/

# NSS fun
cp -P -r /usr/lib/x86_64-linux-gnu/nss ./usr/lib/

# Use linuxdeployqt to deploy
cd /build
wget -c "https://github.com/probonopd/linuxdeployqt/releases/download/continuous/linuxdeployqt-continuous-x86_64.AppImage"
chmod a+x linuxdeployqt*.AppImage
./linuxdeployqt-continuous-x86_64.AppImage --appimage-extract
rm ./linuxdeployqt-continuous-x86_64.AppImage
unset QTDIR; unset QT_PLUGIN_PATH ; unset LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/app/usr/lib/
./squashfs-root/AppRun ${DESKTOP_FILE} -bundle-non-qt-libs -qmldir=$DRONE_WORKSPACE/src/gui

# Set origin
./squashfs-root/usr/bin/patchelf --set-rpath '$ORIGIN/' /app/usr/lib/lib${APPLICATION_SHORTNAME}sync.so.0

# Build AppImage
./squashfs-root/AppRun ${DESKTOP_FILE} -appimage

mv *.AppImage ${APPLICATION_SHORTNAME}-${SUFFIX}-${DRONE_COMMIT}-x86_64.AppImage
