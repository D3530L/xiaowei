ARCHS = arm64
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = DidiTingdan
DidiTingdan_FILES = TDDylib.m TDTaskProbe.m TDStore.m TDOverlay.m
DidiTingdan_FRAMEWORKS = UIKit Foundation CoreLocation
DidiTingdan_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/library.mk
