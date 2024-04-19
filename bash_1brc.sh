#!/bin/bash

# Petr Cvek 2024 for https://1brc.dev/
# MIT License (same as 1brc)

#sample generator used from https://github.com/dannyvankooten/1brc.git

#There are 3 possible categories:
#Vanilla
#	Limited to only 1 main thread and 1 coprocess
#	Seems to run with multiple coprocesses, but bash throws warning
#Recompiled
#	Use multiple coprocesses, which are experimental in bash, needs recompilation
#	Before starting configuration, you need to define MULTIPLE_COPROCS to 1 in bash/config-top.h
#	Also change #!/bin/bash or run manually:
#		path_to_experimental/bash ./bash_1brc.sh measurements.txt 4
#Softened rules
#	Background subshells requires mkfifo utility to create pipes

#NOTICE if you use vanilla bash, you can still use this program, but set JOBS to 1
#code works fastest for 4-5 threads on ryzen 3600
#	for 4 worker threads the main is underused, for 5 it is saturated

#multiple coprocesses on vanilla bash could be created by recursion

#results are stored in the following format, precision is 0.1, rounding up
#STATION_NAME;MIN_TEMPERATURE;AVERAGE_TEMPERATURE;MAX_TEMPERATURE

#######################################################

#Benchmark time depends even on whitespaces
# ((CNT++))				0m17,272s
# CNT=$((CNT+1))		0m20,786s
# ((CNT+=1))			0m17,860s
# ((CNT=CNT+1))			0m18,343s
# ((CNT     =       CNT            +           1))	0m19,051s
# ARR+=(${#ARR[@]}) is 10% slower than ARR[$CNT]=$CNT


#jobs bench for 10M rows (without final sorting)
#8		3m20.271s 3m18.493s 3m18.010s
#7		3m16.187s 3m10.745s 3m13.879s 3m8.987s
#6		2m44.932s 2m42.913s 2m44.238s
#5		2m42.962s 2m44.110s 2m44.254s
#4		2m49.934s 2m52.511s 2m48.420s
#3		3m46.326s 3m49.379s 3m46.112s
#2		5m30.734s 5m31.594s 5m33.132s
#1		10m54.130s

#1st run, 4 JOBS
#real	338m12,274s
#user	219m31,485s
#sys	85m49,691s

#2nd run, 4 JOBS
#real	348m41,391s
#user	228m21,530s
#sys	87m1,022s

#3rd time, 4 JOBS, fixed rounding
# real	342m35,498s
# user	223m33,945s
# sys	85m42,287s


#######################################################


if [ -z "${1}" ]; then
	echo "No input file defined" >&2
	echo "Use ${0} <input file> [number of jobs]" >&2
	echo 'Will return write result into "sorted_<start_time>_<end_time>.txt"' >&2
	exit
else
	MEASUREMENTS="${1}"
fi

if [ -z "${2}" ]; then
	echo "No number of workers set, using 1 worker thread" >&2
	JOBS=1
else
	JOBS=${2}
fi

# JOBS=4

#timestamp for output file, roughly start of the script
printf -v TS_START '%(%s)T' -1

declare -a L
declare -a H
declare -a A
declare -a A_COUNT

IDX=0
#pregenerate statistics for max 10k unique names
#arrays inherited in workers
while [ $IDX -lt 10000 ]; do
	L[$IDX]=1000
	H[$IDX]=-1000
	A[$IDX]=0
	A_COUNT[$IDX]=0

	((IDX++))
done


