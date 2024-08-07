#!/bin/bash
# Generate a very minimal filesystem from slackware

set -e

if [ -z "$ARCH" ]; then
  case "$( uname -m )" in
    i?86) ARCH="" ;;
    arm*) ARCH=arm ;;
 aarch64) ARCH=aarch64 ;;
       *) ARCH=64 ;;
  esac
fi

BUILD_NAME=${BUILD_NAME:-"slackware"}
VERSION=${VERSION:="current"}
RELEASENAME=${RELEASENAME:-"slackware${ARCH}"}
RELEASE=${RELEASE:-"${RELEASENAME}-${VERSION}"}
if [ -z "$MIRROR" ]; then
  if [ "$ARCH" = "arm" ] || [ "$ARCH" = "aarch64" ] ; then
    MIRROR=${MIRROR:-"http://slackware.uk/slackwarearm"}
  else
    MIRROR=${MIRROR:-"http://slackware.osuosl.org"}
  fi
fi
CACHEFS=${CACHEFS:-"/tmp/${BUILD_NAME}/${RELEASE}"}
ROOTFS=${ROOTFS:-"/tmp/rootfs-${RELEASE}"}
MINIMAL=${MINIMAL:-yes}
CHECKSUMS=${CHECKSUMS:-no}
CWD=$(pwd)

base_pkgs="a/aaa_base \
	a/elflibs \
	a/aaa_elflibs \
	a/aaa_libraries \
	a/coreutils \
	a/glibc-solibs \
	a/aaa_glibc-solibs \
	a/aaa_terminfo \
	a/fileutils \
	a/sh-utils \
	a/pam \
	a/cracklib \
	a/libpwquality \
	a/lzlib \
	a/e2fsprogs \
	a/nvi \
	a/pkgtools \
	a/shadow \
	a/tar \
	a/xz \
	a/bash \
	a/etc \
	a/gzip \
	a/textutils \
	l/pcre2 \
	l/libpsl \
	l/libusb \
	n/wget \
	n/gnupg \
	a/elvis \
	ap/slackpkg \
	slackpkg-0.99 \
	l/ncurses \
	a/bin \
	a/bzip2 \
	a/grep \
	a/acl \
	l/pcre \
	l/gmp \
	a/attr \
	a/sed \
	a/dialog \
	a/file \
	a/gawk \
	a/time \
	a/gettext \
	a/libcgroup \
	a/patch \
	a/sysfsutils \
	a/time \
	a/tree \
	a/utempter \
	a/which \
	a/util-linux \
	a/elogind \
	l/libseccomp \
	l/mpfr \
	l/libunistring \
	ap/diffutils \
	a/procps \
	n/net-tools \
	a/findutils \
	n/iproute2 \
	n/openssl"

if [ "$VERSION" = "15.0" ] && [ "$ARCH" = "arm" ] ; then
	base_pkgs="installer_fix \
	$base_pkgs"
fi

function cacheit() {
	local file=$1
	local check=$2
	if [ ! -f "${CACHEFS}/${file}"  ] ; then
		mkdir -p $(dirname ${CACHEFS}/${file})
		echo "Fetching ${MIRROR}/${RELEASE}/${file}" >&2
		curl -s -o "${CACHEFS}/${file}" "${MIRROR}/${RELEASE}/${file}"

		if [ "$CHECKSUMS" = "yes" ] || [ "$CHECKSUMS" = "1" ] ; then
			if [ "$check" = "md5" ] || [ "$check" = "both" ] ; then
				(
					cd "${CACHEFS}"
					grep "${file}"$ "CHECKSUMS.md5" | md5sum --strict --check --quiet || { ret=$? && rm -f "${file}" && return "$ret" ; }
				)
			fi
			if [ "$check" = "both" ] ; then
				cacheit "${file}".asc > /dev/null
				gpg --batch --verify "${CACHEFS}/${file}.asc" "${CACHEFS}/${file}" || { ret=$? && rm -f "${CACHEFS}/${file}"* && return "$ret" ; }
			fi
		fi
	fi
	echo "/cdrom/${file}"
}

