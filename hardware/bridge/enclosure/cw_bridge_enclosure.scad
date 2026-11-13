// =============================================================================
//  CW Bridge rev 2.1 PCB enclosure — two-part screw-together box.
//
//  * Base tray: the 100 x 80 mm cw_bridge PCB sits on four corner posts with
//    the 1S LiPo cell underneath it. Side-wall openings for USB-C (rear),
//    power slide switch (rear), SMA antenna bulkhead (rear), USB-A host port
//    (right), a window to reach the RUN/FLASH slide switch SW3
//    (right) and the two 3.5 mm TRS jacks (left). A small gutter beside the
//    rear-left corner lets the battery lead come up from under the board to
//    the J10 header.
//  * Lid: carries the front-panel parts — 0.96" I2C OLED on four M2 bosses,
//    KY-040 encoder, 3x 12 mm panel buttons (BTN1-3) + 2 small ones (RESET, BOOT), 3x 5 mm
//    LED holders.
//    Four spacer tubes hang from the lid onto the PCB's corner holes.
//  * Fasteners: 4x M3 from BELOW. Each screw goes up through a counterbore in
//    the floor, the post, the PCB mounting hole, and threads into the lid
//    tube. One set of screws clamps both the PCB and the lid.
//
//  Coordinates: X = PCB left -> right  (KiCad x - 50)
//               Y = PCB front -> rear  (130 - KiCad y)
//               Z = up, 0 at the underside of the base; PCB top = board_z.
//  (0,0) is the PCB's front-left corner. Positions below are taken from
//  hardware/bridge/cw_bridge.kicad_pcb (rev 2.1, 2026-09-28) and the
//  connector datasheets / KiCad STEP models. Panel-part dimensions are
//  typical values — see README.md "Verify before printing".
//
//  Set `part`, press F6 (render), then export STL.
// =============================================================================

/* [What to render] */
part = "assembly";   // "base" | "lid" | "spacers" | "assembly" (assembly = fit check only, don't print)
// "acrylic": laser-cut 3 mm top (make_lid_panel.py -> lid_panel.svg/.xcs), four
//            printed spacer tubes, M3 screws from the TOP into the floor posts.
// "printed": the 3D-printed lid with integral tubes, M3 screws from BELOW.
lid_style = "acrylic";
acrylic_t = 3.0;     // sheet thickness
$fn = 48;

/* [Shell] */
wall      = 2.4;     // side wall thickness
floor_t   = 3.0;     // base floor (must hold the screw-head counterbore)
lid_t     = 2.4;     // lid plate thickness
corner_r  = 3.0;     // outer vertical-edge radius
fit       = 0.4;     // gap between PCB edge and cavity wall, each side
standoff  = 8.0;     // floor top -> PCB underside (the battery lives here)
top_clear = 27.0;    // PCB top -> lid underside (tallest lid part + tallest board part under it)
lip_h     = 3.0;     // lid alignment lip, depth into the cavity
lip_t     = 1.2;     // lip thickness
lip_fit   = 0.3;     // lip clearance to the cavity wall

/* [PCB] */
pcb_l = 100;  pcb_w = 80;  pcb_t = 1.6;
hole_in = 4;         // H1..H4 are 4 mm in from each corner
holes = [[hole_in, hole_in], [pcb_l - hole_in, hole_in],
         [hole_in, pcb_w - hole_in], [pcb_l - hole_in, pcb_w - hole_in]];

/* [Fasteners] */
post_d   = 7.5;      // floor post under each PCB hole
screw_d  = 3.4;      // M3 clearance through floor, post and PCB
head_d   = 6.5;      // screw-head counterbore on the underside
head_h   = 2.2;
tube_d   = 7.0;      // lid spacer tube (lands on the PCB corner)
thread_d = 2.5;      // 2.5 = M3 self-tapping; 4.0 = M3 heat-set insert, in the floor posts.
                     // Both tops screw down from above into the posts, so one base fits either.
thread_h = 9.0;
oled_m2_d = 2.2;     // M2 clearance in the acrylic for the OLED screws

