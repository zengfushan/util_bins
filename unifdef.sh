#!/bin/bash
ORI_CMD="$@"

function _dbg_out()
{
	local info="$*"
	echo "dbg $info">&2
}
#_dbg_out "${ORI_CMD}"

SYSROOT=~/cppoutput
PROG=$1
CPP=~/opt/bin/mcpp
PIPE="|"

if [ ${#PROG} -lt 3 ]; then
	if [ "${PROG}" != "cc" ]; then
		exit 0
	fi
else
	if [[ ! ${PROG:0-3} =~ ([^a-zA-Z]|g)cc ]]; then
	if [[ ! "${PROG:0-3}" =~ "g++" ]]; then
	if [[ ! "${PROG:0-5}" =~ "clang" ]]; then
		exit 0
	fi
	fi
	fi
fi

shift

if [[ "${PROG:0-5}" =~ "clang" ]]; then
	cctype="clang"
else
	cctype="gcc"
fi

dbg=0
dbgcmd=0
dbgstate=0
GENERATE_CPP_FILE=1
GENERATE_DBG_FILE=0
GENERATE_CMD_FILE=1
function do_cmd()
{
	local _cmd=$1;
	if [ ${dbgcmd} -ne 0 ]; then
		_dbg_out ""
		_dbg_out "CMD_O: ${_cmd}";
		eval _dbg_out "\"CMD_E: ${_cmd}\"";
	fi
	eval ${_cmd};
}
function dbg_out()
{
	local cond=$1
	local info=$2
	if [ ! $cond -eq 0 ]; then
		_dbg_out "$info"
	fi
}
function dbg_info_out()
{
	local info=$*
	dbg_out $dbg "$info"
}
function dbg_cmd_out()
{
	local info=$*
	dbg_out $dbgcmd "$info"
}
function dbg_state_out()
{
	local info=$*
	dbg_out $dbgstate "$info"
}
function escape_macro_str()
{
	local str=$1
	local no_blank=
	no_blank=`echo ${str} | sed -e 's/.\+=[^ ]\+[ ]\+[^ ].*//'`
	if [ "${no_blank}" != "" ]; then
		echo ${str}
	else
		echo ${str} | sed -e 's/\(.\+\)=\([^"]\+\)/\1="\2"/'
	fi
}

#_dbg_out "$ori_cmd"
#_dbg_out "PID of this script: $$"
#_dbg_out "PPID of this script: $PPID"
#_dbg_out "UID of this script: $UID"
#_dbg_out "`cat /proc/$$/maps`"
#if [ 0 -eq 1 ]; then
#while [ "1" == "1" ]
#do
#	 echo pause>/dev/null
#done
#fi

#skip cmd
shift

# sometimes macro will have spaces, so here use arrays to save each macro
declare -a macro_args
prog_args=
cpp_args=
inc_args=
include_files=
isystem_dirs=
idirafter_dirs=

bcompile=0
bstdinfile=0
bnostdinc=0
bnotcompile=0
pred_h_file=${SYSROOT}/pred.h
src_file_name=
src_is_cpp=0

function handle_args()
{
	#cmd_post_flg:
	#0: neither need it
	#1: gcc should add it
	#2: cpp should add it
	#3: both should add it
	local cmd_post_flg=0
	local tmparg=
	local mac_idx=0
	while [ "$1" != "" ]
	do
		#_dbg_out "handle: $1"
		cmd_post_flg=0
		tmparg=$1
#no one should add it-------------------------------------
		if [ "${tmparg:0:8}" == "-Wp,-MD," ]; then
			:
		elif [ "${tmparg:0:9}" == "-Wp,-MMD," ]; then
			:
		elif [ "${tmparg:0:6}" == "-Wp,-M" ]; then
			:
		elif [ "${tmparg:0:7}" == "-Wp,-MM" ]; then
			:
		elif [ "${tmparg:0:7}" == "-Wp,-MF" ]; then
			:
		elif [ "${tmparg:0:7}" == "-Wp,-MG" ]; then
			:
		elif [ "${tmparg:0:7}" == "-Wp,-MP" ]; then
			:
		elif [ "${tmparg:0:7}" == "-Wp,-MT" ]; then
			:
		elif [ "${tmparg:0:7}" == "-Wp,-MQ" ]; then
			:
		elif [ "${tmparg}" == "-M" ]; then
			:
		elif [ "${tmparg}" == "-MM" ]; then
			:
		elif [ "${tmparg}" == "-MF" ]; then
			shift
			tmparg=$1
		elif [ "${tmparg}" == "-MG" ]; then
			:
		elif [ "${tmparg}" == "-MP" ]; then
			:
		elif [ "${tmparg}" == "-MT" ]; then
			shift
			tmparg=$1
		elif [ "${tmparg}" == "-MQ" ]; then
			shift
			tmparg=$1
		elif [ "${tmparg}" == "-MD" ]; then
			shift
			tmparg=$1
		elif [ "${tmparg}" == "-MMD" ]; then
			shift
			tmparg=$1
		elif [ "${tmparg}" == "-dM" ]; then
			bnotcompile=1
		elif [ "${tmparg}" == "-dD" ]; then
			bnotcompile=1
		elif [ "${tmparg}" == "-dN" ]; then
			bnotcompile=1
		elif [ "${tmparg}" == "-dI" ]; then
			bnotcompile=1
		elif [ "${tmparg}" == "-dU" ]; then
			bnotcompile=1
		elif [ "${tmparg}" == "-c" ]; then
			bcompile=1
		elif [ "${tmparg}" == "-S" ]; then
			bcompile=1
		elif [ "${tmparg}" == "-E" ]; then
			bcompile=1
		elif [ "${tmparg}" == "-o" ]; then
			shift
			tmparg=$1
		elif [ "${tmparg}" == "-" ]; then
			bstdinfile=1
##add manual----------------------------------------------
		elif [ "${tmparg:0:1}" != "-" ]; then
			src_file_name=${tmparg}
		elif [ "${tmparg}" == "-include" ]; then
			shift
			tmparg=$1
			include_files+=" -include ${tmparg}"
		elif [ "${tmparg}" == "-isystem" ]; then
			prog_args+=" ${tmparg}"
			shift
			tmparg=$1
			isystem_dirs+=" -I${tmparg}"
			cmd_post_flg=1
		elif [ "${tmparg}" == "-B" ]; then
		#-B also used for gcc where to find binary to execute
			prog_args+=" ${tmparg}"
			shift
			tmparg=$1
			isystem_dirs+=" -I${tmparg}"
			cmd_post_flg=1
		elif [ "${tmparg:0:2}" == "-B" ]; then
			prog_args+=" ${tmparg}"
			isystem_dirs+=" -I${tmparg:2}"
		elif [ "${tmparg:0:10}" == "-idirafter" ]; then
			prog_args+=" ${tmparg}"
			if [ "${tmparg:10}" != "" ]; then
				idirafter_dirs+=" -I${tmparg:10}"
			else
				shift
				tmparg=$1
				idirafter_dirs+=" -I${tmparg}"
				prog_args+=" ${tmparg}"
			fi
		elif [ "${tmparg}" == "-x" ]; then
			prog_args+=" ${tmparg}"
			shift
			tmparg=$1
			cmd_post_flg=1
		elif [ "${tmparg}" == "-nostdinc" ]; then
			bnostdinc=1
			cmd_post_flg=1
		elif [ "${tmparg}" == "-I" ]; then
			shift
			tmparg=$1
			inc_args+=" -I${tmparg}"
		elif [ "${tmparg:0:2}" == "-I" ]; then
			inc_args+=" ${tmparg}"
		elif [ "${tmparg:0:2}" == "-D" ]; then
			tmparg=`escape_macro_str "${tmparg}"`
			macro_args[${mac_idx}]="-D${tmparg:2}"
			mac_idx=$((mac_idx+1))
		elif [ "${tmparg:0:2}" == "-U" ]; then
			macro_args[${mac_idx}]="-U${tmparg:2}"
			mac_idx=$((mac_idx+1))
		elif [ "${tmparg:0:7}" == "--param" ]; then
			prog_args+=" ${tmparg}"
			shift
			tmparg=$1
			cmd_post_flg=1
#cpp should add it----------------------------------------

#both should add it---------------------------------------
		elif [ "${tmparg}" == "-C" ]; then
			cmd_post_flg=3
		elif [ "${tmparg}" == "-m32" ]; then
			cmd_post_flg=3
		elif [ "${tmparg}" == "-m64" ]; then
			cmd_post_flg=3
#gcc should add it----------------------------------------
		else
			cmd_post_flg=1
			dbg_info_out "unknown option ${tmparg}"
		fi

		if [ ${cmd_post_flg} -eq 1 ]; then
			prog_args+=" ${tmparg}"
		elif [ ${cmd_post_flg} -eq 2 ]; then
			cpp_args+=" ${tmparg}"
		elif [ ${cmd_post_flg} -eq 3 ]; then
			cpp_args+=" ${tmparg}"
			prog_args+=" ${tmparg}"
		fi
		shift
	done
}
# use $@ to handle cases when there are spaces in args
handle_args "$@"


if [ $bnotcompile -ne 0 ]; then
	bcompile=0
elif [ ${bcompile} -eq 0 ]; then
	if [ "${src_file_name}" != "" ]; then
#		if [ "${src_file_name:0:5}" != "/dev/" ]; then
		bcompile=1
#		fi
	fi
fi

function normalize_path()
{
	local lc_path=$1
	readlink -f ${lc_path}
}

#file1 newer than file2
function is_newer()
{
	local lc_file1=$1
	local lc_file2=$2
	local lc_newer=`find ${lc_file1} -newer ${lc_file2}`
	if [ "${lc_newer}" != "" ]; then
		echo 1
	else
		echo 0
	fi
}

#should normalize path first
function is_subdir()
{
	local lc_basedir=$1
	local lc_subdir=$2
	if [ "${lc_subdir:0:${#lc_basedir}}" == "${lc_basedir}" ]; then
		echo 1
	else
		echo 0
	fi
}

function copy_file()
{
	local src_f=$1
	local dst_f=$2
	( flock 9; cat ${src_f}>&9 ) 9>${dst_f}
}

function do_escape()
{
#	echo "$*" | sed -e 's/\"/\\\"/g' | sed -e 's/\([()]\)/\"\1\"/g'
	echo "$*" | sed -e 's/\"\([^"]*\)\"/'"\'\\\"\1\\\"\'/g" | sed -e 's/\([()]\)/\"\1\"/g'
}

function check_is_cpp()
{
	local _file_ext=${1##*.}
	if [ "${_file_ext}" == "cpp" ];then
		echo 1
	elif [ "${_file_ext}" == "cc" ];then
		echo 1
	else
		echo 0
	fi
}

function check_src_file()
{
	local _file_ext=${1##*.}
	if [ "${_file_ext}" == "o" ];then
		echo 0
	else
		echo 1
	fi
}

dbg_info_out "bstdinfile=$bstdinfile bcompile=$bcompile bnostdinc=${bnostdinc} src_file_name=${src_file_name}"
dbg_info_out "PROG=${PROG}"
dbg_info_out "prog_args=${prog_args}"
dbg_info_out "inc_args=${inc_args}"
dbg_info_out "macro_args=${macro_args[*]}"
dbg_info_out "include_files=${include_files}"
dbg_info_out "isystem_dirs=${isystem_dirs}"
dbg_info_out "idirafter_dirs=${idirafter_dirs}"

src_file_valid=`check_src_file "${src_file_name}"`
if [ "${src_file_valid}" != "1" ]; then
	exit 0
fi

if [ $bstdinfile -eq 0 ]; then
if [ $bcompile -ne 0 ]; then
if [ ${src_file_name} != "" ]; then

if [[ "${PROG:0-3}" =~ "g++" ]]; then
	src_is_cpp=1
else
	src_is_cpp=`check_is_cpp "${src_file_name}"`
fi
dbg_info_out "src_is_cpp=${src_is_cpp}"

mkdir -p ${SYSROOT}

if [ ${src_is_cpp} -eq 1 ];then
prog_extra_args=-xc++
else
prog_extra_args=
fi

additional_prefdef=
if [ "${cctype}" = "clang" ]; then
additional_prefdef=$(cat <<- "_ACEOF"
	#define __has_builtin(a) __prog_macro_cached(__has_builtin(a),,)
	#define __has_attribute(a) __prog_macro_cached(__has_attribute(a),,)
	#define __has_feature(a) __prog_macro_cached(__has_feature(a),,)
	#define __has_extension(a) __prog_macro_cached(__has_extension(a),,)
	#define __has_cpp_attribute(a) __prog_macro_cached(__has_cpp_attribute(a),,)
	#define __has_c_attribute(a) __prog_macro_cached(__has_c_attribute(a),,)
	//__has_include_next(a) must be used in directive
	#define __has_include_next(a) __prog_macro_cached(__has_include_next(a),,eval ${__PROG_MACRO_CMD2})
	#define __has_declspec_attribute(a) __prog_macro_cached(__has_declspec_attribute(a),,)
	#define __is_identifier(a) __prog_macro_cached(__is_identifier(a),,)
	#define __has_include(a) __prog_macro_cached(__has_include(a),,)
	#define __has_warning(a) __prog_macro_cached(__has_warning(a),,)
	#define __has_error(a) __prog_macro_cached(__has_error(a),,)
_ACEOF
)
__MACRO_TEST_CODE1='echo -n "${__PROG_MACRO_NAME}"'
__MACRO_TEST_CODE2='{ echo "#if ${__PROG_MACRO_NAME}";echo 1;echo "#else"; echo 0; echo "#endif"; }'
__CLANG_MACRO_CMD="${PROG} -E -xc -P -"
export __PROG_MACRO_CMD2="${__MACRO_TEST_CODE2} | ${__CLANG_MACRO_CMD} | tr -d '\n\r'"
export __PROG_MACRO_CMD="${__MACRO_TEST_CODE1}  | ${__CLANG_MACRO_CMD} | tr -d '\n\r'"
fi

# list of all macro definitions
dbg_state_out "before dump predef pwd=`pwd`"
pred_h_file=`mktemp -t pred.h.XXXXXXXXXXXX`
trap "unlink ${pred_h_file}" EXIT
do_cmd 'cat /dev/null | ${PROG} -E -dM ${prog_extra_args} "${macro_args[@]}" ${prog_args} - >${pred_h_file}'
if [ "${additional_prefdef}" != "" ]; then
do_cmd 'echo "${additional_prefdef}" >> ${pred_h_file}'
fi
#exit 0

filefullpath=`normalize_path ${src_file_name}`
new_file_fullpath=${SYSROOT}/${filefullpath}
mkdir -p ${new_file_fullpath%/*}

#get include path
if [ ${bnostdinc} -eq 0 ]; then
dbg_state_out "before dump include"
cpp_extra_args=`do_cmd "cat /dev/null | ${PROG} -E ${prog_extra_args} ${prog_args} -Wp,-v - 2>&1 | sed -n '/^[ \t]*\//s/^[ \t]*/-I/p' | xargs " `
else
cpp_extra_args=
fi
dbg_info_out "cpp_extra_args=${cpp_extra_args}"

cpp_arg_whole="-nostdinc -include ${pred_h_file} ${include_files} ${inc_args} ${isystem_dirs} ${cpp_extra_args} ${cpp_args} ${idirafter_dirs}"
if [ ${GENERATE_CPP_FILE} -eq 1 ]; then
dbg_state_out "before cpp1"
do_cmd '${CPP} -w -Lki -Lne -z -C -P -N ${cpp_arg_whole} "${macro_args[@]}" -o ${new_file_fullpath} ${src_file_name}'
fi

if [ ${GENERATE_DBG_FILE} -eq 1 ]; then
dbg_state_out "before cpp2"
do_cmd '${CPP} -w -Lne -N ${cpp_arg_whole} "${macro_args[@]}" -o ${new_file_fullpath}.dbg ${src_file_name}'
fi

dbg_state_out "end cpp2"

unlink ${pred_h_file}
trap EXIT

escaped_file_name=${src_file_name##*/}
escaped_file_name=${escaped_file_name//./\\.}
dependency_list=`do_cmd '${PROG} -MM ${include_files} ${inc_args} "${macro_args[@]}" ${prog_args} ${filefullpath}' `
dependency_list=`echo ${dependency_list} | sed 's/\\$//g' | sed 's/[^: ]\{1,\}\.o[[:space:]]*://g' | sed 's/[[:space:]]\{1,\}/\n/g' | sed '/^[[:space:]]*$/d' | xargs `
dbg_info_out "dependency_list=${dependency_list}"
normal_file_name=`normalize_path ${src_file_name}`

if [ ! ${GENERATE_CPP_FILE} -eq 1 ]; then
dependency_list="${dependency_list} ${src_file_name}"
fi

for h_file in ${dependency_list}
do
	normal_h_file=`normalize_path ${h_file}`
	if [ "${normal_file_name}" == "${normal_h_file}" ]; then
		if [ ${GENERATE_CPP_FILE} -eq 1 ]; then
#		 _dbg_out "notcopy ${normal_h_file}"
		continue;
		fi
	fi
#	 _dbg_out "copy ${normal_h_file}"
	new_h_file_full=${SYSROOT}/${normal_h_file}
	mkdir -p ${new_h_file_full%/*}
	if [ -e "${new_h_file_full}" ]; then
	if [ "`is_newer \"${new_h_file_full}\" \"${normal_h_file}\"`" == "0" ]; then
		# copy file in background
		copy_file "${normal_h_file}" "${new_h_file_full}" &
	fi
	else
	# copy file in background
	copy_file "${normal_h_file}" "${new_h_file_full}" &
	fi
done

if [ ${GENERATE_CMD_FILE} -eq 1 ]; then
cmd_file_name="${new_file_fullpath}.cmd"
pwd >${cmd_file_name} 2>&1
do_escape "${ORI_CMD}" >> ${cmd_file_name}
do_escape "cat /dev/null | ${PROG} -E -dM ${prog_extra_args} "${macro_args[@]}" ${prog_args} - >${pred_h_file}" >> ${cmd_file_name}
do_escape "${CPP} -w -Lki -Lne -z -C -P -N ${cpp_arg_whole} "${macro_args[@]}" -o ${new_file_fullpath} ${src_file_name}" >> ${cmd_file_name}
do_escape "${CPP} -w -Lne -N ${cpp_arg_whole} "${macro_args[@]}" -o ${new_file_fullpath}.dbg ${src_file_name}" >> ${cmd_file_name}
fi

fi
fi
fi
# wait all child to finish
wait
exit 0
