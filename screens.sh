#!/bin/bash

# Get a list of detached sessions and append "Quit" to the list
sessions=$(screen -ls | grep "(Detached)" | awk '{print $1}')

# Add 'Quit' to the options
options=($sessions "Quit")

if [ -z "$sessions" ]; then
    echo "No detached screen sessions found."
    exit 0
fi

echo "Select a session to reattach to:"
PS3="Selection (Enter number): "

select session in "${options[@]}"; do
    case $session in
        "Quit")
            echo "Exiting."
            exit 0
            ;;
        *)
            if [ -n "$session" ]; then
                echo "Reattaching to: $session"
                screen -r "$session"
                break
            else
                echo "Invalid selection. Please try again."
            fi
            ;;
    esac
done
