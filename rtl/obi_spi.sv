module obi_spi #(
  parameter int unsigned BASE_ADDR                = 0,
  parameter int unsigned ADDR_WIDTH               = 32,
  parameter int unsigned DATA_WIDTH               = 32,
  parameter int unsigned NUM_SLAVES               = 4,
  parameter int unsigned SCLK_COUNTER_RESET_VALUE = 0,
  parameter int unsigned SPI_DATA_LENGTH          = 8
) (
  input logic clk_i,
  input logic rstn_i,

  // OBI interface
  //  A channel
  input   logic                     obi_areq_i,
  output  logic                     obi_agnt_o,
  input   logic [ADDR_WIDTH-1:0]    obi_aaddr_i,
  input   logic [DATA_WIDTH-1:0]    obi_awdata_i,

  input   logic                     obi_awe_i,
  input   logic [DATA_WIDTH/8-1:0]  obi_abe_i,

  //  R channel
  output  logic                     obi_rvalid_o,
  input   logic                     obi_rready_i,
  output  logic [DATA_WIDTH-1:0]    obi_rdata_o,
  output  logic                     obi_rerr_o,   // Response Error - TODO

  // SPI master
  output  logic [NUM_SLAVES-1 : 0]  spi_ss_o,
  output  logic                     spi_sclk_o,
  output  logic                     spi_mosi_o,
  input   logic                     spi_miso_i,

  // Output complete
  output  logic                     complete_o
);
  /**************************************************************
  **********                 LOCALPARAM                **********
  **************************************************************/

  // Register Address Offsets
  localparam int TxDataRegAddrOffset        = BASE_ADDR + 0;
  localparam int RxDataRegAddrOffset        = BASE_ADDR + 4;
  localparam int SpiDivClkRegAddrOffset     = BASE_ADDR + 8;
  localparam int SsRegAddrOffset            = BASE_ADDR + 12;
  localparam int CtrlRegAddrOffset          = BASE_ADDR + 16;

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
  typedef enum reg [1:0] {
    eSPI_IDLE,      // Waiting for instructions
    eSPI_WRITING,   // Sending an SPI transaction
    eSPI_READING,   // Reading an SPI transaction
    eSPI_DONE       // Done sending an SPI transaction
    } spi_state_t;

  // OBI states
  typedef enum reg [1:0] {
    eOBI_IDLE,       // Waiting for instructions
    eOBI_READING,    // OBI read transfer
    eOBI_WRITING     // OBI write transfer
  } obi_state_t;

  /**************************************************************
  **********                DEFINITIONS                **********
  **************************************************************/

  // TX data register
  logic [SPI_DATA_LENGTH-1:0] tx_data_reg;

  // RX data register
  logic [SPI_DATA_LENGTH-1:0] rx_data_reg;

  // SPI Division clock register
  logic [DATA_WIDTH-1 : 0] spi_div_clk_reg;

  // SS Register
  logic [NUM_SLAVES-1 : 0] ss_reg;

  // Control Register Bits
  //  0 bit: Start Write - start sending on SPI
  logic ctrl_start_writing_bit;
  //  1 bit: Start Read - start reading from SPI
  logic ctrl_start_reading_bit; 
  //  2 bit: Busy - currently sending or reading on SPI
  logic ctrl_busy_bit;
  //  3 bit: TX buffer empty - clears on OBI write to TX register
  logic ctrl_tx_buffer_empty_bit;
  //  4 bit: RX buffer non-empty - clears on OBI read from RX register
  logic ctrl_rx_buffer_non_empty_bit;
  //  5 bit: Complete (TX or RX) - "Writable" - sets after SPI transaction completes, waits for clear from CPU - IRQ for CPU
  logic ctrl_complete_bit;

  logic ctrl_complete_bit_next, ctrl_complete_bit_write;

  // Control Register Register Value
  logic [5:0] ctrl_reg_value;

  // OBI
  //  Obi Address Channel Accepted Transaction
  logic obi_a_fire;
  //  Obi Address Channel Write/Read Accepted Transaction
  logic obi_a_write, obi_a_read;
  //  Obi Address Channel Valid Write Transaction
  logic obi_a_write_valid;

  logic obi_started_reading, obi_started_writing, obi_done;

  obi_state_t obi_state, obi_state_next;

  logic [DATA_WIDTH-1 : 0] obi_read_value;

  // SPI
  logic [3:0] spi_data_index;

  logic [DATA_WIDTH-1:0] spi_sclk_counter;

  logic spi_sclk_prev;
  logic spi_sclk_counter_en;

  logic spi_started_writing, spi_stopped_writing, spi_started_reading, spi_stopped_reading, spi_completed;

  spi_state_t spi_state, spi_state_next;

  /**************************************************************
  **********               CONTROL LOGIC               **********
  **************************************************************/

  // Control Complete Bit
  register ctrl_complete_bit_inst (.clk(clk_i), .rstn(rstn_i), .ce(ctrl_complete_bit_write), .in(ctrl_complete_bit_next), .out(ctrl_complete_bit));

  assign ctrl_complete_bit_write = (obi_a_write && obi_aaddr_i == CtrlRegAddrOffset && obi_abe_i[0]) || spi_state == eSPI_DONE;

  always_comb begin
    ctrl_complete_bit_next = ctrl_complete_bit;
    if(obi_a_write && obi_aaddr_i == CtrlRegAddrOffset && obi_abe_i[0])
      ctrl_complete_bit_next = obi_awdata_i[CtrlCompleteBit];
    else if(spi_state == eSPI_DONE)
      ctrl_complete_bit_next = '1;
  end

  // Control Start Reading Bit
  register ctrl_start_reading_bit_inst (.clk (clk_i), .rstn (rstn_i && ~spi_completed), .ce(spi_started_reading), .in(1'b1), .out(ctrl_start_reading_bit));

  // Control Start Writing Bit
  register ctrl_start_writing_bit_inst (.clk (clk_i), .rstn (rstn_i && ~spi_completed), .ce(spi_started_writing), .in(1'b1), .out(ctrl_start_writing_bit));

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

  // Receive Data Register
  shift_register #(
    .WORD_WIDTH(SPI_DATA_LENGTH)
  ) rx_data_reg_inst (
    .clk  (clk_i),
    .rstn (rstn_i),
    .ce   (~spi_sclk_prev && spi_sclk_o && ctrl_start_reading_bit),
    .in   (spi_miso_i),
    .out  (rx_data_reg)
  );

  // SPI Data Counter
  cntr #(
    .WORD_WIDTH(4)
  ) spi_data_index_inst (
      .clk (clk_i),
      .rstn(rstn_i && ~({28'b0, spi_data_index} == SPI_DATA_LENGTH)),
      .ce  (spi_sclk_counter == 0 && ~spi_sclk_o && spi_sclk_prev),
      .count (spi_data_index)
  );

  // SPI Serial Clock Counter
  cntr #(
    .WORD_WIDTH(DATA_WIDTH)
  ) spi_sclk_counter_inst (
      .clk (clk_i),
      .rstn(rstn_i && ~(spi_sclk_counter == spi_div_clk_reg) && spi_sclk_counter_en),
      .ce  ((spi_sclk_counter < spi_div_clk_reg) && spi_sclk_counter_en),
      .count (spi_sclk_counter)
  );

  // Previous SPI serial clock
  register spi_sclk_prev_inst (.clk(clk_i), .rstn(rstn_i), .ce(clk_i), .in(spi_sclk_o), .out(spi_sclk_prev));
  // SPI Serial Clock
  register spi_sclk_o_inst (.clk(clk_i), .rstn(rstn_i && spi_ss_o < '1), .ce(spi_sclk_counter == spi_div_clk_reg), .in(~spi_sclk_o), .out(spi_sclk_o));

  /**************************************************************
  **********                  SPI FSM                  **********
  **************************************************************/

  //  Output assignment
  assign spi_sclk_counter_en = (spi_state == eSPI_WRITING || spi_state == eSPI_READING);
  
  assign spi_ss_o = ~(ss_reg);

  assign spi_mosi_o = (spi_state == eSPI_IDLE || spi_data_index == SPI_DATA_LENGTH || spi_state == eSPI_DONE || spi_state == eSPI_READING) ? 1'b0 : tx_data_reg[SPI_DATA_LENGTH - 1 - {28'b0, spi_data_index}];
  
  assign complete_o = ctrl_complete_bit;

  assign spi_started_reading = obi_a_write_valid && obi_aaddr_i == CtrlRegAddrOffset && obi_abe_i[0] && ((obi_awdata_i & CtrlStartReadingBitMask) > '0);
  assign spi_started_writing = obi_a_write_valid && obi_aaddr_i == CtrlRegAddrOffset && obi_abe_i[0] && ((obi_awdata_i & CtrlStartWritingBitMask) > '0);

  assign ctrl_busy_bit = (spi_state == eSPI_READING || spi_state == eSPI_WRITING);

  // SPI FSM conditions for transitions
  always_comb begin
    spi_stopped_writing =   spi_state == eSPI_WRITING  && {28'b0, spi_data_index} == SPI_DATA_LENGTH;
    spi_stopped_reading = spi_state == eSPI_READING && {28'b0, spi_data_index} == SPI_DATA_LENGTH;
    spi_completed = spi_state == eSPI_DONE && ~ctrl_complete_bit;
  end

  // SPI FSM transitions
  always_comb begin
    spi_state_next = spi_started_writing                          ? eSPI_WRITING : spi_state;
    spi_state_next = spi_started_reading                          ? eSPI_READING : spi_state_next;
    spi_state_next = (spi_stopped_writing || spi_stopped_reading) ? eSPI_DONE :    spi_state_next;
    spi_state_next = spi_completed                                ? eSPI_IDLE :    spi_state_next;
  end

  // SPI FSM current state assignment
  register #(.DTYPE(spi_state_t), .RESET_VALUE(eSPI_IDLE)) spi_state_inst (.clk(clk_i), .rstn(rstn_i), .ce(clk_i), .in(spi_state_next), .out(spi_state));

  /**************************************************************
  **********                    OBI                    **********
  **************************************************************/

  // Obi Response Error Output
  assign obi_rerr_o = 1'b0;
  // Obi Address Channel Accepted Transaction
  assign obi_a_fire = obi_areq_i && obi_agnt_o;
  // Obi Address Channel Accepted Write Transaction
  assign obi_a_write = obi_a_fire && obi_awe_i;
  // Obi Address Channel Accepted Read Transaction
  assign obi_a_read = obi_a_fire && ~obi_awe_i;
  // Obi Address Channel Valid Write Transaction
  assign obi_a_write_valid = obi_a_write && spi_state == eSPI_IDLE && obi_state == eOBI_IDLE;

  // Transfer Data Register
  register #(
    .DTYPE(logic[SPI_DATA_LENGTH-1:0])
  ) tx_data_reg_inst (
    .clk  (clk_i),
    .rstn (rstn_i),
    .ce   (obi_a_write_valid && obi_aaddr_i == TxDataRegAddrOffset && obi_abe_i[0]),
    .in   (obi_awdata_i[SPI_DATA_LENGTH - 1:0]),
    .out  (tx_data_reg)
  );

  // SPI Clock Divisor Register
  register #(
    .DTYPE(logic[DATA_WIDTH-1:0]),
    .RESET_VALUE(SCLK_COUNTER_RESET_VALUE)
  ) spi_div_clk_reg_inst (
    .clk  (clk_i),
    .rstn (rstn_i),
    .ce   (obi_a_write_valid && obi_aaddr_i == SpiDivClkRegAddrOffset && obi_abe_i[0]),
    .in   (obi_awdata_i),
    .out  (spi_div_clk_reg)
  );

  // Slave Select Register
  register #(
    .DTYPE(logic[NUM_SLAVES-1:0])
  ) ss_reg_inst (
    .clk  (clk_i),
    .rstn (rstn_i),
    .ce   (obi_a_write_valid && obi_aaddr_i == SsRegAddrOffset && obi_abe_i[0]),
    .in   (obi_awdata_i[NUM_SLAVES-1:0]),
    .out  (ss_reg)
  );

  // OBI Response Data Out Register
  register #(.DTYPE(logic[DATA_WIDTH-1:0])) obi_rdata_o_inst (.clk(clk_i), .rstn(rstn_i && (obi_a_read || ~obi_done)), .ce(obi_a_read), .in(obi_read_value), .out(obi_rdata_o));

  always_comb begin
    unique case (obi_aaddr_i)
      TxDataRegAddrOffset: obi_read_value = {24'b0, tx_data_reg};
      RxDataRegAddrOffset: obi_read_value = {24'b0, rx_data_reg};
      SpiDivClkRegAddrOffset: obi_read_value = spi_div_clk_reg;
      SsRegAddrOffset: obi_read_value = {28'b0, ss_reg};
      CtrlRegAddrOffset: obi_read_value = {26'b0, ctrl_reg_value};
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
    obi_started_reading = obi_state == eOBI_IDLE && obi_a_read;
    obi_started_writing = obi_state == eOBI_IDLE && obi_a_write;
    obi_done            = obi_rvalid_o && obi_rready_i;
  end

  // OBI FSM transitions
  always_comb begin
    obi_state_next = obi_started_reading  ? eOBI_READING : obi_state;
    obi_state_next = obi_started_writing  ? eOBI_WRITING : obi_state_next;
    obi_state_next = obi_done             ? eOBI_IDLE    : obi_state_next;
  end

  // OBI FSM current state assignment
  register #(.DTYPE(obi_state_t), .RESET_VALUE(eOBI_IDLE)) obi_state_inst (.clk(clk_i), .rstn(rstn_i), .ce(clk_i), .in(obi_state_next), .out(obi_state));

 /**************************************************************
 **********                   MISC                    **********
 **************************************************************/

endmodule
