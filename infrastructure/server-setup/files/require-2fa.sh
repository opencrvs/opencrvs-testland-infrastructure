#!/bin/bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# OpenCRVS is also distributed under the terms of the Civil Registration
# & Healthcare Disclaimer located at http://opencrvs.org/license.
#
# Copyright (C) The OpenCRVS Authors located at https://github.com/opencrvs/opencrvs-core/blob/master/AUTHORS.

#------------------------------------------------------------------------------------------------------------------
# sshd runs this script (ForceCommand) for every SSH session of a user that must use two-factor authentication.
#
# pam_google_authenticator is set to "nullok": a user without ~/.google_authenticator passes the one-time password
# step. This script makes sure that such a user can only start an interactive login, which sets up the second factor.
# Commands, scp, sftp and sessions without a terminal are refused until the set-up is done.
# A user that has set up the second factor gets the shell or the command that was requested.
#------------------------------------------------------------------------------------------------------------------

if [ ! -f "$HOME/.google_authenticator" ]; then
  if [ -n "$SSH_ORIGINAL_COMMAND" ] || [ ! -t 0 ]; then
    echo "Two-factor authentication is not set up for this user." >&2
    echo "Log in without a command from a terminal (for example: ssh $(id -un)@<host>) to set it up." >&2
    exit 1
  fi

  printf '\n\033[1;37;41m !!! You must set up two-factor authentication. !!! \033[0m\n\n'
  google-authenticator || exit 1

  [ -f "$HOME/.google_authenticator" ] || exit 1
fi

: "${SHELL:=/bin/bash}"

if [ -n "$SSH_ORIGINAL_COMMAND" ]; then
  exec "$SHELL" -c "$SSH_ORIGINAL_COMMAND"
fi

# sshd does not show the login banner (MOTD) when a ForceCommand is set, so show it here
cat /run/motd.dynamic /etc/motd 2>/dev/null

unset SSH_ORIGINAL_COMMAND
exec -l "$SHELL"
