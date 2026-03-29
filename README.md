# Pyre Native App

Native macOS and iOS Apple app for [pyre](https://github.com/chrislaskey/pyre) and [pyre_web](https://github.com/chrislaskey/pyre_web).

## Connecting to a Pyre server

The app connects to a Phoenix application that has `pyre` and `pyre_web`
installed. It communicates over Phoenix channels using a WebSocket connection.

### Server requirements

The host Phoenix application must have `PyreWeb.Socket` mounted in its
endpoint. See the
[pyre_web README](https://github.com/chrislaskey/pyre/tree/main/pyre_web#readme)
for full setup instructions.

In short, the host app's `endpoint.ex` needs:

```elixir
socket "/pyre", PyreWeb.Socket,
  websocket: [connect_info: [:peer_data, :x_headers]]
```

### Connection URL

When adding a connection in the app, the **Base URL** should be the full URL
to the Pyre mount point — for example:

- Local development: `http://localhost:4000/pyre`
- Production: `https://myapp.example.com/pyre`

The app automatically converts this to a WebSocket URL
(`ws://localhost:4000/pyre/websocket` or `wss://myapp.example.com/pyre/websocket`)
and connects using Phoenix channels.

### Connection Presence

The app maintains a persistent WebSocket connection to report its presence to
the server. On connect, it sends system information (computer name, CPU,
memory, OS version) so the PyreWeb homepage can display which native app
instances are currently online.

- The connection is tied to the active connection — switching connections in
  the app automatically leaves the old presence and joins the new one.
- Reconnection is handled automatically by the underlying Phoenix socket
  layer (exponential backoff from 1s to 30s).
- Connected apps are visible on the PyreWeb homepage in the "Connected Apps"
  panel.
