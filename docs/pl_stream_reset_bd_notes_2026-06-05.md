# PL stream reset BD notes

Scope: `code/pusu_20260604` PL DSP stream path.

## Register contract

- `CONTROL[0]` remains the persistent PL DSP enable bit.
- `CONTROL[1]` soft reset, `CONTROL[2]` clear status, `CONTROL[3]` mode update, and `CONTROL[4]` abort remain write-pulse controls.
- `CONTROL[5]` is the persistent `stream_reset` request. Write `1` to hold the PL stream and FIFO in reset, write `0` to release.
- `STATUS[7]` is `stream_reset_active`, after synchronization into the PL DSP `aclk` domain. Existing `STATUS[6:0]` meanings are kept.

## Block Design wiring

Connect:

- `pusu_pl_dsp_axi_regs_0/pl_stream_reset` to `pusu_pl_dsp_core_0/stream_reset`
- `pusu_pl_dsp_core_0/axis_fifo_aresetn` to `axis_data_fifo_0/s_axis_aresetn`

This direct resetn connection assumes `pusu_pl_dsp_core_0/aclk` and `axis_data_fifo_0/s_axis_aclk` are the same clock domain. If the FIFO S_AXIS clock is changed later, keep `stream_reset` synchronized to that S_AXIS clock before driving `s_axis_aresetn`.

## PS-side sequence

The intended DMA-arm sequence is:

1. Set `CONTROL[5]=1`.
2. Optionally update RBW/output/frame registers and pulse `CONTROL[3]`.
3. Wait until `STATUS[7]=1`.
4. Reset/arm AXI DMA S2MM for the next 4096-word transfer.
5. Set `CONTROL[5]=0`.
6. Optionally wait until `STATUS[7]=0`, then wait for DMA completion.

While `stream_reset` is active, `pusu_pl_dsp_core` holds `s_axis_tready=0`, clears `m_axis_tvalid`, `m_axis_tlast`, `packet_count`, `decim_count`, and the I/Q accumulators. After release, the next emitted word starts from `packet_count=0`, so the next TLAST is generated after the configured `frame_words` count, normally 4096 words.
