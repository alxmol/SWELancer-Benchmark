#!/bin/bash

# Redirect all output to a log file within the container
LOG_FILE="/app/tests/run_sh.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

set -e # Exit immediately if a command exits with a non-zero status.

echo "Log started at $(date)"
echo "Starting run.sh script..."
echo "Script location: $(readlink -f "$0")"
echo "Current working directory: $(pwd)"
echo "Environment variables:"
printenv
echo "------------------------------------"

if [ "$EVAL_VARIANT" = "swe_manager" ]; then
    echo "EVAL_VARIANT is set to swe_manager. Skipping setup steps."
else
    echo "EVAL_VARIANT is '$EVAL_VARIANT'. Proceeding with full setup..."

    # Start Xvfb for a virtual display
    echo "Starting Xvfb on display :99..."
    Xvfb :99 -screen 0 2560x1600x24 &
    Xvfb_PID=$!
    echo "Xvfb PID: $Xvfb_PID. Waiting for Xvfb..."
    sleep 3 # Increased sleep slightly

    # Start bspwm window manager
    echo "Starting bspwm window manager..."
    bspwm &
    bspwm_PID=$!
    echo "bspwm PID: $bspwm_PID. Waiting for bspwm..."
    sleep 3 # Increased sleep slightly

    # Start x11vnc to expose the Xvfb display
    echo "Starting x11vnc server..."
    x11vnc -display :99 -forever -rfbport 5900 -noxdamage &
    x11vnc_PID=$!
    echo "x11vnc PID: $x11vnc_PID. Waiting for x11vnc..."
    sleep 3 # Increased sleep slightly

    # Start NoVNC to allow browser access
    echo "Starting NoVNC..."
    websockify --web=/usr/share/novnc/ 5901 localhost:5900 &
    websockify_PID=$!
    echo "NoVNC (websockify) PID: $websockify_PID. Waiting for NoVNC..."
    sleep 3 # Increased sleep slightly

    # Modify host file to point to ws-mt1.pusher.com
    echo "Adding ws-mt1.pusher.com to /etc/hosts..."
    if echo "127.0.0.1 ws-mt1.pusher.com" >> /etc/hosts; then
        echo "/etc/hosts modified successfully."
    else
        echo "ERROR: Failed to modify /etc/hosts"
        exit 1
    fi
    echo "Contents of /etc/hosts:"
    cat /etc/hosts
    echo "------------------------------------"

    # Start Pusher-Fake in the background
    echo "Starting Pusher-Fake service..."
    echo "Current directory before starting Pusher-Fake: $(pwd)"
    # Per Dockerfile: cd /app/ # Do not set this to where the EXP repo is cloned, as it causes gem conflicts
    # Ensuring we are in /app as per original Dockerfile comments for pusher-fake
    cd /app/
    echo "Changed to directory: $(pwd) for Pusher-Fake"
    pusher-fake --id "$PUSHER_APP_ID" --key "$PUSHER_APP_KEY" --secret "$PUSHER_APP_SECRET" \
        --web-host 0.0.0.0 --web-port 57004 \
        --socket-host 0.0.0.0 --socket-port 57003 --verbose &
    pusher_fake_PID=$!
    echo "Pusher-Fake PID: $pusher_fake_PID. Waiting for Pusher-Fake..."
    sleep 5 # Give pusher-fake a bit more time to start and log if verbose

    # Start NGINX
    echo "Starting NGINX..."
    nginx -g "daemon off;" &
    nginx_PID=$!
    echo "NGINX PID: $nginx_PID. Waiting for NGINX..."
    sleep 3 # Give nginx a moment to start

    # Create aliases
    echo "Creating user-tool alias in ~/.bashrc..."
    echo "alias user-tool='ansible-playbook -i \"localhost,\" --connection=local /app/tests/run_user_tool.yml'" >> ~/.bashrc
    echo "Alias created. Contents of ~/.bashrc:"
    cat ~/.bashrc
    echo "------------------------------------"
    
    # Sourcing .bashrc to make alias available if any subsequent step in this script needs it
    # Though ansible playbooks are called directly.
    echo "Sourcing ~/.bashrc"
    source ~/.bashrc

    # Run ansible playbooks to setup expensify and mitmproxy
    echo "Running setup_expensify.yml Ansible playbook..."
    echo "Ansible playbook command: ansible-playbook -i \"localhost,\" --connection=local /app/tests/setup_expensify.yml -vvv"
    ansible-playbook -i "localhost," --connection=local /app/tests/setup_expensify.yml -vvv # Added -vvv for very verbose Ansible output
    if [ $? -ne 0 ]; then
        echo "Ansible playbook setup_expensify.yml FAILED"
        exit 1
    fi
    echo "Ansible playbook setup_expensify.yml COMPLETED"

    echo "Running setup_mitmproxy.yml Ansible playbook..."
    echo "Ansible playbook command: ansible-playbook -i \"localhost,\" --connection=local /app/tests/setup_mitmproxy.yml -vvv"
    ansible-playbook -i "localhost," --connection=local /app/tests/setup_mitmproxy.yml -vvv # Added -vvv for very verbose Ansible output
    if [ $? -ne 0 ]; then
        echo "Ansible playbook setup_mitmproxy.yml FAILED"
        exit 1
    fi
    echo "Ansible playbook setup_mitmproxy.yml COMPLETED"

    # Set an environment variable to indicate that the setup is done
    echo "Creating /setup_done.txt indicator file..."
    if echo "done" > /setup_done.txt; then
        echo "/setup_done.txt created successfully."
    else
        echo "ERROR: Failed to create /setup_done.txt"
        exit 1
    fi
    echo "Contents of /setup_done.txt:"
    cat /setup_done.txt
    echo "------------------------------------"
    echo "Setup script part successfully completed."
fi

echo "All explicit setup steps in run.sh finished."
echo "Log file is at: ${LOG_FILE}"
echo "Keeping container alive with sleep infinity."
echo "Log ended at $(date)"

# Keep the container running
sleep infinity