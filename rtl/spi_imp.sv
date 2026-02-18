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
  //  A channel
  input   logic                     obi_req_i,    // Request - address transfer request
  output  logic                     obi_gnt_o,    // Grant - ready to accept address transfer
  input   logic [ADDR_WIDTH-1:0]    obi_addr_i,   // Address
  input   logic [DATA_WIDTH-1:0]    obi_wdata_i,  // Write Data - only valid for write transaction

  input   logic                     obi_we_i,     // Write Enable - high write, low read
  input   logic [DATA_WIDTH/8-1:0]  obi_be_i,     // Byte Enable - is set for the bytes to read/write
  
  //  R channel
  output  logic                     obi_rvalid_o, // Read Valid - response transfer request
  output  logic [DATA_WIDTH-1:0]    obi_rdata_o   // Read Data - only valid for read transactions
);

typedef enum {
  IDLE,
  ADDRESS_PHASE,
  RESPONSE_PHASE

} state_t;

state_t state, state_next;

logic [ADDR_WIDTH/8-1:0] read_ptr, write_ptr;

reg [DATA_WIDTH-1:0] int_data [ADDR_WIDTH];

// This state decision
always_ff @(posedge clk_i) begin
  // If reset is low:
  // rvalid shall be driven low.
  if(!rstn_i) begin
    state <= IDLE;
  end else begin
    // State is assigned on every positive clk edge (if rstn is not activated)
    state <= state_next;
  end
end

// Next state assignment
always_comb begin
  case(state)
    IDLE: begin
      obi_rvalid_o <= 1'b0;
      obi_rdata_o <= '0;
      obi_gnt_o <= '0;
      if(obi_req_i) begin
        // Manager indicated validity of address phase signals with setting req high
        // We go to address phase
        state_next <= ADDRESS_PHASE;
      end else begin
        // Else we stay in IDLE
        state_next <= IDLE;
      end

    end
    ADDRESS_PHASE: begin
      // Subordinate indicates its readiness to accept the address phase signals by setting gnt high
      obi_gnt_o <= 1'b1;
      if(obi_req_i) begin
        state_next <= RESPONSE_PHASE;
      end else begin
        state_next <= IDLE;
      end

    end

    RESPONSE_PHASE: begin
      // After a granted request, the subordinate indicates the validity of its response phase signals by setting rvalid high
      obi_rvalid_o <= 1'b1;
      // The manager indicates its readiness to accept the response phase signals by setting rready high
      // rready is not mandatory, i skip
      if(obi_rvalid_o) begin
        if(obi_we_i) begin
          // Write transaction
          int_data[obi_addr_i] <= obi_wdata_i;
        end else begin
          // Read transaction
          obi_rdata_o <= int_data[obi_addr_i];
        end
        state_next <= IDLE;
      end
    end
    
  endcase
end

endmodule
