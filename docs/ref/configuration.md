## Configuration Management

### Precedence Order (highest to lowest)
1. Command-line flags
2. Environment variables (`MYTOOL_*` prefix)
3. Local config file (`./.mytoolrc` or `./mytool.{json,yaml,toml}`)
4. User config file (`~/.config/mytool/config`)
5. System config (`/etc/mytool/config`)
6. Built-in defaults

### Configuration File Locations
```bash
# Standard locations (XDG Base Directory Specification)
~/.config/mytool/           # User config directory
~/.local/share/mytool/      # User data directory
~/.cache/mytool/            # User cache directory
/etc/mytool/                # System config directory

# Legacy support (if needed)
~/.mytool                   # Old-style dotfile
~/.mytool.conf              # Old-style config
```

### Environment Variables
```bash
# Naming convention
MYTOOL_CONFIG_FILE=/path/to/config
MYTOOL_LOG_LEVEL=debug
MYTOOL_FORMAT=json
MYTOOL_NO_COLOR=1

# Special variables
MYTOOL_HOME              # Override base directory
MYTOOL_DISABLE_UPDATE    # Disable auto-update checks
MYTOOL_AGENT_MODE=1      # Force agent mode
```

### Working Directory Behavior
1. Explicit paths in arguments are relative to CWD
2. Config files search order:
   - Relative to CWD first (project-specific)
   - Relative to script location (bundled configs)
   - Standard system locations
3. Use `--config=PATH` to override
4. Document this behavior clearly

