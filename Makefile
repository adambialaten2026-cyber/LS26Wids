export THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LS26wids
LS26wids_FILES = Tweak.xm LSWManager.m LSWWidgets.m
LS26wids_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
LS26wids_FRAMEWORKS = UIKit CoreGraphics QuartzCore EventKit

include $(THEOS_MAKE_PATH)/tweak.mk
