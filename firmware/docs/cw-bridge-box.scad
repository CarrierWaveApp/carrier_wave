// =====================================================================
// CW Bridge field enclosure — Heltec WiFi Kit 32 v3.1 + USB-A host jack
// Parametric, two-part friction-fit box. Open in OpenSCAD, set `part`,
// press F6 (render), then Export as STL.
//
//   part = "base"  -> the box that holds the Heltec
//   part = "lid"   -> the snap-on lid with the OLED window
//   part = "both"  -> preview both side by side (don't print this)
//
//  >>> MEASURE YOUR ACTUAL PARTS WITH CALIPERS AND ADJUST <<<
//  Defaults are for the Heltec WiFi Kit 32 v3.1 (PCB ~50.2 x 25.4 mm)
//  and a generic panel-mount USB-A female jack. Print a quick test of
//  just one end wall before committing to the full box if unsure.
// =====================================================================

part = "both";      // "base" | "lid" | "both"
$fn = 48;

// ---- Heltec board ----------------------------------------------------
board_l   = 50.5;   // X, PCB length (+ a hair of clearance)
board_w   = 25.6;   // Y, PCB width
board_t   = 1.6;    // PCB thickness
fit       = 0.4;    // clearance around the board on each side

// ---- box shell -------------------------------------------------------
wall      = 2.0;    // side-wall thickness
floor_t   = 1.6;    // base floor thickness
lid_t     = 1.6;    // lid top thickness
standoff  = 4.5;    // board sits this high off the floor (clears the
                    // underside JST battery connector + your hookup wires)
top_clear = 7.0;    // space above the PCB for the OLED + wiring + lid lip
corner_r  = 2.0;    // outer corner rounding

// ---- USB-C (power / programming) — one short end --------------------
usbc_w    = 10.0;   // cutout width  (Y)
usbc_h    = 4.5;    // cutout height (Z)
usbc_yoff = 0;      // shift along Y if the port isn't centered

// ---- USB-A host jack — opposite short end ---------------------------
usba_w    = 14.5;   // cutout width  (Y)  — panel-mount USB-A shell
usba_h    = 7.0;    // cutout height (Z)
usba_screws   = true;   // two M3 flange holes (common on panel jacks)
usba_screw_dx = 22.0;   // hole spacing (measure yours!)
usba_screw_d  = 3.2;    // M3 clearance

// ---- OLED window (in the lid) ---------------------------------------
oled_win_l = 26.0;  // X length of the window
oled_win_w = 13.0;  // Y width
oled_win_xoff = 8.0;// shift toward the USB-C end (the OLED is offset)

// ---- optional control holes in the lid (EC-11 + 3 buttons) ----------
include_controls = false;   // set true to add encoder + button holes
enc_hole_d  = 7.2;          // EC-11 bushing
btn_hole_d  = 12.2;         // 12 mm panel tactile (use 6.5 for 6 mm)
ctrl_yoff   = 0;            // row position along Y

// ===================== derived ========================================
in_l = board_l + 2*fit;             // inner cavity X
in_w = board_w + 2*fit;             // inner cavity Y
in_h = standoff + board_t + top_clear; // inner cavity Z
out_l = in_l + 2*wall;
out_w = in_w + 2*wall;
board_z = floor_t + standoff;        // top of standoffs = board underside

module rrect(l, w, h, r) {           // rounded box
    hull() for (xx=[r, l-r], yy=[r, w-r])
        translate([xx, yy, 0]) cylinder(h=h, r=r);
}

// ===================== BASE ===========================================
module base() {
    difference() {
        union() {
            // outer shell
            rrect(out_l, out_w, floor_t + in_h, corner_r);
        }
        // hollow cavity
        translate([wall, wall, floor_t])
            cube([in_l, in_w, in_h + 1]);
        // USB-C cutout (+X end), at board level
        translate([out_l - wall - 1, out_w/2 - usbc_w/2 + usbc_yoff, board_z])
            cube([wall + 2, usbc_w, usbc_h]);
        // USB-A cutout (-X end)
        translate([-1, out_w/2 - usba_w/2, board_z])
            cube([wall + 2, usba_w, usba_h]);
        if (usba_screws)
            for (s=[-1,1])
                translate([-1, out_w/2 + s*usba_screw_dx/2, board_z + usba_h/2])
                    rotate([0,90,0]) cylinder(h=wall+2, d=usba_screw_d);
    }
    // four corner standoffs the PCB rests on
    for (xx=[wall+fit+3, wall+fit+in_l-fit*2-3],
         yy=[wall+fit+3, wall+fit+in_w-fit*2-3])
        translate([xx-3, yy-3, floor_t]) cube([6, 6, standoff]);
}

// ===================== LID ============================================
module lid() {
    lip_h   = 4;            // depth the lip plugs into the cavity
    lip_fit = 0.3;          // friction clearance
    difference() {
        union() {
            // top plate (same footprint as the box)
            rrect(out_l, out_w, lid_t, corner_r);
            // inner lip that friction-fits into the cavity
            translate([wall + lip_fit, wall + lip_fit, -lip_h])
                cube([in_l - 2*lip_fit, in_w - 2*lip_fit, lip_h]);
        }
        // OLED window
        translate([out_l/2 - oled_win_l/2 + oled_win_xoff,
                   out_w/2 - oled_win_w/2, -lip_h - 1])
            cube([oled_win_l, oled_win_w, lid_t + lip_h + 2]);
        // optional control holes: EC-11 near the USB-A end, then three
        // buttons in a row toward the USB-C end. Tune positions to taste —
        // these can't overlap the OLED window, so a taller box/longer lid
        // may be wanted if you mount all four on top.
        if (include_controls) {
            translate([10, out_w/2 + ctrl_yoff, -lip_h-1])
                cylinder(h=lid_t+lip_h+2, d=enc_hole_d);
            for (i=[0:2])
                translate([out_l - 12 - i*13, out_w/2 + ctrl_yoff, -lip_h-1])
                    cylinder(h=lid_t+lip_h+2, d=btn_hole_d);
        }
    }
}

// ===================== render =========================================
if (part == "base") base();
else if (part == "lid") translate([0,0,floor_t+in_h]) rotate([180,0,0]) lid();
else { base(); translate([0, out_w + 8, 0]) lid(); }   // "both" preview
