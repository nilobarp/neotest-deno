# LSP Integration

This version of neotest-deno has been enhanced to use Deno's Language Server Protocol (LSP) testing interface when available, providing better support for nested tests and test steps.

## Features

### LSP-based Test Discovery
When the Deno LSP is available and supports the testing API, the plugin will:
- Use LSP notifications to discover tests and test steps
- Properly handle nested test steps using `t.step()`
- Support dynamic test discovery during runtime
- Provide accurate test ranges and positions

### Fallback TreeSitter Support
When LSP is not available or doesn't support testing API, the plugin falls back to:
- TreeSitter-based parsing for test discovery
- Support for basic `Deno.test()` calls
- Support for nested `t.step()` calls
- BDD-style `describe()` and `it()` blocks

## Configuration

```lua
require("neotest").setup({
  adapters = {
    require("neotest-deno")({
      use_lsp_testing = true, -- Enable LSP testing interface (default: true)
      -- ... other options
    })
  }
})
```

## LSP Requirements

To use the LSP testing interface:
1. Have the Deno LSP (denols) installed and running
2. Ensure the LSP client supports the experimental `testingApi` capability
3. The Deno version should support the testing API extensions

## Nested Test Support

The plugin now properly supports Deno's nested test steps:

```typescript
Deno.test("Top-level test", async (t) => {
    await t.step("First nested test", () => {
        expect(1 + 1).toBe(2);
    });

    await t.step("Second-level nested test", async (t) => {
        await t.step("Third-level nested test", () => {
            expect(2 * 2).toBe(4);
        });
    });
});
```

Each test step will be discovered as a separate runnable test in the neotest interface.

## Benefits of LSP Integration

- **More Accurate**: Uses Deno's own test parsing logic
- **Dynamic Discovery**: Can discover tests that are created at runtime
- **Better Performance**: No need to parse files multiple times
- **Future-Proof**: Automatically supports new Deno testing features
- **Nested Steps**: Full support for deeply nested test steps

## Troubleshooting

If LSP integration isn't working:
1. Check that denols is running: `:LspInfo`
2. Verify testing API support in LSP capabilities
3. Set `use_lsp_testing = false` to use TreeSitter fallback
4. Check Deno version supports testing API extensions
