// Task to start the accelerator
// and wait for it to finish its task
task automatic start_and_wait_gemm();
begin
  automatic int cycle_count;
  cycle_count = 0;
  // Start the GEMM operation
  @(posedge clk_i);
  start = 1'b1;
  @(posedge clk_i);
  start = 1'b0;
  while (done == 1'b0) begin
  @(posedge clk_i);
  cycle_count = cycle_count + 1;
  if (cycle_count > 100000) begin
    $display("ERROR: GEMM operation timeout after %0d cycles", cycle_count);
    $fatal;
  end
  end
  @(posedge clk_i);
  $display("GEMM operation completed in %0d cycles", cycle_count);
end
endtask

// Task to verify the resulting matrix
task automatic verify_result_c(
  input logic signed [OutDataWidth-1:0] golden_data [DataDepth],
  input logic signed [OutDataWidth-1:0] actual_data [DataDepth],
  input logic        [   AddrWidth-1:0] num_data,
  input logic                           fatal_on_mismatch
);
begin
    // Compare with SRAM C contents
  for (int unsigned addr = 0; addr < num_data; addr++) begin
  if (golden_data[addr] !== actual_data[addr]) begin
    $display("ERROR: Mismatch at address %0d: expected %h, got %h",
            addr, golden_data[addr], actual_data[addr]);
    if (fatal_on_mismatch)
    $fatal;
  end
  end
  $display("Result matrix C verification passed!");
end
endtask

task automatic verify_result_tile(
  input logic signed [OutDataWidth-1:0] golden_data [DataDepth],
  input logic signed [OutDataWidth-1:0] actual_data [DataDepth],
  input int unsigned tile_base_addr,   // start index of the tile in C
  input int unsigned tile_size,        // normally 64
  input logic         fatal_on_mismatch
);
  int unsigned i;
  for (i = 0; i < tile_size; i++) begin
    if (golden_data[tile_base_addr + i] !== actual_data[tile_base_addr + i]) begin
      $display("ERROR: mismatch at C[%0d]: expected %h, got %h",
               tile_base_addr + i,
               golden_data[tile_base_addr + i],
               actual_data[tile_base_addr + i]);
      if (fatal_on_mismatch)
        $fatal;
    end
  end
  $display("Tile verification PASSED (tile starting at %0d)", tile_base_addr);
endtask
