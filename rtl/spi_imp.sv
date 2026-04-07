module spi_imp #(
  parameter int unsigned ADDR_WIDTH = 32,
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned NUM_SLAVES = 4,
  parameter int unsigned SCLK_COUNTER_RESET_VALUE = 19,
  parameter int unsigned SPI_DATA_LENGTH = 8
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
  output  logic                     obi_rvalid_o, // Read Valid - response transfer request
  input   logic                     obi_rready_i, // Read ready - master is ready to accept response transfer
  output  logic [DATA_WIDTH-1:0]    obi_rdata_o,  // Read Data - only valid for read transactions
  output  logic                     obi_rerr_o,

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

  localparam TxDataRegAddr = 0;
  localparam RxDataRegAddr = 4;
  localparam SpiDivClkRegAddr = 8;
  localparam SsRegAddr = 12;
  localparam CtrlRegAddr = 16;

  localparam CtrlStartWritingBitMask = 1;
  localparam CtrlStartReadingBitMask = 2;
  localparam CtrlBusyBitMask = 4;
  localparam CtrlTxBufferEmptyBitMask = 8;
  localparam CtrlRxBufferNonEmptyBitMask = 16;
  localparam CtrlCompleteBitMask = 32;

  localparam CtrlStartWritingBit       = 0;
  localparam CtrlStartReadingBit       = 1;
  localparam CtrlBusyBit                = 2;
  localparam CtrlTxBufferEmptyBit     = 3;
  localparam CtrlRxBufferNonEmptyBit = 4;
  localparam CtrlCompleteBit            = 5;

  /**************************************************************
  **********                  TYPEDEF                  **********
  **************************************************************/

  // three states: sending, done, idle
  typedef enum {
    eSPI_IDLE,     // Waiting for instructions
    eSPI_WRITING,  // Sending an SPI transaction
    eSPI_READING,
    eSPI_DONE      // Done sending an SPI transaction
    } spi_state_t;

  typedef enum {
    eOBI_IDLE,       // Waiting for instructions
    eOBI_READING,    // OBI read transfer
    eOBI_WRITING     // OBI write transfer
  } obi_state_t;

  /**************************************************************
  **********                DEFINITIONS                **********
  **************************************************************/

  //logic [DATA_WIDTH-1:0] spi_write_reg, spi_read_reg;
  logic [SPI_DATA_LENGTH-1:0] tx_data_reg, rx_data_reg;

  logic [DATA_WIDTH-1 : 0] spi_div_clk_reg;

  logic [NUM_SLAVES-1 : 0] ss_reg;

  logic [5:0] CTRL_REG;
  logic ctrl_start_writing_bit, 
        ctrl_start_reading_bit, 
        ctrl_busy_bit, 
        ctrl_tx_buffer_empty_bit, 
        ctrl_rx_buffer_non_empty_bit, 
        ctrl_complete_bit;

  logic [5:0] control_reg_value;
  /*
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

  int spi_sclk_counter;
  logic spi_sclk_second_time;
  logic spi_sclk_prev;
  logic spi_sclk_counter_en;

  logic spi_started_writing, spi_stopped_writing, spi_started_reading, spi_stopped_reading, spi_completed;

  spi_state_t spi_state, spi_state_next;

  logic obi_started_reading, obi_started_writing, obi_done;

  obi_state_t obi_state, obi_state_next;

  /**************************************************************
  **********               CONTROL LOGIC               **********
  **************************************************************/

  // TX data register
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      tx_data_reg <= '0;
    else if (obi_awe_i && obi_aaddr_i == TxDataRegAddr && obi_abe_i[0] && spi_state == eSPI_IDLE && obi_state == eOBI_IDLE)
      tx_data_reg <= obi_awdata_i[SPI_DATA_LENGTH - 1:0];
    end

  // RX data register
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      rx_data_reg <= '0;
    else if (obi_awe_i && obi_aaddr_i == RxDataRegAddr && obi_abe_i[0] && spi_state == eSPI_IDLE && obi_state == eOBI_IDLE)
      rx_data_reg <= obi_awdata_i[SPI_DATA_LENGTH - 1:0];
    end

  // SPI division clock register
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      spi_div_clk_reg <= SCLK_COUNTER_RESET_VALUE;
    else if (obi_awe_i && obi_aaddr_i == SpiDivClkRegAddr && obi_abe_i[0] && spi_state == eSPI_IDLE && obi_state == eOBI_IDLE)
      spi_div_clk_reg <= obi_awdata_i;
    end

  // Slave select register ss_reg
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      ss_reg <= '0;
    else if(obi_awe_i && obi_aaddr_i == SsRegAddr && obi_abe_i[0] && spi_state == eSPI_IDLE && obi_state == eOBI_IDLE)
      ss_reg <= obi_awdata_i[NUM_SLAVES-1:0];
  end

  // Control complete bit
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      ctrl_complete_bit <= 1'b0;
    else if(obi_awe_i && obi_aaddr_i == CtrlRegAddr && obi_abe_i[0] && spi_state == eSPI_DONE)
      ctrl_complete_bit <= obi_awdata_i[CtrlCompleteBit];
    else if(~obi_awe_i && obi_aaddr_i == CtrlRegAddr && obi_abe_i[0])
      ctrl_complete_bit <= obi_rdata_o;
  end

  assign control_reg_value = (
      ({31'b0, ctrl_start_writing_bit} << CtrlStartWritingBitMask)
    | ({31'b0, ctrl_start_reading_bit} << CtrlStartReadingBitMask)
    | ({31'b0, ctrl_busy_bit} << CtrlBusyBitMask)
    | ({31'b0, ctrl_tx_buffer_empty_bit} << CtrlTxBufferEmptyBitMask)
    | ({31'b0, ctrl_rx_buffer_non_empty_bit} << CtrlRxBufferNonEmptyBitMask)
    | ({31'b0, ctrl_complete_bit} << CtrlCompleteBitMask)
    | 32'b0
  );

  // // Cotrol register assignment
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      CTRL_REG <= 6'b0;
    else if (spi_started_reading || spi_started_writing)
      CTRL_REG[2] <= 1'b1;
    else if (spi_stopped_writing || spi_stopped_reading) begin
      CTRL_REG[2] <= 1'b0;
      CTRL_REG[5] <= 1'b1;
    end else if (obi_a_fire && obi_awe_i && obi_aaddr_i == CtrlRegAddr && obi_abe_i[0] && ~CTRL_REG[2])
      CTRL_REG <= obi_awdata_i[5:0];
  end
  
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

  // Data index counter
  always_ff @(posedge clk_i) begin
    if(~rstn_i)
      spi_data_index <= 4'b0;
    else if(spi_sclk_counter == 0 && ~spi_sclk_o && spi_sclk_prev)
      spi_data_index++;
    else if(spi_data_index == SPI_DATA_LENGTH)
      spi_data_index <= 4'b0;
  end

  // SPI sclk
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      spi_sclk_o <= 1'b0;
    else if(spi_sclk_counter == spi_div_clk_reg && spi_sclk_second_time)
      spi_sclk_o <= ~spi_sclk_o;
    else if(spi_ss_o == 4'b1111)
      spi_sclk_o <= 1'b0;
  end

  // SPI sclk count number to 2
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      spi_sclk_second_time <= 1'b0;
    else if(spi_sclk_counter == spi_div_clk_reg && spi_sclk_counter_en)
      spi_sclk_second_time <= ~spi_sclk_second_time;
  end

  //   SPI sclk counter
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      spi_sclk_counter <= 0;
    else if(spi_sclk_counter < spi_div_clk_reg && spi_sclk_counter_en)
      spi_sclk_counter++;
    else if(spi_sclk_counter == spi_div_clk_reg)
      spi_sclk_counter <= 0;
  end

  always_ff @(posedge clk_i) begin
    if(~rstn_i)
      rx_data_reg <= '0;
    // On rising edge of SPI SCLK we gather data
    else if(~spi_sclk_prev && spi_sclk_o)
      rx_data_reg[spi_data_index - 1] <= spi_miso_i;
  end

  /**************************************************************
  **********                  SPI FSM                  **********
  **************************************************************/

  //  Output assignment
  assign spi_sclk_counter_en = (spi_state == eSPI_WRITING || spi_state == eSPI_READING);
  
  assign spi_ss_o = ~(ss_reg);

  assign spi_mosi_o = (spi_state == eSPI_IDLE) ? 1'b0 : tx_data_reg[SPI_DATA_LENGTH - 1 - spi_data_index];
  
  assign complete_o = CTRL_REG[5];

  assign spi_started_writing = obi_awe_i && obi_aaddr_i == CtrlRegAddr && obi_abe_i[0] && spi_state == eSPI_IDLE && obi_state == eOBI_IDLE && (obi_awdata_i & CtrlStartWritingBitMask);
  assign spi_started_reading = obi_awe_i && obi_aaddr_i == CtrlRegAddr && obi_abe_i[0] && spi_state == eSPI_IDLE && obi_state == eOBI_IDLE && (obi_awdata_i & CtrlStartReadingBitMask);

  assign ctrl_busy_bit = (spi_state == eSPI_READING || spi_state == eSPI_WRITING);

  // SPI FSM conditions for transitions
  always_comb begin
    spi_stopped_writing =   spi_state == eSPI_WRITING  && spi_data_index == SPI_DATA_LENGTH;
    spi_stopped_reading = spi_state == eSPI_READING && spi_data_index == SPI_DATA_LENGTH;
    spi_completed = spi_state == eSPI_DONE     && ~CTRL_REG[5];

  end

  // SPI FSM transitions
  always_comb begin
    spi_state_next = spi_started_writing                        ? eSPI_WRITING : spi_state;
    spi_state_next = spi_started_reading                        ? eSPI_READING : spi_state_next;
    spi_state_next = spi_stopped_writing || spi_stopped_reading ? eSPI_DONE :    spi_state_next;
    spi_state_next = spi_completed                              ? eSPI_IDLE :    spi_state_next;
  end

  // SPI FSM current state assignment
  always_ff @(posedge clk_i) begin
    if(~rstn_i)
      spi_state <= eSPI_IDLE;
    else
      spi_state <= spi_state_next;
  end

  /**************************************************************
  **********                    OBI                    **********
  **************************************************************/

  assign obi_a_fire = obi_areq_i && obi_agnt_o;

  /**************************************************************
  **********                  OBI FSM                  **********
  **************************************************************/

  // Output assignment
  assign obi_agnt_o = (obi_state == eOBI_IDLE);
  assign obi_rvalid_o = (obi_state == eOBI_READING || obi_state == eOBI_WRITING);
  assign obi_rdata_o = (obi_state == eOBI_READING) ? {24'b0, tx_data_reg} : 32'b0;

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
