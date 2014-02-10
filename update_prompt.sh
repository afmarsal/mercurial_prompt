#!/bin/bash

#***************************************************************#
# @name: mp_update_prompt.sh
# @author: Albert Fernandez Marsal
# @description
#	In conjunction with retrieve_repos_info.sh, it shows the info of the
# current mercurial repository in the bash prompt
#***************************************************************#

# List of monitored branches. Use absolute paths, with no soft links!
MP_BRANCH_PATHS=(
$HOME/branches/tuenti-ng
$HOME/branches/android-messenger
)

# Hosted VM name
MP_HOSTED_VM=gemenon

# Sleep time between retries (in seconds)
MP_SLEEP_BETWEEN_REFRESHES=120

# Branch name in prompt will be truncated to these many chars
MP_BRANCH_MAX_LENGTH=12

# Where the files with repo information will be stored
MP_INFO_FILES_STORE=/tmp

# Seconds that when added to the MP_SLEEP_BETWEEN_REFRESHES will
# make a file considered "outdated". Also used for making lock
# file outdated
MP_OUTDATE_INFO_FILE_AFTER=60

# --------------------------------------------------------- #
# DON'T TOUCH THIS
MP_UPDATE_REPO_INFO_SCRIPT=retrieve_repos_info.sh
MP_UPDATE_REPO_INFO_LOCK=$MP_INFO_FILES_STORE/mp_${USER}_${MP_UPDATE_REPO_INFO_SCRIPT}.pid

# --------------------------------------------------------- #
# Writes a message to the stderr stream
# @param $1 the message to print
# @stdout void
# @stderr the message
# @return void
# --------------------------------------------------------- #
mp_debugmsg() {
	if $DEBUG; then 
		echo "$@" 1>&2;
	fi 
}

# --------------------------------------------------------- #
# Writes the elapsed time of the script in milliseconds
# @param $1 message to show along the time
# @assumedvar $t contains the time when the script was started
# in nanoseconds
# @stdout void
# @return void
# @stderr the elapsed time
# --------------------------------------------------------- #
mp_print_elapsed_time() {
	local t2="$(($(date +%s%N)-t))"
	t2=$((t2/1000000))
	mp_debugmsg "Time: $t2 millis ($1)"
}