mkdir -p $ROOTFS $CACHEFS

# clear any checksums, filelists so we know if the cache is up to date
rm -f "${CACHEFS}"/CHECKSUMS.md5*
rm -f "${CACHEFS}"/paths*

if [ "$CHECKSUMS" = "yes" ] || [ "$CHECKSUMS" = "1" ] ; then
	cacheit "CHECKSUMS.md5"
	cacheit "CHECKSUMS.md5.asc"

	gpg --batch --verify "${CACHEFS}/CHECKSUMS.md5.asc" "${CACHEFS}/CHECKSUMS.md5" || { ret=$? && rm "${CACHEFS}/CHECKSUMS.md5"* && exit "$ret" ; }
elif [ "$CHECKSUMS" = "yes-no-checksums-gpg" ] ; then
	CHECKSUMS=1
	cacheit "CHECKSUMS.md5"
fi

if [ -z "$INITRD" ]; then
	if [ "$ARCH" = "arm" ] ; then
		case "$VERSION" in
			12*|13*|14.0|14.1) INITRD=initrd-versatile.img ;;
			*) INITRD=initrd-armv7.img ;;
		esac
	elif [ "$ARCH" = "aarch64" ] ; then
		INITRD=initrd-armv8.img
	else
		INITRD=initrd.img
	fi
fi

if [ "$ARCH" = "aarch64" ] ; then
	cacheit "installer/$INITRD" "md5"
	mv ${CACHEFS}/installer ${CACHEFS}/isolinux
else
	cacheit "isolinux/$INITRD" "md5"
fi

cd $ROOTFS
# extract the initrd to the current rootfs
## ./slackware64-14.2/isolinux/initrd.img:    gzip compressed data, last modified: Fri Jun 24 21:14:48 2016, max compression, from Unix, original size 68600832
## ./slackware64-current/isolinux/initrd.img: XZ compressed data
if file ${CACHEFS}/isolinux/$INITRD | grep -wq XZ ; then
	xzcat "${CACHEFS}/isolinux/$INITRD" | cpio -idvm --null --no-absolute-filenames
else
	zcat "${CACHEFS}/isolinux/$INITRD" > ${CACHEFS}/isolinux/$INITRD.decompressed
	if file ${CACHEFS}/isolinux/$INITRD.decompressed | grep -wq cpio ; then
		< "${CACHEFS}/isolinux/$INITRD".decompressed cpio -idvm --null --no-absolute-filenames
	else
		mkdir -p $ROOTFS.mnt
		mount -o loop ${CACHEFS}/isolinux/$INITRD.decompressed $ROOTFS.mnt
		rsync -aAXHv $ROOTFS.mnt/ $ROOTFS
		umount $ROOTFS.mnt
		rm -rf $ROOTFS.mnt
		if [ -e bin/gzip.bin ] ; then
			(cd bin && ln -sf gzip.bin gzip)
		fi
	fi
	rm "${CACHEFS}/isolinux/$INITRD".decompressed
fi

if stat -c %F $ROOTFS/cdrom | grep -q "symbolic link" ; then
	rm $ROOTFS/cdrom
fi
mkdir -p $ROOTFS/{mnt,cdrom,dev,proc,sys}

for dir in cdrom dev sys proc ; do
	if mount | grep -q $ROOTFS/$dir  ; then
		umount $ROOTFS/$dir
	fi
done

mount --bind $CACHEFS ${ROOTFS}/cdrom
mount -t devtmpfs none ${ROOTFS}/dev
mount --bind -o ro /sys ${ROOTFS}/sys
mount --bind /proc ${ROOTFS}/proc

mkdir -p mnt/etc
cp etc/ld.so.conf mnt/etc

# older versions than 13.37 did not have certain flags
install_args=""
if [ -f ./sbin/upgradepkg ] &&  grep -qw terse ./sbin/upgradepkg ; then
	install_args="--install-new --reinstall --terse"
elif [ -f ./usr/lib/setup/installpkg ] &&  grep -qw terse ./usr/lib/setup/installpkg ; then
	install_args="--terse"
