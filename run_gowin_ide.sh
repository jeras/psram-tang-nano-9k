#!/usr/bin/env sh

export QT_QPA_PLATFORM_PLUGIN_PATH=/usr/lib/x86_64-linux-gnu/qt5/plugins
export QT_QPA_PLATFORM=xcb
export QT_XCB_GL_INTEGRATION=none

export QT_AUTO_SCREEN_SCALE_FACTOR=0
export QT_SCALE_FACTOR=1.5
export QT_FONT_DPI=144

#export QT_QPA_PLATFORM=wayland

export GOWIN_PATH=/home/$USER/VLSI/Gowin_V1.9.12.04_linux
export LD_LIBRARY_PATH=$GOWIN_PATH/IDE/lib;
export PATH=$PATH:$GOWIN_PATH/Programmer/bin/
export LD_PRELOAD="/lib/x86_64-linux-gnu/libfreetype.so.6 /usr/lib/x86_64-linux-gnu/libz.so.1"

$GOWIN_PATH/IDE/bin/gw_ide
#$GOWIN_PATH/Programmer/bin/programmer
#LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libfreetype.so.6 $GOWIN_PATH/IDE/lib/libcrypto.so.10" $GOWIN_PATH/IDE/bin/gw_ide
#LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libfreetype.so.6 /usr/lib/x86_64-linux-gnu/libz.so.1 $GOWIN_PATH/IDE/lib/libcrypto.so.10" $GOWIN_PATH/Programmer/bin/programmer