# --------------------------------------------------------- #
# Prints the name of the file to use for saving the repository
# info
# @param $1 name of the repository
# @stdout file name for storing the repository info
# @return
# --------------------------------------------------------- #
mp_get_repo_info_file() {
	echo -n $MP_INFO_FILES_STORE/mp_${USER}_${@##*/}.dat	
}

# --------------------------------------------------------- #
# Prints the branch name of the current dir
# @param $1 base directory of the repository
# @stdout branch name
# @return
# --------------------------------------------------------- #
mp_get_branch_name() {
	# This is waaaaay faster than invoking "hg ..."
	cat $1/.hg/branch 2>/dev/null || echo invalid-branch
}

# --------------------------------------------------------- #
# Returns the root path of the current repo
# @param void
# @stdout current repo root dir, or nothing if not in a 
# repository
# @return
# --------------------------------------------------------- #
mp_get_current_repo() {
	local currentDir=$(pwd -P)
	for branch in ${MP_BRANCH_PATHS[@]}; do
		if [[ "$currentDir" == "$branch"* ]]; then
			echo -n $branch
			return
		fi
	done
}

# --------------------------------------------------------- #
# Returns whether the file passed as paratemer exists and was
# modified recently
# @param $1 name of the file to check
# @stdout void
# @return TRUE (0) if file exists and is "new", FALSE (1) otherwise 
# --------------------------------------------------------- #
mp_is_file_newer_than() {
	if [[ ! -f $1 ]]; then
		mp_debugmsg "File $1 does not exist"
		return 1
	fi
	local myFile=$1
	local maxSeconds=$(( MP_SLEEP_BETWEEN_REFRESHES + MP_OUTDATE_INFO_FILE_AFTER ))
	local fileDate=$(stat -c %Y $myFile)
	local now=$(date +%s)
	mp_debugmsg "$myFile, $now, $fileDate, $(($now - $fileDate)), $maxSeconds"
	if [[ "$(( now - fileDate ))" -lt "$maxSeconds" ]]; then
		mp_debugmsg "File $myFile is newer than $maxSeconds seconds"
		return 0
	else
		mp_debugmsg "File $myFile is older than $maxSeconds seconds"
		return 1
	fi
}

# --------------------------------------------------------- #
# Prints the part of the prompt corresponding to the host
# name. It sets the color depending on the host
# @param void
# @stdout prompt value
# @return
# --------------------------------------------------------- #
mp_get_host_and_path_part() {
	local hostColor
	local pathColor
	local host=$HOSTNAME

	# devX
	if [[ $host == dev* ]]; then
		hostColor=$EMRED
		pathColor=$EMYELLOW

	# tbox
	elif [[ $host == tbox* ]]; then
		hostColor=$EMGREEN
		pathColor=$EMBLUE
		host=tbox

	# hosted VM
	elif [[ $HOSTNAME == $MP_HOSTED_VM ]]; then	
		hostColor=$EMGREEN
		pathColor=$EMYELLOW

	# localhost
	else
		hostColor=$EMCYAN
		pathColor=$EMYELLOW
		host="local"
	fi

	local showDir=$(pwd)
	echo -n "$hostColor$host$RESET:$pathColor${showDir/$HOME/~}$RESET"
}

# --------------------------------------------------------- #
# Returns the color for the repository part depending on if
# it's clean (0), unknown (?) or dirty (>0)
# @param $1 the string to parse
# @stdout color
# @return
# --------------------------------------------------------- #
mp_get_repo_part_color() {
	if [[ "$1" == "0" ]]; then
		echo -n $cleanColor
	elif [[ "$1" == "?" ]]; then
		echo -n $unknownColor
	else
		echo -n $dirtyColor
	fi
}

# --------------------------------------------------------- #
# Prints the part of the prompt corresponding to the 
# repository: branch, incoming and outgoing changesets, and
# "dirtyness" (pending changes to commit)
# @assumedvars
#	- currentRepo - path of the root of the respository being processed
# @param void
# @stdout prompt value
# @return
# --------------------------------------------------------- #
mp_get_repo_part() {
	local infoFile=$(mp_get_repo_info_file $currentRepo)

	# Some colors configuration
	local delimiterColor=$WHITE
	local branchColor=$GREEN
	local dirtyColor=$WHITE$BGRED
	local unknownColor=$EMBLACK$BGYELLOW
	local cleanColor=$WHITE

	local branchName=$(mp_get_branch_name $currentRepo)
	# Show the branch name truncated if it exceeds limit
	local showBranchName=$branchName
	if [[ ${#branchName} -ge $MP_BRANCH_MAX_LENGTH ]]; then
		showBranchName="~${branchName:(-$MP_BRANCH_MAX_LENGTH)}"
	fi

	local incomingChangesets="?"
	local outgoingChangesets="?"
	local dirtyFiles="?"
	# Check if info file for branch exists and has "updated" information
	if mp_is_file_newer_than $infoFile; then
		local repoInfo=$(cat $infoFile)
		local tokenized=(${repoInfo//,/ })
		# tokenized[0]: branch name
		# tokenized[1]: incoming changesets
		# tokenized[2]: outgoing changesets
		# tokenized[3]: dirty files
		# Check that we are on the branch we have the info for
		if [ "$branchName" == "${tokenized[0]}" ]; then
			incomingChangesets=${tokenized[1]}
			outgoingChangesets=${tokenized[2]}
			dirtyFiles=${tokenized[3]}
		fi
	fi
	# Build branch colors
	local colorIncoming=$(mp_get_repo_part_color $incomingChangesets)
	local colorOutgoing=$(mp_get_repo_part_color $outgoingChangesets)	
	local colorDirtyness=$(mp_get_repo_part_color $dirtyFiles)

	repoPrompt="$delimiterColor[$branchColor$showBranchName: $colorIncoming${incomingChangesets}i${delimiterColor}/${colorOutgoing}${outgoingChangesets}o$RESET"
	# Only add "dirtyness" if it's dirty
	[[ "$dirtyFiles" != "0" ]] && repoPrompt="$repoPrompt ${colorDirtyness}*"
	repoPrompt="$repoPrompt$delimiterColor]$RESET"

	echo -n $repoPrompt
}

# --------------------------------------------------------- #
# Prints the value of the prompt with the repo 
# information if the current directory matches one of the
# monitored ones
# @param void
# @stdout prompt value
# @return
# --------------------------------------------------------- #
mp_update_prompt() {

	mp_launch_update_script_if_not_running

	local t="$(date +%s%N)"
	# Special
	local RESET='\[\e[0m\]'

  	# regular colors
	local BLACK='\[\e[0;30m\]'
	local RED='\[\e[0;31m\]'
	local GREEN='\[\e[0;32m\]'
	local YELLOW='\[\e[0;33m\]'
	local BLUE='\[\e[0;34m\]'
	local MAGENTA='\[\e[0;35m\]'
    local CYAN='\[\e[0;36m\]'
    local WHITE='\[\e[0;37m\]'
    
    # emphasized (bolded) colors
	local EMBLACK='\[\e[1;30m\]'
	local EMRED='\[\e[1;31m\]'
	local EMGREEN='\[\e[1;32m\]'
	local EMYELLOW='\[\e[1;33m\]'
	local EMBLUE='\[\e[1;34m\]'
	local EMMAGENTA='\[\e[1;35m\]'
	local EMCYAN='\[\e[1;36m\]'
	local EMWHITE='\[\e[1;37m\]'
    
	# background colors
	local BGBLACK='\[\e[40m\]'
	local BGRED='\[\e[41m\]'
	local BGGREEN='\[\e[42m\]'
	local BGYELLOW='\[\e[43m\]'
	local BGBLUE='\[\e[44m\]'
	local BGMAGENTA='\[\e[45m\]'
	local BGCYAN='\[\e[46m\]'
	local BGWHITE='\[\e[47m\]'

	local hostAndPathPart=$(mp_get_host_and_path_part)

	# Check if current dir is in the list of the monitoried branch dirs
	local currentRepo=$(mp_get_current_repo)
	mp_debugmsg "Current repo: $currentRepo"
	local repoPart=
	[[ -n $currentRepo ]] && repoPart=$(mp_get_repo_part)

	PS1="$hostAndPathPart$repoPart$ "
}

# --------------------------------------------------------- #
# Returns if this script that updates the repository 
# information is already running
# @param void
# @stdout void
# @return true if the script is already running, false
# otherwise
# --------------------------------------------------------- #
mp_is_script_already_running() {
	if mp_is_file_newer_than $MP_UPDATE_REPO_INFO_LOCK; then
		mp_debugmsg "Lock file found"
		return 0
	else
		mp_debugmsg "Lock file $MP_UPDATE_REPO_INFO_LOCK does not exist or too old"
		if [[ -f $MP_UPDATE_REPO_INFO_LOCK ]]; then
			mp_debugmsg "Lock file exists but too old. Trying to kill"
			cat $MP_UPDATE_REPO_INFO_LOCK | xargs kill -9 {} 2> /dev/null
		fi
		return 1
	fi
}

# --------------------------------------------------------- #
# Launches the retrieve_repos_info.sh script in case it's not 
# already running
# @param void
# @stdout void
# @return void
# --------------------------------------------------------- #
mp_launch_update_script_if_not_running() {
	mp_debugmsg "Checking whether $MP_UPDATE_REPO_INFO_SCRIPT is running"
	# Launch script to update repository info if not already running
	if ! mp_is_script_already_running; then
		# Create "lock"
		mp_debugmsg "Creating lock file $MP_UPDATE_REPO_INFO_LOCK"
		touch $MP_UPDATE_REPO_INFO_LOCK
		mp_debugmsg "Launching $currentDir/$MP_UPDATE_REPO_INFO_SCRIPT in background"
		currentDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
		. $currentDir/$MP_UPDATE_REPO_INFO_SCRIPT &
	else
		mp_debugmsg "$MP_UPDATE_REPO_INFO_SCRIPT already running"
	fi
}

#-----------------------------------------------------------
# START LOGIC
#-----------------------------------------------------------
DEBUG=false
if [[ $1 = "-d" ]]; then
	DEBUG=true
	mp_debugmsg "Running in debug mode" 
fi

mp_launch_update_script_if_not_running
# Set prompt
PROMPT_COMMAND=mp_update_prompt
