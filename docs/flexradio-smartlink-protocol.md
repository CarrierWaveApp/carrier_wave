# FlexRadio SmartLink WAN Protocol Reference

> Compiled from open-source implementations and the DXLab SmartLink API Guide.

## Overview

SmartLink is FlexRadio's proprietary remote access protocol that brokers WAN connections to Flex-6000 series radios through a central relay server. The protocol uses Auth0 for authentication, a TLS control channel to the SmartLink server for radio discovery and connection brokering, and then establishes a direct TLS+UDP connection to the radio itself.

## Auth0 Configuration (Production)

All known implementations use the same Auth0 tenant:

| Parameter | Value |
|-----------|-------|
| **Domain** | `frtest.auth0.com` |
| **Client ID** | `4Y9fEIIsVYyQo5u6jr7yBWc4lV5ugC2m` |
| **Authenticate URL** | `https://frtest.auth0.com/oauth/ro` |
| **Delegation URL** | `https://frtest.auth0.com/delegation` |
| **Authorize URL** | `https://frtest.auth0.com/authorize` |
| **Token URL** | `https://frtest.auth0.com/oauth/token` |
| **Redirect URI** | `https://frtest.auth0.com/mobile` |
| **Connection** | `Username-Password-Authentication` |
| **Scope** | `openid offline_access email given_name family_name picture` |

> Note: The domain says "frtest" but this IS the production tenant. All shipping FlexRadio products use it.

### Authentication Flows

**Password Grant (Legacy Resource Owner):**
```
POST https://frtest.auth0.com/oauth/ro
Content-Type: application/json

{
  "client_id": "4Y9fEIIsVYyQo5u6jr7yBWc4lV5ugC2m",
  "connection": "Username-Password-Authentication",
  "device": "any",
  "grant_type": "password",
  "username": "<email>",
  "password": "<password>",
  "scope": "openid offline_access email picture"
}

Response: { "id_token": "<JWT>", "refresh_token": "<token>" }
```

**PKCE Authorization Code Flow (Modern - NetKeyer uses this):**
1. Generate code_verifier (32 random bytes, base64url encoded)
2. Generate code_challenge = SHA256(code_verifier), base64url encoded
3. Open browser to `https://frtest.auth0.com/authorize?client_id=...&response_type=code&code_challenge=...&code_challenge_method=S256&redirect_uri=...&scope=...&state=...`
4. User logs in, receives authorization code via redirect
5. Exchange code for tokens at `https://frtest.auth0.com/oauth/token`

**Token Refresh via Delegation:**
```
POST https://frtest.auth0.com/delegation
Content-Type: application/json

{
  "client_id": "4Y9fEIIsVYyQo5u6jr7yBWc4lV5ugC2m",
  "target": "4Y9fEIIsVYyQo5u6jr7yBWc4lV5ugC2m",
  "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
  "refresh_token": "<refresh_token>",
  "scope": "openid email given_name family_name picture"
}
```

**JWT tokens expire 60 seconds after creation.** Refresh tokens do not expire.

## SmartLink WAN Server

| Parameter | Value |
|-----------|-------|
| **Hostname** | `smartlink.flexradio.com` |
| **Port** | `443` |
| **Protocol** | TLS over TCP (NOT WebSocket, NOT HTTPS -- raw TLS socket) |
| **Message framing** | Newline-delimited text (`\n`) |
| **Message format** | Space-delimited `key=value` pairs |
| **Keepalive** | `ping from client\n` every 10 seconds |

## Connection Flow (Complete Sequence)

### Phase 1: Authentication
1. Authenticate with Auth0 to obtain `id_token` (JWT) and `refresh_token`
2. Store refresh_token securely for future sessions

### Phase 2: SmartLink Server Connection
3. TCP connect to `smartlink.flexradio.com:443`
4. Initiate TLS handshake (validate peer name against `smartlink.flexradio.com`)
5. After TLS secured, send registration:
   ```
   application register name=<appName> platform=<platform> token=<id_token>\n
   ```
