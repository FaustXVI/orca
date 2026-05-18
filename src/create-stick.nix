{ isoImage, pkgs, ORCA_DISK_NAME, orca_config, ... }:
let
  cvault = orca_config.latest_cvault;
  is_init = cvault == null;
  rootUsbScript = pkgs.writeShellScriptBin "root-iso-to-usb" ''
    set -e
    TARGET_DEVICE="$1"
    function force_unmount(){
      for MOUNTED in $(${pkgs.util-linux}/bin/lsblk -n -o MOUNTPOINTS $TARGET_DEVICE)
      do
        ${pkgs.lib.getExe pkgs.umount} "$MOUNTED"
      done
    }
    force_unmount
    ISO_SIZE=$(wc -c "${isoImage}/iso/${isoImage.isoName}")
    echo "Going to write $ISO_SIZE bytes to the USB stick at $TARGET_DEVICE"
    ${pkgs.util-linux}/bin/wipefs --all --force "$TARGET_DEVICE"
    dd if=${isoImage}/iso/${isoImage.isoName} of="$TARGET_DEVICE" status=progress
    force_unmount
    echo "start=,size=" | ${pkgs.util-linux}/bin/sfdisk -f -a "$TARGET_DEVICE"
    sleep 2
    force_unmount
    ${pkgs.e2fsprogs}/bin/mkfs.ext4 -F -L "${ORCA_DISK_NAME}" ''${TARGET_DEVICE}3
    force_unmount
    ${if !is_init then ''
    BACKUP="$2"
    MOUNT_POINT=$(${pkgs.lib.getExe pkgs.mktemp} -d)
    ${pkgs.lib.getExe pkgs.mount} ''${TARGET_DEVICE}3 $MOUNT_POINT
    tar --same-owner -xf "$BACKUP" -C $MOUNT_POINT
    CVAULT=$(cd $MOUNT_POINT && find . -type f -exec sha256sum -b {} \; | sort -k2 | sha256sum - | cut -d " " -f 1 )
    force_unmount
    if [ "$CVAULT" != "${pkgs.lib.toLower cvault}" ]; then
      echo "$BACKUP has a cvault of $CVAULT but we expected ${cvault}" >&2
      exit -2
    fi
    '' else ""}
    echo "The stick is ready to be used for a ceremony. You should switch it to read-only."
  '';
  usbScript = pkgs.writeShellScriptBin "iso-to-usb" ''
    set -e
    ${if is_init then 
    ''if [ "$#" -ne 1 ]; then
      echo "Usage : $0 /dev/selected_mass_storage" >&2
      echo "with /dev/selected_mass_storage being the raw device (and not a partition) for a USB stick on which to install the vault live image" >&2
      exit -1
    fi'' else
    ''if [ "$#" -ne 2 ]; then
      echo "Usage : $0 /dev/selected_mass_storage /path/to/ORCA_backup.tar" >&2
      echo "with /dev/selected_mass_storage being the raw device (and not a partition) for a USB stick on which to install the vault live image" >&2
      echo "and /path/to/ORCA_backup.tar the path to the backup to restore" >&2
      exit -1
    fi''
    }
    KEY="$1"
    if [ "$(<''${KEY/dev/sys\/block}/removable)" != "1" ]; then
      echo "Error : $KEY is not removable." >&2
      exit -2
    fi
    BACKUP="$2"

    echo "We need to become root in order to format $KEY"

    sudo ${pkgs.lib.getExe rootUsbScript} "$KEY" "$BACKUP"
  '';
in
{
  type = "app";
  program = "${pkgs.lib.getExe usbScript}";
}