fi

# an update in upgradepkg during the 14.2 -> 15.0 cycle changed/broke this
root_env=""
root_flag=""
if [ -f ./sbin/upgradepkg ] && grep -qw -- '"--root"' ./sbin/upgradepkg ; then
	root_flag="--root /mnt"
elif [ -f ./usr/lib/setup/installpkg ] && grep -qw -- '"-root"' ./usr/lib/setup/installpkg ; then
	root_flag="-root /mnt"
fi
if [ "$VERSION" = "current" ] || [ "${VERSION}" = "15.0" ]; then
	root_env='ROOT=/mnt'
	root_flag=''
fi

relbase=$(echo ${RELEASE} | cut -d- -f1 | sed 's/armedslack/slackware/;s/slackwarearm/slackware/;s/slackwareaarch64/slackware/')
if [ ! -f ${CACHEFS}/paths ] ; then
	bash ${CWD}/get_paths.sh -r ${RELEASE} -m ${MIRROR} > ${CACHEFS}/paths
fi
if [ ! -f ${CACHEFS}/paths-patches ] ; then
	bash ${CWD}/get_paths.sh -r ${RELEASE} -m ${MIRROR} -p > ${CACHEFS}/paths-patches
fi
if [ ! -f ${CACHEFS}/paths-extra ] ; then
	bash ${CWD}/get_paths.sh -r ${RELEASE} -m ${MIRROR} -e > ${CACHEFS}/paths-extra
