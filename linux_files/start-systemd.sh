#!/usr/bin/env bash

if [ -z "${WSL_INTEROP}" ]; then
    echo "Error: start-systemd requires WSL 2."
    echo " -> Try upgrading your distribution to WSL 2."
    echo "Alternatively you can try wslsystemctl which provides basic functionality for WSL 1."
    echo " -> sudo wslsystemctl start <my-service-name>"
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
	echo "Systemd is ready."

	exec /usr/bin/nsenter --mount --pid --target "$SYSTEMD_PID" -- su \
	  --whitelist-environment="WSL_INTEROP,WSL_DISTRO_NAME,WIN_HOME,DISPLAY" \
	  --login "$SUDO_USER"
fi