worker() {
	declare -A NAME2IDX

	local NAME
	local VAL
	local INT_VAL

	local IDX_COUNT=0
	local IDX=0

	local KEY

	IDX=0

	IFS=";"

	#time critical section
	while read -r NAME VAL; do
		[ -z "$NAME" ] && break;

		[[ "$VAL" =~ ^(-*)0*([^\.]*)\.(.)$ ]]
		INT_VAL=${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}

		if [ -n "${NAME2IDX["$NAME"]}" ]; then
			IDX=${NAME2IDX["$NAME"]}
		else
			IDX=$IDX_COUNT

			NAME2IDX["$NAME"]=$IDX

			((IDX_COUNT++))
		fi

		[ $INT_VAL -lt ${L[$IDX]} ] && L[$IDX]=$INT_VAL

		[ $INT_VAL -gt ${H[$IDX]} ] && H[$IDX]=$INT_VAL

		((A[$IDX]+=INT_VAL))

		((A_COUNT[$IDX]++))
	done

	for KEY in ${!NAME2IDX[@]}; do
		IDX=${NAME2IDX["$KEY"]}
		echo "$KEY;${L[$IDX]};${H[$IDX]};${A[$IDX]};${A_COUNT[$IDX]}"
	done

	#signalize end of worker
	echo ";;;;"

	read
}

############ MAIN

#for vanilla bash, you need to save FDs right after starting coprocess
#another started coprocess will overwrite it

#read FDs
declare -a R

#write FDs
declare -a W

J=0
while [ $J -lt $JOBS ]; do
	#spawn coprocesses
	coproc worker

	#COPROC[0] STDOUT from worker
	R+=(${COPROC[0]})

	#COPROC[1] STDIN to worker
	W+=(${COPROC[1]})

	((J++))
done

IFS=";"

#critical section, send each line to workers
J=0
while read -r I; do
	echo "$I" >&${W[$J]}

	((J=(J+1) % $JOBS))
done < "${MEASUREMENTS}"

#signalize load exit to workers
J=0
while [ $J -lt $JOBS ]; do
	echo ";" >&"${W[$J]}"
	((J++))
done


declare -A NAME2IDX
declare -a L
declare -a H
declare -a A
declare -a A_COUNT

IDX_COUNT=0
IDX=0

final_merge() {
	local I_NAME
	local I_L
	local I_H
	local I_A
	local I_A_COUNT

	local FD_IN="$1"

	IFS=";"

	while read -r I_NAME I_L I_H I_A I_A_COUNT; do
		[ -z "$I_NAME" ] && break;

		if [ -n "${NAME2IDX["$I_NAME"]}" ]; then
			IDX=${NAME2IDX["$I_NAME"]}
		else
			IDX=$IDX_COUNT

			NAME2IDX["$I_NAME"]=$IDX

			(( IDX_COUNT++ ))
		fi

		[ $I_L -lt ${L[$IDX]} ] && L[$IDX]=$I_L

		[ $I_H -gt ${H[$IDX]} ] && H[$IDX]=$I_H

		(( A[$IDX] += I_A ))

		(( A_COUNT[$IDX] += I_A_COUNT ))
	done <&${FD_IN}
}

J=0
while [ $J -lt $JOBS ]; do
	final_merge ${R[$J]}
	((J++))
done

################# insertion sort

####test
# NAME2IDX=()
# NAME2IDX["a"]=10
# NAME2IDX["z"]=6
# NAME2IDX["h"]=1
# NAME2IDX["i"]=7
# NAME2IDX["o"]=0
# NAME2IDX["b"]=8
# NAME2IDX["c"]=9
# NAME2IDX["j"]=2
# NAME2IDX["l"]=5
# NAME2IDX["k"]=3
# NAME2IDX["w"]=4
#
#
# dump_unsorted() {
# 	local UNSORTED_IDX=0
# 	while [ $UNSORTED_IDX -lt ${#SORT2IDX[@]} ] ; do
# 		echo -n "${IDX2NAME[${SORT2IDX[$UNSORTED_IDX]}]} "
# 		((UNSORTED_IDX++))
# 	done
#
# 	echo
# }
#
# dump_sorted() {
# 	local SORTED_IDX=0
# 	while [ $SORTED_IDX -lt ${#SORTED[@]} ] ; do
# 		echo -n "${IDX2NAME[${SORTED[$SORTED_IDX]}]} "
# 		((SORTED_IDX++))
# 	done
# 	echo
# }
####test


