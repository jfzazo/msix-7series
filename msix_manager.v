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

  reg     [C_NUM_IRQ_INPUTS-1:0] irq_s;     // List of asked IRQs by the user. The IRQs are acumulated in this vector.
  integer irq_count [C_NUM_IRQ_INPUTS-1:0]; // Number of IRQs to generate of each type.
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
  
  /* 
    This process will activate the cfg_interrupt_msix_int signal when necessary.
    It also counts the number of IRQs asked by the external design.
  */
  always @(negedge rst_n or posedge clk) begin
    if(~rst_n) begin
      irq_s                  <= {C_NUM_IRQ_INPUTS{1'b0}};
      cfg_interrupt_msix_int <= 1'b0;
      for(i=0; i<C_NUM_IRQ_INPUTS; i=i+1) begin
        irq_count[i] <= 0;
      end
    end else begin
      case(state) 
        ACTIVE_IRQ: begin
          for(i=0; i<C_NUM_IRQ_INPUTS; i=i+1) begin
            if(irq_number==i) begin
              irq_count[i] <= irq_count[i] +  irq[i] - 1;
            end else begin
              irq_count[i] <= irq_count[i] +  irq[i];
            end
          end
          for(i=0; i<C_NUM_IRQ_INPUTS; i=i+1) begin
            if(irq_number==i && irq_count[irq_number] == 1 ) begin
              irq_s[i] <= 1'b0;
            end else begin
              irq_s[i]   <= irq[i] | irq_s[i];
            end
          end
          cfg_interrupt_msix_int <= 1'b1;
        end

        default: begin
          for(i=0; i<C_NUM_IRQ_INPUTS; i=i+1) begin
            irq_count[i] <= irq_count[i] +  irq[i];
          end
          irq_s                  <= irq | irq_s;
          cfg_interrupt_msix_int <= 1'b0;
        end
      endcase
    end
  end

  /* This process is in charge of updating the registers:

        cfg_interrupt_msix_data        
        cfg_interrupt_msix_address_msb 
        cfg_interrupt_msix_address_lsb 
        current_pba           

    with the information read from the bram
  */
  always @(negedge rst_n or posedge clk) begin
    if(~rst_n) begin
      cfg_interrupt_msix_data        <= 32'h0; 
      cfg_interrupt_msix_address_msb <= 32'h0; 
      cfg_interrupt_msix_address_lsb <= 32'h0; 
      current_pba                    <= 32'h0;
    end else begin
      case(state) 
        GET_ADDR2: begin
          cfg_interrupt_msix_address_lsb <= doa; 
        end
        GET_DATA: begin
          cfg_interrupt_msix_address_msb <= doa; 
        end

        READ_PBA: begin
          cfg_interrupt_msix_data        <= doa; 
        end
        WRITE_PBA: begin
          current_pba                    <= doa;
        end
        default: begin
          cfg_interrupt_msix_data        <= cfg_interrupt_msix_data; 
          cfg_interrupt_msix_address_msb <= cfg_interrupt_msix_address_msb; 
          cfg_interrupt_msix_address_lsb <= cfg_interrupt_msix_address_lsb; 
          current_pba                    <= current_pba;
        end
      endcase
    end
  end

  /*
     This process is in charge of updating the BRAM memory (PBA) 
    with the current pending IRQ. It enables the write signal 
    and writes to dia the new value. The direction is specified in the
    next process.
  */
  always @(negedge rst_n or posedge clk) begin
    if(~rst_n) begin
      dia     <= 32'h0; 
      enawren <= 1'b0;
    end else begin
      case(state)
        WRITE_PBA: begin
          dia     <= doa | irq_pba;
          enawren <= 1'b1;
        end
        CLEAR_PBA: begin
          if(cfg_interrupt_msix_sent || cfg_interrupt_msix_fail) begin
            enawren     <= 1'b1;
            dia         <= current_pba & (~irq_pba); 
          end else begin
            enawren     <= 1'b0;
            dia         <= dia;
          end
        end
        WAIT: begin
          enawren <= enawren;
          dia     <= dia;
        end
        default: begin
          enawren <= 1'b0;
          dia     <= dia;
        end
      endcase
    end
  end
  

  /*
    Main FSM. It will assign the PORT A of the BRAM the corresponding direction
    (MSI-x table IRQ data and address and PBA position) according with the current state.
  */
  always @(negedge rst_n or posedge clk) begin
    if(~rst_n) begin
      state                  <= IDLE;
      next_state             <= IDLE;
      irq_number             <= 0;
      irq_pba                <= 32'h0; //Position in the PBA (position in a  32 bit vector)      
    end else begin
      case(state) 
        IDLE: begin /* Check if new IRQs has been asked. */
          if( cfg_interrupt_msix_enable && irq_s != {C_NUM_IRQ_INPUTS{1'b0}} ) begin   
            state   <= TO_BINARY;
          end else begin
            state   <= IDLE;
          end

          irq_number <= 0;
        end
        TO_BINARY:begin  /* Choose one of the asked IRQs (First bit  active from the left. ) */
          for(i=0; i<C_NUM_IRQ_INPUTS; i=i+1) begin
            if(irq_s[i]) begin
              irq_number <= i;
              irq_pba    <= (1<<(i%32));
            end 
          end

          state   <= GET_ADDR1;
        end
        GET_ADDR1: begin /* Read from the RAM address and data*/
          addrardaddr <= 9'h0 + C_MSIX_TABLE_OFFSET  + irq_number*9'h10;

          state       <= WAIT;
          next_state  <= GET_ADDR2;
        end
        GET_ADDR2: begin
          addrardaddr <= 9'h4 + C_MSIX_TABLE_OFFSET  + irq_number*9'h10;

          state       <= WAIT;
          next_state  <= GET_DATA;
        end
        GET_DATA: begin
          addrardaddr <= 9'h8 + C_MSIX_TABLE_OFFSET  + irq_number*9'h10;

          state       <= WAIT;
          next_state  <= READ_PBA;
        end
        READ_PBA: begin /* Get the previous value of the PBA */
          addrardaddr <= C_MSIX_PBA_OFFSET  + ((irq_number/32)<<2);

          state       <= WAIT;
          next_state  <= WRITE_PBA;
        end
        WRITE_PBA: begin /* Add the current IRQ to the PBA */
          addrardaddr <= C_MSIX_PBA_OFFSET  + ((irq_number/32)<<2); 

          state       <= WAIT;
          next_state  <= ACTIVE_IRQ;
        end
        ACTIVE_IRQ: begin /* Activate IRQ and remove the IRQ from the list irq_s */
          state                      <= CLEAR_PBA;
        end
        CLEAR_PBA: begin /* Remove the IRQ from the PBA */
          if(cfg_interrupt_msix_sent || cfg_interrupt_msix_fail) begin
            addrardaddr <= C_MSIX_PBA_OFFSET  + ((irq_number/32)<<2);
            
            state       <= WAIT;
            next_state  <= IDLE;
          end else begin
            state       <= CLEAR_PBA;
          end
        end
        WAIT: begin // one cycle must be wait because addrardaddr is a register. 
                    // The bram will get the correct address in the next pulse.
          state   <= next_state;
        end
        default: begin
          state                    <= IDLE;
          next_state               <= IDLE;
        end
      endcase
    end

  end
endmodule