6. Start ping timer: send `ping from client\n` every 10 seconds
7. Begin reading newline-delimited responses

### Phase 3: Radio Discovery
8. Server sends `application info public_ip=<your_public_ip>`
9. Server sends `application user_settings callsign=<call> first_name=<> last_name=<>`
10. Server sends `radio list` message containing all registered radios:
    ```
    radio list <radio1_kvpairs>|<radio2_kvpairs>|...
    ```
    Each radio entry contains (pipe-separated, key=value within):
    - `serial=<serial_with_dashes>`
    - `model=<model>`
    - `nickname=<name>` (underscores replace spaces)
    - `callsign=<callsign>`
    - `ip=<public_ip>`
    - `status=<Available|In Use>`
    - `version=<firmware_version>`
    - `port=<tcp_port>` (4992 typically)
    - `public_tls_port=<port>` / `public_udp_port=<port>`
    - `public_upnp_tls_port=<port>` / `public_upnp_udp_port=<port>`
    - `max_licensed_version=<version>`
    - `requires_additional_license=<0|1>`
    - `gui_client_handles=<handles>` / `gui_client_hosts=<hosts>` / etc.

### Phase 4: Connection Brokering
11. Send connect request to SmartLink server:
    ```
    application connect serial=<serial> hole_punch_port=<port>\n
    ```
    - `serial`: radio serial number with dashes
    - `hole_punch_port`: 0 (default) or random between 25000-65000

12. Wait for connect_ready response:
    ```
    radio connect_ready serial=<serial> handle=<wan_handle>
    ```
    - `handle` is the WAN connection handle needed for validation

### Phase 5: Direct Radio Connection (TLS)
13. Determine radio's public address:
    - If manual port forwarding: use `public_tls_port` and `public_udp_port`
    - If UPnP: use `public_upnp_tls_port` and `public_upnp_udp_port`
    - Otherwise: use hole punching
14. TLS connect directly to the radio at `<public_ip>:<public_tls_port>`
15. **First command MUST be** the WAN validation:
    ```
    C<seq>|wan validate handle=<wan_handle>\n
    ```
    - The handle is from the `connect_ready` message
    - Any other command first causes immediate disconnect
16. Wait for client handle response (standard FlexRadio API flow)

### Phase 6: UDP Data Stream Setup
17. Create UDP socket to `<public_ip>:<public_udp_port>`
18. Send UDP registration (over UDP, NOT TCP):
    ```
    client udp_register handle=0x<client_handle>\n
    ```
    - `client_handle` is the hex handle received from the radio in step 16
    - This replaces the LAN command `client udpport <port>`
19. Send keepalive ping over UDP every 5 seconds:
    ```
    client ping handle=0x<client_handle>\n
    ```

### Phase 7: Normal Operation
20. Use standard FlexRadio TCP/IP API (commands on TLS TCP, data on UDP)
    - TCP command port: typically 4992 (but use the port from discovery)
    - UDP data port: 4991 (VITA-49 streams)
    - Command format: `C[D]<seq_number>|<command>\n`
    - Response format: `R<seq_number>|<error_code>|<message>\n`
    - Status format: `S<handle>|<object> <key=value pairs>\n`

## Additional SmartLink Server Commands

```
application disconnect_users serial=<serial>\n
application disconnect_users serial=<serial> handle=<handle>\n
application test_connection serial=<serial>\n
```

Test connection results include NAT/port forwarding diagnostics:
- Forward TCP port working
- Forward UDP port working
- UPnP TCP port working
- UPnP UDP port working
- NAT supports hole punch

## VITA-49 Discovery Protocol (LAN)

On local networks, radios broadcast VITA-49 discovery packets:

| Parameter | Value |
|-----------|-------|
| **Port** | 4991 (UDP broadcast) |
| **Stream ID** | `0x00000800` |
| **Class ID** | `0x534CFFFF` |
| **Payload** | `model=%s serial=%s version=%s name=%s callsign=%s ip=%u.%u.%u.%u port=%u` |

