//---------------------------
// The 1-MAC GeMM accelerator top module
//
// Description:
// This module implements a simple General Matrix-Matrix Multiplication (GeMM)
// accelerator using a single Multiply-Accumulate (MAC) Processing Element (PE).
// It interfaces with three SRAMs for input matrices A and B, and output matrix C.
//
// It includes a controller to manage the GeMM operation and address generation logic
// for accessing the SRAMs based on the current matrix sizes and counters.
//
// Parameters:
// - InDataWidth  : Width of the input data (matrix elements).
// - OutDataWidth : Width of the output data (result matrix elements).
// - AddrWidth    : Width of the address bus for SRAMs.
// - SizeAddrWidth: Width of the size parameters for matrices.
//
// Ports:
// - clk_i        : Clock input.
// - rst_ni       : Active-low reset input.
// - start_i      : Start signal to initiate the GeMM operation.
// - M_size_i     : Size of matrix M (number of rows in A and C
// - K_size_i     : Size of matrix K (number of columns in A and rows in B).
// - N_size_i     : Size of matrix N (number of columns in B and C).
// - sram_a_addr_o: Address output for SRAM A.
// - sram_b_addr_o: Address output for SRAM B.
// - sram_c_addr_o: Address output for SRAM C.
// - sram_a_rdata_i: Data input from SRAM A.
// - sram_b_rdata_i: Data input from SRAM B.
// - sram_c_wdata_o: Data output to SRAM C.
// - sram_c_we_o  : Write enable output for SRAM C.
// - done_o       : Done signal indicating completion of the GeMM operation.
//---------------------------

