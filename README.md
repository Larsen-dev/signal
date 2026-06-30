# Signal

Fast generic-typed Signal implementation for Luau written based on known practices used in GoodSignal, Sleitnick's Signal and Signal+ implementations. Provides :Fire(), :FireDeferred(), :Connect(), :Once() and :Wait() methods presented in `RBScriptSignal` API, :DisconnectAll() implemented in other realisations and :Disconnect() for Connection variant.

## Installation

```toml
signal = "larsen-dev/signal@1.0.0"
```

Or using .rbxm package at Releases page.

## Usage

```lua
local signal = require(Packages.signal)

local sig = signal.new() :: signal.Signal<string>

sig:Connect(function(message) -- message: string
    print(message)
end)

sig:Fire("Hello!")
```
