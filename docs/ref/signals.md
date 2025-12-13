## Signal Handling

### Standard Signal Behavior

#### Core Signals
```bash
SIGINT (2)    # Ctrl-C: Graceful interruption
SIGTERM (15)  # Graceful termination request
SIGQUIT (3)   # Ctrl-\: Quit with core dump
SIGHUP (1)    # Hangup: Reload configuration
SIGUSR1 (10)  # User-defined: Often toggle debug
SIGUSR2 (12)  # User-defined: Often rotate logs
SIGPIPE (13)  # Broken pipe: Handle gracefully
SIGALRM (14)  # Timer expired
SIGCHLD (17)  # Child process status change
```

#### SIGINT (Ctrl-C) Handling
```bash
# Graceful interruption pattern
handle_sigint() {
    echo "Interrupt received, cleaning up..." >&2
    cleanup_temp_files
    save_progress
    exit 130  # 128 + 2 (SIGINT)
}
trap handle_sigint INT

# Progressive interruption
First Ctrl-C:  "Gracefully stopping... (press again to force)"
Second Ctrl-C: "Force stopping..."
Third Ctrl-C:  Immediate termination
```

#### EOF (Ctrl-D) Handling
```bash
# Ctrl-D sends EOF, not a signal
# Proper handling in interactive mode:
while IFS= read -r line; do
    process_line "$line"
done
# Ctrl-D here ends input gracefully

# Detection and response
if [ -t 0 ]; then  # Interactive terminal
    echo "Press Ctrl-D or type 'exit' to quit"
fi
```

#### SIGHUP Configuration Reload
```bash
# Standard SIGHUP behavior
handle_sighup() {
    echo "Reloading configuration..." >&2
    reload_config
    reopen_log_files  # Important for log rotation
    reset_connections
}
trap handle_sighup HUP

# Usage
kill -HUP $(pidof mytool)  # Reload config
```

### Signal Safety

#### Critical Section Protection
```bash
# Prevent interruption during critical operations
critical_section_start() {
    trap '' INT TERM  # Ignore signals
    CRITICAL=1
}

critical_section_end() {
    CRITICAL=0
    trap handle_sigint INT
    trap handle_sigterm TERM
    # Process any pending signals
    if [ -n "$PENDING_SIGNAL" ]; then
        kill -s "$PENDING_SIGNAL" $$
    fi
}
```

#### Cleanup Guarantees
```bash
# Ensure cleanup happens
cleanup() {
    local exit_code=$?
    set +e  # Don't exit on errors during cleanup
    
    # Remove temp files
    rm -f "$TMPFILE"
    
    # Release locks
    flock -u 9 2>/dev/null
    
    # Restore terminal settings
    stty "$SAVED_STTY" 2>/dev/null
    
    # Kill child processes
    jobs -p | xargs kill 2>/dev/null
    
    exit $exit_code
}
trap cleanup EXIT INT TERM
```

### Signal Propagation

#### Child Process Management
```bash
# Propagate signals to children
handle_signal() {
    local signal=$1
    # Send signal to process group
    kill -$signal 0  # 0 means current process group
    wait  # Wait for children to terminate
}

# Start processes in same group
set -m  # Enable job control
mytool &
child_pid=$!
```

#### Background Job Handling
```bash
# Proper daemon signal handling
--daemon
--pidfile=/var/run/mytool.pid
--signal-forward  # Forward signals to workers

# Signal commands
mytool signal reload    # Send SIGHUP
mytool signal stop      # Send SIGTERM
mytool signal kill      # Send SIGKILL
mytool signal status    # Check if responding
```

