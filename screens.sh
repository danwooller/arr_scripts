#!/bin/bash

# Get a list of detached screens
# The output format of 'screen -ls' is parsed to get the session IDs
#sessions=$(screen -ls | grep Detached | awk '{print $1}')
sessions=$(screen -ls | grep "(Detached)" | awk '{print $1}')

if [ -z "$sessions" ]; then
    echo "No detached screen sessions found."
    exit 0
fi

echo "Select a session to reattach to:"
select session in $sessions; do
    if [ -n "$session" ]; then
        echo "Reattaching to: $session"
        screen -r "$session"
        break
    else
        echo "Invalid selection. Please try again."
    fi
done
