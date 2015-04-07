//////////////////////////////////////////////////////////////////////////////////
// Company:  HPCN-UAM
// Engineer: Jose Fernando Zazo
// 
// Create Date: 06/04/2015 01:04:59 PM
// Module Name: msix_manager
// Description: Implement the MSI-X structure (table and PBA) in a BRAM memory.
//            This module also offers the necessary interconnection for interact with the Xilinx
//            7 Series Integrated block for PCIe.
//            **Signals with higher value have more priority.
//            
// Dependencies: bram_tdp, block ram of 36kbits in TDP (true dual port)
//////////////////////////////////////////////////////////////////////////////////



/*


The MSI-X Table Structure contains multiple entries and eachentry represents one interrupt vector. Each entry has 4 QWORDs and consists of a32-bit lower Message Address, 32-bit upper Message Address, 32-bit data, and asingle Mask bit in the Vector Control field as shown in Figure 4 below. When the device wants to transmit a MSI-X interrupt message, it does

    Picks up an entry in the Table Structure, sendsout a PCIe memory write with the address and data in the table to the system host.
    Sets the associated bit in the PBA structure torepresent which MSI-X interrupt is sent. The host software can read the bit inthe PBA to determine which interrupt is generated and start the correspondinginterrupt service routine.
    After the interrupt is serviced, the functionwhich generates the MSI-X interrupt clears the bit.


The following is the flow about how the MSI-X is configured and is used.

    The system enumerates the FPGA, the host software does configuration read to the MSI-X Capability register located in the PCIe HIP to determine the table’s size.
    The host does memory writes to configure the MSI-X Table.
    To issue a MSI-X interrupt, the user logic reads the address and data of an entry in the MSI-X Table structure, packetize a memory write with the address and data and then does an upstream memory write to the system memory in PCIe domain.
    The user logic also sets the pending bit in MSI-X PBA structure, which is associated to the entry in the Table structure.
    When the system host receives the interrupt, it may read the MSI-X PBA structure through memory read to determine which interrupt is asserted and then calls the appropriate interrupt service routine.
    After the interrupt is served, the user logic needs to clear the pending bit in the MSI-X PBA structure. 


*/