/* [Battery - EEMB 1100 mAh 603449-class pouch, flat under the PCB] */
bat_l    = 49;  bat_w = 34;  bat_t = 6.0;   // measure yours
bat_clr  = 1.0;      // pocket clearance per side
bat_x    = 25;  bat_y = 24;                 // pocket origin (clear of all THT pins)
frame_h  = 2.5;      // retaining corner height
frame_t  = 1.6;
frame_leg = 8;
gutter_w  = 4.0;     // lead gutter beside the rear-left corner (left wall)
gutter_y0 = 65;  gutter_y1 = 79;

/* [Rear wall ports (Y = rear)] */
usbc_x     = 83.0;   // J9 centre (KiCad x 133)
usbc_port  = [13.5, 7.5];   // plug-overmold opening, centred 1.65 mm above the PCB
usbc_zc    = 1.65;
sw2_x      = 26.0;   // SW2 PCM12 power switch (KiCad x 76), actuator at the board edge
sw2_slot   = [8.0, 3.5];    // slot, bottom 0.5 mm below the PCB top
sma_x      = 66.0;   // SMA bulkhead for the U.FL pigtail
sma_d      = 6.6;    // 1/4-36 bulkhead thread
sma_z      = 14.0;   // hole centre above the PCB top

/* [Right wall port (X = right)] */
usba_y     = 49.7;   // J1 centre (KiCad y 80.3); shell is 1.2 mm proud of the PCB edge
usba_inner = [14.2, 8.0];   // receptacle shell opening, from 0.5 mm below the PCB top
usba_outer = [16.5, 9.5];   // plug-overmold opening, centred 3.3 mm above the PCB
usba_zc    = 3.3;
usba_step  = 1.2;    // wall thickness kept at the receptacle-size opening

/* [Left wall ports - CUI SJ1-3515N TRS jacks] */
trs_y      = [58.0, 32.0];  // J8 AUDIO IN (KiCad y 72), J7 AUDIO OUT (KiCad y 98)
trs_zc     = 3.0;    // plug axis above the PCB (datasheet)
trs_bush_d = 6.8;    // bushing is 6.0, protrudes 1.3 mm past the PCB edge
trs_plug_d = 11.0;   // plug overmold bore through the rest of the wall
trs_step   = 1.0;

/* [Lid - OLED 0.96" 128x64 I2C module] */
oled_c      = [15.15, 56.14]; // module centre (from the hand-edited lid_panel.xs saved 2026-10-14 08:35)
oled_pcb    = [27.5, 27.8]; // module PCB (X, Y); pin header on the +Y (rear) edge (vendor drawing)
oled_holes  = [23.5, 23.8]; // Ø2.0 holes, 2.0 mm in from each edge (vendor drawing)
oled_boss_d = 4.0;
oled_boss_h = 2.0;          // glass/frame thickness above the module PCB — VERIFY
oled_pilot  = 1.6;          // M2 self-tap
oled_win    = [23.8, 13.0]; // window = visible area 23.74 x 12.86 (active 21.74 x 10.86)
oled_win_dy = 2.1;          // active-area centre is 11.8 mm from the pin edge, PCB centre 13.9 -> 2.1 toward the pins

/* [Lid - KY-040 encoder module] */
// Module-local frame (u, v) centred on the shaft: u across the 19 mm width toward the
// mounting-hole edge, v along the 26 mm length. Geometry from a KY-040 panel footprint
// (CrashOverride85/zc95: 3 mm holes, 13.85 pitch, 8 mm beside the shaft); sellers list a
// 13.75 pitch. MEASURE your module and hold it against a test print before the real one.
enc_c      = [14.06, 22.07];  // shaft centre (from lid_panel.xs)
enc_hole_d = 7.2;             // M7 bushing
enc_rot    = 0;               // module rotation about the shaft, deg: 0 = holes toward +X
enc_pcb    = [19, 26];        // module PCB (u, v)
enc_pcb_c  = [1.45, -0.35];   // PCB centre relative to the shaft (u, v)
enc_holes  = [[8.0, -6.75], [8.0, 7.1]];   // mounting holes (u, v), Ø3 in the module PCB
enc_body   = [11.8, 12.6];    // EC11 metal body footprint (u, v), kept clear of the columns
enc_body_clr = 0.3;
enc_columns = true;           // screw columns on the printed lid
enc_stand  = 6.5;             // MEASURE: module PCB top -> bushing shoulder (EC11 body height).
                              // Column length; the shoulder then seats against the lid underside.
