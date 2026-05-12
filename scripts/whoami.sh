#!/bin/bash
set -e

CPU_ARCH=$(uname -m)
OS=$(uname -o)
KERNEL_RLS=$(uname -r)
FULL_DETAIL=$(cat /etc/*-release)

echo -e "$OS: $KERNEL_RLS ($CPU_ARCH)\n$FULL_DETAIL"
