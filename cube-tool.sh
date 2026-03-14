#!/bin/bash
command_string="$0 $*"

if [ -t 1 ]; then
	reset="\033[0m"
	 bold="\033[1m"
	  red="\033[91m"
	green="\033[32m"
   yellow="\033[33m"
else
	reset=""
	 bold=""
	  red=""
	green=""
   yellow=""
fi

msginfo="c ${bold}${green}CUBE-TOOL        ${reset}"
msghead="c ${bold}${green}CUBE-TOOL   ##   ${reset}"
msgwarn="c ${bold}${yellow}CUBE-TOOL WARNING${reset}"
msgerr="c ${bold}${red}CUBE-TOOL  ERROR${reset}"

# ENCODING DEFAULTS
declare -i enc_ks=0
declare -i enc_tf=0
declare -i enc_ms=0

# SPECIAL PARAMS DEFAULTS
dimacs=""
declare -i vertices=0
declare -i assignment_cutoff=0
declare -i ac_factor=12
declare -i target_cube_count=5000
declare -i prerun_time=600 #seconds
declare -i verify_time=0 #seconds
declare -i cutoff=20000 # smsg --cutoff

# FLAG DEFAULTS
declare -i immediately_conquer=0
declare -i reuse_prerun_args=0 # reuse prerun args for conquer
declare -i reuse_learned_clauses=0 # reuse learned clauses for conquer
declare -i execute_prerun=1

# JOB PARAMS
declare -i pthreads=1
declare -i cube_batch_size=1
env_file=""

python_cmd=python3

prerun_solver="smsg"
prerun_args=()

cuber="march"
declare -rA cuber_command=(
	["march"]="march_cu"
	["sms-def"]="smsg"
	["sms-la-all"]="smsg"
	["sms-la-edge"]="smsg"
)
declare -rA cuber_test=(
	["march"]="march_cu -h"
	["sms-def"]="smsg --help"
	["sms-la-all"]="smsg --help"
	["sms-la-edge"]="smsg --help"
)
declare -rA cuber_ext_cmd=(
	["march"]="march_cu"
	["sms-def"]="smsg --simple-assignment_cutoff"
	["sms-la-all"]="smsg --assignment-cutoff"
	["sms-la-edge"]="smsg --lookahead-only-edge-vars --assignment-cutoff"
)
cube_args=()
tmp_cube_args=()

conquer_solver="${prerun_solver}"
conquer_args=()

echo -e "$msghead invoked by"
echo -e "c '$command_string'"
echo "c"

usage () {
cat <<EOF
usage: cube-tool.sh [args...] dimacs

Writes execution information to /dev/stdout.

The script expects a DIMACS file, or will create its own dimacs file with a default name if a
scenario is selected. It will calculate an "output tag," which is a unique identifier used for
auxiliary files. The files written are as follows:

  dimacs.<tag>.cub           the resulting collection of cubes (also used for intermediate cube
                             sets when computing the assignment cutoff)
  dimacs.<tag>.smp           the simplified formula after prerun
  dimacs.<tag>.lrn           the learned clasues after prerun
  dimacs.<tag>.prerun.log    the log of the prerun; contains any solutions found
  dimacs.<tag>.cube.log      the log of the cubing; contains all attempts
  dimacs.<tag>.cub.job       a qsub-submittable script of an array job that solves all the cubes
                             with the conquer setup given by the options below. This job will be
                             automatically submitted if -i is specified. The results will be
                             written to the directory results_conquer_<tag>

Options:

-h | --help                  print this command line option summary

# PREDEFINED SCENARIOS (only one may be selected)
     --kochen-specker        create the Kochen-Specker encoding (if it does not already exist),
                             and set up SMS args correctly
     --triangle-free         create the Triangle-free  encoding (if it does not already exist),
                             and set up SMS args correctly
     --murty-simon           create the Murty-Simon    encoding (if it does not already exist),
                             and set up SMS args correctly

# CUBER CHOICE
-b | --cuber                 options: ${!cuber_command[*]} (default: $cuber})

# SPECIFIC PARAMETERS
-v | --vertices              smsg --vertices (default $vertices, not meaningful)
-t | --prerun-time           smsg --prerun (formerly --assignment-cutoff-prerun-time; default $prerun_time)
-f | --cutoff                smsg --cutoff (warning: unlike in SMS, the default is $cutoff)
-a | --assignment-cutoff     assignment cutoff for cubing. Omit to determine automatically (default)
-q | --ac-factor             1 / q fraction of the variables as initial guess for assignment cutoff (default $ac_factor)
-r | --target-cube-count     the desired number of cubes when computing assignment cutoff (default $target_cube_count)
-d | --reuse-learned-clauses use learned clauses for solving (conquer), not just for cubing (default off)
-l | --veri-time-limit       perform cube verification for at most this many seconds, 0 means unlimited (default $verify_time)

