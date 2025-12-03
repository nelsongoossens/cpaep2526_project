function automatic void gemm_golden(
    input logic [SizeAddrWidth-1:0] M,
    input logic [SizeAddrWidth-1:0] K,
    input logic [SizeAddrWidth-1:0] N,

    input logic signed [Height-1:0][InDataWidth-1:0] A_i [DataDepth],
    input logic signed [Length-1:0][InDataWidth-1:0] B_i [DataDepth],

    output logic signed [64*OutDataWidth-1:0] Y_o [DataDepth]
);

    int m, n, k, q, l, addr_a, addr_b, addr_c;
    longint acc;


    for (m = 0; m < M/Height; m++) begin
        for (n = 0; n < N/Length; n++) begin

            for (q = 0; q < Height; q++) begin
                for (l = 0; l < Length; l++) begin
                    acc = '0;
                    for (k = 0; k < K; k++) begin
                        addr_a = m * K + k;
                        addr_b = n * K + k;
                        acc += $signed(A_i[addr_a][q]) * $signed(B_i[addr_b][l]);
                    end
                    addr_c = n + m * (N/Length);
                    Y_o[addr_c][(q*Length + l)*OutDataWidth +: OutDataWidth] = acc;
                end
            end
        end
    end
endfunction