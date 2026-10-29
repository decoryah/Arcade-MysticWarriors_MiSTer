// Full-system bench wrapper: mw_core behind the real MiSTer memory subsystem
// (target/mister/mw_mem.sv: the loader, the caches and the SDRAM controller) and a
// behavioural SDRAM chip. The ROM image goes in through the loader's byte port exactly
// as the HPS delivers it, so the loader's placing of the regions is part of what is tested.
// (This board has no DDR3 client: the flip buffers of the platform layer are outside the machine.)
`default_nettype none

module tb_mw_top #(
    parameter int STEP_COST_BUS = 16,
    parameter int STEP_COST_INT = 8     // the interrupts and the sprite list's instant are mw_core's (MAME's)
) (
    input  logic        clk,
    input  logic        reset,          // the platform's reset: SDRAM init and the machine
    input  logic        dl_hold,        // an image is loading: the machine stays in reset
    input  logic        dl_start,
    input  logic        dl_we, input logic [24:0] dl_addr, input logic [7:0] dl_data,
    output logic        dl_wait,
    output logic        mem_ready,

    input  logic        eep_we, input logic [6:0] eep_waddr, input logic [7:0] eep_wdata,
    input  logic [15:0] in_p1_p2,
    input  logic [15:0] in_p3_p4,
    input  logic  [7:0] in0,
    input  logic  [7:0] in1,

    output logic        cen_pix,
    output logic [23:0] rgb,
    output logic        hsync, vsync, de, vblank,
    output logic [23:0] dbg_addr,
    output logic [15:0] dbg_data,
    output logic  [1:0] dbg_busstate,
    output logic        dbg_step, dbg_irq2, dbg_irq4, dbg_overrun, dbg_overrun_line, dbg_unsupported, dbg_shadow_overlap,
    output logic  [7:0] dbg_irq_ctrl,
    output logic  [2:0] dbg_overrun_src,
    output logic        dbg_spr_we,
    output logic  [9:0] dbg_objcount,
    output logic  [8:0] dbg_vcount,
    output logic [15:0] dbg_zpc,
    output logic        dbg_zstep, dbg_zwait, dbg_zwr, dbg_zrd,
    output logic  [7:0] dbg_zwdata,
    output logic [15:0] snd_l, snd_r,
    output logic        snd_valid,
    output logic  [7:0] eep_q,
    output logic        eep_dirty
);
    logic        prog_req, prog_ack, tile_req, tile_ack, spr_req, spr_ack;
    logic [22:1] prog_addr; logic [18:0] tile_addr; logic [19:0] spr_addr;
    logic [15:0] prog_q; logic [39:0] tile_q; logic [79:0] spr_q;
    // read by the C++ bench's ROM check (ROMCHK=1)
    logic        chk_tile_ack /*verilator public_flat_rd*/, chk_spr_ack /*verilator public_flat_rd*/;
    logic        chk_spr_req /*verilator public_flat_rd*/;
    assign chk_spr_req = spr_req;
    logic [18:0] chk_tile_addr /*verilator public_flat_rd*/;
    logic [39:0] chk_tile_q /*verilator public_flat_rd*/;
    logic [19:0] chk_spr_addr /*verilator public_flat_rd*/;
    logic [79:0] chk_spr_q /*verilator public_flat_rd*/;
    assign chk_tile_ack = tile_ack; assign chk_tile_addr = tile_addr; assign chk_tile_q = tile_q;
    assign chk_spr_ack  = spr_ack;  assign chk_spr_addr  = spr_addr;  assign chk_spr_q  = spr_q;
    logic        srom_req, srom_ack, pcmr_req, pcmr_ack;
    logic [17:0] srom_addr; logic [21:0] pcmr_addr;
    logic  [7:0] srom_q, pcmr_q;
    logic        vram_req, vram_we, vram_ack;
    logic [15:0] vram_addr, vram_wdata, vram_q;
    logic  [1:0] vram_be;

    wire  [15:0] dram_dq; wire [12:0] dram_a; wire [1:0] dram_ba, dram_dqm;
    wire         dram_clk, dram_cke, dram_ras_n, dram_cas_n, dram_we_n;

    mw_mem u_mem (
        .clk(clk), .clk_sdram(clk), .init(reset), .dl_start(dl_start), .ready(mem_ready), .rd_late(1'b0), .burst_slow(1'b0),
        .test_start(1'b0), .test_run(), .test_done(), .test_ok(), .test_stable(), .vram_ok(), .vram_bad(),
        .dl_we(dl_we), .dl_addr(dl_addr), .dl_data(dl_data), .dl_wait(dl_wait),
        .fl_go(1'b0), .fl_len(25'd0), .fl_done(),
        .ddr_rd(), .ddr_addr(), .ddr_burst(), .ddr_busy(1'b0), .ddr_dout(64'd0), .ddr_dready(1'b0),
        .prog_req(prog_req), .prog_addr(prog_addr), .prog_ack(prog_ack), .prog_q(prog_q),
        .tile_req(tile_req), .tile_addr(tile_addr), .tile_ack(tile_ack), .tile_q(tile_q),
        .spr_req(spr_req), .spr_addr(spr_addr), .spr_ack(spr_ack), .spr_q(spr_q),
        .snd_req(srom_req), .snd_addr(srom_addr), .snd_ack(srom_ack), .snd_q(srom_q),
        .pcm_req(pcmr_req), .pcm_addr(pcmr_addr), .pcm_ack(pcmr_ack), .pcm_q(pcmr_q),
        .vram_req(vram_req), .vram_we(vram_we), .vram_addr(vram_addr), .vram_be(vram_be), .vram_wdata(vram_wdata),
        .vram_ack(vram_ack), .vram_q(vram_q),
        .dram_dq(dram_dq), .dram_a(dram_a), .dram_ba(dram_ba), .dram_dqm(dram_dqm),
        .dram_clk(dram_clk), .dram_cke(dram_cke), .dram_ras_n(dram_ras_n), .dram_cas_n(dram_cas_n), .dram_we_n(dram_we_n)
    );
    sdram_model #(.PHASE_LAG(0), .AW(24)) chip (
        .clk(clk), .dq(dram_dq), .a(dram_a), .ba(dram_ba), .dqml(dram_dqm[0]), .dqmh(dram_dqm[1]),
        .cs_n(1'b0), .ras_n(dram_ras_n), .cas_n(dram_cas_n), .we_n(dram_we_n), .cke(dram_cke)
    );

    // the machine waits for the memories and for the image, as MysticWarriors.sv does
    wire core_reset = reset | ~mem_ready | dl_hold;
    mw_core #(.HEXDIR("../rtl/data"), .STEP_COST_BUS(STEP_COST_BUS), .STEP_COST_INT(STEP_COST_INT)) u_core (
        .clk(clk), .reset(core_reset), .vid_reset(reset),
        .prog_req(prog_req), .prog_addr(prog_addr), .prog_ack(prog_ack), .prog_q(prog_q),
        .tile_req(tile_req), .tile_addr(tile_addr), .tile_ack(tile_ack), .tile_q(tile_q),
        .spr_req(spr_req), .spr_addr(spr_addr), .spr_ack(spr_ack), .spr_q(spr_q),
        .vram_req(vram_req), .vram_we(vram_we), .vram_addr(vram_addr), .vram_be(vram_be), .vram_wdata(vram_wdata),
        .vram_ack(vram_ack), .vram_q(vram_q),
        .snd_rom_req(srom_req), .snd_rom_addr(srom_addr), .snd_rom_ack(srom_ack), .snd_rom_q(srom_q),
        .pcm_req(pcmr_req), .pcm_addr(pcmr_addr), .pcm_ack(pcmr_ack), .pcm_q(pcmr_q),
        .eep_ld_we(eep_we), .eep_ld_addr(eep_waddr), .eep_ld_wdata(eep_wdata), .eep_ld_q(eep_q), .eep_dirty(eep_dirty),
        .in_p1_p2(in_p1_p2), .in_p3_p4(in_p3_p4), .in0(in0), .in1(in1),
        .cen_pix(cen_pix), .rgb(rgb), .bri(), .bri_post(1'b0), .hsync(hsync), .vsync(vsync), .de(de), .vblank(vblank),
        .snd_l(snd_l), .snd_r(snd_r), .snd_valid(snd_valid),
        .dbg_addr(dbg_addr), .dbg_data(dbg_data), .dbg_busstate(dbg_busstate), .dbg_step(dbg_step),
        .dbg_irq2(dbg_irq2), .dbg_irq4(dbg_irq4), .dbg_irq_ctrl(dbg_irq_ctrl),
        .dbg_overrun(dbg_overrun), .dbg_overrun_line(dbg_overrun_line), .dbg_overrun_src(dbg_overrun_src),
        .dbg_draw_objs(), .dbg_draw_rows(), .dbg_draw_cols(), .dbg_draw_pxw(),
        .dbg_spr_we(dbg_spr_we), .dbg_k55(),
        .dbg_unsupported(dbg_unsupported), .dbg_shadow_overlap(dbg_shadow_overlap),
        .dbg_objcount(dbg_objcount), .dbg_vcount(dbg_vcount), .dbg_zpc(dbg_zpc), .dbg_zstep(dbg_zstep), .dbg_zwait(dbg_zwait),
        .dbg_zwr(dbg_zwr), .dbg_zrd(dbg_zrd), .dbg_zwdata(dbg_zwdata)
    );
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused = ^{dram_clk};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