enc_col_d  = 5.0;
enc_col_pilot = 2.1;          // 2.1 = M2.5 self-tapping (module holes are Ø3); 1.6 for M2

/* [Lid - panel buttons: GTIWUNG / PBS-110 7 mm momentary, pre-wired] */
btn_pos = [[40.74, 58.25], [55.74, 58.25], [70.74, 58.25],   // BTN1 BTN2 BTN3 (rear row)
           [31.73, 9.32], [43.21, 9.32]];                    // RESET BOOT (front)
btn_ds  = [7.2, 7.2, 7.2, 7.2, 7.2];   // hole per button, same order (7 mm switch, 1/4" thread)
btn_body_d = 9.5;           // widest part below the panel (nut / body) — assembly ghost only
btn_depth  = 19.0;          // MEASURE: lid underside -> bottom of the solder lugs + heatshrink

/* [Lid - 5 mm LED holders: PWR BT USB] */
led_d   = 6.4;              // VERIFY: clip-style holders ~6.4, bezel-style ~8.0
led_pos = [[68.84, 10.02], [76.84, 10.02], [84.84, 10.02]];   // PWR BT USB (front right)

/* [Right wall - SW3 RUN/FLASH access notch] */
sw3_c       = [97.3, 63];   // KiCad (147.3, 67); body 3.6 x 9, actuator slides along Y
sw3_notch_w = 7.0;          // window width; kept narrow so a web remains next to the USB-A plug pocket
sw3_notch_h = 7.5;          // window from 0.5 mm below the PCB top to 7 mm above it (actuator top ~5.5);
                            // poke the actuator from the side with a pick/fingernail
sw3_skin    = 1.0;          // wall left above the window: thinned from the inside up to the rim
                            // so the actuator clears it while the board goes in
sw3_slot_on = false;        // legacy 4 x 11 lid slot above SW3 (16 mm above the actuator)
sw3_slot    = [4.0, 11.0];

// ============================ derived ========================================
board_z = floor_t + standoff + pcb_t;   // PCB top face
cav_top = board_z + top_clear;          // lid underside = top of the base walls
ox0 = -fit - gutter_w - wall;  ox1 = pcb_l + fit + wall;
oy0 = -fit - wall;             oy1 = pcb_w + fit + wall;
out_l = ox1 - ox0;  out_w = oy1 - oy0;
lid_thk = (lid_style == "acrylic") ? acrylic_t : lid_t;
total_h = cav_top + lid_thk;
echo(str("Outer size: ", out_l, " x ", out_w, " x ", total_h, " mm"));

bx0 = bat_x - bat_clr;  by0 = bat_y - bat_clr;
bx1 = bat_x + bat_l + bat_clr;  by1 = bat_y + bat_w + bat_clr;

module rrect(l, w, h, r) {
    hull() for (x = [r, l - r], y = [r, w - r]) translate([x, y, 0]) cylinder(h = h, r = r);
}
module shell(h) translate([ox0, oy0, 0]) rrect(out_l, out_w, h, corner_r);

module cav2d() translate([-fit, -fit]) square([pcb_l + 2 * fit, pcb_w + 2 * fit]);

module cavity(z0, h) {
    translate([-fit, -fit, z0]) cube([pcb_l + 2 * fit, pcb_w + 2 * fit, h]);
    translate([-fit - gutter_w, gutter_y0, z0]) cube([gutter_w + 0.01, gutter_y1 - gutter_y0, h]);
}

// --- wall cutters (all cut from the outside face inward by `depth`) ---------
module rear_cut(cx, w, h, z0, depth = wall + 1)
    translate([cx - w / 2, oy1 - depth, z0]) cube([w, depth + 0.5, h]);
module rear_hole(cx, d, zc, depth = wall + 1)
    translate([cx, oy1 - depth, zc]) rotate([-90, 0, 0]) cylinder(d = d, h = depth + 0.5);
module right_cut(cy, w, h, z0, depth = wall + 1)
    translate([ox1 - depth, cy - w / 2, z0]) cube([depth + 0.5, w, h]);
module left_hole(cy, d, zc, depth = wall + gutter_w + 1)
    translate([ox0 - 0.5, cy, zc]) rotate([0, 90, 0]) cylinder(d = d, h = depth + 0.5);