# GENERAL SOLVER PARAMETERS
-p | --prerun-args           scan all following arguments until '--' and use for prerun
-c | --cube-args             scan all following arguments until '--' and use for cubing
-u | --conquer-args          scan all following arguments until '--' and use for solving (and validation)
-y | --reuse-prerun-args     copy prerun args into conquer args

# FLOW CONTROL
-no-p | --no-prerun          skip prerun, cube original formula
-i | --immediately-conquer   conquer the cubes immediately (submit qsub job at the end of the script)
--pthreads                   make the job script use this many pthreads (default: $pthreads)
--cube-batch-size            each cube solving process should solve this many cubes (default: $cube_batch_size)

# MISC
--py | --python              specify python command (default $python_cmd)
--env                        specify a file to be sourced (for environment variable declarations)
EOF
}

ERRINT="expecting a number after"
ERRSTR="expecting a string after"
checksum="$(md5sum <<< "${*}")"
checksum="${checksum% *}"
checksum="${checksum:0:8}"

while [ $# -gt 0 ]
do
  case $1 in
    -h|--help)                  usage; exit 0;;
### ENCODINGS
	--kochen-specker)           enc_ks=1;;
	--triangle-free)            enc_tf=1;;
	--murty-simon)              enc_ms=1;;
### SOLVER SETTING
    -b|--cuber)              	if [ $# -eq 1 ]; then echo "$ERRSTR $1" && exit 200; else shift; cuber="$1";              fi;;
  --py|--python)                if [ $# -eq 1 ]; then echo "$ERRSTR $1" && exit 200; else shift; python_cmd="$1";         fi;;
       --env)                   if [ $# -eq 1 ]; then echo "$ERRSTR $1" && exit 200; else shift; env_file="$1";           fi;;
### INT ARGS
    -v|--vertices)              if [ $# -eq 1 ]; then echo "$ERRINT $1" && exit 200; else shift; vertices="$1";           fi;;
    -t|--prerun-time)           if [ $# -eq 1 ]; then echo "$ERRINT $1" && exit 201; else shift; prerun_time="$1";        fi;;
    -l|--veri-time-limit)       if [ $# -eq 1 ]; then echo "$ERRINT $1" && exit 201; else shift; verify_time="$1";        fi;;
    -f|--cutoff)                if [ $# -eq 1 ]; then echo "$ERRINT $1" && exit 202; else shift; cutoff="$1";             fi;;
    -a|--assignment-cutoff)     if [ $# -eq 1 ]; then echo "$ERRINT $1" && exit 203; else shift; assignment_cutoff="$1";  fi;;
    -q|--ac-factor)             if [ $# -eq 1 ]; then echo "$ERRINT $1" && exit 204; else shift; ac_factor="$1";          fi;;
    -r|--target-cube-count)     if [ $# -eq 1 ]; then echo "$ERRINT $1" && exit 205; else shift; target_cube_count="$1";  fi;;
       --pthreads)              if [ $# -eq 1 ]; then echo "$ERRINT $1" && exit 206; else shift; pthreads="$1";           fi;;
       --cube-batch-size)       if [ $# -eq 1 ]; then echo "$ERRINT $1" && exit 207; else shift; cube_batch_size="$1";    fi;;
### FLAGS
    -i|--immediately-conquer)   immediately_conquer=1;;
    -y|--reuse-prerun-args)     reuse_prerun_args=1;;
    -d|--reuse-learned-clauses) reuse_learned_clauses=1;;
 -no-p|--no-prerun)             execute_prerun=0;;
### ARRAY ARGS
    -p|--prerun-args)
        shift
        while [ $# -gt 0 ]; do
            if [ "$1" == "--" ]; then
                break
            else
                prerun_args+=("$1");
                shift
            fi
        done
        ;;
    -c|--cube-args)
        shift
        while [ $# -gt 0 ]; do
            if [ "$1" == "--" ]; then
                break
            else
                tmp_cube_args+=("$1");
                shift
            fi
        done
        ;;
    -u|--conquer-args)
        shift
        while [ $# -gt 0 ]; do
            if [ "$1" == "--" ]; then
                break
            else
                conquer_args+=("$1");
                shift
            fi
        done
        ;;
### POSITIONAL ARGS
    *)  if [[ "$1" == -* ]]; then
            echo "unknown argument '$1' (try '-h')"
            exit 219
        elif [ "$dimacs" != "" ]; then
            echo "input CNF file '$dimacs' already specified when positional argument '$1' encountered (try '-h')"
            exit 220
        else
            dimacs="$1"
        fi
        ;;
  esac
  shift
