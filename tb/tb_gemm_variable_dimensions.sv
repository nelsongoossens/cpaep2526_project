`timescale 1ns/1ps

module tb_gemm_variable_dimensions;

  // ================================================================
  // PARAMETERS
  // ================================================================
  parameter int InDataWidth    = 8;
  parameter int RowPar         = 4;
  parameter int ColPar         = 16;

  parameter int InDataWidth_a  = RowPar * InDataWidth;     // 32 bits
  parameter int InDataWidth_b  = ColPar  * InDataWidth;    // 128 bits
  parameter int OutDataWidth   = 32;

  parameter int DataDepth      = 4096;
  parameter int AddrWidth      = (DataDepth <= 1) ? 1 : $clog2(DataDepth);
  parameter int SizeAddrWidth  = 32;

  localparam int TileSize       = RowPar * ColPar;         // 64
  localparam int PackedOutWidth = TileSize * OutDataWidth; // 2048 bits



  // ================================================================
  // DUT SIGNALS
  // ================================================================
  logic clk_i;
  logic rst_ni;
  logic start_i;
  logic done_o;

  logic [SizeAddrWidth-1:0] M_i;
  logic [SizeAddrWidth-1:0] K_i;
  logic [SizeAddrWidth-1:0] N_i;

  logic [AddrWidth-1:0] sram_a_addr_o;
  logic [AddrWidth-1:0] sram_b_addr_o;
  logic [AddrWidth-1:0] sram_c_addr_o;

  logic signed [InDataWidth_a-1:0]  sram_a_rdata_i;
  logic signed [InDataWidth_b-1:0]  sram_b_rdata_i;
  logic signed [PackedOutWidth-1:0] sram_c_wdata_o;

  logic sram_c_we_o;



  // ================================================================
  // INTERNAL TB STORAGE
  // ================================================================
  logic signed [OutDataWidth-1:0] C_scalar        [DataDepth];
  logic signed [OutDataWidth-1:0] golden_results  [DataDepth];

  int M_tiles;
  int N_tiles;
  int Total_tiles;



  // ================================================================
  // MEMORY MODELS
  // ================================================================
  single_port_memory #(
    .DataWidth(InDataWidth_a),
    .DataDepth(DataDepth),
    .AddrWidth(AddrWidth)
  ) memA (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .mem_addr_i(sram_a_addr_o),
    .mem_we_i(1'b0),
    .mem_wr_data_i('0),
    .mem_rd_data_o(sram_a_rdata_i)
  );

  single_port_memory #(
    .DataWidth(InDataWidth_b),
    .DataDepth(DataDepth),
    .AddrWidth(AddrWidth)
  ) memB (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .mem_addr_i(sram_b_addr_o),
    .mem_we_i(1'b0),
    .mem_wr_data_i('0),
    .mem_rd_data_o(sram_b_rdata_i)
  );

  single_port_memory #(
    .DataWidth(PackedOutWidth),
    .DataDepth(DataDepth),
    .AddrWidth(AddrWidth)
  ) memC (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .mem_addr_i(sram_c_addr_o),
    .mem_we_i(sram_c_we_o),
    .mem_wr_data_i(sram_c_wdata_o),
    .mem_rd_data_o()
  );



  // ================================================================
  // DUT
  // ================================================================
  gemm_accelerator_top #(
    .InDataWidth(InDataWidth),
    .InDataWidth_a(InDataWidth_a),
    .InDataWidth_b(InDataWidth_b),
    .OutDataWidth(OutDataWidth),
    .AddrWidth(AddrWidth),
    .SizeAddrWidth(SizeAddrWidth),
    .RowPar(RowPar),
    .ColPar(ColPar)
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



  // ================================================================
  // CLOCK GENERATION
  // ================================================================
  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic clk_delay(input int n);
    int i;
    begin
      for (i = 0; i < n; i++) begin
        @(posedge clk_i);
      end
    end
  endtask



  // ================================================================
  // START AND WAIT TASK
  // ================================================================
  task automatic start_and_wait();
    int cycles;
    begin
      cycles = 0;

      @(posedge clk_i);
      start_i = 1'b1;

      @(posedge clk_i);
      start_i = 1'b0;

      while (!done_o) begin
        @(posedge clk_i);
        cycles++;
        if (cycles > 200000) begin
          $display("ERROR: TIMEOUT waiting for done_o");
          $fatal;
        end
      end

      @(posedge clk_i);
      $display("DONE in %0d cycles", cycles);
    end
  endtask



  // ================================================================
  // MEMORY INITIALIZATION A
  // ================================================================
  task automatic init_mem_A();
    int rb;
    int k;
    int q;
    int addr;
    logic [InDataWidth_a-1:0] wordA;
    begin
      for (rb = 0; rb < M_tiles; rb++) begin
        for (k = 0; k < K_i; k++) begin
          addr = rb*K_i + k;
          wordA = '0;
          for (q = 0; q < RowPar; q++) begin
            if (rb*RowPar + q < M_i)
              //wordA[q*InDataWidth +: InDataWidth] = $urandom_range(0,255);
              wordA[q*InDataWidth +: InDataWidth] = $urandom() % (2 ** InDataWidth);
            else
              wordA[q*InDataWidth +: InDataWidth] = 0;
          end
          memA.memory[addr] = wordA;
        end
      end
    end
  endtask



  // ================================================================
  // MEMORY INITIALIZATION B
  // ================================================================
  task automatic init_mem_B();
    int cb;
    int k;
    int l;
    int addr;
    logic [InDataWidth_b-1:0] wordB;
    begin
      for (cb = 0; cb < N_tiles; cb++) begin
        for (k = 0; k < K_i; k++) begin
          addr = cb*K_i + k;
          wordB = '0;
          for (l = 0; l < ColPar; l++) begin
            if (cb*ColPar + l < N_i)
              // wordB[l*InDataWidth +: InDataWidth] = $urandom_range(0,255);
              wordB[l*InDataWidth +: InDataWidth] = $urandom() % (2 ** InDataWidth);
            else
              wordB[l*InDataWidth +: InDataWidth] = 0;
          end
          memB.memory[addr] = wordB;
        end
      end
    end
  endtask



  // ================================================================
  // GOLDEN MODEL
  // ================================================================
  task automatic compute_golden();
    int i;
    int m;
    int n;
    int k;
    int rb;
    int off_m;
    int cb;
    int off_n;
    int gm;
    int gn;
    int tile_m;
    int tile_n;
    int q;
    int l;
    int tile_index;

    int addrA;
    int addrB;
    logic signed [InDataWidth-1:0] a_val;
    logic signed [InDataWidth-1:0] b_val;

    longint acc;

    begin
      for (i = 0; i < DataDepth; i++) begin
        C_scalar[i]       = 0;
        golden_results[i] = 0;
      end

      for (m = 0; m < M_i; m++) begin
        for (n = 0; n < N_i; n++) begin
          acc = 0;

          rb    = m / RowPar;
          off_m = m % RowPar;
          cb    = n / ColPar;
          off_n = n % ColPar;

          for (k = 0; k < K_i; k++) begin
            addrA = rb*K_i + k;
            addrB = cb*K_i + k;

            a_val = memA.memory[addrA][off_m*InDataWidth +: InDataWidth];
            b_val = memB.memory[addrB][off_n*InDataWidth +: InDataWidth];

            acc += $signed(a_val) * $signed(b_val);
          end

          C_scalar[m*N_i + n] = acc;
        end
      end

      for (tile_m = 0; tile_m < M_tiles; tile_m++) begin
        for (tile_n = 0; tile_n < N_tiles; tile_n++) begin

          tile_index = tile_m*N_tiles + tile_n;

          for (q = 0; q < RowPar; q++) begin
            for (l = 0; l < ColPar; l++) begin
              gm = tile_m*RowPar + q;
              gn = tile_n*ColPar + l;
              if (gm < M_i && gn < N_i)
                golden_results[tile_index*TileSize + (q*ColPar + l)] =
                  C_scalar[gm*N_i + gn];
            end
          end

        end
      end
    end
  endtask



  // ================================================================
  // VERIFY TILES
  // ================================================================

	task automatic verify_tiles();
	  int t;
	  int i;
	  logic signed [PackedOutWidth-1:0] data;
	  logic signed [OutDataWidth-1:0] actual;
	  logic signed [OutDataWidth-1:0] golden;

	  begin
	    $display("Verifying %0d tiles...", Total_tiles);

	    for (t = 0; t < Total_tiles; t++) begin
	      data = memC.memory[t];

	      $display("\n-----------------------------------------------");
	      $display(" TILE %0d", t);
	      $display("-----------------------------------------------");

	      for (i = 0; i < TileSize; i++) begin
		      actual = data[i*OutDataWidth +: OutDataWidth];
		      golden = golden_results[t*TileSize + i];

		      // if (actual === golden) begin
		      //   $display("  Tile %0d Elem %0d : OK     | actual = %0d (0x%h) | golden = %0d (0x%h)",
		      //       t, i, actual, actual, golden, golden);
		      // end
		      // else begin
		      //   $display("  Tile %0d Elem %0d : MISMATCH!", t, i);
		      //   $display("       actual = %0d (0x%h)", actual, actual);
		      //   $display("       golden = %0d (0x%h)", golden, golden);
		      //   $fatal;   // stop immediately on mismatch
		      // end
          if (actual !== golden) begin
            $display("  Tile %0d Elem %0d : MISMATCH!", t, i);
		        $display("       actual = %0d (0x%h)", actual, actual);
		        $display("       golden = %0d (0x%h)", golden, golden);
		        $fatal;   // stop immediately on mismatch
          end
	      end

	      $display("Tile %0d verification COMPLETE — all elements match.\n", t);
	    end

	    $display("ALL tiles verified OK.");
	  end
	endtask


  // ================================================================
  // MAIN TEST SEQUENCE — TWO TESTS
  // ================================================================
  initial begin

    clk_i   = 0;
    rst_ni  = 0;
    start_i = 0;

    clk_delay(5);
    rst_ni = 1;

    // ------------------------------------------------------------
    // TEST 1: 32×32 multiply 32×32
    // ------------------------------------------------------------

//    $display("\n========== TEST 1: 32×32 ==========\n");
//
  //  M_i = 32;
  //  K_i = 32;
  //  N_i = 32;
//
  //  M_tiles     = (M_i + RowPar - 1) / RowPar;   // 8
  //  N_tiles     = (N_i + ColPar - 1) / ColPar;   // 2
  //  Total_tiles = M_tiles * N_tiles;             // 16
//
  //  init_mem_A();
  //  init_mem_B();
  //  compute_golden();
  ////  clk_delay(2);
  //  start_and_wait();
  //  verify_tiles();


  //  $display("TEST 1 PASSED.\n");


    // ------------------------------------------------------------
    // TEST 2: 4×64 multiply 64×16 (one tile)
    // ------------------------------------------------------------

  //  $display("\n========== TEST 2: 4×64 × 64×16 ==========\n");


  //  M_i = 4;
  //  K_i = 64;
  //  N_i = 16;

  //  M_tiles     = (M_i + RowPar - 1) / RowPar;   // 1
  //  N_tiles     = (N_i + ColPar - 1) / ColPar;   // 1
  //  Total_tiles = M_tiles * N_tiles;

//    init_mem_A();
  //  init_mem_B();
  //  compute_golden();
  //  clk_delay(2);
  //  start_and_wait();
  //  verify_tiles();

  //  $display("TEST 2 PASSED.\n");
    
    
    // ------------------------------------------------------------
    // TEST 3: 8×16 multiply 16×32 (4 tiles)
    // ------------------------------------------------------------
  //  $display("\n========== TEST 3: 8×16 × 16×32 ==========\n");

  //  M_i = 8;
  //  K_i = 16;
  //  N_i = 32;

  //  M_tiles     = (M_i + RowPar - 1) / RowPar;   //2 
  //  N_tiles     = (N_i + ColPar - 1) / ColPar;   //2 
  //  Total_tiles = M_tiles * N_tiles; //4

  //  init_mem_A();
  //  init_mem_B();
  //  compute_golden();
  //  clk_delay(2);
  //  start_and_wait();
  //  verify_tiles();

  //  $display("TEST 3 PASSED.\n");
    
    // ------------------------------------------------------------
    // TEST 4: 5×64 multiply 64×16 (two tiles)
    // ------------------------------------------------------------
    $display("\n========== TEST 4: 5×64 × 64×16 ==========\n");

    M_i = 5;
    K_i = 64;
    N_i = 16;

    M_tiles     = (M_i + RowPar - 1) / RowPar;   //2
    N_tiles     = (N_i + ColPar - 1) / ColPar;   //1
    Total_tiles = M_tiles * N_tiles; //2

    init_mem_A();
    init_mem_B();
    compute_golden();
    clk_delay(2);
    start_and_wait();
    verify_tiles();

    $display("TEST 4 PASSED.\n");
    
    
    // ------------------------------------------------------------
    // TEST 5: 4×30 multiply 30×10 (one tile)
    // ------------------------------------------------------------
    $display("\n========== TEST 5: 4×30 × 30×10 ==========\n");

    M_i = 4;
    K_i = 30;
    N_i = 10;

    M_tiles     = (M_i + RowPar - 1) / RowPar;   //1
    N_tiles     = (N_i + ColPar - 1) / ColPar;   //1
    Total_tiles = M_tiles * N_tiles; //1

    init_mem_A();
    init_mem_B();
    compute_golden();
    clk_delay(2);
    start_and_wait();
    verify_tiles();

    $display("TEST 5 PASSED.\n");
    
    
    
    
    
    
    
    

    // ------------------------------------------------------------
    // TEST 3: 16×64 multiply 64×4 (one tile)
    // Put transposed A in sram_B, put transposed B in sram_A --> answer is transposed C in sram_C
    // ------------------------------------------------------------
    $display("\n========== TEST 3: 16X64 X 64X4 - Case 2 ==========\n");

    M_i = 4;
    K_i = 64;
    N_i = 16;

    M_tiles     = (M_i + RowPar - 1) / RowPar;   // 1
    N_tiles     = (N_i + ColPar - 1) / ColPar;   // 1
    Total_tiles = 1;

    init_mem_A();
    init_mem_B();
    compute_golden();
    clk_delay(2);
    start_and_wait();
    verify_tiles();

    $display("TEST 3 PASSED.\n");    

    $display("====================================");
    $display("           ALL TESTS PASSED");
    $display("====================================");

    $finish;
  end

endmodule