module ports() {
    // USB-C J9: single plug-size opening (the plug must reach the receptacle through the wall)
    rear_cut(usbc_x, usbc_port[0], usbc_port[1], board_z + usbc_zc - usbc_port[1] / 2);
    // SW2 power switch slot
    rear_cut(sw2_x, sw2_slot[0], sw2_slot[1], board_z - 0.5);
    // SMA bulkhead
    rear_hole(sma_x, sma_d, board_z + sma_z);
    // USB-A J1: receptacle-size opening through the whole wall, plug-size pocket from outside
    right_cut(usba_y, usba_inner[0], usba_inner[1], board_z - 0.5);
    right_cut(usba_y, usba_outer[0], usba_outer[1], board_z + usba_zc - usba_outer[1] / 2, wall - usba_step);
    // SW3 RUN/FLASH: side window at actuator height
    right_cut(sw3_c[1], sw3_notch_w, sw3_notch_h, board_z - 0.5);
    translate([pcb_l + fit - 0.01, sw3_c[1] - sw3_notch_w / 2, board_z - 0.5])
        cube([wall - sw3_skin + 0.01, sw3_notch_w, cav_top - board_z + 1.5]);
    // TRS jacks: bushing-size hole through, plug-size bore from outside
    for (y = trs_y) {
        left_hole(y, trs_bush_d, board_z + trs_zc);
        left_hole(y, trs_plug_d, board_z + trs_zc, wall + gutter_w - trs_step);
    }
}

module battery_frame() difference() {
    translate([bx0 - frame_t, by0 - frame_t, floor_t - 0.01])
        cube([bx1 - bx0 + 2 * frame_t, by1 - by0 + 2 * frame_t, frame_h]);
    translate([bx0, by0, floor_t - 1]) cube([bx1 - bx0, by1 - by0, frame_h + 2]);
    translate([bx0 + frame_leg, by0 - frame_t - 1, floor_t - 1])
        cube([bx1 - bx0 - 2 * frame_leg, by1 - by0 + 2 * frame_t + 2, frame_h + 2]);
    translate([bx0 - frame_t - 1, by0 + frame_leg, floor_t - 1])
        cube([bx1 - bx0 + 2 * frame_t + 2, by1 - by0 - 2 * frame_leg, frame_h + 2]);
}

// ================================ BASE ======================================
module base() {
    difference() {
        union() {
            difference() { shell(cav_top); cavity(floor_t, cav_top); }
            for (p = holes) translate([p[0], p[1], 0]) cylinder(d = post_d, h = floor_t + standoff);
            battery_frame();
        }
        for (p = holes)   // screws come from the top (either lid): blind thread in the post
            translate([p[0], p[1], floor_t + standoff - thread_h]) cylinder(d = thread_d, h = thread_h + 1);
        ports();
    }
}

// ================================ LID =======================================
function oled_hole_pts() = [for (sx = [-1, 1], sy = [-1, 1])
    [oled_c[0] + sx * oled_holes[0] / 2, oled_c[1] + sy * oled_holes[1] / 2]];

function enc_pt(p) = [enc_c[0] + p[0] * cos(enc_rot) - p[1] * sin(enc_rot),
                     enc_c[1] + p[0] * sin(enc_rot) + p[1] * cos(enc_rot)];

module enc_body_keepout(z0, h)   // EC11 body + clearance, in place
    translate([enc_c[0], enc_c[1], z0]) rotate(enc_rot)
        translate([-enc_body[0] / 2 - enc_body_clr, -enc_body[1] / 2 - enc_body_clr, 0])
            cube([enc_body[0] + 2 * enc_body_clr, enc_body[1] + 2 * enc_body_clr, h]);

module panel_cutouts(cut_z, cut_h) {   // shared by the printed lid and the acrylic plate
    translate([oled_c[0] - oled_win[0] / 2, oled_c[1] + oled_win_dy - oled_win[1] / 2, cut_z])
        cube([oled_win[0], oled_win[1], cut_h]);
    translate([enc_c[0], enc_c[1], cut_z]) cylinder(d = enc_hole_d, h = cut_h);
    for (i = [0 : len(btn_pos) - 1]) translate([btn_pos[i][0], btn_pos[i][1], cut_z]) cylinder(d = btn_ds[i], h = cut_h);
    for (p = led_pos) translate([p[0], p[1], cut_z]) cylinder(d = led_d, h = cut_h);
    if (sw3_slot_on)
        translate([sw3_c[0] - sw3_slot[0] / 2, sw3_c[1] - sw3_slot[1] / 2, cut_z]) cube([sw3_slot[0], sw3_slot[1], cut_h]);
}

