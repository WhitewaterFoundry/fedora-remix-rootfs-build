#!/usr/bin/env bash

if [ -z "${WSL_INTEROP}" ]; then
    echo "Error: start-systemd requires WSL 2."
    echo " -> Try upgrading your distribution to WSL 2."
    echo "Alternatively you can try wsl-systemctl which provides basic functionality for WSL 1."
    echo " -> wsl-systemctl start <my-service-name>"
    exit 0
fi

SYSTEMD_EXE="$(command -v systemd)"

if [ -z "$SYSTEMD_EXE" ]; then
	if [ -x "/usr/lib/systemd/systemd" ]; then
		SYSTEMD_EXE="/usr/lib/systemd/systemd"
	else
		SYSTEMD_EXE="/lib/systemd/systemd"
	fi
fi

SYSTEMD_EXE="$SYSTEMD_EXE --unit=multi-user.target" # snapd requires multi-user.target not basic.target
SYSTEMD_PID="$(ps -C systemd -o pid= | head -n1)"

if [ -z "$SYSTEMD_PID" ] || [ "$SYSTEMD_PID" -ne 1 ]; then
	if [ -z "$SUDO_USER" ]; then
		[ -f "$HOME/.systemd.env" ] && rm "$HOME/.systemd.env"
		export > "$HOME/.systemd.env"
	fi

	if [ "$USER" != "root" ]; then
		case "$0" in
			*"zsh")
				WSL_SYSTEMD_EXECUTION_ARGS="$ZSH_EXECUTION_STRING"
				;;
			*)
				WSL_SYSTEMD_EXECUTION_ARGS="$@"
				;;
		esac
		export WSL_SYSTEMD_EXECUTION_ARGS
		case "$0" in
			*"bash")
				exec sudo /bin/sh "$(realpath "${BASH_SOURCE[0]}")"
				;;
			*"zsh")
				exec sudo /bin/sh "$(realpath "${(%):-%x}")"
				;;
			*"ksh")
				exec sudo /bin/sh "$(realpath "${.sh.file}")"
				;;
			*)
				exec sudo /bin/sh "$(realpath /usr/local/bin/start-systemd)"
				;;
		esac
	fi

	if ! grep -q WSL_INTEROP /etc/environment; then
		echo "WSL_INTEROP='/run/WSL/$(ls -rv /run/WSL | head -n1)'" >> /etc/environment
	else
		sed -i "s|WSL_INTEROP=.*|WSL_INTEROP='/run/WSL/$(ls -rv /run/WSL | head -n1)'|" /etc/environment
	fi

	if ! grep -q WSL_DISTRO_NAME /etc/environment; then
		echo "WSL_DISTRO_NAME='$WSL_DISTRO_NAME'" >> /etc/environment
	fi

	if [ -z "$DISPLAY" ]; then
		if [ -f "/tmp/.X11-unix/X0" ]; then
			echo "DISPLAY=:0" >> /etc/environment
		else
			echo "DISPLAY=$(awk '/nameserver/ { print $2":0" }' /etc/resolv.conf)" >> /etc/environment
		fi
	elif ! grep -q DISPLAY /etc/environment; then
		echo "DISPLAY='$DISPLAY'" >> /etc/environment
	else
		sed -i "s/DISPLAY=.*/DISPLAY='$DISPLAY'/" /etc/environment
	fi

	if [ -z "$SYSTEMD_PID" ]; then
		env -i /usr/bin/unshare --fork --mount-proc --pid --propagation shared -- sh -c "
			mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
			exec $SYSTEMD_EXE
			" &
		while [ -z "$SYSTEMD_PID" ]; do
			SYSTEMD_PID="$(ps -C systemd -o pid= | head -n1)"
			sleep 1
		done
	fi

	IS_SYSTEMD_READY_CMD="/usr/bin/nsenter --mount --pid --target $SYSTEMD_PID -- systemctl is-system-running"
	WAITMSG="$($IS_SYSTEMD_READY_CMD 2>&1)"
	if [ "$WAITMSG" = "initializing" ] || [ "$WAITMSG" = "starting" ] || [ "$WAITMSG" = "Failed to connect to bus: No such file or directory" ]; then
		echo "Waiting for systemd to finish booting"
	fi
	while [ "$WAITMSG" = "initializing" ] || [ "$WAITMSG" = "starting" ] || [ "$WAITMSG" = "Failed to connect to bus: No such file or directory" ]; do
		echo -n "."
		sleep 1
		WAITMSG="$($IS_SYSTEMD_READY_CMD 2>&1)"
	done
	printf "\nSystemd is ready.\n"

	if [ -n "$WSL_SYSTEMD_EXECUTION_ARGS" ]; then
		exec /usr/bin/nsenter --mount --pid --target "$SYSTEMD_PID" -- sudo -u "$SUDO_USER" /bin/sh -c "unset WSL_SYSTEMD_EXECUTION_ARGS; set -a; . '$HOME/.systemd.env'; set +a; eval \"$WSL_SYSTEMD_EXECUTION_ARGS\""
	else
		exec /usr/bin/nsenter --mount --pid --target "$SYSTEMD_PID" -- su - "$SUDO_USER"
	fi
fi

unset SYSTEMD_EXE
unset SYSTEMD_PID

if [ -f "$HOME/.systemd.env" ]; then
	set -a
	source "$HOME/.systemd.env"
	set +a
	rm "$HOME/.systemd.env"
fi

for script in /etc/profile.d/*.sh; do
	source "$script"
done

cd "$PWD"

if [ -d "$HOME/.wslprofile.d" ]; then
	for script in "$HOME/.wslprofile.d/"*; do
		source "$script"
	done
	unset script
fi
