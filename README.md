# ProtoNexus

**ProtoNexus** is a modern, cloud-native industrial data broker built for
flexibility, speed, and simplicity. It bridges industrial systems like PLCs,
SCADA, and IoT devices using a powerful transformation pipeline. Designed with
a container-friendly architecture and written in Zig, ProtoNexus is lightweight
and secure.

The web-based frontend (built with Vite and React) provides a drag-and-drop
interface for creating data flows. Transform modules can be chained,
configured visually, or enhanced with custom scripting. ProtoNexus supports
real-time processing and protocol adapters like OPC UA, MQTT, Modbus, and more.

The backend serves both the API and the frontend static files, making
deployment seamless. You can run ProtoNexus locally with minimal dependencies
or containerize it for production environments. ProtoNexus is the
next-generation alternative to bulky, expensive industrial data brokers. Start
building smarter, simpler, and more maintainable industrial systems today.

## Dependencies

### Backend

The backend is written in Zig and follows Zig long term releases.  Currently,
it uses Zig 0.14.1.

The OPC server uses a C dependency called open62541, which is included using
zig translate-c with few modifications to get around struct packed bitfields,
which are not currently supported by transport-c and needed to be manually 
created.

open65241 requires libmbedtls.  We build libmbedtls internally in our build
pipeline and everything works cross-plaform on linux, windows, and macos.

You just need to make sure to pull in git sub modules, as do not copy 3rd
party code for libmbedtls directly into the repo since we want to stay current
with their main branch.

```bash
git submodule update --init --recursive --remote
```

### Frontend

The frontend is built with Vite and React. It requires Node.js and npm.
To install the frontend dependencies, run:

```bash
cd client/protonexus
npm install
```

To build the frontend, run:
```bash
cd client/protonexus
npm run build
```

This will create a production build in the `dist` directory, which will be served
as static files by the Zig backend using Zap.