done

if [ "$dimacs" != "" ]; then
    if [ ! -f "$dimacs" ]; then
		echo -e "$msgerr the encoding file '$dimacs' does not exist!"
		exit 221
	fi
    if [ ! -s "$dimacs" ]; then
		echo -e "$msgerr the encoding file '$dimacs' is empty!"
		exit 222
	fi
fi

if [ "$reuse_prerun_args" -eq 1 ]; then
    conquer_args+=("${prerun_args[@]}") # concatenate arrays
	if [ "$cuber" != "march" ]; then
		cube_args+=("${prerun_args[@]}") # concatenate arrays
	fi
fi

if [ "$assignment_cutoff" -eq 0 ]; then
	ac_info="automatic"
else
	ac_info="$assignment_cutoff"
fi

if [ "$vertices" -gt 0 ]; then
	is_already_present=0
	for x in "${prerun_args[@]}"; do
		if [ "$x" == "-v" ] || [ "$x" == "--vertices" ]; then
			is_already_present=1
			echo -e "$msgwarn ${yellow}'$x'${reset} specified twice for prerun, ignoring the global instance"
			break
		fi
	done
	if [ "$is_already_present" -eq 0 ]; then
		prerun_args+=(--vertices "$vertices")
		if [ "$cuber" != "march" ]; then
			cube_args+=(--vertices "$vertices")
		fi
	fi
	
	is_already_present=0
	for x in "${conquer_args[@]}"; do
		if [ "$x" == "-v" ] || [ "$x" == "--vertices" ]; then
			is_already_present=1
			echo -e "$msgwarn ${yellow}'$x'${reset} specified twice for conquer, ignoring the global instance"
			break
		fi
	done
	if [ "$is_already_present" -eq 0 ]; then
		conquer_args+=(--vertices "$vertices")
	fi
fi

if [ "$cutoff" -gt 0 ]; then
	is_already_present=0
	for x in "${prerun_args[@]}"; do
		if [ "$x" == "--cutoff" ]; then
			is_already_present=1
			echo -e "$msgwarn ${yellow}'$x'${reset} specified twice for prerun, ignoring the global instance"
			break
		fi
	done
	if [ "$is_already_present" -eq 0 ]; then
		prerun_args+=(--cutoff "$cutoff")
		if [ "$cuber" != "march" ]; then
			cube_args+=(--cutoff "$cutoff")
		fi
	fi
	
	is_already_present=0
	for x in "${conquer_args[@]}"; do
		if [ "$x" == "--cutoff" ]; then
			is_already_present=1
			echo -e "$msgwarn ${yellow}'$x'${reset} specified twice for conquer, ignoring the global instance"
			break
		fi
	done
	if [ "$is_already_present" -eq 0 ]; then
		conquer_args+=(--cutoff "$cutoff")
	fi
fi

is_already_present=0
for x in "${prerun_args[@]}"; do
	if [ "$x" == "-a" ] || [ "$x" == "--all-graphs" ]; then
		is_already_present=1
		break
	fi
done
if [ "$is_already_present" -eq 0 ]; then
	echo -e "$msginfo appending ${green}'--all-graphs'${reset} to prerun args"
	prerun_args+=(--all-graphs)
	if [ "$cuber" != "march" ]; then
		cube_args+=(--all-graphs)
	fi
fi

is_already_present=0
for x in "${conquer_args[@]}"; do
	if [ "$x" == "-a" ] || [ "$x" == "--all-graphs" ]; then
		is_already_present=1
		break
	fi
done
if [ "$is_already_present" -eq 0 ]; then
	echo -e "$msginfo appending ${green}'--all-graphs'${reset} to conquer args"
	conquer_args+=(--all-graphs)
fi


if [ $((enc_ks + enc_tf + enc_ms)) -gt 1 ]; then
	echo -e "$msgerr cannot specify more than one encoding scenario"
	exit 1;
fi

