# Signal

Fast generic-typed Signal implementation for Luau written based on known practices used in GoodSignal, Sleitnick's Signal and Signal+ implementations. Provides :Fire(), :FireDeferred(), :Connect(), :Once() and :Wait() methods presented in `RBScriptSignal` API, :DisconnectAll() implemented in other realisations and :Disconnect() for Connection variant.

## Installation

```toml
signal = "larsen-dev/signal@1.0.2"
```

Or using .rbxm package at Releases page.

## Usage

```luau
local signal = require(Packages.signal)

type testSignal = signal.Signal<(namedArg0: number, namedArg1: string) -> (), number, string>

local sig = signal.new() :: testSignal

sig:Connect(function(namedArg0, namedArg1) -- namedArg0: number, namedArg1: string
    print(namedArg0, namedArg1)
end)

sig:Fire(1, "Hello!")
```
