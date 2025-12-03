// FOR MULTIPLE TILES:
// function automatic void gemm_golden(
//     input logic [SizeAddrWidth-1:0] M,
//     input logic [SizeAddrWidth-1:0] K,
//     input logic [SizeAddrWidth-1:0] N,

//     input logic signed [Height-1:0][InDataWidth-1:0] A_i [DataDepth],
//     input logic signed [Length-1:0][InDataWidth-1:0] B_i [DataDepth],

//     output logic signed [64*OutDataWidth-1:0] Y_o [DataDepth]
// );

//     int m, n, k, q, l, addr_a, addr_b, addr_c;
//     longint acc;


//     for (m = 0; m < M/Height; m++) begin
//         for (n = 0; n < N/Length; n++) begin

//             for (q = 0; q < Height; q++) begin
//                 for (l = 0; l < Length; l++) begin
//                     acc = '0;
//                     for (k = 0; k < K; k++) begin
//                         addr_a = m * K + k;
//                         addr_b = n * K + k;
//                         acc += $signed(A_i[addr_a][q]) * $signed(B_i[addr_b][l]);
//                     end
//                     addr_c = n + m * (N/Length);
//                     Y_o[addr_c][(q*Length + l)*OutDataWidth +: OutDataWidth] = acc;
//                 end
//             end
//         end
//     end
// endfunction

//--------------------------
// Useful functions for testing, FOR ONE TILE
//--------------------------
function automatic void gemm_golden(
  input  logic [AddrWidth-1:0] M,
  input  logic [AddrWidth-1:0] K,
  input  logic [AddrWidth-1:0] N,
  input  logic signed [ InDataWidth_a-1:0] A_i [DataDepth],
  input  logic signed [ InDataWidth_b-1:0] B_i [DataDepth],
  output logic signed [ OG_OutDataWidth-1:0 ] Y_o [DataDepth]
);
  int unsigned m, n, k;
  logic signed [OG_OutDataWidth-1:0] acc;
  logic signed [InDataWidth-1:0] a_elem;
  logic signed [InDataWidth-1:0] b_elem;

  for (m = 0; m < M; m++) begin
    for (n = 0; n<N; n++) begin
      acc = '0;
      for (k = 0; k < K; k++) begin
        // unpack A[m][k] from A_i[k]
        a_elem = A_i[k][m*InDataWidth +: InDataWidth];
        // unpack B[k][n] from B_i[k]
        b_elem = B_i[k][n*InDataWidth +: InDataWidth];

        acc += a_elem * b_elem;
      end
      Y_o[m*N + n] = acc;
    end
  end
endfunction

// Case 2
function automatic void gemm_golden_2(
  input  logic [AddrWidth-1:0] P,
  input  logic [AddrWidth-1:0] K,
  input  logic [AddrWidth-1:0] Q,
  input  logic signed [ InDataWidth_a-1:0] A_i [DataDepth],
  input  logic signed [ InDataWidth_b-1:0] B_i [DataDepth],
  output logic signed [ OG_OutDataWidth-1:0 ] Y_o [DataDepth]
);
  int unsigned p,q,k;
  logic signed [OG_OutDataWidth-1:0] acc;
  logic signed [InDataWidth-1:0] a_elem;
  logic signed [InDataWidth-1:0] b_elem;
  logic signed [OG_OutDataWidth-1:0] C2 [0:15][0:3];

  for (p = 0; p < P; p++) begin
    for (q = 0; q<Q; q++) begin
      acc = '0;
      for (k = 0; k < K; k++) begin
        // unpack A[m][k] from A_i[k]
        a_elem = A_i[k][p*InDataWidth +: InDataWidth];
        // unpack B[k][n] from B_i[k]
        b_elem = B_i[k][q*InDataWidth +: InDataWidth];

        acc += a_elem * b_elem;
      end
      C2[p][q] = acc;
    end
  end

  for (int m = 0; m < 4; m++) begin
    for (int n = 0; n < 16; n++) begin
      Y_o[m*16 + n] = C2[n][m];
    end
  end
endfunction
