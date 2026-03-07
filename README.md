# Local Alpine Linux images

## Flashing and Updating

### Initial Image Install

To write the initial image to your SD card (replace /dev/mmcblk0 with your actual device path):

```
zcat image.img.gz | sudo dd of=/dev/mmcblk0 bs=4M status=progress
```

### Remote Update

If the system is already running and you want to update it over the network using the A/B partition scheme:

```
ssh hostname ab_flash - < image.img.gz
```

## Serial console server

Convert a Raspberry Pi into a remote serial console server using a Digi Edgeport USB-to-Serial converter to manage multiple network devices (switches, routers, etc.) over network.

## SANE scanner node

Use Raspberry Pi as SANE scanner node.
