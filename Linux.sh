#!/bin/sh

# Set variables
HA_OS_URL="OS_IMAGE_URL" # Replace with the actual URL of the Home Assistant OS image
TARGET_DISK="/dev/sda" # Modify this to your target disk path

# Ensure running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root!"
    exit 1
fi

# Download and write image to disk directly
echo "Downloading and writing Home Assistant OS image to $TARGET_DISK..."
wget -qO- "$HA_OS_URL" | xz -d | dd of="$TARGET_DISK" bs=1M status=progress iflag=fullblock oflag=direct
if [ $? -ne 0 ]; then
    echo "Failed to write image! Please check the disk path or environment."
    exit 1
fi

# Sync buffers
sync

echo "Home Assistant OS installation completed! The system will reboot now."
reboot
