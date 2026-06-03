# Khoron (`kh.src`)

Lua-lite language for Cropbots programming puzzles. Integrated from `lua/` via `require("init")` after `src.Gfx` sets `package.path`.

## Syntax (sketch)

- No `local` — assign with `name = value`
- String concat: `"a" + "b"`
- Blocks: `if cond:`, `while cond:`, `repeat n:`, `function name():` … `end`
- Optional `()` on zero-arg calls: `print "hi"` or `print("hi")`

## Builtins

| Name | Role |
|------|------|
| `print` | Notebook console |
| `input` | Prompt (notebook) |
| `move`, `turn_left`, `turn_right`, `collect`, `attack` | Robot (game hooks later) |

## API

```lua
local Khoron = require("init")
Khoron.run(source, builtins)
local s = Khoron.stepper(source, builtins)
s:setSpeed("regular") -- cheetah … turtle
s:reset()
s:update(dt)
```

Step mode highlights the current line and dims executed lines; `repeat` shows a countdown label.
