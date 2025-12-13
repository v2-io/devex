## Command-Line Interface

### Universal Flags
Every tool should support:
```bash
-h, --help                    # Show help
-v, --verbose                 # Increase verbosity (stackable: -vvv)
-q, --quiet                   # Suppress non-error output
--version                     # Show version and exit
--format=FORMAT               # Output format (json|text|csv|tsv|yaml)
--no-color                    # Disable colored output
--color=auto|always|never     # Color output control
--dry-run                     # Preview what would be done
--debug                       # Maximum verbosity for debugging
```

### Flag Conventions
```bash
# Short flags (single dash, single letter)
-v              # Boolean flag
-f filename     # With argument (space)
-ffilename      # With argument (no space)
-abc            # Combined boolean flags (equals -a -b -c)

# Long flags (double dash, descriptive)
--verbose                     # Boolean flag
--file=filename              # With argument (equals)
--file filename              # With argument (space)

# Special conventions
--                          # Stop processing flags
-                           # Stdin/stdout placeholder
@filename                   # Read arguments from file
```

### Exit Codes
```bash
0     Success
1     General errors
2     Misuse of shell command (invalid options, missing arguments)
64    Command line usage error (EX_USAGE)
65    Data format error (EX_DATAERR)
66    Cannot open input (EX_NOINPUT)
67    Addressee unknown (EX_NOUSER)
68    Host name unknown (EX_NOHOST)
69    Service unavailable (EX_UNAVAILABLE)
70    Internal software error (EX_SOFTWARE)
71    System error (EX_OSERR)
72    Critical OS file missing (EX_OSFILE)
73    Can't create output file (EX_CANTCREAT)
74    I/O error (EX_IOERR)
75    Temporary failure (EX_TEMPFAIL)
76    Remote error in protocol (EX_PROTOCOL)
77    Permission denied (EX_NOPERM)
78    Configuration error (EX_CONFIG)
126   Command found but not executable
127   Command not found
128+n Fatal signal n (e.g., 130 = 128+2 = SIGINT)
```

