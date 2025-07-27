# neotest-deno

A [neotest](https://github.com/rcarriga/neotest) adapter for [deno](https://deno.land/).

Features:
- **LSP Integration**: Uses Deno's Language Server Protocol testing interface for accurate test discovery
- **Nested Test Support**: Full support for Deno's `t.step()` nested test steps
- **Fallback Support**: TreeSitter-based parsing when LSP is not available
- **BDD Support**: Works with `describe()` and `it()` style tests

![neotest-deno1](https://user-images.githubusercontent.com/21696951/206565569-3d7b6489-da56-42e3-bf72-9b2599dc3a30.gif)

## Installation

Requires [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter).

Install and configure like any other neotest adapter:

```lua
use "markemmons/neotest-deno"

require("neotest").setup({
	adapters = {
		require("neotest-deno"),
		-- ... other adapters
	}
})
```

## Configuration

```lua
require("neotest").setup({
	adapters = {
		require("neotest-deno")({
			use_lsp_testing = true, -- Use LSP for test discovery (default: true)
			args = {}, -- Additional arguments for deno test
			allow = "--allow-all", -- Deno permissions
			-- ... other options
		})
	}
})
```

## LSP Integration

This adapter leverages Deno's LSP testing interface when available. See [LSP_INTEGRATION.md](LSP_INTEGRATION.md) for detailed information about:
- Setting up LSP testing
- Nested test step support
- Troubleshooting LSP issues

## Test Support

- [x] Deno.test tests
- [x] bdd - nested tests
- [ ] bdd - flat tests
- [ ] Chai
- [ ] Sinon.JS
- [ ] fast-check
- [ ] Documentation tests

## DAP Support

![neotest-deno2](https://user-images.githubusercontent.com/21696951/206599082-2c1759d2-6158-41e5-9121-cb3bdb7fbe08.gif)

## Benchmarks

TODO

## Coverage

TODO
