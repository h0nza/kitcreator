#! /bin/bash

if [ ! -f 'build.sh' ]; then
	echo 'ERROR: This script must be run from the directory it is in' >&2

	exit 1
fi
if [ -z "${TCLVERS}" ]; then
	echo 'ERROR: The TCLVERS environment variable is not set' >&2

	exit 1
fi

SRC="src/tk${TCLVERS}.tar.gz"
SRCURL="http://prdownloads.sourceforge.net/tcl/tk${TCLVERS}-src.tar.gz"
BUILDDIR="$(pwd)/build/tk${TCLVERS}"
PATCHDIR="$(pwd)/patches"
OUTDIR="$(pwd)/out"
INSTDIR="$(pwd)/inst"
PATCHSCRIPTDIR="$(pwd)/patchscripts"
export SRC SRCURL BUILDDIR PATCHDIR OUTDIR INSTDIR PATCHSCRIPTDIR

# Must be kept in-sync with "../tcl/build.sh"
TCLFOSSILDATE="../tcl/src/tcl${TCLVERS}.tar.gz.date"
export TCLFOSSILDATE

rm -rf 'build' 'out' 'inst'
mkdir 'build' 'out' 'inst' || exit 1

# Determine Tcl version
TCL_VERSION="unknown"
if [ -f "${TCLCONFIGDIR}/tclConfig.sh" ]; then
	source "${TCLCONFIGDIR}/tclConfig.sh"
fi
export TCL_VERSION


if [ ! -f "${SRC}" ]; then
	mkdir 'src' >/dev/null 2>/dev/null

	use_fossil='0'
	if echo "${TCLVERS}" | grep '^cvs_' >/dev/null; then
		use_fossil='1'
	elif echo "${TCLVERS}" | grep '^fossil_' >/dev/null; then
		use_fossil='1'
	fi

	if [ -d 'buildsrc' ]; then
		# Override here to avoid downloading tarball from Fossil if we
		# have a particular tree already available.
		use_fossil='0'
	fi

	if [ "${use_fossil}" = "1" ]; then
		(       
			FOSSILDATE="$(cat "${TCLFOSSILDATE}" 2>/dev/null)"

			cd src || exit 1

			workdir="tmp-$$${RANDOM}${RANDOM}${RANDOM}"
			rm -rf "${workdir}"

			mkdir "${workdir}" || exit 1
			cd "${workdir}" || exit 1

			wget -O "tmp-tk.tar.gz" "http://core.tcl.tk/tk/tarball/tk-fossil.tar.gz?uuid=${FOSSILDATE}" || rm -f 'tmp-tk.tar.gz'
			gzip -dc "tmp-tk.tar.gz" | tar -xf -

			mv "tk-fossil" "tk${TCLVERS}"
                        
			tar -cf - "tk${TCLVERS}" | gzip -c > "../../${SRC}"

			cd ..
			rm -rf "${workdir}"
		)
	else
		if [ ! -d 'buildsrc' ]; then
			rm -f "${SRC}.tmp"
			wget -O "${SRC}.tmp" "${SRCURL}" || exit 1
			mv "${SRC}.tmp" "${SRC}"
		fi
	fi
fi

