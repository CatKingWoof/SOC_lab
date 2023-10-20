`timescale 1ns / 1ps
module fir
       #(  parameter pADDR_WIDTH = 12,
           parameter pDATA_WIDTH = 32,
           parameter Tape_Num    = 11
        )
       (
           //axilite interface==============================
           //write(input)--
           output  wire                     awready,
           output  wire                     wready,
           input   wire                     awvalid,
           input   wire [(pADDR_WIDTH-1):0] awaddr,
           input   wire                     wvalid,
           input   wire [(pDATA_WIDTH-1):0] wdata,
           //read(output)---
           output  wire                     arready,
           input   wire                     rready,
           input   wire                     arvalid,
           input   wire [(pADDR_WIDTH-1):0] araddr,
           output  wire                     rvalid,
           output  wire [(pDATA_WIDTH-1):0] rdata,
           //stream slave (input data)=========================
           input   wire                     ss_tvalid,
           input   wire [(pDATA_WIDTH-1):0] ss_tdata,
           input   wire                     ss_tlast,
           output  reg                     ss_tready,
           //stream master (output data)=======================
           input   wire                     sm_tready,
           output  reg                     sm_tvalid,
           output  reg [(pDATA_WIDTH-1):0] sm_tdata,
           output  reg                     sm_tlast,

           // bram for tap RAM
           output  reg [3:0]               tap_WE,
           output  wire                     tap_EN,
           output  reg [(pDATA_WIDTH-1):0] tap_Di,
           output  reg [(pADDR_WIDTH-1):0] tap_A,
           input   wire [(pDATA_WIDTH-1):0] tap_Do,

           // bram for data RAM
           output  reg [3:0]               data_WE,
           output  wire                     data_EN,
           output  reg [(pDATA_WIDTH-1):0] data_Di,
           output  reg [(pADDR_WIDTH-1):0] data_A,
           input   wire [(pDATA_WIDTH-1):0] data_Do,

           input   wire                     axis_clk,
           input   wire                     axis_rst_n
       );
parameter idle=0,
          setup = 1,
          set_start_fir=2,
          warmup=3,
          done_fir=4;
reg [2:0] current_state,next_state;
reg ap_start,ap_done,ap_idle;
reg [3:0] counter,iter;
reg rrflag,wflag;
reg [9:0] stream_out_count;
always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n)
    begin
        current_state<=idle;
    end
    else
        current_state<=next_state;
end
always @(*) begin
    case (current_state)
        idle:
        begin
            next_state=setup;
        end
        setup:
        begin
            if(awaddr==0 && wdata=={1'b1,1'b0,1'b0,29'b0} && tap_EN && tap_WE) //ap_start==1
                next_state=set_start_fir;
            else
                next_state=setup;
        end
        set_start_fir:
        begin
            if(ss_tvalid==1)
                next_state=warmup;
            else
                next_state=set_start_fir;
        end
        warmup:
        begin
            if(stream_out_count==600)
                next_state=done_fir;
            else
                next_state=warmup;
        end
        done_fir:
        begin
            next_state=set_start_fir;
        end
        default: next_state=idle;
    endcase
end


// notice that before changing block status,evertyhing should be settled
assign tap_EN=1;
always @(*) begin
    if(current_state==idle)
        tap_WE='b1111;
    else if(current_state==setup)
    begin
        if(wvalid && wready)
            tap_WE='b1111;
        else
            tap_WE='b0000;
    end
    else if(current_state==set_start_fir)
    begin
        tap_WE='b1000;
    end
    else if(current_state==done_fir)
    begin
        tap_WE='b1000;
    end
    else
        tap_WE='b0000;
end
always @(*) begin
    if(current_state==idle)
        tap_A=0;
    else if(current_state==setup)
    begin
        if(wvalid)
            tap_A=awaddr;
        else if(arvalid)
            tap_A=araddr;
        else
            tap_A=0;
    end
    else if(current_state==set_start_fir)
        tap_A=0;
    else if(current_state==done_fir)
        tap_A=0;
    else if(current_state==warmup)
        tap_A=(counter+1)<<2;
    else
    begin
        tap_A=0;
    end
end
always @(*) begin
    if(current_state==idle)
        tap_Di={1'b0,1'b0,1'b1,29'b0};
    else if(current_state==setup)
    begin
        if(tap_WE)
            tap_Di=wdata;
        else
            tap_Di=0;
    end
    else if(current_state==set_start_fir)
        tap_Di={1'b0,1'b0,1'b0,29'b0};
    else if(current_state==done_fir)
        tap_Di={1'b0,1'b1,1'b1,29'b0};
    else
    begin
        tap_Di=0;
    end
end
//assign rdata=tap_Do;


//axi-write 1.length 2.tap parameter 3.ap_start=1 (addreess with data)
// --------------------------------------------------------------------------------------------------------
// clk        :__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__
// aw/wdata   :|x|0          |1         |2
// aw/wvalid  :__/▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔

// aw/wready  :________/▔▔\______/▔▔\____
// ---------------------------------------------------------------------------------------------------------

assign awready=1;
assign wready=1;

//axi-read
//read request->read data is continuos controlled by rvalid
// --------------------------------------------------------------------------------------------------------
// clk        :__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__
// araddr     :  |addr1            |addr2           |addr3
// arvalid:   :__/▔▔▔▔▔\______/▔▔▔▔\________/▔▔▔▔\________

// arready always 1 if tap RAM address=araddr
// arready    :▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
// ---------------------------------------------------------------------------------------------------------
// rready     :__/▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
//need 1cycle to read tap RAM data then pull rdata and rvalid

// rdata      :|x      |0              |1         |2
// rvalid     :________/▔▔\__________/▔▔\_____/▔▔\
// ---------------------------------------------------------------------------------------------------------
assign arready=1;
always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n)
        rrflag<=0;
    else
    begin
        if(current_state==setup)
        begin
            if(arvalid && rrflag==0)
                rrflag<=1;
            else
                rrflag<=0;
        end
        else
            rrflag<=0;
    end
end
assign rdata=(rrflag)? tap_Do : 0;
assign rvalid=(rrflag)? 1 : 0;


//data_ram

reg add_reset;
reg [(pADDR_WIDTH-1):0] Din_addr;
wire signed [(pDATA_WIDTH-1):0] mult_in1,mult_in2;
reg  signed[(pDATA_WIDTH-1):0] mult_out;
wire signed [(pDATA_WIDTH-1):0] add_in1,add_in2;
reg  signed[(pDATA_WIDTH-1):0] add_out;
reg out1,out2,out3;
reg [3:0]offset;
//assign Din_addr=(iter-counter)<<2;
always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n)
        Din_addr<=0;
    else
    begin
        if(current_state==set_start_fir)
            Din_addr<=0;
        else if(current_state==warmup)
        begin
            if(counter==iter)
                Din_addr<=((iter+offset)%11)<<2;
            else
            begin
                if(Din_addr==0)
                    Din_addr<=40;
                else
                    Din_addr<=Din_addr-4;
            end
        end
    end
end
assign data_EN=1;
always @(posedge axis_clk or negedge axis_rst_n ) begin
    if(!axis_rst_n)
        data_WE<='b0000;
    else
    begin
        if(current_state==set_start_fir)
            data_WE<='b1111;
        else if(current_state==warmup)
        begin
            if(counter==iter)
                data_WE<='b1111;
            else
                data_WE<='b0000;
        end
    end
end
always @(*) begin
    if(current_state==warmup)
        data_Di=ss_tdata;
    else
        data_Di=0;
end
always @(*) begin
    if(current_state==warmup)
        data_A=Din_addr;
    else
        data_A=0;
end
reg dram_valid;
//ALU
always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n)
        mult_out<=0;
    else
    begin
        mult_out<=mult_in1*mult_in2;
    end
end
assign mult_in1=tap_Do;
assign mult_in2=data_Do;
always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n)
        add_out<=0;
    else
    begin
        if(current_state==warmup && dram_valid)
        begin
            if(out3)
                add_out<=mult_out;
            else
                add_out<= add_in1+add_in2;
        end
    end
end
assign add_in1=mult_out;
assign add_in2=add_out;
always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n)
        counter<=0;
    else
    begin
        if(current_state ==set_start_fir)
            counter<=0;
        else if(current_state == warmup)
        begin
            if(counter== iter)
                counter<=0;
            else
                counter<=counter+1;
        end
    end
end
always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n)
        iter<=0;
    else
    begin
        if(current_state==set_start_fir)
            iter<=0;
        else if(current_state==warmup)
        begin
            if(counter==iter)
            begin
                if(iter == 10)
                    iter<=iter;
                else
                    iter<=iter+1;
            end
        end
    end
end
always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n)
        offset<=0;
    else
    begin
        if(current_state==set_start_fir)
            offset<=1;
        else
            if(current_state==warmup)
            begin
                if(iter<10)
                    offset<=1;
                else if(counter==iter)
                begin
                    offset<=(offset+1)%11;
                end
            end
    end
end
always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n)
        dram_valid<=0;
    else
    begin
        if(current_state==set_start_fir)
            dram_valid<=0;
        else if(current_state==warmup)
        begin
            if(out1)
                dram_valid<=1;
        end
    end
end

//axi-ss : input Din  use tready=1 to get the next input
// --------------------------------------------------------------------------------------------------------
// clk     :__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__
// tdata   :|x|0          |1         |2
// tvalid  :▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
// tlast   :_______________________________/▔▔\_______

// tready  :________/▔▔\______/▔▔\______/▔▔\____
// ---------------------------------------------------------------------------------------------------------
always @(posedge axis_clk or negedge axis_rst_n ) begin
    if(!axis_rst_n)
        ss_tready<='b0;
    else
    begin
        if(current_state==set_start_fir)
        begin
            if(ss_tvalid)
                ss_tready<='b1;
        end
        else if(current_state==warmup)
        begin
            if(counter==iter)
                ss_tready<='b1;
            else
                ss_tready<='b0;
        end
    end
end


//axi-sm :output Dout use sm_tvalid=1 to trasmit an answer
// --------------------------------------------------------------------------------------------------------
// clk     :__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__/▔\__
// tready  :▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔

// tdata   :|x|0          |1         |2
// tvalid  :________/▔▔\______/▔▔\______/▔▔\____
// tlast   :_______________________________/▔▔\_______
// ---------------------------------------------------------------------------------------------------------

always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n)
        out1<=0;
    else if(current_state==warmup)
        out1<=(counter == iter);
end
always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n)
        out2<=0;
    else if(current_state==warmup)
        out2<=out1;
end
always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n)
        out3<=0;
    else if(current_state==warmup)
        out3<=out2;
end
always @(*) begin
    sm_tdata=add_out;
end
always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n)
        sm_tvalid<=0;
    else
    begin
        if(current_state==warmup)
        begin
            if(out2)
                sm_tvalid<=1;
            else
                sm_tvalid<=0;
        end
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n)
        stream_out_count<=0;
    else
    begin
        if(current_state==set_start_fir)
            stream_out_count<=0;
        else
            if(current_state==warmup)
            begin
                if(sm_tvalid==1)
                    stream_out_count<=stream_out_count+1;
            end
    end
end


endmodule