C structure:
```c
typedef struct {
    uint32 header;       // VITA-49 flags
    uint32 stream_id;    // 0x00000800
    uint32 class_id_h;   // 0x534C...
    uint32 class_id_l;   // ...FFFF
    uint32 timestamp_int;
    uint32 timestamp_frac_h;
    uint32 timestamp_frac_l;
    char payload[MAX_DISCOVERY_PAYLOAD_SIZE];
} vita_ext_data_discovery;
```

Over WAN, the SmartLink server provides equivalent discovery info in the `radio list` text message (no VITA-49 packets).

## WAN Object Properties (Radio Status)

The radio reports WAN state via standard status messages:

| Property | Key | Type |
|----------|-----|------|
| Server Connected | `server_connected` | Bool |
| Radio Authenticated | `radio_authenticated` | Bool |
| Public TLS Port | `public_tls_port` | Int |
| Public UDP Port | `public_udp_port` | Int |
| Public UPnP TLS Port | `public_upnp_tls_port` | Int |
| Public UPnP UDP Port | `public_upnp_udp_port` | Int |
| UPnP Supported | `upnp_supported` | Bool |

## WAN Commands (Radio-Side)

```
wan register owner_token=<token>
wan unregister owner_token=<token>
wan set public_tls_port=<port> public_udp_port=<port>
wan validate handle=<handle>
```

## Open-Source Implementations

### Swift/macOS (K3TZR - Douglas Adams)
- **K3TZR/ApiPackage** - Latest Swift Package, `ListenerSmartlink.swift`
- **K3TZR/SDRApiFeatures** - TCA-based, `SmartlinkListener.swift` + `SmartlinkParser.swift` + `Authentication.swift`
- **K3TZR/xLib6000** - Original implementation, `WanServer.swift` (most mature, ~1100 lines)
- **K3TZR/xSDR6000** - Full macOS client using xLib6000
- Uses `CocoaAsyncSocket` (GCDAsyncSocket) for TLS
- IPv4 preferred, IPv6 disabled

### C# / .NET (FlexLib)
- **mgi2212/FlexLibDemos** - `FlexLib/WanServer.cs` (reference implementation)
- **jeffu231/Flexlib** - Fork with WanServer.cs
- **mkcmsoftware/smartlink** - WPF SmartLink V2 sample client
- **KevinSShaffer/JJFlexRadio** - Multiple API versions
- **NetKeyer/NetKeyer** - `SmartLinkAuthService.cs` with PKCE flow
- Uses `SslClient` wrapper around `SslStream`

### Go
- **kc2g-flex-tools/flexclient** - Clean Go implementation with `InitWANUDP()`, `WithTLS()` option

### Python
- **OpenResearchInstitute/flexclient** - `SmartLink.py`, Selenium-based auth
- **sconklin/gnu-radio-implementation-for-flex** - `SmartLink.py` fork

### C++ / Qt
- **ten9876/AetherSDR** - `SmartLinkClient.h/.cpp`, `WanConnection.h/.cpp`

### PowerShell
- **rfoust/FlexModule** - `Connect-FlexSmartLink.ps1`

## Key Implementation Notes

1. **TLS, not WebSocket**: The SmartLink server uses raw TLS sockets, not WebSocket or HTTPS REST. Messages are newline-delimited plaintext over the TLS channel.

2. **JWT expiry is 60 seconds**: Tokens must be fresh. Always use delegation/refresh to get a new JWT before connecting.

3. **wan validate MUST be first**: After connecting directly to the radio over TLS, the very first command must be `wan validate handle=<h>`. Any other command causes immediate disconnect.

4. **UDP registration differs from LAN**: On LAN you send `client udpport <port>` over TCP. On WAN you send `client udp_register handle=0x<handle>` over UDP directly to the radio.

5. **UDP keepalive required**: Send `client ping handle=0x<handle>` over UDP every ~5 seconds to keep the NAT mapping alive.

6. **Port selection priority**: Manual forwarded ports > UPnP ports > hole punching.

7. **Character encoding**: The WAN server uses cp1252/ASCII encoding, not UTF-8.
