`timescale 1ns/1ps

module tb_gemm_variable_dimensions;

  // ==========================================================
  // PARAMETERS
  // ==========================================================
  parameter int InDataWidth    = 8;
  parameter int RowPar         = 4;
  parameter int ColPar         = 16;

  parameter int InDataWidth_a  = RowPar * InDataWidth;   // 32 bits
  parameter int InDataWidth_b  = ColPar * InDataWidth;   // 128 bits
  parameter int OutDataWidth   = 32;

  parameter int DataDepth      = 4096;
  parameter int AddrWidth      = $clog2(DataDepth);
  parameter int SizeAddrWidth  = 32;

  localparam int TileSize       = RowPar * ColPar;            // 64
  localparam int PackedOutWidth = TileSize * OutDataWidth;    // 2048


  // ==========================================================
  // DUT SIGNALS
  // ==========================================================
  logic clk_i;
  logic rst_ni;
  logic start_i;
  logic done_o;

  logic [SizeAddrWidth-1:0] M_i, K_i, N_i;

  logic [AddrWidth-1:0] sram_a_addr_o;
  logic [AddrWidth-1:0] sram_b_addr_o;
  logic [AddrWidth-1:0] sram_c_addr_o;

  logic signed [InDataWidth_a-1:0]  sram_a_rdata_i;
  logic signed [InDataWidth_b-1:0]  sram_b_rdata_i;
  logic signed [PackedOutWidth-1:0] sram_c_wdata_o;
  logic                             sram_c_we_o;


  // ==========================================================
  // INTERNAL TB STORAGE
  // ==========================================================
  logic signed [OutDataWidth-1:0] golden_results [DataDepth];

  int M_tiles;
  int N_tiles;
  int Total_tiles;


  // ==========================================================
  // MEMORY MODELS
  // ==========================================================
  single_port_memory #(
    .DataWidth (InDataWidth_a),
    .DataDepth (DataDepth),
    .AddrWidth (AddrWidth)
  ) memA (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .mem_addr_i(sram_a_addr_o),
    .mem_we_i(1'b0),
    .mem_wr_data_i('0),
    .mem_rd_data_o(sram_a_rdata_i)
  );

  single_port_memory #(
    .DataWidth (InDataWidth_b),
    .DataDepth (DataDepth),
    .AddrWidth (AddrWidth)
  ) memB (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .mem_addr_i(sram_b_addr_o),
    .mem_we_i(1'b0),
    .mem_wr_data_i('0),
    .mem_rd_data_o(sram_b_rdata_i)
  );

  single_port_memory #(
    .DataWidth (PackedOutWidth),
    .DataDepth (DataDepth),
    .AddrWidth (AddrWidth)
  ) memC (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .mem_addr_i(sram_c_addr_o),
    .mem_we_i(sram_c_we_o),
    .mem_wr_data_i(sram_c_wdata_o),
    .mem_rd_data_o()
  );


  // ==========================================================
  // DUT
  // ==========================================================
  gemm_accelerator_top #(
    .InDataWidth   (InDataWidth),
    .InDataWidth_a (InDataWidth_a),
    .InDataWidth_b (InDataWidth_b),
    .OutDataWidth  (OutDataWidth),
    .AddrWidth     (AddrWidth),
    .SizeAddrWidth (SizeAddrWidth),
    .RowPar        (RowPar),
    .ColPar        (ColPar)
  ) dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(start_i),
    .M_size_i(M_i),
    .K_size_i(K_i),
    .N_size_i(N_i),
    .sram_a_addr_o(sram_a_addr_o),
    .sram_b_addr_o(sram_b_addr_o),
    .sram_c_addr_o(sram_c_addr_o),
    .sram_a_rdata_i(sram_a_rdata_i),
    .sram_b_rdata_i(sram_b_rdata_i),
    .sram_c_wdata_o(sram_c_wdata_o),
    .sram_c_we_o(sram_c_we_o),
    .done_o(done_o)
  );


  // ==========================================================
  // CLOCK
  // ==========================================================
  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic clk_delay(int n);
    repeat(n) @(posedge clk_i);
  endtask


  // ==========================================================
  // START + WAIT
  // ==========================================================
  task automatic start_and_wait();
    int cycles;
    cycles = 0;

    @(posedge clk_i);
    start_i <= 1;
    @(posedge clk_i);
    start_i <= 0;

    while (!done_o) begin
      @(posedge clk_i);
      cycles++;
      if (cycles > 200000) begin
        $display("ERROR: Timeout waiting for done_o");
        $fatal;
      end
    end

    @(posedge clk_i);
    $display("DONE in %0d cycles", cycles);
  endtask


  // ==========================================================
  // MEMORY INITIALIZATION FOR A & B
  // ==========================================================
  task automatic init_mem_A();
    int tile_row, k, q, addr;
    logic [InDataWidth_a-1:0] word_a;

    for (tile_row = 0; tile_row < M_tiles; tile_row++) begin
      for (k = 0; k < K_i; k++) begin
        addr = tile_row*K_i + k;
        for (q = 0; q < RowPar; q++) begin
          if (tile_row*RowPar + q < M_i)
            word_a[q*InDataWidth +: InDataWidth] = $urandom();
          else
            word_a[q*InDataWidth +: InDataWidth] = 0;
        end
        memA.memory[addr] = word_a;
      end
    end
  endtask


  task automatic init_mem_B();
    int tile_col, k, l, addr;
    logic [InDataWidth_b-1:0] word_b;

    for (tile_col = 0; tile_col < N_tiles; tile_col++) begin
      for (k = 0; k < K_i; k++) begin
        addr = tile_col*K_i + k;
        for (l = 0; l < ColPar; l++) begin
          if (tile_col*ColPar + l < N_i)
            word_b[l*InDataWidth +: InDataWidth] = $urandom();
          else
            word_b[l*InDataWidth +: InDataWidth] = 0;
        end
        memB.memory[addr] = word_b;
      end
    end
  endtask


  // ==========================================================
  // GOLDEN MODEL
  // ==========================================================
  task automatic compute_golden();
    int tile_m, tile_n, q, l, k;
    int global_m, global_n;
    int tile_index;
    int addrA, addrB;
    int a_val, b_val;
    longint acc;

    for (int i = 0; i < DataDepth; i++)
      golden_results[i] = 0;

    for (tile_m = 0; tile_m < M_tiles; tile_m++) begin
      for (tile_n = 0; tile_n < N_tiles; tile_n++) begin

        tile_index = tile_m * N_tiles + tile_n;

        for (q = 0; q < RowPar; q++) begin
          for (l = 0; l < ColPar; l++) begin

            global_m = tile_m*RowPar + q;
            global_n = tile_n*ColPar + l;

            if (global_m >= M_i || global_n >= N_i)
              continue;

            acc = 0;

            for (k = 0; k < K_i; k++) begin
              addrA = tile_m*K_i + k;
              addrB = tile_n*K_i + k;

              a_val = memA.memory[addrA][q*InDataWidth +: InDataWidth];
              b_val = memB.memory[addrB][l*InDataWidth +: InDataWidth];

              acc += $signed(a_val) * $signed(b_val);
            end

            golden_results[tile_index*TileSize + (q*ColPar + l)] = acc;
          end
        end

      end
    end
  endtask


  // ==========================================================
  // VERIFICATION
  // ==========================================================
  task automatic verify_tiles();
    int t, i;
    logic signed [PackedOutWidth-1:0] data;
    logic signed [OutDataWidth-1:0] actual, golden;

    $display("Checking %0d tiles ...", Total_tiles);

    for (t = 0; t < Total_tiles; t++) begin
      data = memC.memory[t];

      // RTL packs MSB ← temp_C[0][0]
      for (i = 0; i < TileSize; i++) begin
        actual = data[(TileSize-1-i)*OutDataWidth +: OutDataWidth];
        golden = golden_results[t*TileSize + i];
        if (actual !== golden) begin
          $display("ERROR: Tile %0d elem %0d mismatch", t, i);
          $display("  DUT   = %0d (0x%h)", actual, actual);
          $display("  GOLD  = %0d (0x%h)", golden, golden);
          $fatal;
        end
      end

      $display("Tile %0d OK", t);
    end

    $display("Verification complete.");
  endtask


  // ==========================================================
  // MAIN TEST SEQUENCE (TWO TESTS)
  // ==========================================================
  initial begin
    clk_i   = 0;
    rst_ni  = 0;
    start_i = 0;

    clk_delay(5);
    rst_ni = 1;

    // -------------------------------
    // TEST 1: 32 × 32 × 32 × 32
    // -------------------------------
    $display("\n========== TEST 1: 32x32 ==========\n");

    M_i = 32;
    K_i = 32;
    N_i = 32;

    M_tiles     = M_i / RowPar;    // 32/4 = 8
    N_tiles     = N_i / ColPar;    // 32/16 = 2
    Total_tiles = M_tiles * N_tiles; // 16

    init_mem_A();
    init_mem_B();
    compute_golden();
    clk_delay(2);
    start_and_wait();
    verify_tiles();

    $display("TEST 1 PASSED.\n");


    // -------------------------------
    // TEST 2: 4 × 64 × 64 × 16 (1 tile)
    // -------------------------------
    $display("\n========== TEST 2: 4x64 x 64x16 ==========\n");

    M_i = 4;
    K_i = 64;
    N_i = 16;

    M_tiles     = M_i / RowPar;     // 4/4 = 1
    N_tiles     = N_i / ColPar;     // 16/16 = 1
    Total_tiles = 1;

    init_mem_A();
    init_mem_B();
    compute_golden();
    clk_delay(2);
    start_and_wait();
    verify_tiles();

    $display("TEST 2 PASSED.\n");


    $display("\n===============================");
    $display("        ALL TESTS PASSED");
    $display("===============================\n");

    $finish;
  end

endmodule

