module spi_imp #(
  parameter int unsigned ADDR_WIDTH = 32,
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned NUM_SLAVES = 4,

  //parameter int unsigned INPUT_CLK_FREQ_MHZ = 1000,
  //parameter int unsigned OUTPUT_SPI_CLK_FREQ = 50000000,
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

  localparam TX_DATA_REG_ADDR = 0;
  localparam RX_DATA_REG_ADDR = 4;
  localparam SPI_DIV_CLK_REG_ADDR = 8;
  localparam SS_REG_ADDR = 12;
  localparam CTRL_REG_ADDR = 16;

  //localparam CtrlRegAddr = 0;
  //localparam StatusRegAddr = 1;
  //localparam DataOutRegAddr = 2;

  // Initial value for max SCLK counter
  localparam SCLK_COUNTER_MAX = 19;

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
  logic [SPI_DATA_LENGTH-1:0] TX_DATA_REG, RX_DATA_REG;

  logic [DATA_WIDTH-1 : 0] SPI_DIV_CLK_REG;

  logic [NUM_SLAVES-1 : 0] SS_REG;

  logic [5:0] CTRL_REG;
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
  
  int spi_data_index = 0;  

  int spi_sclk_counter;
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
      TX_DATA_REG <= '0;
    else if (obi_awe_i && obi_aaddr_i == TX_DATA_REG_ADDR && obi_abe_i[0] && spi_state == eSPI_IDLE && obi_state == eOBI_IDLE)
      TX_DATA_REG <= obi_awdata_i[SPI_DATA_LENGTH - 1:0];
    end

  // RX data register
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      RX_DATA_REG <= '0;
    else if (obi_awe_i && obi_aaddr_i == RX_DATA_REG_ADDR && obi_abe_i[0] && spi_state == eSPI_IDLE && obi_state == eOBI_IDLE)
      RX_DATA_REG <= obi_awdata_i[SPI_DATA_LENGTH - 1:0];
    end

  // SPI division clock register
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      SPI_DIV_CLK_REG <= SCLK_COUNTER_MAX;
    else if (obi_awe_i && obi_aaddr_i == SPI_DIV_CLK_REG_ADDR && obi_abe_i[0] && spi_state == eSPI_IDLE && obi_state == eOBI_IDLE)
      SPI_DIV_CLK_REG <= obi_awdata_i;
    end

  // Slave select register SS_REG
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      SS_REG <= 4'b0;
    else if(obi_awe_i && obi_aaddr_i == SS_REG_ADDR && obi_abe_i[0] && spi_state == eSPI_IDLE && obi_state == eOBI_IDLE)
      SS_REG <= obi_awdata_i[3:0];
  end

  // Control register start write bit (0)
  // always_ff @(posedge clk_i) begin
  //   if (~rstn_i)
  //     CTRL_REG[0] <= 1'b0;
  //   else if (obi_a_fire && obi_awe_i && obi_aaddr_i == CTRL_REG_ADDR && obi_abe_i[0] && ~CTRL_REG[2])
  //     CTRL_REG[0] <= obi_awdata_i[0];
  // end

  // Control register busy bit (2)
  // always_ff @(posedge clk_i) begin
  //   if (~rstn_i)
  //     CTRL_REG[2] <= 1'b0;
  //   else if (spi_started_writing || spi_started_reading)
  //     CTRL_REG[2] <= 1'b1;
  //   else if (spi_stopped_writing || spi_stopped_reading)
  //     CTRL_REG[2] <= 1'b0;
  // end

  // Cotrol register assignment
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      CTRL_REG <= 6'b0;
    else if (spi_started_reading || spi_started_writing)
      CTRL_REG[2] <= 1'b1;
    else if (spi_stopped_writing || spi_stopped_reading) begin
      CTRL_REG[2] <= 1'b0;
      CTRL_REG[5] <= 1'b1;
    end else if (obi_a_fire && obi_awe_i && obi_aaddr_i == CTRL_REG_ADDR && obi_abe_i[0] && ~CTRL_REG[2])
      CTRL_REG <= obi_awdata_i[5:0];
  end
  
  /**************************************************************
  **********                    SPI                    **********
  **************************************************************/

//  assign CTRL_REG[0] = (obi_a_fire && obi_awe_i && obi_aaddr_i == CTRL_REG_ADDR && obi_abe_i[0] && ~CTRL_REG[2] && obi_awdata_i[0]);
  // assign CTRL_REG[1] = (obi_a_fire && obi_awe_i && obi_aaddr_i == CTRL_REG_ADDR && obi_abe_i[0] && ~CTRL_REG[2] && obi_awdata_i[1]);
//  assign CTRL_REG[5] = (obi_a_fire && obi_awe_i && obi_aaddr_i == CTRL_REG_ADDR && obi_abe_i[0] && ~CTRL_REG[2] && obi_awdata_i[5]);

//  assign CTRL_REG[2] = 
//  assign CTRL_REG[3]
//  assign CTRL_REG[4] = 

  // Previous SPI serial clock
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
    else if(spi_sclk_o && ~spi_sclk_prev && spi_data_index < SPI_DATA_LENGTH)
      spi_data_index++;
    else if(spi_data_index == SPI_DATA_LENGTH)
      spi_data_index <= 0;
  end

  //   SPI sclk counter
  always_ff @(posedge clk_i) begin
    if (~rstn_i)
      spi_sclk_counter <= 0;
    else if(spi_sclk_counter < SPI_DIV_CLK_REG*2 && spi_sclk_counter_en)
      spi_sclk_counter++;
    else
      spi_sclk_counter <= 0;
  end

  always_ff @(posedge clk_i) begin
    if(~rstn_i)
      RX_DATA_REG <= '0;
    // On rising edge of SPI SCLK we gather data
    else if(~spi_sclk_prev && spi_sclk_o)
      RX_DATA_REG[spi_data_index - 1] <= spi_miso_i;
  end

  /**************************************************************
  **********                  SPI FSM                  **********
  **************************************************************/

  //  Output assignment
  //assign spi_ss_o = (spi_state == eSPI_WRITING) ? 1'b0 : 1'b1;
  assign spi_sclk_counter_en = (spi_state == eSPI_WRITING || spi_state == eSPI_READING) ? 1'b1 : 1'b0;
  
  assign spi_ss_o = (spi_state == eSPI_READING || spi_state == eSPI_WRITING) ? ~(SS_REG) : 4'b1111;

  assign spi_sclk_o = ((spi_state == eSPI_WRITING || spi_state == eSPI_READING) && spi_sclk_counter <= SPI_DIV_CLK_REG && spi_state != eSPI_IDLE) ? 1'b0 : 1'b1;
  assign spi_mosi_o = (spi_state == eSPI_IDLE) ? 1'b0 : TX_DATA_REG[SPI_DATA_LENGTH - 1 - spi_data_index];

  //assign spi_done_o = CTRL_REG[5];
  
  assign complete_o = CTRL_REG[5];

  // SPI FSM conditions for transitions
  always_comb begin
    spi_started_writing =   (spi_state == eSPI_IDLE)     && CTRL_REG[0];
    spi_started_reading = (spi_state == eSPI_IDLE) && CTRL_REG[1];
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
  assign obi_rdata_o = (obi_state == eOBI_READING) ? {24'b0, TX_DATA_REG} : 32'b0;

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