problem="none"
pyargs_ks=(--vertices "$vertices" --partial-sym-break)
pyargs_tf=(--vertices "$vertices" --partial-sym-break  --no-subsuming-neighborhoods --mtf --chi-low 5 --delta-low 4)
pyargs_ms=(--vertices "$vertices" --partial-sym-break --diam2-critical --num-edges-low $((vertices*vertices/4)) --Delta-upp $((vertices*7/10)))
if [ $((enc_ks + enc_tf + enc_ms)) -eq 1 ]; then
	if [ "$dimacs" != "" ]; then
		echo -e "$msgerr cannot specify both an encoding scenario and an existing DIMACS file"
		exit 1;
	fi
	if [ "$enc_ks" -eq 1 ]; then
		dimacs="ks${vertices}.cnf"
		problem="Kochen-Specker"
		if [ ! -s "$dimacs" ]; then
			echo -e "$msginfo generating $problem encoding into '$green$dimacs$reset'"
			echo -e "$msginfo running '$python_cmd kochen_specker.py ${pyargs_ks[*]} --no-solve > $dimacs'"
			if [ ! -f "kochen_specker.py" ]; then
				echo -e "$msgerr ${red}kochen_specker.py${reset} not found. Please copy into this directory. Cannot create encoding, exiting"
				exit 170
			fi
			$python_cmd kochen_specker.py "${pyargs_ks[@]}" --no-solve > "$dimacs" ||
				{ echo -e "$msgerr failed to create $problem encoding (PySMS not installed or wrong Python used? Specify Python binary with --py)" ; exit 171 ; }
		else
			echo -e "$msginfo $problem encoding found at '$green$dimacs$reset'"
		fi
		# add SMS arguments
		prerun_args+=(--non010)
		prerun_args+=(--triangle-vars $((vertices*(vertices-1)/2+1)))
		conquer_args+=(--non010)
		conquer_args+=(--triangle-vars $((vertices*(vertices-1)/2+1)))
		if [ "$cuber" != "march" ]; then
			cube_args+=(--non010)
			cube_args+=(--triangle-vars $((vertices*(vertices-1)/2+1)))
		fi
	fi
	if [ "$enc_tf" -eq 1 ]; then
		dimacs="tf${vertices}.cnf"
		problem="Triangle-free"
		if [ ! -s "$dimacs" ]; then
			echo -e "$msginfo generating $problem encoding into '$green$dimacs$reset'"
			echo -e "$msginfo running '$python_cmd -m pysms.graph_builder ${pyargs_tf[*]} --no-solve > $dimacs'"
			$python_cmd -m pysms.graph_builder "${pyargs_tf[@]}" --no-solve > "$dimacs" ||
				{ echo -e "$msgerr failed to create $problem encoding (PySMS not installed or wrong Python used? Specify Python binary with --py)" ; exit 181 ; }
		else
			echo -e "$msginfo $problem encoding found at '$green$dimacs$reset'"
		fi
		# add SMS arguments
		prerun_args+=(--chi 5)
		conquer_args+=(--chi 5)
		if [ "$cuber" != "march" ]; then
			cube_args+=(--chi 5)
		fi
	fi
	if [ "$enc_ms" -eq 1 ]; then
		dimacs="ms${vertices}.cnf"
		problem="Murty-Simon"
		if [ ! -s "$dimacs" ]; then
			echo -e "$msginfo generating $problem encoding into '$green$dimacs$reset'"
			echo -e "$msginfo running '$python_cmd -m pysms.graph_builder ${pyargs_ms[*]} --no-solve > $dimacs'"
			$python_cmd -m pysms.graph_builder "${pyargs_ms[@]}" --no-solve > "$dimacs" ||
				{ echo -e "$msgerr failed to create $problem encoding (PySMS not installed or wrong Python used? Specify Python binary with --py)" ; exit 191 ; }
		else
			echo -e "$msginfo $problem encoding found at '$green$dimacs$reset'"
		fi
		# no SMS arguments necessary here
	fi
fi

if [ -n "$env_file" ]; then
	if [ ! -f "$env_file" ]; then
		echo -e "$msgerr the file $red'$env_file'$reset given by --env does not exist"
		exit 1
	fi
fi

