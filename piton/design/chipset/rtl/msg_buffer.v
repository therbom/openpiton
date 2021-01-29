/*
 *  Copyright (C) 2021 Marco Brohet
 *
 *  All rights reserved.
 *
 *  This module buffers incoming NoC messages completely, before handing it
 *  over to the module attached to this module's outputs.
 */

`include "define.tmp.h"

module msg_buffer (
    input wire                       clk,
    input wire                       rst_n,

    /* Input data. */
    input wire [`NOC_DATA_WIDTH-1:0] data_in,
    input wire                       valid_in,
    output reg                       ready_in,

    /* Output data. */
    output reg [`NOC_DATA_WIDTH-1:0] data_out,
    output reg                       valid_out,
    input wire                       ready_out
);

wire valid_and_ready_in, valid_and_ready_out;

assign valid_and_ready_in = valid_in && ready_in;
assign valid_and_ready_out = valid_out && ready_out;


/*
 *  States for the finite state machine of this module.
 *  We are either receiving a message, processing it or sending it.
 */
localparam STATE_RECEIVING  = 2'd0;
//localparam STATE_PROCESSING = 2'd1;
localparam STATE_SENDING    = 2'd2;

reg [1:0] state, state_next;


/*
 *  Buffer for the entire message.
 */
localparam MSG_BUF_IDX_HDR_0 = 4'd0;

reg [`NOC_DATA_WIDTH-1:0] msg_buf [8:0];
reg [3:0] msg_buf_idx, msg_buf_idx_next;


/*
 *  Extract the number of remaining flits from the first header flit.
 *  Note that this is a bit complicated, because we already need to know this
 *  number when we are receiving the first header flit. Since we then need
 *  to decide whether to wait for the next flit or go on sending it.
 */
wire [3:0] curr_remaining_flits;
reg [3:0] remaining_flits, real_remaining_flits;

assign curr_remaining_flits = data_in[`MSG_LENGTH];

always @ *
begin
    real_remaining_flits = remaining_flits;

    if (valid_and_ready_in && msg_buf_idx == MSG_BUF_IDX_HDR_0)
    begin
        real_remaining_flits = curr_remaining_flits;
    end
end

always @ (posedge clk)
begin
    if (!rst_n)
    begin
        remaining_flits <= 4'd1;
    end
    else if (valid_and_ready_in && msg_buf_idx == MSG_BUF_IDX_HDR_0)
    begin
        remaining_flits <= curr_remaining_flits;
    end
end


/*
 *  Determine the state, i.e. if we are still receiving the current message, or
 *  if we are sending the currently buffered message.
 */
always @ *
begin
    state_next = state;

    if (!rst_n)
    begin
        state_next = STATE_RECEIVING;
    end
    else if (msg_buf_idx == real_remaining_flits)
    begin
        if (valid_and_ready_in)
        begin
            state_next = STATE_SENDING;

            $display(" >>>> msg_buffer: [ RECEIVING ] Transitioning to SENDING");
        end
        else if (valid_and_ready_out)
        begin
            state_next = STATE_RECEIVING;

            $display(" >>>> msg_buffer: [  SENDING  ] Transitioning to RECEIVING");
        end
    end
end


/*
 *  Note: Just "data_out = msg_buf[msg_buf_idx]" resulted in timing constraints
 *  not being met in Vivado 2018.2.
 */
always @ (posedge clk)
begin
    state <= state_next;

    if (state_next == STATE_SENDING)
    begin
        data_out <= msg_buf[msg_buf_idx_next];
    end
end


always @ *
begin
    msg_buf_idx_next = msg_buf_idx;

    if (!rst_n || state != state_next)
    begin
        msg_buf_idx_next = 4'd0;
    end
    else if (valid_and_ready_in || valid_and_ready_out)
    begin
        msg_buf_idx_next = msg_buf_idx + 4'd1;

        if (state == STATE_RECEIVING)
        begin
            $display(" >>>> msg_buffer: [ RECEIVING ] Processed flit no. %d", msg_buf_idx);
        end
        else if (state == STATE_SENDING)
        begin
            $display(" >>>> msg_buffer: [  SENDING  ] Processed flit no. %d", msg_buf_idx);
        end
    end
end

always @ (posedge clk)
begin
    msg_buf_idx <= msg_buf_idx_next;
end


always @ *
begin
    ready_in = state == STATE_RECEIVING;
end


always @ (posedge clk)
begin
    if (valid_and_ready_in)
    begin
        msg_buf[msg_buf_idx] <= data_in;
    end
end


always @ *
begin
    valid_out = state == STATE_SENDING;
end

endmodule
