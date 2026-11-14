#!/bin/bash
# The system instance's first boot (Terraform templatefile): join the ECS cluster, mount the
# database volume at /var/lib/worca-db, and keep host-network containers away from the
# instance's credentials. Runs before the ECS agent starts, so no task sees an unmounted volume.
set -euo pipefail

cat >> /etc/ecs/ecs.config <<CONFIG
ECS_CLUSTER=${cluster}
ECS_ENABLE_TASK_IAM_ROLE=true
ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true
ECS_CONTAINER_STOP_TIMEOUT=90s
CONFIG

# The database volume (Nitro: an NVMe device named after the volume id). Formatted once; a
# replacement instance mounts the same data.
dev=/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_$(echo "${volume_id}" | tr -d -)
for _ in $(seq 1 120); do [ -e "$dev" ] && break; sleep 5; done
[ -e "$dev" ] || { echo "the database volume ${volume_id} was not attached" >&2; exit 1; }
blkid "$dev" >/dev/null 2>&1 || mkfs.xfs -q "$dev"
mkdir -p /var/lib/worca-db
grep -q "/var/lib/worca-db" /etc/fstab || echo "$dev /var/lib/worca-db xfs defaults,nofail 0 2" >> /etc/fstab
mount /var/lib/worca-db
chown 1000:1000 /var/lib/worca-db
chmod 0750 /var/lib/worca-db

# The controller's task shares the host network, so the hop limit does not keep it from the
# instance metadata service: only root (the ECS agent) may reach it. Task role credentials come
# from 169.254.170.2, which stays open. Re-applied on every boot.
cat > /var/lib/cloud/scripts/per-boot/imds-root-only.sh <<'SCRIPT'
#!/bin/sh
iptables -C OUTPUT -d 169.254.169.254/32 -m owner ! --uid-owner 0 -j DROP 2>/dev/null \
  || iptables -I OUTPUT -d 169.254.169.254/32 -m owner ! --uid-owner 0 -j DROP
SCRIPT
chmod 0755 /var/lib/cloud/scripts/per-boot/imds-root-only.sh
/var/lib/cloud/scripts/per-boot/imds-root-only.sh
