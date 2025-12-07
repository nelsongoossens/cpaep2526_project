# How to run the testbench (`tb/tb_gemm_variable_dimensions.sv`)
- From the repo root, run:
```
make TEST_MODULE=tb_gemm_variable_dimensions questasim-run
```
- During simulation, the console will print progress for each executed test and should end with `ALL TESTS PASSED`
- Any mismatch between hardware output and the golden model causes an immediate `$fatal`.

# Predefined workloads

## Test 1–3: Core validation cases

These are the three primary tests and map directly onto the three accelerator cases:
- Test 1 = Case 1: 4 × 64 multiplied by 64 × 16
→ exactly one output tile.
- Test 2 = Case 2: Uses the same shapes as Test 1, but swaps and transposes the inputs
(A stored in B, B stored in A) to verify correctness of transposed operation mode.
- Test 3 = Case 3: 32 × 32 multiplied by 32 × 32
→ produces multiple tiles (8 × 2 = 16 tiles) and validates full tiling logic.

These tests run by default and should all report PASSED.

## Optional Tests (commented out)

The following tests are provided but disabled by default:
- Test 4: 8 × 16 × 16 × 32 — 4-tile result
- Test 5: 5 × 64 × 64 × 16 — 2-tile result
- Test 6: 4 × 30 × 30 × 10 — 1 tile, non-aligned dimensions

Uncomment these blocks in the testbench if you want to run them.

# Running your own workloads

You can freely modify `M_i, K_i, N_i` in the testbench to run your own workloads.



