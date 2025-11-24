// The controller for GeMM operation
module gemm_controller #(
    parameter int unsigned AddrWidth = 16
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic start_i,
    input  logic input_valid_i,
    output logic result_valid_o,
    output logic busy_o,
    output logic done_o,

    // The current M, K, N sizes
    input  logic [AddrWidth-1:0] M_size_i,
    input  logic [AddrWidth-1:0] K_size_i,
    input  logic [AddrWidth-1:0] N_size_i,

    output logic [AddrWidth-1:0] M_count_o,
    output logic [AddrWidth-1:0] K_count_o,
    output logic [AddrWidth-1:0] N_count_o
);

  //-----------------------
  // Wires and logic
  //-----------------------
  // 
  logic move_K_counter;
  logic move_N_counter;
  logic move_M_counter;
  logic move_counter;
  assign move_K_counter = move_counter;

  logic clear_counters;
  logic last_counter_last_value;

  // State machine states
  typedef enum logic [1:0] {
    ControllerIdle,
    ControllerBusy,
    ControllerFinish
  } controller_state_t;

  controller_state_t current_state, next_state;

  assign busy_o = (current_state == ControllerBusy) || (current_state == ControllerFinish);

  //-----------------------
  // Counters for M, K, N
  //-----------------------

  // K Counter
  ceiling_counter #(
      .Width        (      AddrWidth ),
      .HasCeiling   (              1 )
  ) i_K_counter (
      .clk_i        ( clk_i          ),
      .rst_ni       ( rst_ni         ),
      .tick_i       ( move_K_counter ),
      .clear_i      ( clear_counters ),
      .ceiling_i    ( K_size_i       ),
      .count_o      ( K_count_o      ),
      .last_value_o ( move_N_counter )
  );

  // N Counter
  ceiling_counter #(
      .Width        (      AddrWidth ),
      .HasCeiling   (              1 )
  ) i_N_counter (
      .clk_i        ( clk_i          ),
      .rst_ni       ( rst_ni         ),
      .tick_i       ( move_N_counter ),
      .clear_i      ( clear_counters ),
      .ceiling_i    ( N_size_i       ),
      .count_o      ( N_count_o      ),
      .last_value_o ( move_M_counter )
  );

  // M Counter
  ceiling_counter #(
      .Width        (               AddrWidth ),
      .HasCeiling   (                       1 )
  ) i_M_counter (
      .clk_i        ( clk_i                   ),
      .rst_ni       ( rst_ni                  ),
      .tick_i       ( move_M_counter          ),
      .clear_i      ( clear_counters          ),
      .ceiling_i    ( M_size_i                ),
      .count_o      ( M_count_o               ),
      .last_value_o ( last_counter_last_value )
  );

  //-----------------------
  // Main controller state machine
  //-----------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      current_state <= ControllerIdle;
    end else begin
      current_state <= next_state;
    end
  end

  always_comb begin
    // Default assignments
    next_state     = current_state;
    clear_counters = 1'b0;
    move_counter   = 1'b0;
    result_valid_o = 1'b0;
    done_o         = 1'b0;

    case (current_state)
      ControllerIdle: begin
        if (start_i) begin
          move_counter = input_valid_i;
          next_state   = ControllerBusy;
        end
      end

      ControllerBusy: begin
        move_counter = input_valid_i;
        // Check if we are done
        if (last_counter_last_value) begin
          next_state = ControllerFinish;
        end else if (input_valid_i
                     && K_count_o == '0 
                     && (M_count_o != '0 || N_count_o != '0)) begin
          // Check when result_valid_o should be asserted
          result_valid_o = 1'b1;
        end
      end

      ControllerFinish: begin
        done_o         = 1'b1;
        result_valid_o = 1'b1;
        clear_counters = 1'b1;
        next_state     = ControllerIdle;
      end

      default: begin
        next_state = ControllerIdle;
      end
    endcase
  end
endmodule
