#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

# base_vendor.mk adds the HIDL CAS service, which FCM level 8 deprecates, to
# devices that launched with API 33 or lower, and reads this when it is inherited.
# Without it the AIDL service in com.android.hardware.cas is installed instead.
TARGET_REQUIRES_HIDL_CAS_HAL := false

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit from device makefile.
$(call inherit-product, device/xiaomi/gold/device.mk)

# Inherit some common LineageOS stuff.
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

PRODUCT_NAME := lineage_gold
PRODUCT_DEVICE := gold
PRODUCT_MANUFACTURER := Xiaomi
PRODUCT_BRAND := Redmi
PRODUCT_MODEL := 2312DRAABG

PRODUCT_GMS_CLIENTID_BASE := android-xiaomi

# The Dolby app is the audio effects panel
TARGET_EXCLUDES_AUDIOFX := true

# Lunch banner maintainer variable
RISING_MAINTAINER="Ayus"

# Chipset/Maintainer properties (ro.rising.chipset/ro.rising.maintainer) 
# Set RISING_MAINTAINER for version control 
# (Optional if builder is setting properties via init_<device>.cpp)
PRODUCT_BUILD_PROP_OVERRIDES += \
    RisingChipset="Dimensity 6080" \
    RisingMaintainer="Ayus"

# Disable/enable blur support, false by default
TARGET_ENABLE_BLUR := true

# Whether to ship aperture camera, false by default
PRODUCT_NO_CAMERA := false

# Core Gapps
WITH_GMS := true

# Signing keys
PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/lineage-priv/keys/releasekey
PRODUCT_OTA_PUBLIC_KEYS := vendor/lineage-priv/keys/releasekey

# Embed developer ADB key for recovery root access
# Only the maintainer has access to adb in authorised state
PRODUCT_COPY_FILES += \
    vendor/lineage-priv/keys/adbkey.pub:root/adb_keys