module gemm_accelerator_top #(
  parameter int unsigned InDataWidth = 8,
  parameter int unsigned OutDataWidth = 32,
  parameter int unsigned AddrWidth = 16,
  parameter int unsigned SizeAddrWidth = 8,
  parameter int unsigned RowPar = 4,
  parameter int unsigned ColPar = 16
) (
  input  logic                                                   clk_i,
  input  logic                                                   rst_ni,
  input  logic                                                   start_i,
  input  logic        [SizeAddrWidth-1:0]                        M_size_i,
  input  logic        [SizeAddrWidth-1:0]                        K_size_i,
  input  logic        [SizeAddrWidth-1:0]                        N_size_i,
  output logic        [RowPar-1:0][AddrWidth-1:0]                sram_a_addr_o,
  output logic        [ColPar-1:0][AddrWidth-1:0]                sram_b_addr_o,
  output logic        [RowPar-1:0][ColPar-1:0][AddrWidth-1:0]    sram_c_addr_o,
  input  logic signed [RowPar-1:0][InDataWidth-1:0]              sram_a_rdata_i,
  input  logic signed [ColPar-1:0][InDataWidth-1:0]              sram_b_rdata_i,
  output logic signed [RowPar-1:0][ColPar-1:0][OutDataWidth-1:0] sram_c_wdata_o,
  output logic                                                   sram_c_we_o,
  output logic                                                   done_o
);

  //---------------------------
  // Wires
  //---------------------------

  // logic [SizeAddrWidth-1:0] M_tiles;
  // logic [SizeAddrWidth-1:0] N_tiles;

  logic [SizeAddrWidth-1:0] M_count;
  logic [SizeAddrWidth-1:0] K_count;
  logic [SizeAddrWidth-1:0] N_count;

  // logic [SizeAddrWidth-1:0] row_base;
  // logic [SizeAddrWidth-1:0] col_base;

  // logic [RowPar-1:0]        row_valid;
  // logic [ColPar-1:0]        col_valid;

  logic busy;
  // logic tile_result_valid;
  logic valid_data;
  assign valid_data = start_i || busy;

  // assign M_tiles = (M_size_i + RowPar - 1) / RowPar; //TODO: deze calculation maakt nog geen sense
  // assign N_tiles = (N_size_i + ColPar - 1) / ColPar;


  //---------------------------
  // DESIGN NOTE:
  // This is a simple GeMM accelerator design using a single MAC PE.
  // The controller manages just the counting capabilities.
  // Check the gemm_controller.sv file for more details.
  //
  // Essentially, it tightly couples the counters and an FSM together.
  // The address generation logic is just after this controller.
  //
  // You have the option to combine the address generation and controller
  // all in one module if you prefer. We did this intentionally to separate tasks.
  //---------------------------

  // Main GeMM controller
  gemm_controller #(
    .AddrWidth      ( SizeAddrWidth )
  ) i_gemm_controller (
    .clk_i          ( clk_i       ),
    .rst_ni         ( rst_ni      ),
    .start_i        ( start_i     ),
    .input_valid_i  ( valid_data  ),
    .result_valid_o ( 1'b1 ),       // tile_result_valid
    .busy_o         ( busy        ),
    .done_o         ( done_o      ),
    .M_size_i       ( M_tiles     ),
    .K_size_i       ( K_size_i    ),
    .N_size_i       ( N_tiles     ),
    .M_count_o      ( M_count     ),
    .K_count_o      ( K_count     ),
    .N_count_o      ( N_count     )
  );

  //---------------------------
  // DESIGN NOTE:
  // This part is the address generation logic for the input and output SRAMs.
  // In our example, we made the assumption that both matrices A and B
  // are stored in row-major order. yes
  //
  // Please adjust this part to align with your designed memory layout
  // The counters are used for the matrix A and matrix B address generation;
  // for matrix C, the corresponding address is calculated at the previous cycle,
  // thus adding one cycle delay on c
  //
  // Just be careful to know on which cycle the addresses are valid.
  // Align it carefully with the testbench's memory control.
  //---------------------------

  // Input addresses for matrices A and B
  for(genvar m = 0; m < RowPar; m++) begin : gen_a_addr
    assign sram_a_addr_o[m] = (M_count * K_size_i + SizeAddrWidth'(m));
  end
  
  for(genvar n = 0; n < ColPar; n++) begin : gen_b_addr
    assign sram_b_addr_o[n] = (K_count * N_size_i + SizeAddrWidth'(n));
  end


  // Output address for matrix C
  for(genvar m = 0; m < RowPar; m++) begin : row_c_addr
    for(genvar n = 0; n < ColPar; n++) begin : col_c_addr
      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
          sram_c_addr_o[m][n] <= '0;
        end else if (1'b1) begin  // Always valid in this simple design
          sram_c_addr_o[m][n] <= SizeAddrWidth'(m) * N_size_i + SizeAddrWidth'(n);
        end
      end
    end
  end

  //---------------------------
  // DESIGN NOTE:
  // This part is the MAC PE instantiation and data path logic.
  // Check the general_mac_pe.sv file for more details.
  //
  // In this example, we only use a single MAC PE hence it is a simple design.
  // However, you can expand this part to support multiple PEs
  // by adjusting the data widths and input/output connections accordingly.
  //
  // Systemverilog has a useful mechanism to generate multiple instances
  // using generate-for loops.
  // Below is an example of a 2D generate-for loop to create a grid of PEs.
  //
  // ----------- BEGIN CODE EXAMPLE -----------
  // genvar m, k, n;
  //
  //   for (m = 0; m < M; m++) begin : gem_mac_pe_m
  //     for (n = 0; n < N; n++) begin : gem_mac_pe_n
  //         mac_module #(
  //           < insert parameters >
  //         ) i_mac_pe (
  //           < insert port connections >
  //         );
  //     end
  //   end
  // ----------- END CODE EXAMPLE -----------
  // 
  // There are many guides on the internet (or even ChatGPT) about generate-for loops.
  // We will give it as an exercise to you to modify this part to support multiple MAC PEs.
  // 
  // When dealing with multiple PEs, be careful with the connection alignment
  // across different PEs as it can be tricky to debug later on.
  // Plan this very carefully, especially when dealing with the correct data ports
  // data widths, slicing, valid signals, and so much more.
  //
  // Additionally, this MAC PE is already output stationary.
  // You have the freedom to change the dataflow as you see fit.
  //---------------------------

  // The MAC PE instantiation and data path logics
  
  for (m = 0; m < RowPar; m++) begin : gem_mac_pe_m
    for (n = 0; n < ColPar; n++) begin : gem_mac_pe_n
        general_mac_pe #(
              .InDataWidth  ( InDataWidth            ),
              .NumInputs    ( 1                      ),
              .OutDataWidth ( OutDataWidth           )
              ) i_mac_pe (
              .clk_i        ( clk_i                  ),
              .rst_ni       ( rst_ni                 ),
              .a_i          ( sram_a_rdata_i[m]      ),
              .b_i          ( sram_b_rdata_i[n]      ),
              .a_valid_i    ( valid_data             ),
              .b_valid_i    ( valid_data             ),
              .init_save_i  ( sram_c_we_o || start_i ),
              .acc_clr_i    ( !busy                  ),
              .c_o          ( sram_c_wdata_o[m][n]   )
            );
    end
  end
  

endmodule
