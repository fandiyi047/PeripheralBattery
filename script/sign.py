#!/usr/bin/env python3
"""Sign using an optional stable identity; default to ad-hoc for local builds."""
import os
import subprocess
import sys

identity = os.environ.get('CODE_SIGN_IDENTITY', '-')
command = ['codesign', '--force', '--sign', identity, '--timestamp=none']
keychain = os.environ.get('CODE_SIGN_KEYCHAIN')
if keychain:
    command += ['--keychain', os.path.expanduser(keychain)]
command.append(sys.argv[1])
subprocess.run(command, check=True)
subprocess.run(['codesign', '--verify', '--strict', sys.argv[1]], check=True)
if identity == '-':
    print('Ad-hoc signing: rebuilding may require granting Input Monitoring again.')