fi
for pkg in ${base_pkgs}
do
	installer_fix=false
	if [ "$pkg" = "installer_fix" ] ; then
		# see slackwarearm-15.0 ChangeLog entry from Thu Sep 15 08:08:08 UTC 2022
		installer_fix=true
		pkg=a/aaa_glibc-solibs
	fi
	path=$(grep "^packages/$(basename "${pkg}")-" ${CACHEFS}/paths-patches | cut -d : -f 1)
	if [ ${#path} -eq 0 ] ; then
		path=$(grep ^${pkg}- ${CACHEFS}/paths | cut -d : -f 1)
		if [ ${#path} -eq 0 ] ; then
			path=$(grep "^$(basename "${pkg}")/$(basename "${pkg}")-" ${CACHEFS}/paths-extra | cut -d : -f 1)
			if [ ${#path} -eq 0 ] ; then
				echo "$pkg not found"
				continue
			else
				l_pkg=$(cacheit extra/$path "both")
			fi
		else
			l_pkg=$(cacheit $relbase/$path "both")
		fi
	else
		l_pkg=$(cacheit patches/$path "both")
	fi
	if $installer_fix ; then
		echo PATH=/bin:/sbin:/usr/bin:/usr/sbin \
		chroot . /bin/tar-1.13 -xvf ${l_pkg} lib/incoming/libc-2.33.so
		PATH=/bin:/sbin:/usr/bin:/usr/sbin \
		chroot . /bin/tar -xvf ${l_pkg} lib/incoming/libc-2.33.so
		mv lib/incoming/libc-2.33.so lib && rm -rf lib/incoming
		echo PATH=/bin:/sbin:/usr/bin:/usr/sbin \
		chroot . /bin/test -x /bin/sh
		PATH=/bin:/sbin:/usr/bin:/usr/sbin \
		chroot . /bin/test -x /bin/sh # confirm bug is fixed
	elif [ -e ./sbin/upgradepkg ] ; then
		echo PATH=/bin:/sbin:/usr/bin:/usr/sbin \
		ROOT=/mnt \
		chroot . /sbin/upgradepkg ${root_flag} ${install_args} ${l_pkg}
		PATH=/bin:/sbin:/usr/bin:/usr/sbin \
		ROOT=/mnt \
		chroot . /sbin/upgradepkg ${root_flag} ${install_args} ${l_pkg}
	else
		echo PATH=/bin:/sbin:/usr/bin:/usr/sbin \
		ROOT=/mnt \
		chroot . /usr/lib/setup/installpkg ${root_flag} ${install_args} ${l_pkg}
		PATH=/bin:/sbin:/usr/bin:/usr/sbin \
		ROOT=/mnt \
		chroot . /usr/lib/setup/installpkg ${root_flag} ${install_args} ${l_pkg}
	fi
done

cd mnt
PATH=/bin:/sbin:/usr/bin:/usr/sbin \
chroot . /bin/sh -c '/sbin/ldconfig'

if [ ! -e ./root/.gnupg ] && { [ -e ./usr/bin/gpg ] || [ -e ./usr/bin/gpg1 ] ; } ; then
	cacheit "GPG-KEY" "md5"
	cp ${CACHEFS}/GPG-KEY .
	if [ ! -e ./dev/null ] ; then
		touch ./dev/null
	fi
	if [ -e ./usr/bin/gpg1 ] ;  then
		echo PATH=/bin:/sbin:/usr/bin:/usr/sbin \
		GNUPGHOME='' chroot . /usr/bin/gpg1 --import GPG-KEY
		PATH=/bin:/sbin:/usr/bin:/usr/sbin \
		GNUPGHOME='' chroot . /usr/bin/gpg1 --import GPG-KEY
	else
		echo PATH=/bin:/sbin:/usr/bin:/usr/sbin \
		GNUPGHOME='' chroot . /usr/bin/gpg --import GPG-KEY
		PATH=/bin:/sbin:/usr/bin:/usr/sbin \
		GNUPGHOME='' chroot . /usr/bin/gpg --import GPG-KEY
	fi
	find ./root/.gnupg -name '*.lock' -exec rm -rf {} \;
	rm GPG-KEY
fi

set -x
if [ "$MINIMAL" = "yes" ] || [ "$MINIMAL" = "1" ] ; then
	echo "export TERM=linux" >> etc/profile.d/term.sh
	chmod +x etc/profile.d/term.sh
	echo ". /etc/profile" > .bashrc
fi
if [ -e etc/slackpkg ] ; then
	find etc/slackpkg/ -type f -name "*.new" -exec rename ".new" "" {} \;
fi
if [ -e etc/slackpkg/mirrors ] ; then
	echo "${MIRROR}/${RELEASE}/" >> etc/slackpkg/mirrors
	sed -i 's/DIALOG=on/DIALOG=off/' etc/slackpkg/slackpkg.conf
	sed -i 's/POSTINST=on/POSTINST=off/' etc/slackpkg/slackpkg.conf
	sed -i 's/SPINNING=on/SPINNING=off/' etc/slackpkg/slackpkg.conf
	if [ "$VERSION" = "current" ] ; then
		mkdir -p var/lib/slackpkg
		touch var/lib/slackpkg/current
	fi
fi
if [ ! -f etc/rc.d/rc.local ] ; then
	mkdir -p etc/rc.d
	cat >> etc/rc.d/rc.local <<EOF
#!/bin/sh
#
# /etc/rc.d/rc.local:  Local system initialization script.

EOF
	chmod +x etc/rc.d/rc.local
fi

# now some cleanup of the minimal image
set +x
if [ "$MINIMAL" = "yes" ] || [ "$MINIMAL" = "1" ] ; then
	rm -rf usr/share/locale/*
	rm -rf usr/man/*
	find usr/share/terminfo/ -type f ! -name 'linux' -a ! -name 'xterm' -a ! -name 'screen.linux' -exec rm -f "{}" \;
fi
umount $ROOTFS/dev
rm -f dev/* # containers should expect the kernel API (`mount -t devtmpfs none /dev`)

tar --numeric-owner -cf- . > ${CWD}/${RELEASE}.tar
ls -sh ${CWD}/${RELEASE}.tar

for dir in cdrom dev sys proc ; do
	if mount | grep -q $ROOTFS/$dir  ; then
		umount $ROOTFS/$dir
	fi
done

# clear any checksums, filelists for the next run
rm -f "${CACHEFS}"/CHECKSUMS.md5*
rm -f "${CACHEFS}"/paths*