# WARNING this is the first time the variable dimacs is reliably populated, DO NOT USE before
echo -e "$msghead args"
echo "c       DIMACS file: $dimacs"
echo "c      no. vertices: $vertices"
if [ "$execute_prerun" -eq 0 ]; then
echo "c       prerun time: no prerun"
else
echo "c       prerun time: $prerun_time"
fi
echo "c assignment cutoff: $ac_info"
echo "c target cube count: $target_cube_count"
if [ "$execute_prerun" -eq 0 ]; then
echo "c       prerun args: no prerun"
else
echo "c       prerun args: ${prerun_args[*]}"
fi
echo "c             cuber: ${cuber} (invoked with '${cuber_ext_cmd["$cuber"]}')"
echo "c         cube args: ${cube_args[*]} ${tmp_cube_args[*]}"
echo "c      conquer args: ${conquer_args[*]}"
echo "c        output tag: ${checksum}"
echo "c          scenario: $problem"

# test availability of cuber command
${cuber_test["$cuber"]} > /dev/null || {
	echo -e "$msgerr cannot run '$red${cuber_command["$cuber"]}$reset', command not on \$PATH?"
	echo -e "$msgerr current PATH"
	tmppath="$PATH"
	while [[ "$tmppath" == *:* ]]; do
		loc="${tmppath%%:*}"
		tmppath="${tmppath#*:}"
		echo "  $loc"
	done
	if [ "$tmppath" != "" ]; then
		echo "  $tmppath"
	fi
	exit 1
}

simplified="${dimacs}.${checksum}.smp"
learned_clauses="${dimacs}.${checksum}.lrn"
enriched="${dimacs}.${checksum}.rich"

prerun_args+=(--prerun "${prerun_time}")
prerun_args+=(--simplify "${simplified}")
prerun_args+=(--learned-clauses "${learned_clauses}")
prerun_args+=(--dimacs "${dimacs}")

prerun_log="${dimacs}.${checksum}.prerun.log"
conquer_log="${dimacs}.${checksum}.conquer.log"
cube_log="${dimacs}.${checksum}.cube.log"

obtain_enriched_formula () {
	echo -e "$msginfo running '$prerun_solver ${prerun_args[*]}'"
    $prerun_solver "${prerun_args[@]}" > "$prerun_log"
	retcode=$?
	echo -e "$msginfo prerun finished (see the log at ${green}'$prerun_log'${reset})"
	#TODO forward retcode of SMS and abort if necessary
	echo -e "$msginfo prerun retcode=$retcode"
}

if [ "$execute_prerun" -eq 1 ]; then
	echo -e "$msginfo"
	echo -e "$msghead starting prerun $(date)"
    obtain_enriched_formula
	if [ ! -f "$simplified" ]; then
		echo -e "$msgerr the enriched formula was not created at '$green$simplified$red'"
		echo -e "$msgerr the reason may be that the instance was solved during prerun, check the log"
		echo -e "$msgerr aborting now"
		exit 160
	fi
else
    simplified="$dimacs"
fi

cube_file="${dimacs}.${checksum}.cub"
cube_neg_file="${cube_file}.neg"
cube_veri_file="${cube_file}.veri"

cube_count_cutoff=$((target_cube_count * 2))
case $cuber in
	march)
		cube_args+=("${simplified}") # dimacs argument to march_cu must appear in the first position
		cube_args+=(-o "${cube_file}")
		cube_args+=("${tmp_cube_args[@]}") # append command-line cube args
		if [ "$assignment_cutoff" -eq 0 ]; then
			cube_args+=(--max-num-cubes "$cube_count_cutoff")
		fi
		cube_args+=(-a)
		;;
	sms-def)
		cube_args+=(--dimacs "${simplified}")
		#cube_args+=(--cube-file "${cube_file}")
		cube_args+=("${tmp_cube_args[@]}") # append command-line cube args
		if [ "$assignment_cutoff" -eq 0 ]; then
			cube_args+=(--max-num-cubes "$cube_count_cutoff")
		fi
		cube_args+=(--simple-assignment-cutoff)
		;;
	sms-la-all)
		cube_args+=(--dimacs "${simplified}")
		#cube_args+=(--cube-file "${cube_file}")
		cube_args+=("${tmp_cube_args[@]}") # append command-line cube args
		if [ "$assignment_cutoff" -eq 0 ]; then
			cube_args+=(--max-num-cubes "$cube_count_cutoff")
		fi
		cube_args+=(--assignment-cutoff)
		;;
	sms-la-edge)
		cube_args+=(--dimacs "${simplified}")
		#cube_args+=(--cube-file "${cube_file}")
		cube_args+=("${tmp_cube_args[@]}") # append command-line cube args
		cube_args+=(--lookahead-only-edge-vars)
		if [ "$assignment_cutoff" -eq 0 ]; then
			cube_args+=(--max-num-cubes "$cube_count_cutoff")
		fi
		cube_args+=(--assignment-cutoff)
		;;
