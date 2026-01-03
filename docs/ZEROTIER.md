# ZeroTier Monitor Documentation

## Overview

The `zerotier_clients` function displays the status of ZeroTier network members, including their names, descriptions, assigned IP addresses, and last seen timestamps. It fetches data from the ZeroTier API and caches results for performance.

## Location

`~/env/functions/monitors` (function: `zerotier_clients`)

## Features

- **Member Status**: Shows all network members with non-empty names and descriptions
- **IP Addresses**: Displays all assigned IP addresses for each member
- **Last Seen**: Shows when each member was last online (human-readable ISO 8601 format)
- **Caching**: Results are cached for 5 minutes to reduce API calls
- **Fallback**: Returns cached data if API is unreachable

## Usage

### Basic Usage

```bash
# Source the functions file first
source ~/env/functions/monitors

# Run the function
zerotier_clients
```

### Sample Output

```
Main TV: mi box s | IP Address(es): 10.147.17.11, 10.241.111.13 | Last Seen: 2025-01-03T19:30:15Z
LenovoFlex2: 05283431 | IP Address(es): 10.147.17.151, 10.241.57.239 | Last Seen: 2025-01-03T18:45:22Z
Omri Home: Desk computer in home | IP Address(es): 10.147.17.156, 10.241.94.70 | Last Seen: 2025-01-02T12:18:26Z
```

## Environment Variables

- `ZEROTIER_API_KEY`: API key for ZeroTier authentication (required)
- `ZEROTIER_NETWORK_ID`: Network ID to query (required)
- `ENV_DIR`: Base directory for cache file (defaults to `~/env`)

## API Endpoint

```
https://my.zerotier.com/api/network/{NETWORK_ID}/member
```

## Timestamp Handling

### Important: Millisecond Conversion

ZeroTier API returns timestamps in **milliseconds** (Unix epoch × 1000). The jq expression divides by 1000 to convert to seconds before formatting:

```jq
(.lastSeen | tonumber | . / 1000 | todate)
```

**Why this matters**: Without the `/ 1000` division, timestamps would be interpreted as seconds, resulting in astronomical years like 57956 instead of 2025.

### Examples

| Timestamp (ms) | Timestamp (s) | ISO 8601 Date |
|----------------|---------------|---------------|
| 0 | 0 | 1970-01-01T00:00:00Z |
| 1735689600000 | 1735689600 | 2025-01-01T00:00:00Z |
| 1735929600000 | 1735929600 | 2025-01-03T19:00:00Z |

## Cache File

Location: `~/env/tmp/zerotier_cache`

- **TTL**: 300 seconds (5 minutes)
- **Format**: Plain text output
- **Update**: Automatically refreshed when TTL expires

## Function Details

### `zerotier_clients()`

**Returns**:
- `0`: Success (with or without cached data)
- `1`: API unreachable (falls back to cache if available)

**Process**:
1. Check if cache exists and is fresh (< 5 minutes old)
2. If cache is valid, return cached data
3. Otherwise, fetch from ZeroTier API with timeout
4. Parse JSON response using jq
5. Convert timestamps from milliseconds to ISO 8601
6. Sort output and cache results

## jq Expression

```jq
.[] | select(.name != "" and .description != "") |
  "\(.name): \(.description) | IP Address(es): \(.config.ipAssignments | join(", ")) | Last Seen: \(.lastSeen | tonumber | . / 1000 | todate)"
```

Breakdown:
- `.[]`: Iterate over all array elements
- `select(.name != "" and .description != "")`: Filter out unnamed members
- `\(.name)`: Member name
- `\(.description)`: Member description
- `\(.config.ipAssignments | join(", "))`: Comma-separated IP addresses
- `\(.lastSeen | tonumber | . / 1000 | todate)`: Convert timestamp to ISO date

## Error Handling

- **Timeout**: API request times out after 5 seconds
- **Missing credentials**: Returns "Unable to reach ZeroTier API"
- **Cache fallback**: Returns cached data if API fails

## Testing

Run the ZeroTier tests:

```bash
~/env/tests/zerotier_test.sh
```

The test suite validates:
- Correct millisecond to second conversion
- ISO 8601 date formatting
- Epoch timestamp handling (0 → 1970-01-01)
- Bug prevention (astronomical years from incorrect conversion)

## Dependencies

- `curl`: HTTP client for API requests
- `jq`: JSON processor for parsing responses
- `timeout`: Command timeout protection

## Related Functions

- `kuma_status()`: Display Uptime Kuma monitor status

## See Also

- [ZeroTier API Documentation](https://docs.zerotier.com/api/)
- [jq Manual](https://stedolan.github.io/jq/manual/)
