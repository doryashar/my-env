#! /bin/bash
CPU_ARCH=$(uname -m)
OS=$(uname -o)
KERNEL_RLS=$(uname -r)
FULL_DETAIL=$(cat /etc/*-release)
#cat /proc/cpuinfo

echo "$OS: $KERNEL_RLS ($CPU_ARCH)\n$FULL_DETAIL"

#readelf -a /proc/self/exe |grep Tag_ABI_VFP_args


#debian will have: /etc/debian_version
#fedore will have: /etc/redhat-release 
#arch will have:  /etc/arch-release
#in general: /etc/os-release
#cat /proc/device-tree/model

#python -c "import platform; print platform.dist()"

## check if it is a raspberry pi, because we'll need a special ruby first
#if [ -x "$(command -v python)" ] ; then
#    R_PI=`python -c "import platform; print 'raspberrypi' in platform.uname()"`

#    if [ "$R_PI" = "True" ] ; then
#        # put your raspberry py code here, in my case I upgrade the ruby version:
#        # run ruby upgrade script. source: https://gist.github.com/blacktm/8302741
#        echo RPI
#    fi
#fi