(
	cd 'build' || exit 1

	if [ ! -d '../buildsrc' ]; then
		gzip -dc "../${SRC}" | tar -xf -
	else    
		cp -rp ../buildsrc/* './'
	fi

	cd "${BUILDDIR}" || exit 1

	# Determine Tk version
	TK_VERSION="$(grep '^#.*define.*TK_VERSION' generic/tk.h 2>/dev/null | sed 's@^# *define[[:space:]][[:space:]]*TK_VERSION[[:space:]][[:space:]]*\"@@;s@\"$@@' 2>/dev/null | head -n 1)"
	if [ -z "${TK_VERSION}" ]; then
		TK_VERSION="unknown"
	fi
	export TK_VERSION

	echo "Note: TCL_VERSION=\"${TCL_VERSION}\""
	echo "Note: TK_VERSION=\"${TK_VERSION}\""

	(
		# Apply required patches
		cd "${BUILDDIR}" || exit 1
		for patch in "${PATCHDIR}/all"/tk-${TK_VERSION}-*.diff "${PATCHDIR}/${TCL_VERSION}"/tk-${TK_VERSION}-*.diff; do
			if [ ! -f "${patch}" ]; then
				continue
			fi

			echo "Applying: ${patch}"
			${PATCH:-patch} -p1 < "${patch}"
		done
	)

	# Apply patch scripts if needed
	for patchscript in "${PATCHSCRIPTDIR}"/*.sh; do
		if [ -f "${patchscript}" ]; then
			echo "Running patch script: ${patchscript}"
                                
			(
				. "${patchscript}"
			)
		fi
	done

	for dir in "${TCLCONFIGDIRTAIL}" unix win macosx win64 __fail__; do
		if [ -z "${dir}" ]; then
			continue
		fi

		if [ "${dir}" = "__fail__" ]; then
			exit 1
		fi

		# Windows/amd64 workarounds
		win64="0"
		if [ "${dir}" = "win64" ]; then
			win64="1"
			dir="win"
		fi

		# Remove previous directory's "tkConfig.sh" if found
		rm -f 'tkConfig.sh'

		cd "${BUILDDIR}/${dir}" || exit 1

		if [ "${dir}" = "win" ]; then
			# Statically link Tk to Tclkit if we are compiling for
			# Windows
			STATICTK="1"

			if [ "${win64}" = "1" ]; then
				# Mingw32 for AMD64 requires this, apparently
				CPPFLAGS="${CPPFLAGS} -D_WIN32_IE=0x0501"
				CFLAGS="${CFLAGS} -D_WIN32_IE=0x0501"
				export CPPFLAGS CFLAGS
			fi
		fi

		if [ "${STATICTK}" = "1" ]; then
			echo "Running: ./configure --disable-shared --disable-symbols --prefix=\"${INSTDIR}\" --with-tcl=\"${TCLCONFIGDIR}\" ${CONFIGUREEXTRA}"
			./configure --disable-shared --disable-symbols --prefix="${INSTDIR}" --with-tcl="${TCLCONFIGDIR}" ${CONFIGUREEXTRA}
		else
			echo "Running: ./configure --enable-shared --disable-symbols --prefix=\"${INSTDIR}\" --with-tcl=\"${TCLCONFIGDIR}\" ${CONFIGUREEXTRA}"
			./configure --enable-shared --disable-symbols --prefix="${INSTDIR}" --with-tcl="${TCLCONFIGDIR}" ${CONFIGUREEXTRA}
		fi

		echo "Running: ${MAKE:-make}"
		${MAKE:-make} || (
			# Workaround a bug in Tk on FreeBSD 8.1:
			#   https://sourceforge.net/tracker/?func=detail&atid=112997&aid=3107390&group_id=12997
			LIBTKFILE="$(ls libtk*.so.1 2>/dev/null | head -1)"
			if [ -f "${LIBTKFILE}" ]; then
				NEWLIBTKFILE="$(echo "${LIBTKFILE}" | sed 's@\.so\.1@.so@')"
				cp "${LIBTKFILE}" "${NEWLIBTKFILE}"
			fi

			${MAKE:-make}
		) || continue

		echo "Running: ${MAKE:-make} install"
		${MAKE:-make} install || continue

		# Update to include resources, if found
		if [ "${dir}" = "win" ]; then
			echo ' *** Importing user-specified icon'
			cp "${KITCREATOR_ICON}" rc/tk.ico

			echo ' *** Importing user-specified resources'
			cat "${KITCREATOR_RC}" | grep -v '^ *tclsh  *ICON' >> "./rc/tk_base.rc"

			echo ' *** Creating tkbase.res.o to support Windows build'
			echo "\"${RC:-windres}\" -o tkbase.res.o  --define STATIC_BUILD --include \"./../generic\" --include \"${TCLCONFIGDIR}/../generic\" --include \"${TCLCONFIGDIR}\" --include \"./rc\" \"./rc/tk_base.rc\""
			"${RC:-windres}" -o tkbase.res.o  --define STATIC_BUILD --include "./../generic" --include "${TCLCONFIGDIR}/../generic" --include "${TCLCONFIGDIR}" --include "./rc" "./rc/tk_base.rc"

			if [ -f "tkbase.res.o" ]; then
				cp "tkbase.res.o" "${INSTDIR}/lib/"
			fi
		fi

		if [ "${STATICTK}" = "1" ]; then
			# If we are building statically, don't create a
			# pkgIndex.tcl
			rm -f "${INSTDIR}"/lib/tk*/pkgIndex.tcl
		else
			# Update pkgIndex to load libtk from the local directory rather
			# than the parent directory
			for pkgIndex in "${INSTDIR}"/lib/tk*/pkgIndex.tcl; do
				sed 's@ \.\. @ @g' "${pkgIndex}" > "${pkgIndex}.new"
				mv "${pkgIndex}.new" "${pkgIndex}"
			done
		fi

		mkdir "${OUTDIR}/lib" || exit 1
		cp -r "${INSTDIR}/lib"/tk* "${OUTDIR}/lib/"
		cp -r "${INSTDIR}/lib"/libtk* "${OUTDIR}/lib"/tk*/
		rm -rf "${OUTDIR}/lib"/tk*/demos

		"${STRIP:-strip}" -g "${OUTDIR}"/lib/tk*/*.so >/dev/null 2>/dev/null
		find "${OUTDIR}" -type f -name '*.a' | xargs rm -f >/dev/null 2>/dev/null

		break
	done

	exit 0
) || exit 1

exit 0
