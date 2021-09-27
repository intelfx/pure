# Pure
# by Sindre Sorhus
# https://github.com/sindresorhus/pure
# MIT License

# For my own and others sanity
# git:
# %b => current branch
# %a => current action (rebase/merge)
# prompt:
# %F => color dict
# %f => reset color
# %~ => current path
# %* => time
# %n => username
# %m => shortname host
# %(?..) => prompt conditional - %(condition.true.false)
# terminal codes:
# \e7   => save cursor position
# \e[2A => move cursor 2 lines up
# \e[1G => go to position 1 in terminal
# \e8   => restore cursor position
# \e[K  => clears everything after the cursor on the current line
# \e[2K => clear everything on the current line

# turns seconds into human readable time
# 165392 => 1d 21h 56m 32s
# https://github.com/sindresorhus/pretty-time-zsh
prompt_pure_human_time_to_var() {
	local human=" " total_seconds=$1 var=$2
	local days=$(( total_seconds / 60 / 60 / 24 ))
	local hours=$(( total_seconds / 60 / 60 % 24 ))
	local minutes=$(( total_seconds / 60 % 60 ))
	local seconds=$(( total_seconds % 60 ))
	(( days > 0 )) && human+="${days}d "
	(( hours > 0 )) && human+="${hours}h "
	(( minutes > 0 )) && human+="${minutes}m "
	human+="${seconds}s"

	# store human readable time in variable as specified by caller
	typeset -g "${var}"="${human}"
}

# stores (into prompt_pure_cmd_exec_time) the exec time of the last command if set threshold was exceeded
prompt_pure_check_cmd_exec_time() {
	unset prompt_pure_cmd_exec_time

	if (( ${+prompt_pure_cmd_timestamp} )); then
		local elapsed=$(( EPOCHSECONDS - prompt_pure_cmd_timestamp ))

		if (( elapsed > ${PURE_CMD_MAX_EXEC_TIME:-5} )); then
			prompt_pure_human_time_to_var $elapsed "prompt_pure_cmd_exec_time"
		fi
	fi
}

prompt_pure_clear_screen() {
	# enable output to terminal
	zle -I
	# clear screen and move cursor to (0, 0)
	print -n '\e[2J\e[0;0H'
	# print preprompt
	prompt_pure_preprompt_render precmd
}

prompt_pure_set_title() {
	# emacs terminal does not support settings the title
	(( ${+EMACS} )) && return

	# tell the terminal we are setting the title
	print -n '\e]0;'
	# show hostname if connected through ssh
	[[ -n $SSH_CONNECTION ]] && print -Pn '(%m) '
	case $1 in
		expand-prompt)
			print -Pn $2;;
		ignore-escape)
			print -rn $2;;
	esac
	# end set title
	print -n '\a'
}

prompt_pure_preexec() {
	# prevent async fetch (if it is running) from interfering with user-initiated fetch
	if [[ ${prompt_pure_vcs[fetch]} == 0 && $2 =~ (git|hub)\ .*(pull|fetch) ]]; then
		prompt_pure_async_flush
	fi

	prompt_pure_cmd_timestamp=$EPOCHSECONDS

	# shows the current dir and executed command in the title while a process is active
	prompt_pure_set_title 'ignore-escape' "$PWD:t: $2"
}

