TARGET := iphone:clang:latest:16.0

# Self-contained IPA packaging: the packaged app resolves CydiaSubstrate from
# the bundled framework via the host binary's @executable_path/Frameworks rpath,
# so the linked install-name must be @rpath (rootless vendor stub), NOT the
# default/rootful absolute /Library/Frameworks path, which does not exist on the
# packaging target and kills the process in dyld before launch.
THEOS_PACKAGE_SCHEME := rootless
ARCHS := arm64
FINALPACKAGE := 1

# The public PwEevee application version leads; ../version.txt stays the internal
# 0.60.5 upstream product line this tree derives from, never the released version.
SG_VERSION := $(or $(shell cat ../public-version.txt 2>/dev/null),$(shell cat ../version.txt 2>/dev/null),0.0.0)
PACKAGE_VERSION := $(SG_VERSION)

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := spotifyglass

spotifyglass_FILES := $(shell find Sources -name '*.m' -o -name '*.x' -o -name '*.swift' | sort)
spotifyglass_CFLAGS := -fobjc-arc -ISources -DSG_VERSION=\"$(SG_VERSION)\"
spotifyglass_FRAMEWORKS := UIKit QuartzCore UniformTypeIdentifiers MediaPlayer CoreImage AudioToolbox AVFoundation CoreHaptics Accelerate Network CoreML CoreMotion CoreText NaturalLanguage

spotifyglass_LOGOS_DEFAULT_GENERATOR := internal

SG_AUDIO := ../vendor/audio
spotifyglass_OBJ_FILES := $(SG_AUDIO)/build/ios/libsgaudio.a
Sources/Shared/AudioEffects/SGDSPCrossfeed.m_CFLAGS := -isystem $(SG_AUDIO)/libbs2b
Sources/Shared/AudioEffects/SGDSPLiveprog.m_CFLAGS := -isystem $(SG_AUDIO)/wdl/eel2

include $(THEOS_MAKE_PATH)/tweak.mk

spotifyglass.all.tweak.variables: sg-audio
.PHONY: sg-audio
sg-audio:
	@$(MAKE) --no-print-directory -C $(SG_AUDIO) PLATFORM=ios

before-all::
	@bash ../scripts/check-layers.sh Sources