module msix_manager_br #(
  parameter C_M_AXI_LITE_ADDR_WIDTH          = 9,
  parameter C_M_AXI_LITE_DATA_WIDTH          = 32,
  parameter C_M_AXI_LITE_STRB_WIDTH          = 32,
  parameter C_MSIX_TABLE_OFFSET              = 32'h0,
  parameter C_MSIX_PBA_OFFSET                = 32'h100, /* PBA = Pending bit array */
  parameter C_NUM_IRQ_INPUTS                 = 1
)( 
  input   wire                   clk,
  input   wire                   rst_n,

 /*********************
  * Memory  Interface *
  *********************/
  // Memory Channel
  input  wire [C_M_AXI_LITE_ADDR_WIDTH-1:0]   s_mem_iface_waddr,
  input  wire [C_M_AXI_LITE_ADDR_WIDTH-1:0]   s_mem_iface_raddr,
  input  wire [C_M_AXI_LITE_DATA_WIDTH-1:0]   s_mem_iface_wdata,
  output wire [C_M_AXI_LITE_DATA_WIDTH-1:0]   s_mem_iface_rdata,
  input  wire                                 s_mem_iface_we_norread,

 /***********************
  * Interrupt Interface *
  ***********************/
  // Legacy interrupts
  output wire [3:0]                           cfg_interrupt_int,                  
  output wire [1:0]                           cfg_interrupt_pending,              
  input  wire                                 cfg_interrupt_sent,                        
  // MSI interrupts
  input  wire [1:0]                           cfg_interrupt_msi_enable,          
  input  wire [5:0]                           cfg_interrupt_msi_vf_enable,       
  input  wire [5:0]                           cfg_interrupt_msi_mmenable,        
  input  wire                                 cfg_interrupt_msi_mask_update,             
  input  wire [31:0]                          cfg_interrupt_msi_data,           
  output wire [3:0]                           cfg_interrupt_msi_select,           
  output wire [31:0]                          cfg_interrupt_msi_int,             
  output wire [63:0]                          cfg_interrupt_msi_pending_status,  
  input  wire                                 cfg_interrupt_msi_sent,                    
  input  wire                                 cfg_interrupt_msi_fail,                    
  // MSI-X interrupts
  input  wire [1:0]                           cfg_interrupt_msix_enable,         
  input  wire [1:0]                           cfg_interrupt_msix_mask,           
  input  wire [5:0]                           cfg_interrupt_msix_vf_enable,      
  input  wire [5:0]                           cfg_interrupt_msix_vf_mask,        
  output reg  [31:0]                          cfg_interrupt_msix_data,           
  output wire [63:0]                          cfg_interrupt_msix_address,        
  output reg                                  cfg_interrupt_msix_int,                     
  input  wire                                 cfg_interrupt_msix_sent,                   
  input  wire                                 cfg_interrupt_msix_fail,                   
  // Common ports for MSI and MSI-X
  output wire [2:0]                           cfg_interrupt_msi_attr,
  output wire                                 cfg_interrupt_msi_tph_present,              
  output wire [1:0]                           cfg_interrupt_msi_tph_type,         
  output wire [8:0]                           cfg_interrupt_msi_tph_st_tag,       
  output wire [2:0]                           cfg_interrupt_msi_function_number,
  
 /********************
  * Interrupt Inputs *
  ********************/
  input  wire [C_NUM_IRQ_INPUTS-1:0]          irq
);  
  
  assign cfg_interrupt_int = 4'b0;
  assign cfg_interrupt_pending = 2'h0;

  assign cfg_interrupt_msi_select = 4'h0;
  assign cfg_interrupt_msi_int = 32'b0;
  assign cfg_interrupt_msi_pending_status = 64'h0;
  
  assign cfg_interrupt_msi_attr = 3'h0;
  assign cfg_interrupt_msi_tph_present = 1'b0;
  assign cfg_interrupt_msi_tph_type = 2'h0;
  assign cfg_interrupt_msi_tph_st_tag = 9'h0;
  assign cfg_interrupt_msi_function_number = 3'h0;

  /* Implementation of the MSIx table through a  BRAM*/
  // BRAM signals
  wire   [31:0]             doa;
  wire   [31:0]             dob;
  wire   [31:0]             dib;
  reg    [31:0]             dia;

  wire   [9:0]              addrbrdaddr;
  
  wire                      enbwren;
  reg                       enawren;

  reg    [9:0]              addrardaddr;


  assign s_mem_iface_rdata = dob[C_M_AXI_LITE_DATA_WIDTH-1:0];
            
  assign addrbrdaddr = s_mem_iface_we_norread == 1'b0 ? s_mem_iface_raddr : s_mem_iface_waddr; 
  assign dib         = s_mem_iface_wdata;
  assign enbwren     = s_mem_iface_we_norread; // Enable write port (B)

  //Infer a BRAM from the following verilog design. Easier than manage the connections directly
  bram_tdp #(
    .DATA(32),
    .ADDR(10)
  ) bram_tdp_i (
    // Port A
    .a_clk(clk),
    .a_wr(enawren),
    .a_addr(addrardaddr),
    .a_din(dia),
    .a_dout(doa),
     
    // Port B
    .b_clk(clk),
    .b_wr(enbwren),
    .b_addr(addrbrdaddr),
    .b_din(dib),
    .b_dout(dob)
  );



  // MSI-X IRQ generation logic
  
  integer irq_number, i;
  reg  [31:0] cfg_interrupt_msix_address_msb,cfg_interrupt_msix_address_lsb;
  assign cfg_interrupt_msix_address = {cfg_interrupt_msix_address_msb, cfg_interrupt_msix_address_lsb};

  reg [C_NUM_IRQ_INPUTS-1:0] irq_s; // List of asked IRQs by the user. The IRQs are acumulated in this vector.
  reg [31:0]                irq_pba, current_pba; 
  reg [3:0]                 state;
  reg [3:0]                 next_state;
  localparam IDLE       = 4'b0000;
  localparam TO_BINARY  = 4'b0001;
  localparam GET_ADDR1  = 4'b0010;
  localparam GET_ADDR2  = 4'b0011;
  localparam GET_DATA   = 4'b0100;
  localparam READ_PBA   = 4'b0101;
  localparam WRITE_PBA  = 4'b0110;
  localparam ACTIVE_IRQ = 4'b0111;
  localparam CLEAR_PBA  = 4'b1000;
  localparam WAIT       = 4'b1111;
  always @(negedge rst_n or posedge clk) begin
    if(~rst_n) begin
      cfg_interrupt_msix_int <= 1'b0;
      irq_s                  <= {C_NUM_IRQ_INPUTS{1'b0}};
      irq_pba                <= 32'h0; //Position in the PBA (position in a  32 bit vector)

      cfg_interrupt_msix_data    <= 32'h0; 
      cfg_interrupt_msix_address_msb <= 32'h0; 
      cfg_interrupt_msix_address_lsb <= 32'h0; 
      dia <= 32'h0; 
      state                  <= IDLE;
      next_state             <= IDLE;
      irq_number             <= 0;
      enawren                <= 1'b0;
      current_pba            <= 32'h0;
    end else begin
      case(state) 
        IDLE: begin /* Check if new IRQs has been asked. */
          if( cfg_interrupt_msix_enable && irq_s != {C_NUM_IRQ_INPUTS{1'b0}} ) begin   
            state   <= TO_BINARY;
          end else begin
            state   <= IDLE;
          end

          irq_s   <= irq | irq_s;
          irq_number <= 0;
          enawren    <= 1'b0;
        end
        TO_BINARY:begin  /* Choose one of the asked IRQs (First bit  active from the left. ) */
          for(i=0; i<C_NUM_IRQ_INPUTS; i=i+1) begin
            if(irq_s[i]) begin
              irq_number <= i;
              irq_pba    <= (1<<(i%32));
            end 
          end
          irq_s   <= irq_s | irq;
          state   <= GET_ADDR1;
        end
        GET_ADDR1: begin /* Read from the RAM address and data*/
          addrardaddr <= 9'h0 + C_MSIX_TABLE_OFFSET  + irq_number*9'h10;
          state         <= WAIT;
          next_state    <= GET_ADDR2;

          irq_s   <= irq_s | irq;
        end
        GET_ADDR2: begin
          cfg_interrupt_msix_address_lsb <= doa; 
          addrardaddr <= 9'h4 + C_MSIX_TABLE_OFFSET  + irq_number*9'h10;
          state         <= WAIT;
          next_state    <= GET_DATA;
          irq_s   <= irq_s | irq;
        end
        GET_DATA: begin
          cfg_interrupt_msix_address_msb <= doa; 
          addrardaddr <= 9'h8 + C_MSIX_TABLE_OFFSET  + irq_number*9'h10;

          state         <= WAIT;
          next_state    <= READ_PBA;

          irq_s   <= irq_s | irq;
        end
        READ_PBA: begin /* Get the previous value of the PBA */
          cfg_interrupt_msix_data    <= doa; 

          state                      <= WAIT;
          next_state                 <= WRITE_PBA;

          addrardaddr <= C_MSIX_PBA_OFFSET  + ((irq_number/32)<<2);

          irq_s   <= irq_s | irq;
        end
        WRITE_PBA: begin /* Add the current IRQ to the PBA */
          state         <= WAIT;
          next_state    <= ACTIVE_IRQ;

          enawren       <= 1'b1;

          addrardaddr <= C_MSIX_PBA_OFFSET  + ((irq_number/32)<<2);
          dia           <= doa | irq_pba; 
          current_pba   <= doa;
          irq_s         <= irq_s | irq;
        end
        ACTIVE_IRQ: begin /* Activate IRQ and remove the IRQ from the list irq_s */
          enawren                    <= 1'b0;
          cfg_interrupt_msix_int     <= 1'b1;
          state                      <= CLEAR_PBA;

          for(i=0; i<C_NUM_IRQ_INPUTS; i=i+1) begin
            if(irq_number==i) begin
              irq_s[irq_number] <= 1'b0;
            end else begin
              irq_s[i]   <= irq[i] | irq_s[i];
            end
          end
        end
        CLEAR_PBA: begin /* Remove the IRQ from the PBA */
          cfg_interrupt_msix_int     <= 1'b0;
          irq_s         <= irq_s | irq;

          if(cfg_interrupt_msix_sent || cfg_interrupt_msix_fail) begin
            enawren     <= 1'b1;
            addrardaddr <= C_MSIX_PBA_OFFSET  + ((irq_number/32)<<2);
            dia         <= current_pba & (~irq_pba); 

            state         <= WAIT;
            next_state    <= IDLE;
          end else begin
            state         <= CLEAR_PBA;
          end
        end


        WAIT: begin // one cycle must be wait because addrardaddr is a register. 
                    // The bram will get the correct address in the next pulse.
          state   <= next_state;
          irq_s   <= irq_s | irq;
        end
        default: begin
          state                    <= IDLE;
          next_state               <= IDLE;
        end
      endcase
    end

  end
endmodule
