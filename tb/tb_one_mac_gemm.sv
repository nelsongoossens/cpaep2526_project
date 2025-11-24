module tb_one_mac_gemm;
  //---------------------------
  // Design Time Parameters
  //---------------------------

   // General Parameters
  parameter int unsigned InDataWidth   = 8;
  parameter int unsigned OutDataWidth  = 32;
  parameter int unsigned DataDepth     = 4096;
  parameter int unsigned AddrWidth     = (DataDepth <= 1) ? 1 : $clog2(DataDepth);
  parameter int unsigned SizeAddrWidth = 8;

  parameter int unsigned NumInputA  = 1;
  parameter int unsigned NumInputB  = 1;
  parameter int unsigned NumOutputC = 1;

  //---------------------------
  // Test Parameters
  //---------------------------
  parameter int unsigned MaxNum    = 32;
  parameter int unsigned NumTests  = 10;

  parameter int unsigned SingleM = 8;
  parameter int unsigned SingleK = 8;
  parameter int unsigned SingleN = 8;

  //---------------------------
  // Wires
  //---------------------------
  // Size control
  logic [SizeAddrWidth-1:0] M_i, K_i, N_i;

  // Clock, reset, and other signals
  logic clk_i;
  logic rst_ni;
  logic start;
  logic done;
  
  //---------------------------
  // Memory
  //---------------------------
  // Golden data dump
  logic signed [OutDataWidth-1:0] G_memory [DataDepth];

  // Memory control
  logic        [ NumInputA-1:0][AddrWidth-1:0] sram_a_addr;
  logic        [ NumInputB-1:0][AddrWidth-1:0] sram_b_addr;
  logic        [NumOutputC-1:0][AddrWidth-1:0] sram_c_addr;

  // Memory access
  logic signed [ NumInputA-1:0][  InDataWidth-1:0] sram_a_rdata;
  logic signed [ NumInputB-1:0][  InDataWidth-1:0] sram_b_rdata;
  logic signed [NumOutputC-1:0][ OutDataWidth-1:0] sram_c_wdata;
  logic sram_c_we;

  //---------------------------
  // Declaration of input and output memories
  //---------------------------

  // Input memory A
  // Note: this is read only
  multi_port_memory #(
    .DataWidth  ( InDataWidth  ),
    .NumPorts   ( NumInputA    ),
    .DataDepth  ( DataDepth    ),
    .AddrWidth  ( AddrWidth    )
  ) i_sram_a (
    .clk_i         ( clk_i        ),
    .rst_ni        ( rst_ni       ),
    .mem_addr_i    ( sram_a_addr  ),
    .mem_we_i      ( '0           ),
    .mem_wr_data_i ( '0           ),
    .mem_rd_data_o ( sram_a_rdata )
  );

  // Input memory B
  // Note: this is read only
  multi_port_memory #(
    .DataWidth  ( InDataWidth  ),
    .NumPorts   ( NumInputB    ),
    .DataDepth  ( DataDepth    ),
    .AddrWidth  ( AddrWidth    )
  ) i_sram_b (
    .clk_i         ( clk_i        ),
    .rst_ni        ( rst_ni       ),
    .mem_addr_i    ( sram_b_addr  ),
    .mem_we_i      ( '0           ),
    .mem_wr_data_i ( '0           ),
    .mem_rd_data_o ( sram_b_rdata )
  );

  // Output memory C
  // Note: this is write only
  multi_port_memory #(
    .DataWidth  ( OutDataWidth ),
    .NumPorts   ( NumOutputC   ),
    .DataDepth  ( DataDepth    ),
    .AddrWidth  ( AddrWidth    )
  ) i_sram_c (
    .clk_i         ( clk_i        ),
    .rst_ni        ( rst_ni       ),
    .mem_addr_i    ( sram_c_addr  ),
    .mem_we_i      ( {NumOutputC{sram_c_we}}),
    .mem_wr_data_i ( sram_c_wdata ),
    .mem_rd_data_o ( /* unused */ )
  );

  //---------------------------
  // DUT instantiation
  //---------------------------
  gemm_accelerator_top #(
    .InDataWidth      ( InDataWidth   ),
    .OutDataWidth     ( OutDataWidth  ),
    .AddrWidth        ( AddrWidth     ),
    .SizeAddrWidth    ( SizeAddrWidth )
  ) i_dut (
    .clk_i            ( clk_i         ),
    .rst_ni           ( rst_ni        ),
    .start_i          ( start         ),
    .M_size_i         ( M_i           ),
    .K_size_i         ( K_i           ),
    .N_size_i         ( N_i           ),
    .sram_a_addr_o    ( sram_a_addr   ),
    .sram_b_addr_o    ( sram_b_addr   ),
    .sram_c_addr_o    ( sram_c_addr   ),
    .sram_a_rdata_i   ( sram_a_rdata  ),
    .sram_b_rdata_i   ( sram_b_rdata  ),
    .sram_c_wdata_o   ( sram_c_wdata  ),
    .sram_c_we_o      ( sram_c_we     ),
    .done_o           ( done          )
  );

  //---------------------------
  // Tasks and functions
  //---------------------------
  `include "includes/common_tasks.svh"
  `include "includes/test_tasks.svh"
  `include "includes/test_func.svh"

  //---------------------------
  // Start of testbench
  //---------------------------

  // Clock generation
  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;  // 100MHz clock
  end

  // Test control
  initial begin
  
    // Initial reset
    start = 1'b0;
    rst_ni = 1'b0;
    #50;
    rst_ni = 1'b1;

    for (integer num_test = 0; num_test < NumTests; num_test++) begin
      $display("Test number: %0d", num_test);

      if (NumTests > 1) begin
        M_i = $urandom_range(1, MaxNum);
        K_i = $urandom_range(1, MaxNum);
        N_i = $urandom_range(1, MaxNum);
      end else begin
        M_i = SingleM;
        K_i = SingleK;
        N_i = SingleN;
      end

      $display("M: %0d, K: %0d, N: %0d", M_i, K_i, N_i);

      // Initialize memories with random data
      for (integer m = 0; m < M_i; m++) begin
        for (integer k = 0; k < K_i; k++) begin
          i_sram_a.memory[m*K_i + k] = $urandom()%(2**InDataWidth);
        end
      end

      for (integer k = 0; k < K_i; k++) begin
        for (integer n = 0; n < N_i; n++) begin
          i_sram_b.memory[k*N_i + n] = $urandom()%(2**InDataWidth);
        end
      end

      // Generate golden result
      gemm_golden(
        M_i,
        K_i,
        N_i,
        i_sram_a.memory,
        i_sram_b.memory,
        G_memory
      );

      // Just delay 1 cycle
      clk_delay(1);

      // Execute the GeMM
      start_and_wait_gemm();

      // Verify the result
      verify_result_c(
        G_memory,
        i_sram_c.memory,
        NumOutputC,
        0 // Set this to 1 to make mismatches fatal
      );

      // Just some trailing cycles
      // For easier monitoring in waveform
      clk_delay(10);
    end
    
    $display("All test tasks completed successfully!");
    $finish;
  end

endmodule
