module spi_imp #(
  parameter int unsigned ADDR_WIDTH = 32,
  parameter int unsigned DATA_WIDTH = 32,

  // Arbitrary max number for slck counter
  parameter int unsigned SCLK_COUNTER_MAX = 4095
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
  output  logic                     spi_ss_o = '1,
  output  logic                     spi_sclk_o = '0,
  output  logic                     spi_mosi_o = '0,
  input   logic                     spi_miso_i,

  output  logic                     spi_done_o
);
    localparam DataRegAddr = 0;
    localparam CtrlRegAddr = 1;

    logic [11:0] spi_sclk_counter;

    logic [7:0] data_reg;

    logic ctrl_start_bit;    // 0 bit
    logic ctrl_busy_bit;     // 1 bit
    logic ctrl_complete_bit; // 2 bit

    logic obi_a_fire;
    assign obi_a_fire = obi_req_i && obi_gnt_o;

    logic spi_started_sending = 1'b0;
    logic spi_stopped_sending = 1'b0;


    // OBI
    // Grant
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
        else if (obi_a_fire && obi_we_i && obi_addr_i == DataRegAddr && obi_be_i[0])
            data_reg <= obi_wdata_i[7:0];
    end

    // Data output
    always_ff @(posedge clk_i) begin
        if (~rstn_i)
            obi_rdata_o <= '0;
        else if (obi_a_fire && ~obi_we_i && obi_addr_i == DataRegAddr && obi_be_i[0])
            obi_rdata_o <= {24'b0, data_reg};
        else if (obi_a_fire && ~obi_we_i && obi_addr_i == CtrlRegAddr && obi_be_i[0])
            obi_rdata_o <= {29'b0, ctrl_complete_bit, ctrl_busy_bit, ctrl_start_bit};
    end

    // Valid output
    always_ff @(posedge clk_i) begin
        if (~rstn_i)
            obi_rvalid_o <= 1'b0;
        else
            obi_rvalid_o <= obi_a_fire;
    end

    // CONTROL LOGIC
    // Control start bit
    always_ff @(posedge clk_i) begin
        if (~rstn_i)
            ctrl_start_bit <= 1'b0;
        else if (obi_a_fire && obi_we_i && obi_addr_i == CtrlRegAddr && obi_be_i[0] && ~ctrl_busy_bit)
            ctrl_start_bit <= obi_wdata_i[0];
        else if (spi_started_sending)
            ctrl_start_bit <= 1'b0;
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

    always_ff @(posedge clk_i) begin
        if (~rstn_i)
            ctrl_complete_bit <= 1'b0;
        else if (spi_stopped_sending)
            ctrl_complete_bit <= 1'b1;
        else if (obi_a_fire && obi_we_i && obi_addr_i == CtrlRegAddr && obi_be_i[0])
            ctrl_complete_bit <= obi_wdata_i[2];
    end

    // SPI
    //   SPI start sending
    always_ff @(posedge clk_i) begin
      if (~rstn_i)
        spi_started_sending <= 1'b0;
      else if (ctrl_start_bit)
        spi_started_sending <= 1'b1;
      else
        spi_started_sending <= 1'b0;
    end

    //   SPI stop sending
    always_ff @(posedge clk_i) begin
      if (~rstn_i)
        spi_stopped_sending <= 1'b0;
    end

    //   SPI Slave select
    always_ff @(posedge clk_i) begin
      if (~rstn_i)
        spi_ss_o <= 1'b1;
      else if (spi_started_sending)
        spi_ss_o <= 1'b0;
      else if (spi_stopped_sending)
        spi_ss_o <= 1'b1;
    end

    //   SPI sclk
    always_ff @(posedge clk_i) begin
      if (~rstn_i)
        spi_sclk_o <= 1'b0;
      else if (spi_sclk_counter == SCLK_COUNTER_MAX)
        spi_sclk_o <= 1'b1;
      else
        spi_sclk_o <= 1'b0;
    end

    //   SPI sclk counter
    always_ff @(posedge clk_i) begin
      if (~rstn_i)
        spi_sclk_counter <= 0;
      else if(spi_sclk_counter < SCLK_COUNTER_MAX && spi_started_sending)
        spi_sclk_counter++;
      else
        spi_sclk_counter <= 0;
    end

    assign spi_done_o = ctrl_complete_bit;

endmodule
