#!/bin/bash

#***************************************************************#
# @name: retrieve_repos_info.sh
# @author: Albert Fernandez Marsal
# @description:
# This script retrieves the information of the monitored
# repos and writes its information into a file that is read by 
# update_prompt.sh
#***************************************************************#

# --------------------------------------------------------- #
# Returns if the remote repo is available
# @param void
# @stdout void
# @return true if the remote repo is available, false 
# otherwise
# --------------------------------------------------------- #
is_remote_repo_available() {
	local remoteRepo=$(hg paths default)
	hg id $remoteRepo &> /dev/null
	return $?	
}

# --------------------------------------------------------- #
# Prints the branch name, num of incoming changesets, num
# of outgoing changesets and num of dirty files, separated
# by commas
# @param $1 string <branch folder>
# @stdout the absolute current path
# @return
# --------------------------------------------------------- #
get_repo_info() {
	local repo=$1
	cd $repo

	# Get branch name, truncated to a number of chars
	local branchName=$(mp_get_branch_name $repo)

	# Get incoming and outgoing changesets
	local incomingCount="?"
	local outgoingCount="?"
	if is_remote_repo_available; then
		mp_debugmsg "Remote repo available. Checking incoming/outgoing changesets"
		incomingCount="$(hg incoming -b . --template 'chgst\n' --quiet 2>/dev/null | wc -l)"
		outgoingCount="$(hg outgoing --template 'chgst\n' --quiet 2>/dev/null | wc -l)"
	else
		mp_debugmsg "Remote repo NOT available. Unknown incoming/outgoing changesets"
	fi

	# Get repo dirty
	local dirtyFiles=$(hg st -q | wc -l)

	echo -n "$branchName, $incomingCount, $outgoingCount, $dirtyFiles"
}

# --------------------------------------------------------- #
# Method that contains the infinite loop for refreshing
# the information of the branches
# @param void
# @stdout void
# @return void
# --------------------------------------------------------- #
read_repos() {
	local infoFile=
	local repoInfo=
	while true; do
		# "Keep alive" process
		touch $MP_UPDATE_REPO_INFO_LOCK
		# Loop for writing the repo info to each file
		for repo in ${MP_BRANCH_PATHS[*]}; do
			infoFile=$(mp_get_repo_info_file $repo)
			# Don't use redirection directly, because it truncates the file
			# as soon as the command starts, and it may take a while
			repoInfo=$(get_repo_info $repo)
			mp_debugmsg "Writing $repoInfo > $infoFile"
			echo "$repoInfo" > $infoFile 
		done
		sleep $MP_SLEEP_BETWEEN_REFRESHES
	done
}

# Save PID in lockfile
mp_debugmsg "Writing pid $BASHPID to lock file $MP_UPDATE_REPO_INFO_LOCK and launching read repos script"
echo $BASHPID > $MP_UPDATE_REPO_INFO_LOCK
# Launch main logic
read_repos