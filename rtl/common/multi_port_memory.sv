//-----------------------------
// Multi-Port Memory Module
//-----------------------------

module multi_port_memory #(
  parameter int unsigned DataWidth  = 8,
  parameter int unsigned NumPorts   = 4,
  parameter int unsigned DataDepth  = 4096,
  parameter int unsigned AddrWidth  = (DataDepth <= 1) ? 1 : $clog2(DataDepth)

)(
  input  logic clk_i,
  input  logic rst_ni,
  input  logic        [NumPorts-1:0][AddrWidth-1:0] mem_addr_i,
  input  logic        [NumPorts-1:0]                mem_we_i,
  input  logic signed [NumPorts-1:0][DataWidth-1:0] mem_wr_data_i,
  output logic signed [NumPorts-1:0][DataWidth-1:0] mem_rd_data_o
);

  // Memory array
  logic signed [ DataWidth-1:0] memory [DataDepth];

  // Memory read access
  always_comb begin
    for (int i = 0; i < NumPorts; i++) begin
      mem_rd_data_o[i] = memory[mem_addr_i[i]];
    end
  end

  // Memory write access
  always_ff @(posedge clk_i) begin
    for (int i = 0; i < NumPorts; i++) begin
      if (mem_we_i[i]) begin
        memory[mem_addr_i[i]] <= mem_wr_data_i[i];
      end
    end
  end
endmodule