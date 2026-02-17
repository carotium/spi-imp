//
// OBI master sends instructions for an SPI slave
//

module obi_master #(
  parameter int unsigned ADDR_WIDTH = 32,
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned TEST_WORDS = 8,
  parameter logic [31:0] BASE_ADDR = 32'h0000,
  parameter logic [31:0] TEST_PATTERN = 32'hDEADBEEF
) (
  input logic clk_i,
  input logic rstn_i,

  // OBI interface
  output logic obi_req_o,     // Request
  input logic obi_gnt_i,      // Grant
  output logic [ADDR_WIDTH-1:0] obi_addr_o,   // Address
  output logic obi_we_o,      // Write Enable
  output logic [DATA_WIDTH/8-1:0] obi_be_o    // Byte Enable
  output logic [DATA_WIDTH-1:0] obi_wdata_o   // Write Data

  input logic obi_rvalid_i    // Read Valid
  input logic [DATA_WIDTH-1:0] obi_rdata_i    // Read Data
);

  

endmodule
