module shift_register
#(
  parameter int WORD_WIDTH = 1,
  parameter logic [WORD_WIDTH-1:0] RESET_VALUE = 0
)
(
  input  logic                  clk,
  input  logic                  rstn,
  input  logic                  ce,
  input  logic                  in,
  output logic [WORD_WIDTH-1:0] out
);

  register #(.WORD_WIDTH(WORD_WIDTH), .RESET_VALUE(RESET_VALUE))
  shift_register_inst(
    .clk  (clk),
    .rstn (rstn),
    .ce   (ce),
    .in   ({out[WORD_WIDTH-2:0], in}),
    .out  (out)
  );
endmodule
