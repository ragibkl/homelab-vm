# alpine-jellyfin

**Decommissioned 2026-09-27.** Kept as a record of what ran on
`vmbr1-alpine-jellyfin` (Proxmox VM 231, `10.15.1.157`): Jellyfin, an NFS
server and Transmission, all serving `/mnt/sdb1/shared` on a separate 3.7 TB
data disk.

The VM is now `vmbr1-alpine-storage` and runs Garage (see ../alpine-storage), with 1 GB RAM; the
media on the data disk is untouched and these apps are not run. The cluster proxies for jellyfin.bancuh.net and
transmission.bancuh.net were removed from flux-deploy the same day.
