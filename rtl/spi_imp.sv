//
// OBI slave gets instructions from OBI master
// It is intended to be a SPI master
//

module spi_imp #(
  parameter int unsigned ADDR_WIDTH = 32,
  parameter int unsigned DATA_WIDTH = 32,

  parameter int unsigned TEST_WORDS = 8,
  parameter logic [31:0] BASE_ADDR = 32'h0000
) (
  input logic clk_i,
  input logic rstn_i,

  // OBI interface
  input   logic                     obi_req_i,    // Request
  output  logic                     obi_gnt_o,    // Grant
  input   logic [ADDR_WIDTH-1:0]    obi_addr_i,   // Address
  input   logic                     obi_we_i,     // Write Enable
  input   logic [DATA_WIDTH/8-1:0]  obi_be_i,     // Byte Enable
  input   logic [DATA_WIDTH-1:0]    obi_wdata_i,  // Write Data
  output  logic                     obi_rvalid_o, // Read Valid
  output  logic [DATA_WIDTH-1:0]    obi_rdata_o   // Read Data
);

typedef enum {
  IDLE,
  READ_ADDR

} state_t;

state_t state, state_next;

logic [ADDR_WIDTH/8-1:0] read_ptr, write_ptr;

// This state decision
always_ff @(posedge clk_i) begin
  // If reset is low:
  // rvalid shall be driven low.
  if(!rstn_i) begin
    state <= IDLE;
  end else begin
    state <= state_next;
  end
end

// Write pointer
always_ff @(posedge clk_i) begin
  if(!rstn_i) begin
    write_ptr <= '0;
  end
end

// Read pointer
always_ff @(posedge clk_i) begin
  if(!rstn_i) begin
    read_ptr <= '0;
  end
end

// Next state assignment
always_comb begin
  case(state)
    IDLE: begin
      obi_rvalid_o <= 1'b0;
      if(obi_req_i) begin
        state_next <= READ_ADDR;
      end
    end
    READ_ADDR: begin
      obi_gnt_o <= 1'b1;
    end
  endcase
end

endmodule
