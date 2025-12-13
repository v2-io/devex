## Error Handling

### Error Message Format

#### Human-Readable (default)
```
Error: Failed to parse configuration file
  File: /home/user/.config/mytool/config.yaml
  Line: 42
  Reason: Unexpected token ':'
  
Try 'mytool --help' for more information.
```

#### Machine-Readable (--format=json)
```json
{
  "error": {
    "code": "CONFIG_PARSE_ERROR",
    "message": "Failed to parse configuration file",
    "details": {
      "file": "/home/user/.config/mytool/config.yaml",
      "line": 42,
      "column": 15,
      "token": ":"
    },
    "help": "https://docs.example.com/errors/CONFIG_PARSE_ERROR"
  }
}
```

### Error Categories
- **Usage Errors**: Invalid flags, missing arguments
- **Input Errors**: Malformed data, missing files
- **Runtime Errors**: Network failures, resource exhaustion
- **Configuration Errors**: Invalid config, missing required settings
- **Permission Errors**: Insufficient privileges