esac

obtain_cubes() {
	{
		echo "c" ;
		echo "c CUBE-TOOL running '${cuber_command["$cuber"]} ${cube_args[*]} $assignment_cutoff'" ;
		echo "c"
	} >> "$cube_log"
	echo -e "$msginfo running '${cuber_command["$cuber"]} ${cube_args[*]} $assignment_cutoff'"
	if [ "$cuber" == "march" ]; then
		cube_time=$(/usr/bin/time -q -f %E ${cuber_command["$cuber"]} "${cube_args[@]}" "$assignment_cutoff" 2>&1 >> "$cube_log")
		retcode=$?
	else
		tmp_log=$(mktemp)
		cube_time=$(/usr/bin/time -q -f %E ${cuber_command["$cuber"]} "${cube_args[@]}" "$assignment_cutoff" 2>&1 > "$tmp_log")
		retcode=$?
		grep "^a" "$tmp_log" > "$cube_file"
		grep -v "^a" "$tmp_log" >> "$cube_log"
		rm "$tmp_log"
	fi
	cube_count=$(wc -l < "${cube_file}")
	return $retcode
}

next_ac_attempt() {
	declare -i ac_prev="$1"
	declare -i ac_last="$2"
	declare -i nc_prev="$3"
	declare -i nc_last="$4"
	declare -i nc_targ="$5"
	declare -i ac_diff=$((ac_last-ac_prev))
	ac_incr=""
	if [ "$ac_diff" -gt 1 ] && [ "$nc_last" -gt "$nc_prev" ]; then
		slowdown_factor="e(l(l(1+l($ac_diff)))*1/4)" # 4th root of essentially log log diff ("1+" for zero evasion)
		slowdown_factor=1 # turn off for now
		ac_incr=$(bc -ql <<< "0.5 + ($ac_diff)/$slowdown_factor*l($nc_targ/$nc_last)/l($nc_last/$nc_prev)")
		ac_incr=${ac_incr%.*}
	fi
	if [ "$ac_incr" == "" ]; then
		ac_incr=0
	fi
	if [ "$((ac_incr*100))" -lt "$ac_diff" ]; then
		ac_incr=$(((ac_diff+99)/100)) # always make at least 1% step
	fi
	echo $((ac_last+ac_incr))
}

sqrt() {
	echo "scale=0; sqrt($1 * $2)" | bc -q
}

#####################
# begin computation #
#####################

