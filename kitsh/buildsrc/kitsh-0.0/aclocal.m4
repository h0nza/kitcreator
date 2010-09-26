AC_DEFUN(DC_DO_TCL, [
	AC_MSG_CHECKING([path to tcl])
	AC_ARG_WITH(tcl, AC_HELP_STRING([--with-tcl], [directory containing tcl configuration (tclConfig.sh)]), [], [
		with_tcl="auto"
	])

	if test "${with_tcl}" = "auto"; then
		for dir in `echo "${PATH}" | sed 's@:@ @g'`; do
			if test -f "${dir}/../lib/tclConfig.sh"; then
				tclconfigsh="${dir}/../lib/tclConfig.sh"
				break
			fi
			if test -f "${dir}/../lib64/tclConfig.sh"; then
				tclconfigsh="${dir}/../lib64/tclConfig.sh"
				break
			fi
		done

		if test -z "${tclconfigsh}"; then
			AC_MSG_ERROR([Unable to find tclConfig.sh])
		fi
	else
		tclconfigsh="${with_tcl}/tclConfig.sh"
	fi

	if test -f "${tclconfigsh}"; then
		source "${tclconfigsh}"

		CFLAGS="${CFLAGS} ${TCL_INCLUDE_SPEC} -I${TCL_SRC_DIR}/generic -I${TCL_SRC_DIR}/unix"
		CPPFLAGS="${CPPFLAGS} ${TCL_INCLUDE_SPEC} -I${TCL_SRC_DIR}/generic -I${TCL_SRC_DIR}/unix"
		LDFLAGS="${LDFLAGS}"
		LIBS="${LIBS} ${TCL_LIBS}"
	fi

	AC_SUBST(CFLAGS)
	AC_SUBST(CPPFLAGS)
	AC_SUBST(LDFLAGS)
	AC_SUBST(LIBS)

	AC_MSG_RESULT([$tclconfigsh])
])

AC_DEFUN(DC_DO_STATIC_LINK_LIBCXX, [
	AC_MSG_CHECKING([for how to statically link to libstdc++])

	SAVELIBS="${LIBS}"
	staticlibcxx=""
	for trylink in "-Wl,-Bstatic -lstdc++ -Wl,-Bdynamic" "-Wl,-Bstatic -lCstd -lCrun -Wl,-Bdynamic" "-lstdc++" "-lCstd -lCrun"; do
		LIBS="${SAVELIBS} ${trylink}"

		AC_LINK_IFELSE(AC_LANG_PROGRAM([], []), [
			staticlibcxx="${trylink}"

			break
		])
	done
	LIBS="${SAVELIBS} ${staticlibcxx}"

	AC_MSG_RESULT([${staticlibcxx}])

	AC_SUBST(LIBS)
])

AC_DEFUN(DC_FIND_TCLKIT_LIBS, [

	for proj in mk4tcl tcl tclvfs; do
		AC_MSG_CHECKING([for libraries required for ${proj}])

		libdir="../../../${proj}/inst"
		libfiles="`find "${libdir}" -name '*.a' | tr "\n" ' '`"

		ARCHS="${ARCHS} ${libfiles}"

		AC_MSG_RESULT([${libfiles}])

		if test "${libfiles}" != ""; then
			upperproj=`echo "${proj}" | dd conv=ucase 2>/dev/null`

			AC_DEFINE(KIT_INCLUDES_$upperproj)

			if test "${proj}" = "mk4tcl"; then
				DC_DO_STATIC_LINK_LIBCXX
			fi
		fi
	done

	AC_SUBST(ARCHS)
])
