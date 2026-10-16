# Tên package
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = VCNext

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
