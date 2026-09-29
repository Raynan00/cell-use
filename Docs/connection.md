# Connect from your app

`CellUseConnection` handles the embedded tunnel, Keychain-backed pairings,
device discovery and session streams. Keep one instance in your app's model.
Your app supplies its UI, agent and background execution window.

First add the [embedded tunnel extension](embedded-tunnel.md) and
[native runtime targets](runtime-integration.md). The supplied native runtime
targets iOS 27. The app and tunnel extension use your Developer Program signing
team; users approve the VPN configuration on their phone.

## Create the connection

```swift
import CellUse
import CellUseRuntime
import DeviceHubLive
import DeviceHubTransport

// Create on MainActor and retain in your app model.
let connection = try CellUseConnection(
    configuration: .init(
        appName: "My App",
        providerBundleIdentifier: "com.example.myapp.tunnel",
        pairingService: "com.example.myapp.pairing"
    ),
    nativeSessions: try .deviceHubLive(probeScreenshots: true)
)

connection.onStateChange = { state in
    // Update your app's UI. See the states below.
}
connection.onFrame = { frame in
    // Optional preview. Frame pixels stay here unless your app sends them.
}

// From your app's Connect button:
connection.connect()
```

Keep the pairing service identifier stable between app versions. Credentials
remain in the native Keychain vault. A saved pairing is reused on subsequent
connections; the controller does not delete pairings when a connection fails.

The default diagnostics recorder keeps a bounded buffer in memory and has no
file storage or upload destination. Pass your own `DiagnosticRecorder` to the
initializer if your app manages diagnostic retention.

## Show the next action in your UI

| State | Host UI |
| --- | --- |
| `startingTunnel` | Show connection progress; iOS handles VPN consent. |
| `pairingRequired` | Show a Pair button calling `connection.pair()`. |
| `pairing(code:)` | Direct the user to Settings > Privacy & Security > Developer Mode and your app's advertised name. Display the temporary code when supplied. |
| `chooseDevice(devices)` | Let the user select a saved device, then call `connection.connect(deviceID:)`. |
| `connecting` | The controller is locating the paired device and opening its session. |
| `checkingReadiness` | Wait for a fresh portrait screenshot and input readiness. |
| `ready` | Enable your app's agent-run action. |
| `needsAction(issue)` | Show `issue.message` and a retry or pairing action as appropriate. |
| `stopping`, `idle` | Stop progress UI; offer Connect when idle. |

Pairing continues into connection automatically when it succeeds. The library
holds a system background lease during the pairing visit to Settings. If your
UI presents the temporary code through a notification or Live Activity, handle
that presentation and permission in the host. Do not store the code in logs.

Developer Mode, local-network permission and prepared developer services are
checked through the native connection. When they require user action, setup
returns a specific issue. The controller does not change system settings.

## Run an agent

```swift
// On MainActor, after connection.state.isReady:
let runtime = try connection.makeRuntime(agent: myAgent)
runtime.onUpdate = { snapshot in /* update your run UI */ }
runtime.onEnded = { /* finish your app's background work */ }

// Start when your app's execution window begins.
runtime.start()

// From the user's Stop action or the OS expiration handler:
runtime.cancel("hostStopped")
await connection.disconnect()
```

The connection feeds the runtime from its single frame/event consumers. Do not
also forward frames manually. `makeRuntime` rejects a second active runtime on
the same connection. Loss of fresh frames or input readiness clears `ready`;
stream failure closes the session and exposes a reconnection action. Reconnect
creates a new session and requires a new runtime.

Explicitly disconnect when the host no longer needs the connection. A completed
agent run can leave the connection available for another user-initiated run.
The host still obtains and ends its own OS background execution allowance.