header=$(grep -F "p cnf" "$dimacs" | cut -d' ' -f3,4)
nvar=${header% *}
ncls=${header#* }

header_simp=$(grep -F "p cnf" "$simplified" | cut -d' ' -f3,4)
nvar_simp=${header_simp% *}

nvar_edge=$((vertices*(vertices-1)/2))

now="$(date)"
echo "c CUBE-TOOL cubing log $now" > "$cube_log"
echo -e "$msginfo"
echo -e "$msghead starting to cube $now"
if [ "$assignment_cutoff" -gt 0 ]; then
	obtain_cubes
	echo -e "$msginfo obtained $cube_count cubes with assignment cutoff $assignment_cutoff (time taken: $cube_time)"
else
	nvar_total="$nvar_simp"
	if [ "$cuber" == "march" ]; then
		nvar_total="$nvar_simp"
		nvar_fixed=$(${cuber_command["$cuber"]} "${cube_args[@]}" 1 | grep -F "Fixed variables" | cut -d' ' -f4)
	elif [ "$cuber" == "sms-def" ]; then
		nvar_total="$nvar_edge"
		nvar_fixed=$(awk 'BEGIN {t=0} (NF == 2 && $2 == 0 && $1 <= '$nvar_edge' && $1 >= -'$nvar_edge'){t++} END {print t}' "$simplified")
	else
		#nvar_fixed=$(awk 'BEGIN {t=0} (NF == 2 && $2 == 0){t++} END {print t}' "$simplified")
		nvar_total="$nvar_simp"
		nvar_active=$(${cuber_command["$cuber"]} "${cube_args[@]}" 1 | grep -F "Number of active variables" | cut -d' ' -f6)
		nvar_fixed=$((nvar_total-nvar_active))
	fi

    echo -e "$msginfo computing a suitable assignment cutoff value"
    echo -e "$msginfo target #cubes    = $target_cube_count"
	echo -e "$msginfo #fixed vars      = $((nvar_fixed))"
	echo -e "$msginfo #total vars      = $((nvar_total))"
	ac_diff=$(((nvar_total - nvar_fixed)/ac_factor))
	#old_ac="$((nvar_fixed + ac_diff/2 + 1))"
	base_ac="$nvar_fixed"
	base_cube_count=1
	old_ac="$nvar_fixed"
	ac_ub="$nvar_total" # ac guesses should never be more than this
	#old_cube_count=1
	#assignment_cutoff="$old_ac"
    #echo -e "$msginfo reference value  = $assignment_cutoff"
	#old_cube_count=$(obtain_cubes)

	assignment_cutoff=$((nvar_fixed + ac_diff + 1))
    echo -e "$msginfo initial ac guess = $assignment_cutoff"

    obtain_cubes
	cube_status=$?

	# terminate when within 5% of target
	while [ $((cube_count * 20 / 19)) -lt "$target_cube_count" ] || [ "$cube_status" -eq 25 ]; do
        #assignment_cutoff=$((assignment_cutoff + ac_diff))
		#old_cube_count="$cube_count"
		if [ "$cube_status" -eq 25 ]; then
			new_ac=$(sqrt "$old_ac" "$assignment_cutoff")
			ac_ub=$((assignment_cutoff-1)) # adjust ac_ub against which future guesses are compared, and which they should not exceed
			if [ "$new_ac" -eq "$old_ac" ]; then
				new_ac=$((new_ac+1))
			fi
			if [ "$new_ac" -gt "$ac_ub" ]; then
				printf "$msginfo assignment cutoff ${red}%4d${reset} hit the limit of ${green}%4d${reset} cubes, concluding with ${green}%4d${reset} (time taken: $cube_time)\n" "$assignment_cutoff" "$cube_count_cutoff" "$old_ac"
				assignment_cutoff="$old_ac" #old_ac is the largest value that does not go over the limit, break and converge on it
				obtain_cubes
				break
			fi
			printf "$msginfo assignment cutoff ${red}%4d${reset} hit the limit of ${green}%4d${reset} cubes, will try ${green}%4d${reset} (time taken: $cube_time)\n" "$assignment_cutoff" "$cube_count_cutoff" "$new_ac"
			assignment_cutoff="$new_ac"
		else
			printf "$msginfo assignment cutoff ${green}%4d${reset} produced ${green}%4d${reset} cubes (time taken: $cube_time)\n" "$assignment_cutoff" "$cube_count"
			old_ac="$assignment_cutoff"
			#old_cube_count="$cube_count"
			new_ac=$(next_ac_attempt "$base_ac" "$assignment_cutoff" "$base_cube_count" "$cube_count" "$target_cube_count")
			if [ "$new_ac" -le "$assignment_cutoff" ] || [ "$new_ac" -gt "$ac_ub" ]; then
				new_ac=$(sqrt "$assignment_cutoff" "$ac_ub")
				if [ "$new_ac" -le "$assignment_cutoff" ]; then
					new_ac=$((new_ac+1))
				fi
			fi
			assignment_cutoff="$new_ac"
			if [ "$base_cube_count" -eq "$cube_count" ]; then
				base_ac="$assignment_cutoff"
			fi
		fi
		obtain_cubes
		cube_status=$?
    done
    echo -e "$msginfo converged on assignment cutoff ${green}$assignment_cutoff${reset} for a total of ${green}$cube_count${reset} cubes (target was ${yellow}$target_cube_count${reset}; time for last attempt: $cube_time)"
fi
echo -e "$msginfo cubing finished $(date) (see the log at ${green}'$cube_log'${reset})"

# invert cubes for sanity check
# TODO should somehow check the verification result automatically, get a DRAT proof
sed "s/ -/ +/g; s/ \([1-9]\)/ -\1/g; s/ +/ /g; s/^a //" "$cube_file" > "$cube_neg_file" # negate cubes
ncls_veri=$((ncls + cube_count))
echo "p cnf $nvar $ncls_veri" > "$cube_veri_file"
tail -n +2 "$dimacs" >> "$cube_veri_file"
cat "$cube_neg_file" >> "$cube_veri_file"

echo -e "$msginfo"
echo -e "$msghead verifying integrity of the cubes"
if [ "$verify_time" -gt 0 ]; then
	echo -e "$msginfo running 'timeout ${verify_time}s $conquer_solver ${conquer_args[*]} --dimacs $cube_veri_file'"
	timeout "${verify_time}s" $conquer_solver "${conquer_args[@]}" --dimacs "$cube_veri_file"
	if [ $? -eq 124 ]; then
		echo -e "$msgwarn cube verification timed out after ${verify_time} seconds"
		echo -e "$msgwarn cubes may not be correctly verified"
	fi
else
	echo -e "$msginfo running '$conquer_solver ${conquer_args[*]} --dimacs $cube_veri_file'"
	$conquer_solver "${conquer_args[@]}" --dimacs "$cube_veri_file"
fi


if [ "$reuse_learned_clauses" -eq 1 ] && [ -f "$learned_clauses" ] ; then
	ncls_lrn=$(wc -l < "$learned_clauses")
	ncls_rich=$((ncls + ncls_lrn))
	echo "p cnf $nvar $ncls_rich" > "$enriched"
	tail -n +2 "$dimacs" >> "$enriched"
	cat "$learned_clauses" >> "$enriched"
else
	enriched="$dimacs"
fi


# conquer cubes
#if [ "$immediately_conquer" -eq 1 ]; then
#	# sudo apt install parallel
#    parallel -j0 $conquer_solver "${conquer_args[@]}" --dimacs "$enriched" --cube-file "$cube_file" --cube-line {} ">" "$conquer_log.{}" ::: $(seq 1 "$cube_count")
#elif [ "$immediately_conquer" -eq 2 ]; then
conquer_dir="results_conquer_$checksum"
mkdir -p "$conquer_dir"
job_script="$cube_file.job"
sge_task_step=$((pthreads * cube_batch_size))
conquer_args+=(--dimacs "$enriched" --cube-file "$cube_file")
if [ "$cube_batch_size" -gt 1 ]; then
	conquer_args+=(--cubes-range)
else
	conquer_args+=(--cube-line)
fi
echo -e "$msginfo"
echo -e "$msginfo writing qsub job script to ${green}'$job_script'${reset}"
{
	echo "#!/bin/bash" ;
	echo "#$ -V" ;
	echo "#$ -cwd" ;
	echo "#$ -r y" ;
	echo "#$ -t 1:$cube_count:$sge_task_step" ;
	echo "#$ -e $conquer_dir" ;
	echo "#$ -o $conquer_dir" ;
	echo "#$ -l bc4" ;
	echo "#$ -l mem_free=4G" ;
	echo "#$ -l h_rt=250000" ;
	if [ -f "$env_file" ]; then
		echo ". '$env_file'" ;
	fi
	if [ "$pthreads" -gt 1 ]; then
		echo "#$ -pe pthreads $pthreads" ;
		echo "" ;

		echo "for ((i = SGE_TASK_ID; i < SGE_TASK_ID + $sge_task_step; i+=$cube_batch_size)); do" ;
		echo -e "\tif [ \"\$i\" -le $cube_count ]; then" ;
		if [ "$cube_batch_size" -gt 1 ]; then
			echo -e "\t\tlast_cube=\$((\$SGE_TASK_ID + $((cube_batch_size-1))))" ;
			echo -e "\t\tlast_cube=\$((last_cube < $cube_count ? last_cube : $cube_count))" ;
			echo -e "\t\t$conquer_solver ${conquer_args[*]} \$i \$last_cube" \
			 "> $conquer_dir/$conquer_log.o.batch_\${i}_\$last_cube" \
			 "2> $conquer_dir/$conquer_log.e.batch_\${i}_\$last_cube &" ;
		else
			echo -e "\t\t$conquer_solver ${conquer_args[*]} \$i" \
			 "> $conquer_dir/$conquer_log.o.batch_\${i}" \
			 "2> $conquer_dir/$conquer_log.e.batch_\${i} &" ;
		fi
		echo -e "\tfi" ;
		echo "done" ;
		echo "wait" ;
		echo "rm \"\$SGE_STDOUT_PATH\" \"\$SGE_STDERR_PATH"\" ;
	else
		echo "" ;

		if [ "$cube_batch_size" -gt 1 ]; then
			echo -e "last_cube=\$((\$SGE_TASK_ID + $((cube_batch_size-1))))" ;
			echo -e "last_cube=\$((last_cube < $cube_count ? last_cube : $cube_count))" ;
			echo -e "$conquer_solver ${conquer_args[*]} \$SGE_TASK_ID \$last_cube" ;
		else
			echo -e "$conquer_solver ${conquer_args[*]} \$SGE_TASK_ID" ;
		fi
	fi
} > "$job_script"
if [ "$immediately_conquer" -eq 1 ]; then
	echo -e "$msginfo submitting qsub array job"
	qsub "$job_script"
fi
echo -e "$msginfo done"
