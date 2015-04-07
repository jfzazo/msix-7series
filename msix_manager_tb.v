`timescale 1ps/1ps


module msix_manager_tb;

localparam C_M_AXI_LITE_ADDR_WIDTH          = 9;
localparam C_M_AXI_LITE_DATA_WIDTH          = 32;
localparam C_M_AXI_LITE_STRB_WIDTH          = 32;
localparam C_MSIX_TABLE_OFFSET              = 32'h0;
localparam C_MSIX_PBA_OFFSET                = 32'h100; /* PBA = Pending bit array */
localparam C_NUM_IRQ_INPUTS                 = 4;


reg                                clk;
reg                                rst_n;
reg  [3:0]                         watchdog;
reg  [C_M_AXI_LITE_ADDR_WIDTH-1:0] s_mem_iface_waddr;
reg  [C_M_AXI_LITE_ADDR_WIDTH-1:0] s_mem_iface_raddr;
reg  [C_M_AXI_LITE_DATA_WIDTH-1:0] s_mem_iface_wdata;
wire [C_M_AXI_LITE_DATA_WIDTH-1:0] s_mem_iface_rdata;
reg                                s_mem_iface_we;
wire [3:0]                         cfg_interrupt_int;
wire [1:0]                         cfg_interrupt_pending;
wire                               cfg_interrupt_sent;
wire [1:0]                         cfg_interrupt_msi_enable;
wire [5:0]                         cfg_interrupt_msi_vf_enable;
wire [5:0]                         cfg_interrupt_msi_mmenable;
wire                               cfg_interrupt_msi_mask_update;
wire [31:0]                        cfg_interrupt_msi_data;
wire [3:0]                         cfg_interrupt_msi_select;
wire [31:0]                        cfg_interrupt_msi_int;
wire [63:0]                        cfg_interrupt_msi_pending_status;
wire                               cfg_interrupt_msi_sent;
wire                               cfg_interrupt_msi_fail;
reg  [1:0]                         cfg_interrupt_msix_enable;
wire [1:0]                         cfg_interrupt_msix_mask;
wire [5:0]                         cfg_interrupt_msix_vf_enable;
wire [5:0]                         cfg_interrupt_msix_vf_mask;
wire [31:0]                        cfg_interrupt_msix_data;
wire [63:0]                        cfg_interrupt_msix_address;
wire                               cfg_interrupt_msix_int;
reg                                cfg_interrupt_msix_sent;
wire                               cfg_interrupt_msix_fail;
wire [2:0]                         cfg_interrupt_msi_attr;
wire                               cfg_interrupt_msi_tph_present;
wire [1:0]                         cfg_interrupt_msi_tph_type;
wire [8:0]                         cfg_interrupt_msi_tph_st_tag;
wire [2:0]                         cfg_interrupt_msi_function_number;
reg  [C_NUM_IRQ_INPUTS-1:0]        irq;

msix_manager_br  #(
  .C_M_AXI_LITE_ADDR_WIDTH(C_M_AXI_LITE_ADDR_WIDTH),
  .C_M_AXI_LITE_DATA_WIDTH(C_M_AXI_LITE_DATA_WIDTH),
  .C_M_AXI_LITE_STRB_WIDTH(C_M_AXI_LITE_STRB_WIDTH),
  .C_MSIX_TABLE_OFFSET(C_MSIX_TABLE_OFFSET),
  .C_MSIX_PBA_OFFSET(C_MSIX_PBA_OFFSET), 
  .C_NUM_IRQ_INPUTS(C_NUM_IRQ_INPUTS)
) msix_manager_i ( 
  .clk(clk),
  .rst_n(rst_n),
  .s_mem_iface_waddr(s_mem_iface_waddr),
  .s_mem_iface_raddr(s_mem_iface_raddr),
  .s_mem_iface_wdata(s_mem_iface_wdata),
  .s_mem_iface_rdata(s_mem_iface_rdata),
  .s_mem_iface_we_norread(s_mem_iface_we),
  .cfg_interrupt_int(cfg_interrupt_int),                  
  .cfg_interrupt_pending(cfg_interrupt_pending),              
  .cfg_interrupt_sent(cfg_interrupt_sent),                        
  .cfg_interrupt_msi_enable(cfg_interrupt_msi_enable),          
  .cfg_interrupt_msi_vf_enable(cfg_interrupt_msi_vf_enable),       
  .cfg_interrupt_msi_mmenable(cfg_interrupt_msi_mmenable),        
  .cfg_interrupt_msi_mask_update(cfg_interrupt_msi_mask_update),             
  .cfg_interrupt_msi_data(cfg_interrupt_msi_data),           
  .cfg_interrupt_msi_select(cfg_interrupt_msi_select),           
  .cfg_interrupt_msi_int(cfg_interrupt_msi_int),             
  .cfg_interrupt_msi_pending_status(cfg_interrupt_msi_pending_status),  
  .cfg_interrupt_msi_sent(cfg_interrupt_msi_sent),                    
  .cfg_interrupt_msi_fail(cfg_interrupt_msi_fail),                    
  .cfg_interrupt_msix_enable(cfg_interrupt_msix_enable),         
  .cfg_interrupt_msix_mask(cfg_interrupt_msix_mask),           
  .cfg_interrupt_msix_vf_enable(cfg_interrupt_msix_vf_enable),      
  .cfg_interrupt_msix_vf_mask(cfg_interrupt_msix_vf_mask),        
  .cfg_interrupt_msix_data(cfg_interrupt_msix_data),           
  .cfg_interrupt_msix_address(cfg_interrupt_msix_address),        
  .cfg_interrupt_msix_int(cfg_interrupt_msix_int),                     
  .cfg_interrupt_msix_sent(cfg_interrupt_msix_sent),                   
  .cfg_interrupt_msix_fail(cfg_interrupt_msix_fail),                   
  .cfg_interrupt_msi_attr(cfg_interrupt_msi_attr),
  .cfg_interrupt_msi_tph_present(cfg_interrupt_msi_tph_present),              
  .cfg_interrupt_msi_tph_type(cfg_interrupt_msi_tph_type),         
  .cfg_interrupt_msi_tph_st_tag(cfg_interrupt_msi_tph_st_tag),       
  .cfg_interrupt_msi_function_number(cfg_interrupt_msi_function_number),
  .irq(irq)
);  



always 
	#5 clk = ! clk;


integer i;
initial begin
  clk = 0;
  rst_n = 0;
  irq = 0;
  cfg_interrupt_msix_enable = 2'b01;
  s_mem_iface_waddr = 0;
  s_mem_iface_raddr = 0;
  s_mem_iface_we = 1'b0;
  #25
  rst_n = 1;
  
  for(i=0; i<C_NUM_IRQ_INPUTS; i=i+1) begin
    #10
    s_mem_iface_waddr = 9'h0 + C_MSIX_TABLE_OFFSET + i*9'h10;
    s_mem_iface_wdata = (32'hFFF0+i);
    s_mem_iface_we = 1'b1;
    #10
    s_mem_iface_waddr = 9'h4 + C_MSIX_TABLE_OFFSET + i*9'h10;
    s_mem_iface_wdata = i;
    #10
    s_mem_iface_waddr = 9'h8 + C_MSIX_TABLE_OFFSET + i*9'h10;
    s_mem_iface_wdata = (32'hCAFE + (i<<16));
    #10
    s_mem_iface_waddr = 9'h0 + C_MSIX_PBA_OFFSET;
    s_mem_iface_wdata = 32'h1;
    #10 
    s_mem_iface_we = 1'b0;
    s_mem_iface_raddr = 9'h0 + C_MSIX_TABLE_OFFSET  + i*9'h10;
    #10
    if( s_mem_iface_rdata != (32'hFFF0+i) ) begin
      $display("Error reading MSI-X table (irq=%h)", i); 
      $finish();
    end 
    s_mem_iface_raddr = 9'h4 + C_MSIX_TABLE_OFFSET  + i*9'h10;

    #10
    if( s_mem_iface_rdata != i ) begin
      $display("Error reading MSI-X table (irq=%h)", i); 
      $finish();
    end 
    s_mem_iface_raddr = 9'h8 + C_MSIX_TABLE_OFFSET  + i*9'h10;

    #10
    if( s_mem_iface_rdata != (32'hCAFE + (i<<16)) ) begin
      $display("Error reading MSI-X table (irq=%h)", i); 
      $finish();
    end 
  end


  #10
  irq <= 4'b1101;
  #10
  irq <= 4'b0;

  fork
    watchdog[3] <= #300 1'b1;
  join

  @(posedge cfg_interrupt_msix_int or posedge watchdog[3]);
  if( watchdog[3] ) begin
    $display("IRQ wasnt asserted"); 
    $finish();
  end 
  cfg_interrupt_msix_sent <= 1'b1;
  #10
  cfg_interrupt_msix_sent <= 1'b0;
  #50
  irq <= 4'b0010;
  
  #10
  irq <= 4'b0;
  

  for(i=0; i<3; i=i+1) begin 
    fork
      watchdog[i] <= #300 1'b1;
    join
    @(posedge cfg_interrupt_msix_int or posedge watchdog[i]);
    if( watchdog[i] ) begin
      $display("IRQ wasnt asserted"); 
      $finish();
    end 
    cfg_interrupt_msix_sent <= 1'b1;

    #10
    cfg_interrupt_msix_sent <= 1'b0;
  end
  #100
  $display("Everything as expected"); 
  $finish();
end	





endmodule