# string length ignoring ansi escapes
prompt_pure_string_length() {
	local str=$1
	# perform expansion on str and check length
	echo $(( ${#${(S%%)str//(\%([KF1]|)\{*\}|\%[Bbkf])}} ))
}

prompt_pure_render_path() {
	# path
	pp="%~"
	preprompt+=("%F{blue}$pp%f")
}

prompt_pure_render_vcs() {
	# set color for git branch/dirty status, change color if dirty checking has been delayed
	if (( ${+prompt_pure_vcs[last_worktree]} )); then
		# cached: violet = 13
		local clr_worktree=13
	else
		# normal: highlight (base1 = 14)
		local clr_worktree=14
	fi

	# set color for git upstream status, change color if fetching or if upstream checking has been delayed
	if (( ${+prompt_pure_vcs[last_upstream]} )); then
		# cached: violet = 13
		local clr_upstream=13
	elif (( ${prompt_pure_vcs[fetch]:-0} == 0 )); then
		# fetch-in-process: yellow
		local clr_upstream=yellow
	elif (( ${prompt_pure_vcs[fetch]} < 0 )); then
		# fetch-failed: red
		local clr_upstream=red
	else
		# normal: cyan
		local clr_upstream=cyan
	fi

	# data-na (in-process): secondary (base01 = 10)
	local clr_na=10

	if (( log_enabled )); then log "prompt_pure_preprompt_render: $(declare -p prompt_pure_vcs | command tail -n1)"; fi

	# git info
	if (( ${+prompt_pure_vcs[working_tree]} && ! ${+prompt_pure_vcs[unsure]} )); then
		# branch and action
		pp=""
		[[ -n ${prompt_pure_vcs[action]} ]]  && pp+="${prompt_pure_vcs[action]}: "
		[[ -n ${+prompt_pure_vcs[branch]} ]] && pp+="${prompt_pure_vcs[branch]}"

		# worktree information (appended)
		if (( ${prompt_pure_vcs[worktree]} )); then

			(( ${prompt_pure_vcs[untracked]} )) && pp+=${PURE_GIT_UNTRACKED:-'.'}
			(( ${prompt_pure_vcs[dirty]} ))     && pp+=${PURE_GIT_DIRTY:-'*'}
			(( ${prompt_pure_vcs[staged]} ))    && pp+=${PURE_GIT_STAGED:-'+'}
			(( ${prompt_pure_vcs[unmerged]} ))  && pp+=${PURE_GIT_UNMERGED:-'!'}

		elif ! (( ${+prompt_pure_vcs[worktree]} )); then

			pp+="%F{$clr_na}"
			pp+=${PURE_GIT_WORKTREE_NA:-'?w'}

		fi

		[[ -n $pp ]] && preprompt+=("%F{$clr_worktree}$pp%f")

		# upstream information
		if (( ${prompt_pure_vcs[upstream]} )); then
			local even=$(( ! ${prompt_pure_vcs[right]} && ! ${prompt_pure_vcs[left]} ))

			pp=""
			(( ${prompt_pure_vcs[right]} )) && pp+=${PURE_GIT_DOWN_ARROW:-'⇣'}
			(( ${prompt_pure_vcs[left]} ))  && pp+=${PURE_GIT_UP_ARROW:-'⇡'}
			(( ${even} ))                   && pp+=${PURE_GIT_EVEN_ARROW:-}
			(( ${prompt_pure_vcs[fetch]:-0} == 0 )) && pp+=${PURE_GIT_FETCH_IN_PROCESS:-'(fetch...)'}
			(( ${prompt_pure_vcs[fetch]:-0} < 0 ))  && pp+=${PURE_GIT_FETCH_FAILED:-'(fetch!)'}
			[[ -n $pp ]] && preprompt+=("%F{$clr_upstream}$pp%f")

		elif ! (( ${+prompt_pure_vcs[upstream]} )); then

			pp=${PURE_GIT_UPSTREAM_NA:-'?u'}
			[[ -n $pp ]] && preprompt+=("%F{$clr_na}$pp%f")

		fi
	fi
}

prompt_pure_render_hostname() {
	# username and machine if applicable
	[[ -n $prompt_pure_hostname ]] && preprompt+=($prompt_pure_hostname)
}

prompt_pure_render_exec_time() {
	# execution time
	local pp=""
	if (( ${+prompt_pure_cmd_exec_time} )); then
		pp=${prompt_pure_cmd_exec_time}
		[[ -n $pp ]] && preprompt+=("%F{yellow}$pp%f")
	fi
}

prompt_pure_preprompt_render() {
	# store the current prompt_subst setting so that it can be restored later
	local prompt_subst_status=$options[prompt_subst]

	# make sure prompt_subst is unset to prevent parameter expansion in preprompt
	setopt local_options no_prompt_subst

	# check that no command is currently running, the preprompt will otherwise be rendered in the wrong place
	if (( ${+prompt_pure_cmd_timestamp} )) && [[ $1 != "precmd" ]]; then
		return
	fi

	# construct preprompt
	local preprompt=() pp
	for f in $prompt_pure_pieces; do
		$f
	done
	if (( log_enabled )); then log "prompt_pure_preprompt_render: $(declare -p preprompt | command tail -n1)"; fi
	preprompt="$preprompt"

	# make sure prompt_pure_last_preprompt is a global array
	typeset -g -a prompt_pure_last_preprompt

	# if executing through precmd, do not perform fancy terminal editing
	if [[ "$1" == "precmd" ]]; then
		print -P "\n${preprompt}"
	else
		# only redraw if the expanded preprompt has changed
		[[ "${prompt_pure_last_preprompt[2]}" != "${(S%%)preprompt}" ]] || return

		# calculate length of preprompt and store it locally in preprompt_length
		integer preprompt_length=$(prompt_pure_string_length $preprompt)
		# calculate number of preprompt lines for redraw purposes
		integer lines=$(( ( preprompt_length - 1 ) / COLUMNS + 1 ))

		# calculate previous preprompt lines to figure out how the new preprompt should behave
		integer last_preprompt_length=$(prompt_pure_string_length "${prompt_pure_last_preprompt[1]}")
		integer last_lines=$(( ( last_preprompt_length - 1 ) / COLUMNS + 1 ))

		# clr_prev_preprompt erases visual artifacts from previous preprompt
		local clr_prev_preprompt
		if (( last_lines > lines )); then
			# move cursor up by last_lines, clear the line and move it down by one line
			clr_prev_preprompt="\e[${last_lines}A\e[2K\e[1B"
			while (( last_lines - lines > 1 )); do
				# clear the line and move cursor down by one
				clr_prev_preprompt+='\e[2K\e[1B'
				(( last_lines-- ))
			done

			# move cursor into correct position for preprompt update
			clr_prev_preprompt+="\e[${lines}B"
		# create more space for preprompt if new preprompt has more lines than last
		elif (( last_lines < lines )); then
			# move cursor using newlines because ansi cursor movement can't push the cursor beyond the last line
			printf $'\n'%.0s {1..$(( lines - last_lines ))}
		fi

		# disable clearing of line if last char of preprompt is last column of terminal
		local clr='\e[K'
		(( COLUMNS * lines == preprompt_length )) && clr=

		# modify previous preprompt
		print -Pn "${clr_prev_preprompt}\e[${lines}A\e[${COLUMNS}D${preprompt}${clr}\n"

		if [[ $prompt_subst_status = 'on' ]]; then
			# re-eanble prompt_subst for expansion on PS1
			setopt prompt_subst
		fi

		# redraw prompt (also resets cursor position)
		zle && zle .reset-prompt
	fi

	# store both unexpanded and expanded preprompt for comparison
	prompt_pure_last_preprompt=("$preprompt" "${(S%%)preprompt}")
	log "drawn preprompt: '$preprompt'"
}

prompt_pure_precmd() {
	# check exec time and store it in a variable
	prompt_pure_check_cmd_exec_time

	# shows the full path in the title
	prompt_pure_set_title 'expand-prompt' '%~'

	# perform initial vcs data fetching, synchronously
	prompt_pure_vcs_sync

	# print the preprompt
	prompt_pure_preprompt_render "precmd"

	# allow further preprompt rendering attempts
	unset prompt_pure_cmd_timestamp

	# perform the rest asynchronously after printing preprompt to avoid races
	prompt_pure_vcs_async
}

prompt_pure_async_vcs_info() {
	declare -A reply

	# use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
	builtin cd -q "$*"

	# get vcs info
	vcs_info

	# ignore the dotfiles repository (~/) if we're not in a directory that explicitly belong to dotfiles.
	#
	# otherwise, even if we're deep in ~/Documents/some/long/path/unrelated/to/dotfiles,
	# pure would still show us the dotfiles repository which we do not care about.
	if [[ "${vcs_info_msg_0_}" == "$HOME" ]] && git check-ignore "$PWD" &>/dev/null; then
		declare -p reply
		return
	fi

	# output results: working tree, branch, action
	reply[working_tree]=${vcs_info_msg_0_}
	reply[branch]=${vcs_info_msg_1_}
	reply[action]=${vcs_info_msg_2_:#'(none)'}

	declare -p reply
}

# fastest possible way to check if repo is dirty
prompt_pure_async_git_dirty() {
	local dir=$1 untracked=$2

	# use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
	builtin cd -q $dir

	local args
	if (( $untracked )); then
		args=("-unormal")
	else
		args=("-uno")
	fi

	declare -A reply=(
		worktree 0
		unmerged 0
		dirty 0
		staged 0
		untracked 0
	)

	local line
	while IFS='' read -r line; do
		case ${line:0:2} in
		(DD|AA|?U|U?)
			reply[unmerged]=1 ;;

		(?[MD])
			reply[dirty]=1 ;|

		([MADRC]?)
			reply[staged]=1 ;;

		'??')
			reply[untracked]=1 ;;

		OK)
			reply[worktree]=1 ;;
		esac
	done < <(git status --porcelain "${args[@]}" && echo OK)

	declare -p reply
}

prompt_pure_async_git_upstream() {
	local dir=$1

	# use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
	builtin cd -q $dir

	declare -A reply=(
		upstream 0
	)

	# check if there is an upstream configured for this branch
	if git rev-parse --abbrev-ref @'{u}' >/dev/null; then
		# check git left and right arrow_status
		local arrow_status
		arrow_status="$(command git rev-list --left-right --count HEAD...@'{u}' 2>/dev/null)"

		if (( !$? )); then
			# left and right are tab-separated, split on tab and store as array
			arrow_status=(${(ps:\t:)arrow_status})
			reply[left]=${arrow_status[1]}
			reply[right]=${arrow_status[2]}
			reply[upstream]=1
		fi
	fi

	declare -p reply
}

prompt_pure_async_git_fetch() {
	local dir=$1

	# use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
	builtin cd -q $dir

	log "prompt_pure_async_git_fetch: enter"

	declare -A reply=(
		fetch -1
	)

	log "prompt_pure_async_git_fetch: beginning fetch"

	# set GIT_TERMINAL_PROMPT=0 to disable auth prompting for git fetch (git 2.3+)
	GIT_TERMINAL_PROMPT=0 git -c gc.auto=0 fetch

	if (( !$? )); then
		reply[fetch]=1
	fi

	log "prompt_pure_async_git_fetch: completed fetch"

	declare -p reply

	log "prompt_pure_async_git_fetch: exit"
}

prompt_pure_async_start() {
	log "prompt_pure_async_start: starting async worker"
	async_start_worker "prompt_pure"
	async_register_callback "prompt_pure" prompt_pure_vcs_async_fsm
}

prompt_pure_async_flush() {
	log "prompt_pure_async_flush: stopping async worker"
	async_flush_jobs "prompt_pure"
	prompt_pure_async_start
	prompt_pure_async_reset
}

prompt_pure_async_reset() {
	# if we had any jobs in progress, note that we've just cancelled them
	if [[ ${prompt_pure_vcs[fetch]} == 0 ]]; then
		# mark fetch as "did not happen" (trigger another one post this command)
		log "prompt_pure_async_reset: flush while fetch running -- unsetting fetch status"
		noglob unset prompt_pure_vcs[fetch]
	fi
	# worktree and local branch status do not record in-progress state, so nothing to reset
}

prompt_pure_vcs_sync() {
	# check if the working tree probably changed
	if [[ $PWD != ${prompt_pure_vcs[pwd]} ]]; then
		log "prompt_pure_vcs_sync: cwd changed '${prompt_pure_vcs[pwd]}' -> '$PWD', marking"
		prompt_pure_vcs[unsure]=1
	fi
}

prompt_pure_vcs_async() {
	async_job "prompt_pure" \
		prompt_pure_async_vcs_info \
		"$(builtin pwd)"
}

# this is a poor man's semi-state machine
prompt_pure_vcs_async_fsm() {
	local job=$1
	local code=$2
	local output=$3
	local exec_time=$4

	eval $output

	if (( ${+reply} )); then
		log "prompt_pure_async_fsm: job '$job' exec_time '$exec_time' output '$output'"
	else
		log "prompt_pure_async_fsm: job '$job' exec_time '$exec_time' output '$output' no reply"
	fi

	case $job in
		'[async]')
			if (( code == 2 )); then
				# our worker died unexpectedly
				log "prompt_pure_vcs_async_fsm: worker died, restarting"
				# XXX: work around "async_job:zpty:12: no such pty command: prompt_pure"
				prompt_pure_async_flush
				# XXX: do we want to restart async jobs here?
				#prompt_pure_vcs_async
			fi
			;;

		prompt_pure_async_vcs_info)
			# only perform tasks inside git working tree
			if ! [[ -n ${reply[working_tree]} ]]; then
				log "prompt_pure_vcs_async_fsm: not inside working tree, clearing"
				prompt_pure_async_flush
				prompt_pure_vcs=()
				return
			fi

			# check if the working tree changed
			if [[ ${reply[working_tree]} != ${prompt_pure_vcs[working_tree]} ]]; then
				log "prompt_pure_vcs_async_fsm: working tree changed '${prompt_pure_vcs[working_tree]}' -> '${reply[working_tree]}', clearing"
				prompt_pure_async_flush
				prompt_pure_vcs=()
			else
				log "prompt_pure_vcs_async_fsm: working tree confirmed '${prompt_pure_vcs[working_tree]}', unmarking"
				noglob unset prompt_pure_vcs[unsure]
			fi
			prompt_pure_vcs[pwd]=$PWD

			# merge in new data
			prompt_pure_vcs+=("${(kv)reply[@]}")

			# if fetch is disabled, mark it as completed
			if ! (( ${PURE_GIT_FETCH:-0} )); then
				prompt_pure_vcs[fetch]=1
			fi

			# now see if we have to refresh advanced repository info
			#
			# We have three advanced asynchronous checks:
			# - worktree clean/dirty status (worktree) (may be pretty slow)
			# - local branch upstream difference (upstream) (usually not so slow)
			# - the upstream branch itself (fetch) (_really_ slow and uses network)
			#
			# We also try to track whether the last asynchronous check was fast or not.
			# The worktree and upstream difference checks are refreshed each time
			# if they are fast or once in 60 seconds if they were slow.
			# Fetch check is performed only once when entering the repository.
			#
			# To track check status, we use "worktree", "upstream" and "fetch" keys.
			# They are set to 0 when a check is in progress, non-zero when the check
			# is completed with either result (additional keys are set detailing the
			# check report) and unset when a recheck is desired.
			#
			# To track check speed, we use "last_worktree", "last_upstream" and
			# "last_fetch" keys. They are unset if the last refresh was sufficiently
			# fast, otherwise they are set to the timestamp when the last refresh was
			# completed.
			#
			# Both keys are set in respective completion handlers.
			#
			# Therefore our logic:
			#
			# 1. if the last refresh timestamp is not set, it means that the
			# last refresh was sufficiently fast, so we simply schedule it
			# without erasing the status (so the stale status will be rendered
			# first, then the actual one will be painted on top).
			# 2. if the last refresh timestamp is set, it means that the
			# last refresh was slow, so we schedule a refresh and unset the status
			# (so that a question mark will be rendered in while the refresh is
			# in progress).
			#
			# When both the status and the last refresh timestamp is set,
			# the renderer will use a different color to indicate that
			# the status is likely out of date.
			#

			# worktree status...
			if (( ${+prompt_pure_vcs[last_worktree]} )) && \
			   (( EPOCHSECONDS - ${prompt_pure_vcs[last_worktree]} \
			      > ${PURE_GIT_DELAY_WORKTREE_CHECK:-60} )); then
				log "prompt_pure_vcs_async_fsm: triggering another worktree check by timer"
				noglob unset prompt_pure_vcs[last_worktree] # force another async check
				noglob unset prompt_pure_vcs[worktree] # mark data as N/A for renderer
			fi

			# upstream status...
			if (( ${+prompt_pure_vcs[last_upstream]} )) && \
			   (( EPOCHSECONDS - ${prompt_pure_vcs[last_upstream]} \
			      > ${PURE_GIT_DELAY_UPSTREAM_CHECK:-60} )); then
				log "prompt_pure_vcs_async_fsm: triggering another upstream check by timer"
				noglob unset prompt_pure_vcs[last_upstream] # force another async check
				noglob unset prompt_pure_vcs[upstream] # mark data as N/A for renderer
			fi

			# fetch...
			if (( ${+prompt_pure_vcs[last_fetch]} )) &&
			   (( EPOCHSECONDS - ${prompt_pure_vcs[last_fetch]} \
			      > ${PURE_GIT_DELAY_FETCH_RETRY:-10} )); then
				log "prompt_pure_vcs_async_fsm: triggering another fetch by timer"
				noglob unset prompt_pure_vcs[fetch] # force another async fetch
				noglob unset prompt_pure_vcs[last_fetch] # remove the re-fetch timer

				# fetch is triggered indirectly via the upstream status check handler, so trigger it too
				if (( ${+prompt_pure_vcs[last_upstream]} )); then
					log "triggering another upstream check to chain-start fetch"
					noglob unset prompt_pure_vcs[last_upstream] # trigger the async check
					noglob unset prompt_pure_vcs[upstream] # mark data as N/A for renderer
				fi
			fi

			# render what we've got
			log "prompt_pure_vcs_async_fsm: will render"
			prompt_pure_preprompt_render

			# spawn refreshers if we have to
			# worktree status...
			if ! (( ${+prompt_pure_vcs[last_worktree]} )); then
				log "prompt_pure_vcs_async_fsm: starting worktree check"
				async_job "prompt_pure" \
					prompt_pure_async_git_dirty \
					${prompt_pure_vcs[working_tree]} \
					${PURE_GIT_UNTRACKED:-1}
			fi

			# upstream status...
			if ! (( ${+prompt_pure_vcs[last_upstream]} )); then
				log "prompt_pure_vcs_async_fsm: starting upstream check"
				async_job "prompt_pure" \
					prompt_pure_async_git_upstream \
					${prompt_pure_vcs[working_tree]}
			fi
			;;

		prompt_pure_async_git_dirty)
			# merge in new data
			prompt_pure_vcs+=("${(kv)reply[@]}")

			# render what we've got
			prompt_pure_preprompt_render

			if (( $exec_time > 20 )); then
				# mark dirty check as lengthy
				prompt_pure_vcs[last_worktree]=$EPOCHSECONDS
			fi
			;;

		prompt_pure_async_git_upstream)
			# merge in new data
			prompt_pure_vcs+=("${(kv)reply[@]}")

			# render what we've got
			prompt_pure_preprompt_render

			if (( $exec_time > 20 )); then
				# mark upstream check as lengthy
				prompt_pure_vcs[last_upstream]=$EPOCHSECONDS
			fi

			if (( ${prompt_pure_vcs[upstream]} && ! ${+prompt_pure_vcs[fetch]} )); then
				# fetch upstream
				log "prompt_pure_vcs_async_fsm: starting fetch"
				async_job "prompt_pure" \
					prompt_pure_async_git_fetch \
					${prompt_pure_vcs[working_tree]}

				# mark fetch as "invoked"
				prompt_pure_vcs[fetch]=0

				# unarm re-fetch marker
				noglob unset prompt_pure_vcs[last_fetch]
			fi
			;;

		prompt_pure_async_git_fetch)
			# merge in new data
			prompt_pure_vcs+=("${(kv)reply[@]}")

			if (( ${prompt_pure_vcs[fetch]} < 0 )); then
				# arm another fetch attempt
				prompt_pure_vcs[last_fetch]=$EPOCHSECONDS
			fi

			# just re-run upstream checks
			log "prompt_pure_vcs_async_fsm: re-starting upstream check"
			async_job "prompt_pure" \
				prompt_pure_async_git_upstream \
				${prompt_pure_vcs[working_tree]}
			;;
	esac
}

