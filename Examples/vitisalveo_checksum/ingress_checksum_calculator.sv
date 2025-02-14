`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 02/06/2025 07:13:28 PM
// Design Name:
// Module Name: UDP_checksum
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module ingress_checksum_calculator (

    input  logic        clk,                // Clock signal
    input  logic        rst,              // Active-low reset

    // AXI Stream Input
    input  logic [511:0] s_axis_tdata,      // Input data (512 bits)
    input  logic [63:0]  s_axis_tkeep,      // Input keep signal (64 bits, 1 bit per byte)
    input  logic         s_axis_tlast,      // Input last signal (end of packet)
    output logic         s_axis_tready,     // Input ready signal
    input  logic         s_axis_tvalid,     // Input valid signal

    // Metadata Input
    input  logic [10:0]  metadata_in,       // Input metadata (48 bits)
    input  logic         metadata_valid,    // Metadata valid signal

    //metadata output
    output  logic [43:0]  metadata_out,       // Input metadata (48 bits)
    output  logic         metadata_valid_out,    // Metadata valid signal

    // AXI Stream Output
    output logic [511:0] m_axis_tdata,      // Output data (512 bits)
    output logic [63:0]  m_axis_tkeep,      // Output keep signal (64 bits)
    output logic         m_axis_tlast,      // Output last signal
    input  logic         m_axis_tready,      // Output ready signal
    output logic         m_axis_tvalid     // Output valid signal
);

    // Internal signals
    logic [15:0] checksum;                  // Computed checksum
    logic [15:0] temp_sum;                  // Temporary sum for checksum calculation
    logic [511:0] data_reg;                 // Data register
    logic [63:0]  tkeep_reg;                // tKeep signal register
    logic tlast_reg;                        // tLast signal register
    logic [10:0] meta_reg;                  // Metadata register
    logic [15:0] word_count;                // Word counter for payload
    logic [15:0] counter;                // Word counter for payload
    //logic [15:0] offset_counter;            // Counter to track payload offset
    logic [15:0] payload_offset;            // Payload offset extracted from metadata
    //logic meta_valid_outsig;                //metadata valid out signal
    logic enable;                           //enable for checksum calculation

    //reg [15:0] offset;

typedef enum logic [4:0]{

	IDLE                       = 5'b00001,
	FIRST                      = 5'b00010,
	SECOND                     = 5'b00100,
	THIRD                      = 5'b01000,
	XXRX                       = 5'b10000
	} checksum_FSM;

	checksum_FSM checksum_FSM_current, checksum_FSM_next;


	//state change logic
	always_ff @(posedge clk) begin
	   if (!rst) begin
	       checksum_FSM_current <=IDLE;
	   end
	   else begin
	       checksum_FSM_current <= checksum_FSM_next;
	   end

	end

 always_comb begin : checksum_FSM_next_state
	   checksum_FSM_next <= XXRX;
	   case (checksum_FSM_current)

	       IDLE:
	           if (s_axis_tvalid) begin
                    checksum_FSM_next <= FIRST;
                end else begin
                    checksum_FSM_next <= IDLE;
                end

            FIRST:
               begin
                    if (metadata_valid && s_axis_tvalid) begin
                        checksum_FSM_next <= SECOND;
                    end else begin
                            checksum_FSM_next <= FIRST;
                    end
          end


          SECOND:
                 begin
                    if (word_count > 0) begin
                        checksum_FSM_next  <= SECOND;
                    end else begin
                        checksum_FSM_next  <= THIRD;
                    end
                end


           THIRD:
                begin
                    if (m_axis_tready && tlast_reg) begin
                        checksum_FSM_next  <= IDLE;
                    end else begin
                        checksum_FSM_next  <= THIRD;
                    end
                end



	   endcase
	end

  //output logic
  always_ff @(posedge clk ) begin
        if (!rst) begin
            metadata_valid_out <= 1'b0;
            s_axis_tready <=1'b0;
            checksum <= 16'h0000;
            temp_sum <= 16'h0000;
            data_reg <= 512'b0;
            tkeep_reg <= 64'b0;
            meta_reg <= 11'b0;
            tlast_reg <= 1'b0;
            word_count <= 16'b0;
            payload_offset <= 16'b0;
            //offset_counter <= 16'b0;
            enable <= 1'b0;
            counter <= 16'b0;
            metadata_out <= 44'b0;
            //offset  <= 16'b0;

         end else begin
            case (checksum_FSM_current)
                IDLE:
                    begin
                    metadata_valid_out <= 1'b0;
                    s_axis_tready <=1'b0;  //set saxis traedy 1
                    checksum <= 16'h0000;
                    temp_sum <= 16'h0000;
                    data_reg <= 512'b0;
                    tkeep_reg <= 64'b0;
                    meta_reg <= 11'b0;
                    tlast_reg <= 1'b0;
                    word_count <= 16'b0;
                    payload_offset <= 16'b0;
                    counter <= 16'b0;
                    enable <= 1'b0;
                    metadata_out <= 44'b0;
                    m_axis_tvalid <= 1'b0;
                        if (s_axis_tvalid) begin
                            s_axis_tready <=1'b1;  //set saxis traedy 1
                            enable <= 1'b1;
                        end else begin
                            metadata_valid_out <= 1'b0;
                            s_axis_tready <=1'b0;  //set saxis traedy 1
                            checksum <= 16'h0000;
                            temp_sum <= 16'h0000;
                            data_reg <= 512'b0;
                            tkeep_reg <= 64'b0;
                            meta_reg <= 11'b0;
                            tlast_reg <= 1'b0;
                            word_count <= 16'b0;
                            payload_offset <= 16'b0;
                            counter <= 16'b0;
                            enable <= 1'b0;
                            metadata_out <= 44'b0;
                            m_axis_tvalid <= 1'b0;
                        end
                    end

                FIRST:
                  begin
                        if (metadata_valid && s_axis_tvalid) begin
                            data_reg <= s_axis_tdata;
                            tkeep_reg <= s_axis_tkeep;
                            meta_reg <= metadata_in;
                            tlast_reg <= s_axis_tlast;
                            payload_offset = metadata_in[10:1];   //get payload offeset value
                            s_axis_tready <= 1'b0;
                            word_count <= 32 - (metadata_in[10:1]/16);              // Initialize word counter
                            temp_sum <= 16'h0000;             // Initialize checksum accumulator
                            enable <= 1'b0;
                            //offset <= meta_reg[15:0]/16;
                            counter <=  (metadata_in[10:1]/16)  ;
                        end
                   end


SECOND:
    begin
        if (word_count > 0)  begin
            int word_index = counter ;
            temp_sum <= temp_sum + s_axis_tdata[(word_index * 16) +: 16];
            word_count = word_count - 1;
            counter = counter + 1;
         end else begin

               temp_sum <= ~temp_sum;
         end

    end


                 THIRD:
                      begin
                            if ( m_axis_tready) begin
                                counter <= 16'b0;
                                //offset <= 1'b0;

                                 m_axis_tvalid <= 1'b1;
                                 m_axis_tdata <= data_reg;
                                 m_axis_tkeep <= tkeep_reg;
                                 m_axis_tlast <= tlast_reg;
                                 metadata_out <= {27'b0, temp_sum, meta_reg[0]};
                                 metadata_valid_out <= 1'b1;
                            end else begin
                                s_axis_tready <= 1'b0;
                                data_reg <= s_axis_tdata;
                                tkeep_reg <= s_axis_tkeep;
                                meta_reg <= metadata_in;
                                tlast_reg <= s_axis_tlast;
                                payload_offset = metadata_in[10:1];
                                enable <= 1'b1;
                                m_axis_tvalid <= 1'b0;
                                metadata_valid_out <= 1'b0;

                            end
                    end




		      XXRX :
		          begin
                    metadata_valid_out <= 1'b0;
                    s_axis_tready <=1'b0;
                    checksum <= 16'h0000;
                    temp_sum <= 16'h0000;
                    data_reg <= 512'b0;
                    tkeep_reg <= 64'b0;
                    meta_reg <= 11'b0;
                    tlast_reg <= 1'b0;
                    word_count <= 16'b0;
                    payload_offset <= 16'b0;
                    //offset_counter <= 16'b0;
                    enable <= 1'b0;
                    metadata_out <= 44'b0;
		          end
	      endcase
	   end
	end



endmodule

