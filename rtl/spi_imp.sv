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
  input   logic                     obi_rready_i, // Read ready - master is ready to accept response transfer
  output  logic [DATA_WIDTH-1:0]    obi_rdata_o,  // Read Data - only valid for read transactions

  // SPI master
  output  logic                     spi_ss_o,
  output  logic                     spi_sclk_o,
  output  logic                     spi_mosi_o,
  input   logic                     spi_miso_i,

  output  logic                     spi_done_o
);
  /**************************************************************
  **********                 LOCALPARAM                **********
  **************************************************************/

  localparam DataRegAddr = 0;
  localparam CtrlRegAddr = 1;

  /**************************************************************
  **********                  TYPEDEF                  **********
  **************************************************************/

  // three states: sending, done, idle
  typedef enum {
    SPI_IDLE,     // Waiting for instructions
    SPI_SENDING,  // Sending an SPI transaction
    SPI_DONE      // Done sending an SPI transaction
    } spi_state_t;

  typedef enum {
    OBI_IDLE,       // Waiting for instructions
    OBI_READING,    // OBI read transfer
    OBI_WRITING     // OBI write transfer
  } obi_state_t;

  /**************************************************************
  **********                DEFINITIONS                **********
  **************************************************************/

  logic [7:0] data_reg;

  logic ctrl_start_bit;    // 0 bit
  logic ctrl_busy_bit;     // 1 bit
  logic ctrl_complete_bit; // 2 bit

  logic obi_a_fire;
  
  int spi_data_index = 0;  

  int spi_sclk_counter;
  logic spi_sclk_prev;

  logic spi_start_sending;
  logic spi_started_sending;
  logic spi_stopped_sending;
  logic spi_completed_sending;

  spi_state_t spi_state, spi_state_next;

  logic obi_started_reading, obi_started_writing, obi_done;

  obi_state_t obi_state, obi_state_next;

  /**************************************************************
  **********               CONTROL LOGIC               **********
  **************************************************************/

  // Data register
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      data_reg <= '0;
    else if (obi_we_i && obi_addr_i == DataRegAddr && obi_be_i[0] && spi_state == SPI_IDLE && obi_state == OBI_IDLE)
      data_reg <= obi_wdata_i[SPI_DATA_LENGTH-1:0];
    end

  // Control busy bit
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      ctrl_busy_bit <= 1'b0;
    else if (spi_started_sending)
      ctrl_busy_bit <= 1'b1;
    else if (spi_stopped_sending)
      ctrl_busy_bit <= 1'b0;
  end

  // Cotrol complete bit
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      ctrl_complete_bit <= 1'b0;
    else if (spi_stopped_sending)
      ctrl_complete_bit <= 1'b1;
    else if (obi_a_fire && obi_we_i && obi_addr_i == CtrlRegAddr && obi_be_i[0])
      ctrl_complete_bit <= obi_wdata_i[2];
  end
  
  /**************************************************************
  **********                    SPI                    **********
  **************************************************************/

  assign spi_start_sending = (obi_a_fire && obi_we_i && obi_addr_i == CtrlRegAddr && obi_be_i[0] && ~ctrl_busy_bit && obi_wdata_i[0]);

  always_ff @(posedge clk_i) begin
    if(~rstn_i)
      spi_sclk_prev <= 1'b1;
    else
      spi_sclk_prev <= spi_sclk_o;
  end

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

  /**************************************************************
  **********                    OBI                    **********
  **************************************************************/

  assign obi_a_fire = obi_req_i && obi_gnt_o;

  /**************************************************************
  **********                  SPI FSM                  **********
  **************************************************************/

  //  Output assignment
  assign spi_ss_o = (spi_state == SPI_SENDING) ? 1'b0 : 1'b1;
  assign spi_sclk_o = (spi_state == SPI_SENDING && spi_sclk_counter <= SCLK_COUNTER_MAX/2 && spi_state != SPI_IDLE) ? 1'b0 : 1'b1;
  assign spi_mosi_o = (spi_state == SPI_IDLE) ? 1'b0 : data_reg[7 - spi_data_index];

  assign spi_done_o = ctrl_complete_bit;

  // SPI FSM conditions for transitions
  always_comb begin
    spi_started_sending =   (spi_state == SPI_IDLE)     && spi_start_sending;
    spi_stopped_sending =   spi_state == SPI_SENDING  && spi_data_index == SPI_DATA_LENGTH;
    spi_completed_sending = spi_state == SPI_DONE     && ~ctrl_complete_bit;
  end

  // SPI FSM transitions
  always_comb begin
    spi_state_next = spi_started_sending    ? SPI_SENDING : spi_state;
    spi_state_next = spi_stopped_sending    ? SPI_DONE :    spi_state_next;
    spi_state_next = spi_completed_sending  ? SPI_IDLE :    spi_state_next;
  end

  // SPI FSM current state assignment
  always_ff @(posedge clk_i) begin
    if(~rstn_i)
      spi_state <= SPI_IDLE;
    else
      spi_state <= spi_state_next;
  end

  /**************************************************************
  **********                  OBI FSM                  **********
  **************************************************************/

  // Output assignment
  assign obi_gnt_o = (obi_state == OBI_IDLE);
  assign obi_rvalid_o = (obi_state == OBI_READING || obi_state == OBI_WRITING);
  assign obi_rdata_o = (obi_state == OBI_READING) ? {24'b0, data_reg} : 32'b0;

  // OBI FSM conditions for transitions
  always_comb begin
    obi_started_reading = obi_state == OBI_IDLE && obi_req_i && obi_gnt_o && ~obi_we_i;
    obi_started_writing = obi_state == OBI_IDLE && obi_req_i && obi_gnt_o && obi_we_i;
    obi_done            = (obi_state == OBI_READING || obi_state == OBI_WRITING) && obi_rvalid_o && obi_rready_i;
  end

  // OBI FSM transitions
  always_comb begin
    obi_state_next = obi_started_reading  ? OBI_READING : obi_state;
    obi_state_next = obi_started_writing  ? OBI_WRITING : obi_state_next;
    obi_state_next = obi_done             ? OBI_IDLE    : obi_state_next;
  end

  // OBI FSM current state assignment
  always_ff @(posedge clk_i) begin
    if(~rstn_i)
      obi_state <= OBI_IDLE;
    else
      obi_state <= obi_state_next;
  end

endmodule
