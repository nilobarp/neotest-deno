import { expect } from "https://deno.land/std@0.208.0/expect/mod.ts";

Deno.test("Top-level test", async (t) => {
    await t.step("First nested test", () => {
        expect(1 + 1).toBe(2);
    });

    await t.step("Second-level nested test", async (t) => {
        await t.step("Third-level nested test", () => {
            expect(2 * 2).toBe(4);
        });

        await t.step("Another third-level nested test", () => {
            expect(3 - 1).toBe(2);
        });
    });
});