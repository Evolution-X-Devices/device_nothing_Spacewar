#
# Copyright (C) 2024 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
TARGET_SUPPORTS_OMX_SERVICE := false
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit from Spacewar device
$(call inherit-product, device/nothing/Spacewar/device.mk)

# Inherit some common Lineage stuff.
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

#Evolution X Flags
TARGET_INCLUDE_ACCORD := true
TARGET_SUPPORT_BOOT_ANIMATIONS := true
BUILD_BCR := true

# Enforce Product Packages Existance.
TARGET_DISABLE_EPPE := true

#Blur
TARGET_ENABLE_BLUR := true

#Fingerprint
TARGET_HAS_UDFPS := true

#Boot Animation
TARGET_SCREEN_HEIGHT := 2400
TARGET_SCREEN_WIDTH := 1080


# Device identifier. This must come after all inclusions.
PRODUCT_NAME := lineage_Spacewar
PRODUCT_DEVICE := Spacewar
PRODUCT_BRAND := Nothing
PRODUCT_MODEL := A063
PRODUCT_MANUFACTURER := Nothing

PRODUCT_CHARACTERISTICS := nosdcard

PRODUCT_GMS_CLIENTID_BASE := android-nothing

PRODUCT_BUILD_PROP_OVERRIDES += \
    DeviceProduct=Spacewar \
    BuildFingerprint="Nothing/Spacewar/Spacewar:15/AQ3A.240929.001/2509261631:user/release-keys"
