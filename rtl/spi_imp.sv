module spi_imp #(
  parameter int unsigned ADDR_WIDTH = 32,
  parameter int unsigned DATA_WIDTH = 32,

  parameter int unsigned INPUT_CLK_FREQ_MHZ = 1000,
  parameter int unsigned OUTPUT_SPI_CLK_FREQ = 50000000,
  // Arbitrary max number for slck counter
  parameter int unsigned SCLK_COUNTER_MAX = INPUT_CLK_FREQ_MHZ * 1000000 / OUTPUT_SPI_CLK_FREQ - 1,
  parameter int unsigned SPI_DATA_LENGTH = 8
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
  output  logic [DATA_WIDTH-1:0]    obi_rdata_o,   // Read Data - only valid for read transactions

  // SPI master
  output  logic                     spi_ss_o,
  output  logic                     spi_sclk_o,
  output  logic                     spi_mosi_o,
  input   logic                     spi_miso_i,

  output  logic                     spi_done_o
);
  localparam DataRegAddr = 0;
  localparam CtrlRegAddr = 1;

  int spi_sclk_counter;

  logic spi_sclk_prev;

  logic [7:0] data_reg;

  logic start_sending;

  logic ctrl_start_bit;    // 0 bit
  logic ctrl_busy_bit;     // 1 bit
  logic ctrl_complete_bit; // 2 bit

  logic obi_a_fire;

  assign start_sending = (obi_a_fire && obi_we_i && obi_addr_i == CtrlRegAddr && obi_be_i[0] && ~ctrl_busy_bit && obi_wdata_i[0]);

  int spi_data_index = 0;  

  logic spi_started_sending;
  logic spi_stopped_sending;
  logic spi_completed_sending;

  // three states: sending, done, idle
  typedef enum {
    IDLE,     // Waiting for instructions
    SENDING,  // Sending an SPI transaction
    DONE      // Done sending an SPI transaction
    } spi_state_t;

  spi_state_t spi_state, spi_state_next;

  assign obi_a_fire = obi_req_i && obi_gnt_o;

  // conditions for transitions between states
  always_comb begin
    spi_started_sending =   (spi_state == IDLE)     && start_sending;
    spi_stopped_sending =   spi_state == SENDING  && spi_data_index == SPI_DATA_LENGTH;
    spi_completed_sending = spi_state == DONE     && ~ctrl_complete_bit;
  end
  // transitions as a top priority decoder
  always_comb begin
    spi_state_next = spi_started_sending    ? SENDING : spi_state;
    spi_state_next = spi_stopped_sending    ? DONE :    spi_state_next;
    spi_state_next = spi_completed_sending  ? IDLE :    spi_state_next;
  end

  // OBI
  // Grant
  // Maybe need to add support if we want multiple transfers at same time
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      obi_gnt_o <= 1'b0;
    else if (obi_req_i)
      obi_gnt_o <= 1'b1;
    else
      obi_gnt_o <= 1'b0;
  end

  // Data register
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      data_reg <= '0;
    else if (obi_we_i && obi_addr_i == DataRegAddr && obi_be_i[0] && spi_state == IDLE)
      data_reg <= obi_wdata_i[SPI_DATA_LENGTH-1:0];
    end

  // Data output
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      obi_rdata_o <= '0;
    else if (obi_a_fire && ~obi_we_i && obi_addr_i == DataRegAddr && obi_be_i[0])
      obi_rdata_o <= {24'b0, data_reg};
    else if (obi_a_fire && ~obi_we_i && obi_addr_i == CtrlRegAddr && obi_be_i[0])
      obi_rdata_o <= {29'b0, ctrl_complete_bit, ctrl_busy_bit, 1'b0};
  end

  // Valid output
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      obi_rvalid_o <= 1'b0;
    else
      obi_rvalid_o <= obi_a_fire;
  end

  // CONTROL LOGIC
  // Control busy bit
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      ctrl_busy_bit <= 1'b0;
    else if (spi_started_sending)
      ctrl_busy_bit <= 1'b1;
    else if (spi_stopped_sending)
      ctrl_busy_bit <= 1'b0;
  end

  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      ctrl_complete_bit <= 1'b0;
    else if (spi_stopped_sending)
      ctrl_complete_bit <= 1'b1;
    else if (obi_a_fire && obi_we_i && obi_addr_i == CtrlRegAddr && obi_be_i[0])
      ctrl_complete_bit <= obi_wdata_i[2];
  end

  // SPI    
  always_ff @(posedge clk_i) begin
    if(~rstn_i)
      spi_sclk_prev <= 1'b1;
    else
      spi_sclk_prev <= spi_sclk_o;
  end

  // Current SPI state assignment
  always_ff @(posedge clk_i) begin
    if(~rstn_i)
      spi_state <= IDLE;
    else
      spi_state <= spi_state_next;

  end

  // FSM output assignment

  assign spi_ss_o = (spi_state == SENDING) ? 1'b0 : 1'b1;
  assign spi_sclk_o = (spi_state == SENDING && spi_sclk_counter <= SCLK_COUNTER_MAX/2 && spi_state != IDLE) ? 1'b0 : 1'b1;
  assign spi_mosi_o = (spi_state == IDLE) ? 1'b0 : data_reg[7 - spi_data_index];

  assign spi_done_o = ctrl_complete_bit;

  // Data index counter
  always_ff @(posedge clk_i) begin
    if(~rstn_i)
      spi_data_index <= 0;
    else if(spi_sclk_o && ~spi_sclk_prev && ~spi_ss_o && spi_data_index < SPI_DATA_LENGTH)
      spi_data_index++;
    else if(spi_data_index == SPI_DATA_LENGTH)
      spi_data_index <= 0;
  end

  //   SPI sclk counter
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      spi_sclk_counter <= 0;
    else if(spi_sclk_counter < SCLK_COUNTER_MAX && ~spi_ss_o)
      spi_sclk_counter++;
    else
      spi_sclk_counter <= 0;
  end

endmodule