prompt_pure_setup() {

	if (( ${+PURE_DEBUG} )); then
		exec 3> >(systemd-cat -t zshpure)

		declare -g log_enabled=1

		function log() {
			echo "[$PWD] $*" >&3
		}

		function logcmd() {
			echo -n "[$PWD] " >&3
			command "$@" >&3 2>&3
		}
	else
		declare -g log_enabled=0

		function log() {
			:
		}

		function logcmd() {
			command "$@" &>/dev/null
		}
	fi

	# prevent percentage showing up
	# if output doesn't end with a newline
	export PROMPT_EOL_MARK=''

	prompt_opts=(subst percent)

	zmodload zsh/datetime
	zmodload zsh/zle
	zmodload zsh/parameter

	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info
	autoload -Uz async && async

	add-zsh-hook precmd prompt_pure_precmd
	add-zsh-hook preexec prompt_pure_preexec

	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:*' max-exports 3
	# 1) git root, 2) branch, 3) action (rebase/merge) or '(none)'
	zstyle ':vcs_info:git*' formats '%R' '%b' '(none)'
	zstyle ':vcs_info:git*' actionformats '%R' '%b' '%a'

	#
	# the array used to keep information about current working tree
	#
	# working_tree:
	# - set = we are in vcs repository
	# - contents = root of the current vcs repository
	#
	# unsure:
	# - set = directory was changed and all other fields are stale
	#
	# action:
	# - set = a special action (rebase/merge) exists in the repo
	# - contents = name of the special action
	#
	# last_worktree:
	# - set = worktree checking is throttled
	# - unset = worktree check should be done next time
	# - contents = ts of last check for throttling
	#
	# worktree:
	# - set = the worktree check is completed (fields untracked, dirty, staged, unmerged)
	# - unset = the worktree check is in progress
	# - contents = whether the worktree check was successful
	#
	# untracked, dirty, staged, unmerged:
	# - set = when worktree check has completed successfully
	# - contents = whether the files of said category exist
	#
	# last_upstream:
	# - set = upstream checking is throttled
	# - unset = upstream check should be done next time
	# - contents = ts of last check for throttling
	#
	# upstream:
	# - set = the upstream check is completed (fields left, right)
	# - unset = the upstream check is in progress
	# - contents = whether the upstream exists
	#
	# left, right:
	# - set = when upstream check has completed and the upstream exists
	# - contents = amount of commits since merge base in local resp. tracking branches
	#
	# last_fetch:
	# - set = re-fetch is armed
	# - unset = no re-fetch should be done
	#           NB: meaning of "unset" is inverted wrt. last_{worktree,upstream}_check
	# - contents = ts of last fetch attempt
	#
	# fetch:
	# - set = fetch has been initiated/completed (we do one fetch per repository)
	# - unset = fetch has not been initiated
	# - contents = 0: in progress, 1: completed successfully, -1: completed unsuccessfully
	#
	declare -gA prompt_pure_vcs

	# if the user has not registered a custom zle widget for clear-screen,
	# override the builtin one so that the preprompt is displayed correctly when
	# ^L is issued.
	if [[ $widgets[clear-screen] == 'builtin' ]]; then
		zle -N clear-screen prompt_pure_clear_screen
	fi

	# show username@host if logged in through SSH or if forced
	if [[ -n $SSH_CONNECTION ]]; then
		# ssh: green
		prompt_pure_hostname='@%F{green}%m%f'
	elif (( ${PURE_ALWAYS_SHOW_USER:-0} )); then
		# normal: secondary (base01 = 10)
		prompt_pure_hostname='@%F{10}%m%f'
	fi

	if [[ -n $prompt_pure_hostname ]]; then
		# privileged: bright white (base03 = 15)
		# unprivileged; secondary (base01 = 10)
		prompt_pure_hostname="%(!.%F{15}.%F{10})%n$prompt_pure_hostname"
	fi

	# privileged: bright white (base03 = 15)
	# unprivileged: highlight (base1 = 14)
	# failed command: red
	PROMPT="%(?.%(!.%F{15}.%F{14}).%F{red})${PURE_PROMPT_SYMBOL:-%(!.#.\$)}%f "

	# construct the array of prompt rendering callbacks
	# a prompt rendering callback should append to the preprompt=() array
	# declared in a parent scope
	prompt_pure_pieces=(
		prompt_pure_render_path
		prompt_pure_render_vcs
		prompt_pure_render_hostname
		prompt_pure_render_exec_time
	)

	# initialize async worker
	prompt_pure_async_start
}

prompt_pure_setup "$@"
