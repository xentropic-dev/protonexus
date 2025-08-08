# Conman

**Conman** — the **Concurrent Mediator and Notifier** for coordinating and notifying concurrent tasks in Zig.

## ✨ Features

- ⚡ **Concurrent** command mediation
- 🔔 **Event-based** notification system
- 🧩 Decouples producers and consumers
- 🧵 Built for asynchronous & parallel Zig workflows

## 🚀 Quick Example

```zig
const std = @import("std");
const conman = @import("conman");

pub fn main() void {
    // TODO FILL THIS OUT
}

```

## 🧠 CQRS Support

Conman supports the CQRS (Command Query Responsibility Segregation) pattern:

- Commands go through a mediated channel.
- Queries and notifications remain responsive and decoupled.
  Perfect for message-driven architectures.

## 📦 Installation

Add Conman to your Zig project via build.zig.zon or manual import. Zig package manager support coming soon.

## 🪪 License

MIT © 2025 Christopher Laponsie
