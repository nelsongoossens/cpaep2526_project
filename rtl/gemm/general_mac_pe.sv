//--------------------------
// Simple MAC processing element
// - Does a multiply and add
// - Accumulates the output if inputs are valid
//--------------------------

module general_mac_pe #(
  parameter int unsigned InDataWidth  = 8,
  parameter int unsigned NumInputs    = 4,
  parameter int unsigned OutDataWidth = 32
)(
  // Clock and reset
  input  logic clk_i,
  input  logic rst_ni,
  // Input operands
  input  logic signed [NumInputs-1:0][InDataWidth-1:0] a_i,
  input  logic signed [NumInputs-1:0][InDataWidth-1:0] b_i,
  // Valid signals for inputs
  input  logic a_valid_i,
  input  logic b_valid_i,
  input  logic init_save_i,
  // Clear signal for output
  input  logic acc_clr_i,
  // Output accumulation
  output logic signed [OutDataWidth-1:0] c_o
);

  // Wires and logic
  logic acc_valid;
  logic signed [OutDataWidth-1:0] mult_result;

  assign acc_valid = a_valid_i && b_valid_i;

  // Combined multiplication
  always_comb begin
    mult_result = '0;
    for (int i = 0; i < NumInputs; i++) begin
      mult_result += $signed(a_i[i]) * $signed(b_i[i]);
    end
  end

  // Accumulation unit
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      c_o <= '0;
    end else if (init_save_i) begin
      c_o <= mult_result;
    end else if (acc_valid) begin
      c_o <= c_o + mult_result;
    end else if (acc_clr_i) begin
      c_o <= '0;
    end else begin
      c_o <= c_o;
    end
  end

endmodule
