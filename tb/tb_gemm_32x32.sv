`timescale 1ns/1ps

module tb_gemm_32x32;

  // ==========================================================
  // PARAMETERS
  // ==========================================================
  parameter int RowPar        = 4;
  parameter int ColPar        = 16;

  parameter int InDataWidth   = 8;
  parameter int InDataWidth_a = 32;   // 4×8-bit
  parameter int InDataWidth_b = 128;  // 16×8-bit
  parameter int OutDataWidth  = 32;

  parameter int M_SIZE        = 32;
  parameter int K_SIZE        = 32;
  parameter int N_SIZE        = 32;

  parameter int DataDepth     = 4096;
  parameter int AddrWidth     = $clog2(DataDepth);
  parameter int SizeAddrWidth = 32;

  localparam int M_TILES = M_SIZE / RowPar;      // 8
  localparam int N_TILES = N_SIZE / ColPar;      // 2
  localparam int TOTAL_TILES = M_TILES * N_TILES;// 16

  localparam int TileSize       = RowPar * ColPar;   // 64
  localparam int PackedOutWidth = TileSize * OutDataWidth; // 2048


  // ==========================================================
  // DUT SIGNALS
  // ==========================================================
  logic clk_i;
  logic rst_ni;
  logic start;
  logic done;

  logic [SizeAddrWidth-1:0] M_i, K_i, N_i;

  logic [AddrWidth-1:0] sram_a_addr;
  logic [AddrWidth-1:0] sram_b_addr;
  logic [AddrWidth-1:0] sram_c_addr;

  logic signed [InDataWidth_a-1:0]  sram_a_rdata;
  logic signed [InDataWidth_b-1:0]  sram_b_rdata;
  logic signed [PackedOutWidth-1:0] sram_c_wdata;
  logic                             sram_c_we;

  logic signed [OutDataWidth-1:0] G_output [TOTAL_TILES*TileSize];


  // ==========================================================
  // MEMORY MODULES
  // ==========================================================
  single_port_memory #(
    .DataWidth(InDataWidth_a),
    .DataDepth(DataDepth),
    .AddrWidth(AddrWidth)
  ) i_sram_a (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .mem_addr_i(sram_a_addr),
    .mem_we_i(1'b0),
    .mem_wr_data_i('0),
    .mem_rd_data_o(sram_a_rdata)
  );

  single_port_memory #(
    .DataWidth(InDataWidth_b),
    .DataDepth(DataDepth),
    .AddrWidth(AddrWidth)
  ) i_sram_b (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .mem_addr_i(sram_b_addr),
    .mem_we_i(1'b0),
    .mem_wr_data_i('0),
    .mem_rd_data_o(sram_b_rdata)
  );

  single_port_memory #(
    .DataWidth(PackedOutWidth),
    .DataDepth(DataDepth),
    .AddrWidth(AddrWidth)
  ) i_sram_c (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .mem_addr_i(sram_c_addr),
    .mem_we_i(sram_c_we),
    .mem_wr_data_i(sram_c_wdata),
    .mem_rd_data_o()
  );


  // ==========================================================
  // DUT
  // ==========================================================
  gemm_accelerator_top #(
    .InDataWidth(InDataWidth),
    .InDataWidth_a(InDataWidth_a),
    .InDataWidth_b(InDataWidth_b),
    .OutDataWidth(OutDataWidth),
    .AddrWidth(AddrWidth),
    .SizeAddrWidth(SizeAddrWidth),
    .RowPar(RowPar),
    .ColPar(ColPar)
  ) i_dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(start),
    .M_size_i(M_i),
    .K_size_i(K_i),
    .N_size_i(N_i),
    .sram_a_addr_o(sram_a_addr),
    .sram_b_addr_o(sram_b_addr),
    .sram_c_addr_o(sram_c_addr),
    .sram_a_rdata_i(sram_a_rdata),
    .sram_b_rdata_i(sram_b_rdata),
    .sram_c_wdata_o(sram_c_wdata),
    .sram_c_we_o(sram_c_we),
    .done_o(done)
  );


  // ==========================================================
  // CLOCK
  // ==========================================================
  initial begin
    clk_i = 0;
    forever #5 clk_i = ~clk_i;
  end


  // ==========================================================
  // TASKS
  // ==========================================================
  task automatic clk_delay(int n);
    repeat (n) @(posedge clk_i);
  endtask

  task automatic start_and_wait();
    int cycles;
    cycles = 0;

    @(posedge clk_i);
    start <= 1;
    @(posedge clk_i);
    start <= 0;

    while (!done) begin
      @(posedge clk_i);
      cycles++;
      if (cycles > 200000) begin
        $display("TIMEOUT");
        $fatal;
      end
    end

    @(posedge clk_i);
    $display("DONE after %0d cycles", cycles);
  endtask


  // ==========================================================
  // GOLDEN MODEL (ModelSim-Legal)
  // ==========================================================
  function automatic void compute_golden();
    // -------- ALL DECLARATIONS FIRST --------
    int tile_m, tile_n;
    int q, l, k;
    int global_m, global_n;
    int a_tile_row, a_offset;
    int b_block, b_offset;
    int addr_a, addr_b;
    int tile_index;
    longint acc;
    logic signed [7:0] a_elem;
    logic signed [7:0] b_elem;

    // -------- NOW STATEMENTS --------
    for (tile_m = 0; tile_m < M_TILES; tile_m++) begin
      for (tile_n = 0; tile_n < N_TILES; tile_n++) begin

        tile_index = tile_m * N_TILES + tile_n;

        for (q = 0; q < RowPar; q++) begin
          for (l = 0; l < ColPar; l++) begin

            global_m = tile_m*RowPar + q;
            global_n = tile_n*ColPar + l;
            acc = 0;

            for (k = 0; k < K_SIZE; k++) begin
              // A access
              a_tile_row = global_m / RowPar;
              a_offset   = global_m % RowPar;
              addr_a     = a_tile_row*K_SIZE + k;
              a_elem     = i_sram_a.memory[addr_a][a_offset*8 +: 8];

              // B access
              b_block    = global_n / ColPar;
              b_offset   = global_n % ColPar;
              addr_b     = b_block*K_SIZE + k;
              b_elem     = i_sram_b.memory[addr_b][b_offset*8 +: 8];

              acc += a_elem * b_elem;
            end

            G_output[tile_index*TileSize + (q*ColPar + l)] = acc;
          end
        end

      end
    end
  endfunction


  // ==========================================================
  // TILE VERIFICATION (ModelSim-Legal)
  // ==========================================================
  task automatic verify_tiles();
  // ---------- DECLARATIONS ----------
  int t, i;
  logic signed [PackedOutWidth-1:0] packed_tile;
  logic signed [OutDataWidth-1:0] actual;
  logic signed [OutDataWidth-1:0] golden;

  // ---------- STATEMENTS ----------
  $display("\n================ TILE VERIFICATION ================");

  for (t = 0; t < TOTAL_TILES; t++) begin
    $display("\n--- TILE %0d ---", t);

    packed_tile = i_sram_c.memory[t];

    for (i = 0; i < TileSize; i++) begin
      actual = packed_tile[i*OutDataWidth +: OutDataWidth];
      golden = G_output[t*TileSize + i];

      // PRINT BOTH VALUES
      $display(
        " tile %0d elem %0d : DUT = %0d (0x%h)   GOLDEN = %0d (0x%h)",
         t, i, actual, actual, golden, golden
      );

      // ERROR CHECK
      if (actual !== golden) begin
        $display(" MISMATCH at tile=%0d elem=%0d", t, i);
        $fatal;
      end
    end

    $display("Tile %0d OK\n", t);
    end

    $display("ALL TILES MATCH!");
    $display("===================================================\n");
    endtask


  // ==========================================================
  // MAIN TEST
  // ==========================================================
  initial begin
    // -------- DECLARATIONS FIRST --------
    logic [InDataWidth_a-1:0] word_a;
    logic [InDataWidth_b-1:0] word_b;
    int tile_row, block, k, q, l;
    int addr_a, addr_b;

    start  = 0;
    rst_ni = 0;

    clk_delay(10);
    rst_ni = 1;

    M_i = M_SIZE;
    K_i = K_SIZE;
    N_i = N_SIZE;

    // --------------------------------------------------------
    // INIT A MEMORY (32×32, row-tiled)
    // --------------------------------------------------------
    for (tile_row = 0; tile_row < M_TILES; tile_row++) begin
      for (k = 0; k < K_SIZE; k++) begin
        addr_a = tile_row*K_SIZE + k;

        for (q = 0; q < RowPar; q++)
          word_a[q*8 +: 8] = $urandom();

        i_sram_a.memory[addr_a] = word_a;
      end
    end

    // --------------------------------------------------------
    // INIT B MEMORY (32×32, col-tiled)
    // --------------------------------------------------------
    for (block = 0; block < N_TILES; block++) begin
      for (k = 0; k < K_SIZE; k++) begin
        addr_b = block*K_SIZE + k;

        for (l = 0; l < ColPar; l++)
          word_b[l*8 +: 8] = $urandom();

        i_sram_b.memory[addr_b] = word_b;
      end
    end

    // --------------------------------------------------------
    // GOLDEN MODEL
    // --------------------------------------------------------
    compute_golden();

    // --------------------------------------------------------
    // RUN DUT
    // --------------------------------------------------------
    clk_delay(2);
    start_and_wait();

    // --------------------------------------------------------
    // VERIFY OUTPUT
    // --------------------------------------------------------
    verify_tiles();

    $display("===== 32×32 GEMM TEST PASSED =====");
    $finish;
  end

endmodule