module acrylic_lid() {   // the laser-cut sheet, in place (geometry mirrors make_lid_panel.py)
    difference() {
        translate([ox0, oy0, cav_top]) rrect(out_l, out_w, acrylic_t, corner_r);
        panel_cutouts(cav_top - 1, acrylic_t + 2);
        for (p = holes) translate([p[0], p[1], cav_top - 1]) cylinder(d = screw_d, h = acrylic_t + 2);
        for (h = oled_hole_pts()) translate([h[0], h[1], cav_top - 1]) cylinder(d = oled_m2_d, h = acrylic_t + 2);
    }
}

module spacer() difference() { cylinder(d = tube_d, h = top_clear); translate([0, 0, -1]) cylinder(d = screw_d, h = top_clear + 2); }
module spacers() for (i = [0 : 3]) translate([i * (tube_d + 4), 0, 0]) spacer();   // 4x, print standing up

module lid() {   // the 3D-printed lid, modelled in place, sitting on the base
    cut_z = cav_top - lip_h - 1;
    cut_h = lip_h + lid_t + 2;
    difference() {
        union() {
            translate([ox0, oy0, cav_top]) rrect(out_l, out_w, lid_t, corner_r);
            translate([0, 0, cav_top - lip_h]) linear_extrude(lip_h + 0.01) difference() {
                offset(delta = -lip_fit) cav2d();
                offset(delta = -lip_fit - lip_t) cav2d();
            }
            for (p = holes) translate([p[0], p[1], board_z]) cylinder(d = tube_d, h = top_clear + 0.01);
            for (h = oled_hole_pts()) translate([h[0], h[1], cav_top - oled_boss_h]) cylinder(d = oled_boss_d, h = oled_boss_h + 0.01);
            if (enc_columns) for (q = enc_holes) let (h = enc_pt(q))
                translate([h[0], h[1], cav_top - enc_stand]) cylinder(d = enc_col_d, h = enc_stand + 0.01);
        }
        // M3 from the top: through the plate and tube, the PCB, into the base post
        for (p = holes) translate([p[0], p[1], board_z - 1]) cylinder(d = screw_d, h = top_clear + lid_t + 2);
        panel_cutouts(cut_z, cut_h);
        if (enc_columns) {
            enc_body_keepout(cav_top - enc_stand - 1, enc_stand + 0.99);   // trim the columns off the EC11 body
            for (q = enc_holes) let (h = enc_pt(q))
                translate([h[0], h[1], cav_top - enc_stand - 0.01]) cylinder(d = enc_col_pilot, h = enc_stand + 1);
        }
        for (h = oled_hole_pts()) translate([h[0], h[1], cav_top - oled_boss_h - 0.01])
            cylinder(d = oled_pilot, h = oled_boss_h + 1.4);
    }
}

// ============================ ghosts (assembly only) =========================
module box(x0, y0, x1, y1, z0, h, c = "gray") color(c, 0.45) translate([x0, y0, z0]) cube([x1 - x0, y1 - y0, h]);

