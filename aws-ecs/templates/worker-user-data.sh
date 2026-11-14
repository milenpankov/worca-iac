#!/bin/bash
# A worker instance's first boot (Terraform templatefile): join the ECS cluster. Spot interruption
# notices drain the instance; its worker tasks get SIGTERM and runs pause, to resume elsewhere.
set -euo pipefail

cat >> /etc/ecs/ecs.config <<CONFIG
ECS_CLUSTER=${cluster}
ECS_ENABLE_SPOT_INSTANCE_DRAINING=true
ECS_CONTAINER_STOP_TIMEOUT=60s
CONFIG
