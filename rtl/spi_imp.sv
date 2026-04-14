module spi_imp #(
  parameter int unsigned BASE_ADDR                = 0,
  parameter int unsigned ADDR_WIDTH               = 32,
  parameter int unsigned DATA_WIDTH               = 32,
  parameter int unsigned NUM_SLAVES               = 4,
  parameter int unsigned SCLK_COUNTER_RESET_VALUE = 19,
  parameter int unsigned SPI_DATA_LENGTH          = 8
) (
  input logic clk_i,
  input logic rstn_i,

  // OBI interface
  //  A channel
  input   logic                     obi_areq_i,    // Request - address transfer request
  output  logic                     obi_agnt_o,    // Grant - ready to accept address transfer
  input   logic [ADDR_WIDTH-1:0]    obi_aaddr_i,   // Address
  input   logic [DATA_WIDTH-1:0]    obi_awdata_i,  // Write Data - only valid for write transaction

  input   logic                     obi_awe_i,     // Write Enable - high write, low read
  input   logic [DATA_WIDTH/8-1:0]  obi_abe_i,     // Byte Enable - is set for the bytes to read/write

  //  R channel
  output  logic                     obi_rvalid_o, // Response Valid - response transfer request
  input   logic                     obi_rready_i, // Response ready - master is ready to accept response transfer
  output  logic [DATA_WIDTH-1:0]    obi_rdata_o,  // Response Data - only valid for read transactions
  output  logic                     obi_rerr_o,   // Response Error - TODO

  // SPI master
  output  logic [NUM_SLAVES-1 : 0]  spi_ss_o,     // SPI slave select
  output  logic                     spi_sclk_o,   // SPI serial clock
  output  logic                     spi_mosi_o,   // SPI MOSI - Mater Out Slave In
  input   logic                     spi_miso_i,   // SPI MISO - Master In Slave Out

  // Output complete
  output  logic                     complete_o
);
  /**************************************************************
  **********                 LOCALPARAM                **********
  **************************************************************/

  // Register Address Offsets
  localparam int TxDataRegAddrOffset        = 0;
  localparam int RxDataRegAddrOffset        = 4;
  localparam int SpiDivClkRegAddrOffset     = 8;
  localparam int SsRegAddrOffset            = 12;
  localparam int CtrlRegAddrOffset          = 16;

  // Control Register Bits
  localparam int CtrlStartWritingBit         = 0;
  localparam int CtrlStartReadingBit         = 1;
  localparam int CtrlBusyBit                 = 2;
  localparam int CtrlTxBufferEmptyBit        = 3;
  localparam int CtrlRxBufferNonEmptyBit     = 4;
  localparam int CtrlCompleteBit             = 5;

  // Control Register Bit Masks
  localparam int CtrlStartWritingBitMask     = 1 << CtrlStartWritingBit;
  localparam int CtrlStartReadingBitMask     = 1 << CtrlStartReadingBit;
  localparam int CtrlBusyBitMask             = 1 << CtrlBusyBit;
  localparam int CtrlTxBufferEmptyBitMask    = 1 << CtrlTxBufferEmptyBit;
  localparam int CtrlRxBufferNonEmptyBitMask = 1 << CtrlRxBufferNonEmptyBit;
  localparam int CtrlCompleteBitMask         = 1 << CtrlCompleteBit;

  // SPI Serial Clock Max Value
  localparam int SclkMaxValue = SCLK_COUNTER_RESET_VALUE << 1;

  /**************************************************************
  **********                  TYPEDEF                  **********
  **************************************************************/

  // SPI states
  typedef enum {
    eSPI_IDLE,      // Waiting for instructions
    eSPI_WRITING,   // Sending an SPI transaction
    eSPI_READING,   // Reading an SPI transaction
    eSPI_DONE       // Done sending an SPI transaction
    } spi_state_t;

  // OBI states
  typedef enum {
    eOBI_IDLE,       // Waiting for instructions
    eOBI_READING,    // OBI read transfer
    eOBI_WRITING     // OBI write transfer
  } obi_state_t;

  /**************************************************************
  **********                DEFINITIONS                **********
  **************************************************************/

  // TX data register
  logic [SPI_DATA_LENGTH-1:0] tx_data_reg;

  register #(
    .WORD_WIDTH(SPI_DATA_LENGTH)
  ) tx_data_reg_inst (
    .clk  (clk_i),
    .rstn (rstn_i),
    .ce   (obi_awe_i && obi_aaddr_i == (BASE_ADDR + TxDataRegAddrOffset) && obi_abe_i[0] && spi_state == eSPI_IDLE && obi_state == eOBI_IDLE),
    .in   (obi_awdata_i[SPI_DATA_LENGTH - 1:0]),
    .out  (tx_data_reg)
  );

  // RX data register
  logic [SPI_DATA_LENGTH-1:0] rx_data_reg;

  register #(
    .WORD_WIDTH(SPI_DATA_LENGTH)
  ) rx_data_reg_inst (
    .clk  (clk_i),
    .rstn (rstn_i),
    .ce   (~spi_sclk_prev && spi_sclk_o && ctrl_start_reading_bit),
    .in   (({7'b0, spi_miso_i} << spi_data_index) | rx_data_reg),
    .out  (rx_data_reg)
  );

  // SPI Division clock register
  logic [DATA_WIDTH-1 : 0] spi_div_clk_reg;

  register #(
    .WORD_WIDTH(DATA_WIDTH),
    .RESET_VALUE(SCLK_COUNTER_RESET_VALUE)
  ) spi_div_clk_reg_inst (
    .clk  (clk_i),
    .rstn (rstn_i),
    .ce   (obi_awe_i && obi_aaddr_i == (BASE_ADDR + SpiDivClkRegAddrOffset) && obi_abe_i[0] && spi_state == eSPI_IDLE && obi_state == eOBI_IDLE),
    .in   (obi_awdata_i),
    .out  (spi_div_clk_reg)
  );

  logic [NUM_SLAVES-1 : 0] ss_reg;

  register #(
    .WORD_WIDTH(NUM_SLAVES)
  ) ss_reg_inst (
    .clk  (clk_i),
    .rstn (rstn_i),
    .ce   (obi_awe_i && obi_aaddr_i == (BASE_ADDR + SsRegAddrOffset) && obi_abe_i[0] && spi_state == eSPI_IDLE && obi_state == eOBI_IDLE),
    .in   (obi_awdata_i[NUM_SLAVES-1:0]),
    .out  (ss_reg)
  );

  logic ctrl_start_writing_bit, 
        ctrl_start_reading_bit, 
        ctrl_busy_bit, 
        ctrl_tx_buffer_empty_bit, 
        ctrl_rx_buffer_non_empty_bit, 
        ctrl_complete_bit;

  logic [5:0] ctrl_reg_value;

  /*  Control Register Bits

  0 bit: Start Write - start sending on SPI
  1 bit: Start Read - start reading from SPI
  2 bit: Busy - currently sending or reading on SPI
  3 bit: TX buffer empty - clears on OBI write to TX register
  4 bit: RX buffer non-empty - clears on OBI read from RX register
  5 bit: Complete (TX or RX) - "Writable" - sets after SPI transaction completes, waits for clear from CPU
    - IRQ for CPU
  */

  logic obi_a_fire;
  
  logic [3:0] spi_data_index;

  counter #(
    .WORD_WIDTH(4)
  ) spi_data_index_inst (
      .clk (clk_i),
      .rstn(rstn_i && ~({28'b0, spi_data_index} == SPI_DATA_LENGTH)),
      .ce  (spi_sclk_counter == 0 && ~spi_sclk_o && spi_sclk_prev),
      .count (spi_data_index)
  );

  logic [DATA_WIDTH-1:0] spi_sclk_counter;

  counter #(
    .WORD_WIDTH(DATA_WIDTH)
  ) spi_sclk_counter_inst (
      .clk (clk_i),
      .rstn(rstn_i && ~(spi_sclk_counter == spi_div_clk_reg) && spi_sclk_counter_en),
      .ce  ((spi_sclk_counter < spi_div_clk_reg) && spi_sclk_counter_en),
      .count (spi_sclk_counter)
  );

  logic spi_sclk_count_twice;
  logic spi_sclk_prev;
  logic spi_sclk_counter_en;

  logic spi_started_writing, spi_stopped_writing, spi_started_reading, spi_stopped_reading, spi_completed;

  spi_state_t spi_state, spi_state_next;

  logic obi_started_reading, obi_started_writing, obi_done;

  obi_state_t obi_state, obi_state_next;

  logic [DATA_WIDTH-1 : 0] obi_read_value;

  /**************************************************************
  **********               CONTROL LOGIC               **********
  **************************************************************/

  // Control complete bit

  // register ctrl_complete_bit_inst (.clk  (clk_i), .rstn (rstn_i), .ce (bi_a_fire && obi_awe_i && obi_aaddr_i == (BASE_ADDR + CtrlRegAddrOffset) && obi_abe_i[0]), .in((spi_state == eSPI_DONE) ? 1'b1 : obi_awdata_i[NUM_SLAVES-1:0]), .out(ctrl_complete_bit));

  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      ctrl_complete_bit <= 1'b0;
    else if(obi_a_fire && obi_awe_i && obi_aaddr_i == (BASE_ADDR + CtrlRegAddrOffset) && obi_abe_i[0])
      ctrl_complete_bit <= obi_awdata_i[CtrlCompleteBit];
    else if(spi_state == eSPI_DONE)
      ctrl_complete_bit <= 1'b1;
  end

  // Control Start Reading Bit
  register ctrl_start_reading_bit_inst (.clk (clk_i), .rstn (rstn_i && ~spi_completed), .ce(spi_started_reading), .in(1'b1), .out(ctrl_start_reading_bit));

  // always_ff @(posedge clk_i) begin
  //   if (~rstn_i)
  //     ctrl_start_reading_bit <= '0;
  //   else if(spi_started_reading)
  //     ctrl_start_reading_bit <= 1'b1;
  //   else if(spi_completed)
  //     ctrl_start_reading_bit <= 1'b0;
  // end

  // Control Start Writing Bit
  register ctrl_start_writing_bit_inst (.clk (clk_i), .rstn (rstn_i && ~spi_completed), .ce(spi_started_writing), .in(1'b1), .out(ctrl_start_writing_bit));

  // always_ff @(posedge clk_i) begin
  //   if (~rstn_i)
  //     ctrl_start_writing_bit <= '0;
  //   else if(spi_started_writing)
  //     ctrl_start_writing_bit <= 1'b1;
  //   else if(spi_completed)
  //     ctrl_start_writing_bit <= 1'b0;
  // end

  // Control Register Value
  assign ctrl_reg_value = (
      ({5'b0, ctrl_start_writing_bit} << CtrlStartWritingBit)
    | ({5'b0, ctrl_start_reading_bit} << CtrlStartReadingBit)
    | ({5'b0, ctrl_busy_bit} << CtrlBusyBit)
    | ({5'b0, ctrl_tx_buffer_empty_bit} << CtrlTxBufferEmptyBit)
    | ({5'b0, ctrl_rx_buffer_non_empty_bit} << CtrlRxBufferNonEmptyBit)
    | ({5'b0, ctrl_complete_bit} << CtrlCompleteBit)
    | 6'b0
  );

  /**************************************************************
  **********                    SPI                    **********
  **************************************************************/

  // Previous SPI serial clock
  always_ff @(posedge clk_i) begin
    if(~rstn_i)
      spi_sclk_prev <= 1'b0;
    else
      spi_sclk_prev <= spi_sclk_o;
  end

  // SPI sclk
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      spi_sclk_o <= 1'b0;
    else if(spi_sclk_counter == spi_div_clk_reg && spi_sclk_count_twice)
      spi_sclk_o <= ~spi_sclk_o;
    else if(spi_ss_o == '1)
      spi_sclk_o <= 1'b0;
  end

  // SPI sclk count number to 2
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      spi_sclk_count_twice <= 1'b0;
    else if(spi_sclk_counter == spi_div_clk_reg && spi_sclk_counter_en)
      spi_sclk_count_twice <= ~spi_sclk_count_twice;
  end

  /**************************************************************
  **********                  SPI FSM                  **********
  **************************************************************/

  //  Output assignment
  assign spi_sclk_counter_en = (spi_state == eSPI_WRITING || spi_state == eSPI_READING);
  
  assign spi_ss_o = ~(ss_reg);

  assign spi_mosi_o = (spi_state == eSPI_IDLE) ? 1'b0 : tx_data_reg[SPI_DATA_LENGTH - 1 - {28'b0, spi_data_index}];
  
  assign complete_o = ctrl_complete_bit;

  assign spi_started_reading = obi_awe_i && obi_aaddr_i == (BASE_ADDR + CtrlRegAddrOffset) && obi_abe_i[0] && spi_state == eSPI_IDLE && obi_state == eOBI_IDLE && ((obi_awdata_i & CtrlStartReadingBitMask) > '0);
  assign spi_started_writing = obi_awe_i && obi_aaddr_i == (BASE_ADDR + CtrlRegAddrOffset) && obi_abe_i[0] && spi_state == eSPI_IDLE && obi_state == eOBI_IDLE && ((obi_awdata_i & CtrlStartWritingBitMask) > '0);

  assign ctrl_busy_bit = (spi_state == eSPI_READING || spi_state == eSPI_WRITING);

  // SPI FSM conditions for transitions
  always_comb begin

    spi_stopped_writing =   spi_state == eSPI_WRITING  && {28'b0, spi_data_index} == SPI_DATA_LENGTH;
    spi_stopped_reading = spi_state == eSPI_READING && {28'b0, spi_data_index} == SPI_DATA_LENGTH;
    spi_completed = spi_state == eSPI_DONE && ~ctrl_complete_bit;

  end

  // SPI FSM transitions
  always_comb begin
    spi_state_next = spi_started_writing                        ? eSPI_WRITING : spi_state;
    spi_state_next = spi_started_reading                        ? eSPI_READING : spi_state_next;
    spi_state_next = spi_stopped_writing || spi_stopped_reading ? eSPI_DONE :    spi_state_next;
    spi_state_next = spi_completed                              ? eSPI_IDLE :    spi_state_next;
  end

  // SPI FSM current state assignment
  register #(.WORD_WIDTH(2), .RESET_VALUE(eSPI_IDLE)) spi_state_inst (.clk(clk_i), .rstn(rstn_i), .ce(clk_i), .in(spi_state_next), .out(spi_state));

  // always_ff @(posedge clk_i) begin
  //   if(~rstn_i)
  //     spi_state <= eSPI_IDLE;
  //   else
  //     spi_state <= spi_state_next;
  // end

  /**************************************************************
  **********                    OBI                    **********
  **************************************************************/

  assign obi_a_fire = obi_areq_i && obi_agnt_o;

  // OBI Response Data Out Register
  register #(.WORD_WIDTH(DATA_WIDTH)) obi_rdata_o_inst (.clk(clk_i), .rstn(rstn_i && (~obi_awe_i && obi_a_fire)), .ce(~obi_awe_i && obi_a_fire), .in(obi_read_value), .out(obi_rdata_o));

  // always_ff @(posedge clk_i) begin
  //   if (~rstn_i)
  //     obi_rdata_o <= '0;
  //   else if(~obi_awe_i && obi_a_fire)
  //     obi_rdata_o <= obi_read_value;
  //   else
  //     obi_rdata_o <= '0;
  // end

  always_comb begin
    unique case (obi_aaddr_i)
      (BASE_ADDR + TxDataRegAddrOffset): obi_read_value = {24'b0, tx_data_reg};
      (BASE_ADDR + RxDataRegAddrOffset): obi_read_value = {24'b0, rx_data_reg};
      (BASE_ADDR + SpiDivClkRegAddrOffset): obi_read_value = spi_div_clk_reg;
      (BASE_ADDR + SsRegAddrOffset): obi_read_value = {28'b0, ss_reg};
      (BASE_ADDR + CtrlRegAddrOffset): obi_read_value = {26'b0, ctrl_reg_value};
    endcase
  end

  /**************************************************************
  **********                  OBI FSM                  **********
  **************************************************************/

  // Output assignment
  assign obi_agnt_o = (obi_state == eOBI_IDLE);
  assign obi_rvalid_o = (obi_state == eOBI_READING || obi_state == eOBI_WRITING);

  // OBI FSM conditions for transitions
  always_comb begin
    obi_started_reading = obi_state == eOBI_IDLE && obi_areq_i && obi_agnt_o && ~obi_awe_i;
    obi_started_writing = obi_state == eOBI_IDLE && obi_areq_i && obi_agnt_o && obi_awe_i;
    obi_done            = (obi_state == eOBI_READING || obi_state == eOBI_WRITING) && obi_rvalid_o && obi_rready_i;
  end

  // OBI FSM transitions
  always_comb begin
    obi_state_next = obi_started_reading  ? eOBI_READING : obi_state;
    obi_state_next = obi_started_writing  ? eOBI_WRITING : obi_state_next;
    obi_state_next = obi_done             ? eOBI_IDLE    : obi_state_next;
  end

  // OBI FSM current state assignment
  always_ff @(posedge clk_i) begin
    if(~rstn_i)
      obi_state <= eOBI_IDLE;
    else
      obi_state <= obi_state_next;
  end

 /**************************************************************
 **********                   MISC                    **********
 **************************************************************/
assign obi_rerr_o = 1'b0;

endmodule