declare -a IDX2NAME
declare -a SORT2IDX

#make array of names (from asociative names to index)
for KEY in ${!NAME2IDX[@]}; do
	IDX=${NAME2IDX["$KEY"]}
	IDX2NAME[$IDX]="$KEY"
	SORT2IDX[$IDX]=$IDX
done

#first entry always from index 0
declare -a SORTED=( ${SORT2IDX[0]} )

####test
# dump_unsorted
# dump_sorted
####test

#use SORT2IDX as unmodified source for FROM entries
#create growing SORTED as target for TO, sorted

FROM=1
while [ $FROM -lt ${#SORT2IDX[@]} ] ; do
	#go from FROM back to 0

	NAME_FROM="${IDX2NAME[${SORT2IDX[$FROM]}]}"

	#last field
	TO=$(( ${#SORTED[@]} - 1 ))

	#until NAME_TO is lexicographically before NAME_FROM
	#or until TO is at 0
	while : ; do
		NAME_TO="${IDX2NAME[${SORTED[$TO]}]}"

		[[ "$NAME_TO" < "$NAME_FROM" ]] && { ((TO++)); break; }

		[[ $TO -eq 0 ]] && break;

		((TO--))
	done

	if [ $TO -eq 0 ] ; then
		SORTED=( ${SORT2IDX[${FROM}]} ${SORTED[@]} )

	else
		#sorted_bottom inserted sorted_top
		SORTED=( ${SORTED[@]:0:$((${TO}+0))} ${SORT2IDX[${FROM}]} ${SORTED[@]:$((${TO}+0))} )
	fi

# 	dump_sorted

	((FROM++))
done


#timestamp for output file, roughly end of the script (minus final sorting)
printf -v TS_END '%(%s)T' -1

if [ -d ./results ]; then
	RESULTS="./results/sorted_${TS_START}_${TS_END}.txt"
else
	RESULTS="./sorted_${TS_START}_${TS_END}.txt"
fi

#print FINAL output
#TODO single printf line
for IDX in ${SORTED[@]}; do
	(( L_FIXED = L[IDX] ))
	(( L_DECIMAL = L_FIXED/10 ))
	(( L_FRAC = L_FIXED%10 ))
	[ $L_FRAC -lt 0 ] && L_FRAC=$((- L_FRAC))
	printf -v STR_L_FRAC "%01u" $L_FRAC

	#because doing negative fractions is a mess
	if [ ${A[$IDX]} -ge 0 ]; then
		(( A_FIXED = ((A[IDX] * 10)/A_COUNT[IDX]) + 5 ))
		A_SIGN=""
	else
		(( A_FIXED = (((- A[IDX]) * 10)/A_COUNT[IDX]) + 5 ))
		A_SIGN="-"
	fi

	(( A_DECIMAL = A_FIXED/100 ))
	(( A_FRAC = (A_FIXED/10) % 10 ))
	printf -v STR_A_FRAC "%01u" $A_FRAC

# 	echo ${A[$IDX]} ${A_COUNT[$IDX]} $A_FIXED $A_DECIMAL $A_FRAC

	(( H_FIXED = H[IDX] ))
	(( H_DECIMAL = H_FIXED/10 ))
	(( H_FRAC = H_FIXED%10 ))
	[ $H_FRAC -lt 0 ] && H_FRAC=$((- H_FRAC))
	printf -v STR_H_FRAC "%01u" $H_FRAC

	echo "${IDX2NAME[$IDX]};${L_DECIMAL}.${STR_L_FRAC};${A_SIGN}${A_DECIMAL}.${STR_A_FRAC};${H_DECIMAL}.${STR_H_FRAC}"
# done
done > "${RESULTS}"
