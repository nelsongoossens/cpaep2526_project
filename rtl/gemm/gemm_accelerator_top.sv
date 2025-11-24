// The controller for GeMM operation
module gemm_accelerator_top #(
    parameter int unsigned InDataWidth = 8,
    parameter int unsigned OutDataWidth = 32,
    parameter int unsigned AddrWidth = 16,
    parameter int unsigned SizeAddrWidth = 8
) (
    input  logic                            clk_i,
    input  logic                            rst_ni,
    input  logic                            start_i,
    input  logic        [SizeAddrWidth-1:0] M_size_i,
    input  logic        [SizeAddrWidth-1:0] K_size_i,
    input  logic        [SizeAddrWidth-1:0] N_size_i,
    output logic        [    AddrWidth-1:0] sram_a_addr_o,
    output logic        [    AddrWidth-1:0] sram_b_addr_o,
    output logic        [    AddrWidth-1:0] sram_c_addr_o,
    input  logic signed [  InDataWidth-1:0] sram_a_rdata_i,
    input  logic signed [  InDataWidth-1:0] sram_b_rdata_i,
    output logic signed [ OutDataWidth-1:0] sram_c_wdata_o,
    output logic                            sram_c_we_o,
    output logic                            done_o
);

  logic [SizeAddrWidth-1:0] M_count;
  logic [SizeAddrWidth-1:0] K_count;
  logic [SizeAddrWidth-1:0] N_count;

  logic busy;
  logic valid_data;
  assign valid_data = start_i || busy;  // Always valid in this simple design

  gemm_controller #(
      .AddrWidth      ( SizeAddrWidth )
  ) i_gemm_controller (
      .clk_i          ( clk_i       ),
      .rst_ni         ( rst_ni      ),
      .start_i        ( start_i     ),
      .input_valid_i  ( 1'b1        ),  // Always valid in this simple design
      .result_valid_o ( sram_c_we_o ),
      .busy_o         ( busy        ),
      .done_o         ( done_o      ),
      .M_size_i       ( M_size_i    ),
      .K_size_i       ( K_size_i    ),
      .N_size_i       ( N_size_i    ),
      .M_count_o      ( M_count     ),
      .K_count_o      ( K_count     ),
      .N_count_o      ( N_count     )
  );

  // Address generation logic: Assume the matrices are stored in row-major order
  // Please adjust this part to align with your designed memory layout
  // The counters are used for the matrix A and matrix B address generation;
  // for matrix C, the corresponding address is calculated 
  // at the previous cycle, thus adding one cycle delay on c
  assign sram_a_addr_o = (M_count * K_size_i + K_count);
  assign sram_b_addr_o = (K_count * N_size_i + N_count);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sram_c_addr_o <= '0;
    end else if (1'b1) begin  // Always valid in this simple design
      sram_c_addr_o <= (M_count * N_size_i + N_count);
    end
  end

  // The MAC PE instantiation and data path logics
  general_mac_pe #(
    .InDataWidth  ( InDataWidth            ),
    .NumInputs    ( 1                      ),
    .OutDataWidth ( OutDataWidth           )
  ) i_mac_pe (
    .clk_i        ( clk_i                  ),
    .rst_ni       ( rst_ni                 ),
    .a_i          ( sram_a_rdata_i         ),
    .b_i          ( sram_b_rdata_i         ),
    .a_valid_i    ( valid_data             ),
    .b_valid_i    ( valid_data             ),
    .init_save_i  ( sram_c_we_o || start_i ),
    .acc_clr_i    ( !busy                  ),
    .c_o          ( sram_c_wdata_o         )
  );

endmodule
