# Tên package
TARGET = iphone:clang:latest:8.0
INSTALL_TARGET_PROCESSES = SpringBoard

# Tên module
MODULES = ldid

# Tên tweak chính
TWEAK_NAME = Vcamcobay

# Thêm các file nguồn
Vcamcobay_FILES = Tweak.x
Vcamcobay_FRAMEWORKS = AVFoundation UIKit CoreMedia ImageIO

# Include Theos
include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

# Rule để copy Resources vào đúng vị trí
after-install::
	install.exec "killall SpringBoard"