module ghosts() {
    bz = board_z;
    color("green", 0.35) translate([0, 0, bz - pcb_t]) cube([pcb_l, pcb_w, pcb_t]);
    box(78.5, 72.8, 87.5, 80.2, bz, 3.3, "silver");            // J9 USB-C
    box(86.0, 42.5, 101.2, 56.9, bz, 7.0, "silver");           // J1 USB-A
    for (y = trs_y) {                                          // J7/J8 TRS
        box(2.3, y - 5.75, 16.2, y + 5.75, bz, 6.0, "black");
        color("silver", 0.5) translate([-1.3, y, bz + trs_zc]) rotate([0, 90, 0]) cylinder(d = 6, h = 3.6);
    }
    box(22.65, 73.85, 29.35, 78.0, bz, 1.5, "black");          // SW2
    box(95.5, 58.5, 99.1, 67.5, bz, 5.5, "black");             // SW3
    box(46, 34.4, 64, 53.6, bz, 3.2, "dimgray");               // U4 WROOM
    box(42.5, 70.5, 47.5, 75.5, bz, 4, "dimgray");             // L2
    box(54.5, 23.5, 59.5, 28.5, bz, 4, "dimgray");             // L3
    // JST PH housings (6 mm) + mated plug/wire allowance to 10 mm
    for (b = [[9.64, 70.2, 15.95, 75.1],  [7.64, 15.2, 19.95, 20.1],  [89.2, 16.05, 94.1, 26.36],
              [85.2, 4.05, 90.1, 14.36],  [25.64, 3.2, 31.95, 8.1],   [35.64, 3.2, 41.95, 8.1],
              [45.64, 3.2, 51.95, 8.1],   [55.64, 3.2, 61.95, 8.1],   [65.64, 3.2, 71.95, 8.1],
              [76.04, 51.7, 82.35, 56.6]])
        { box(b[0], b[1], b[2], b[3], bz, 6, "white"); box(b[0], b[1], b[2], b[3], bz + 6, 4, "orange"); }
    box(bat_x, bat_y, bat_x + bat_l, bat_y + bat_w, floor_t, bat_t, "yellow");   // LiPo
    // lid-mounted parts
    if (lid_style == "acrylic") for (p = holes) color("gray", 0.6) translate([p[0], p[1], board_z]) spacer();
    oz = cav_top - oled_boss_h;
    box(oled_c[0] - oled_pcb[0] / 2, oled_c[1] - oled_pcb[1] / 2, oled_c[0] + oled_pcb[0] / 2, oled_c[1] + oled_pcb[1] / 2, oz - 1.6, 1.6, "blue");
    box(oled_c[0] - 13, oled_c[1] + oled_pcb[1] / 2 - 4, oled_c[0] + 13, oled_c[1] + oled_pcb[1] / 2 - 1, oz - 1.6 - 6, 6, "orange"); // soldered leads
    translate([enc_c[0], enc_c[1], 0]) rotate(enc_rot) {     // KY-040: EC11 body, module PCB, shaft
        color("black", 0.4) translate([-enc_body[0] / 2, -enc_body[1] / 2, cav_top - enc_stand]) cube([enc_body[0], enc_body[1], enc_stand]);
        color("blue", 0.45) translate([enc_pcb_c[0] - enc_pcb[0] / 2, enc_pcb_c[1] - enc_pcb[1] / 2, cav_top - enc_stand - 1.6]) cube([enc_pcb[0], enc_pcb[1], 1.6]);
        color("orange", 0.45) translate([enc_pcb_c[0] - 6, enc_pcb_c[1] + enc_pcb[1] / 2, cav_top - enc_stand - 1.6]) cube([12, 6, 2.5]);   // right-angle header
    }
    color("silver", 0.5) translate([enc_c[0], enc_c[1], cav_top]) cylinder(d = 6, h = 15);
    for (i = [0 : len(btn_pos) - 1]) translate([btn_pos[i][0], btn_pos[i][1], 0]) {
        color("black", 0.4) translate([0, 0, cav_top - btn_depth]) cylinder(d = btn_body_d, h = btn_depth);
        color("red", 0.5) translate([0, 0, cav_top + lid_thk]) cylinder(d = 7, h = 6); }
    for (p = led_pos) color("black", 0.4) translate([p[0], p[1], cav_top - 9]) cylinder(d = 8, h = 9);
    color("gold", 0.5) translate([sma_x, pcb_w + fit - 10, bz + sma_z]) rotate([-90, 0, 0]) cylinder(d = 8, h = 10);
    color("black", 0.4) translate([sma_x, oy1, bz + sma_z]) rotate([-90, 0, 0]) cylinder(d = 9, h = 25);
}

// ================================ render ====================================
if (part == "base") base();
else if (part == "lid") translate([0, 0, cav_top + lid_t]) rotate([180, 0, 0]) lid();   // printed lid, top face down
else if (part == "spacers") spacers();
else {
    base();
    if (lid_style == "acrylic") color("lightblue", 0.35) acrylic_lid(); else lid();
    ghosts();
}
