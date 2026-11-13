// =============================================================================
//  Enclosure for MSP3223 3.2" cap-touch IPS LCD + ElectroCookie full breadboard
//  + 2x 18650 battery, fully enclosed with a screw-down lid.
//
//  Layout (stacked):
//    - Breadboard lies FLAT on the floor of the bottom tray.
//    - 2x18650 holder sits on the floor ALONGSIDE the breadboard (in +Y).
//    - The LID carries the display (LANDSCAPE, facing up) in a recessed window,
//      plus a rotary-encoder shaft hole.
//    - Bottom + lid join with 4x M3 corner screws (heat-set inserts in bosses).
//
//  Units: millimetres.  Render with OpenSCAD (https://openscad.org).
//  Choose what to render with the `part` variable below.
//
//  >>> VERIFY the values flagged "CHECK" against your actual parts before
//      printing. Dimensions sourced from lcdwiki MSP3222/MSP3223 spec and
//      ElectroCookie full-size board spec; tolerances vary by batch.
// =============================================================================

/* [What to render] */
// "bottom"   = the tray (print this)
// "lid"      = the top lid (print this)
// "assembly" = both + ghosted parts, for visual check only (do NOT export)
part = "assembly";

$fn = 48;

// -----------------------------------------------------------------------------
//  CORE BUILD PARAMETERS  (tune these)
// -----------------------------------------------------------------------------
/* [Shell] */
wall      = 2.6;   // side wall thickness
floor_th  = 2.6;   // bottom floor thickness
lid_th    = 2.8;   // lid plate thickness
fillet    = 4;     // outer vertical-edge radius
clr       = 0.4;   // general fit clearance

in_h      = 38;    // INTERIOR height (floor-top to lid-underside). Drives total height.

/* [Breadboard - ElectroCookie full size]  measured (datasheet) */
bb_l      = 172.7; // length
bb_w      = 52.1;  // width
bb_h      = 1.6;   // PCB thickness
// Screwed down onto 3 standoff posts at its M3 (Ø3.2) centreline holes:
bb_standoff   = 5.0;   // post height -> lifts board off floor (clears soldered leads)
bb_post_d     = 6.5;   // post outer dia
bb_post_pilot = 2.6;   // pilot for an M3 self-tapping screw (use 4.0 for heat-set)
bb_m3_inset   = 7.65;  // M3 end holes in from each short edge: (172.7-157.4)/2
bb_m3_mid     = 86.35; // middle M3 hole from the left edge (= bb_l/2)

/* [2x 18650 holder]  measured */
bat_l     = 75.21; // along X   (2.961 in)
bat_w     = 38.91; // along Y   (1.532 in)
bat_h     = 20.04; // holder height (0.789 in)
bat_gap   = 4;     // gap between breadboard and battery pocket
bat_hole_d     = 3.2;   // floor through-hole dia for the holder's mounting screws
bat_hole_inset = 10.41; // hole centres in from each short end (0.410 in), on centreline
bat_head_d     = 6.0;   // screw-head counterbore on the case underside
bat_head_h     = 2.5;

/* [MSP3223 display - LANDSCAPE]  measured */
disp_pcb_w   = 90.96;  // module/PCB long edge -> X in landscape (3.581 in)
disp_pcb_h   = 55.22;  // module/PCB short edge -> Y in landscape (2.174 in)
disp_pcb_th  = 1.63;   // PCB thickness (0.064 in)
disp_total_th= 6.22;   // glass front to PCB back (0.245 in)
disp_glass_w = 77.88;  // visible glass width  (3.066 in)
disp_glass_h = 55.22;  // visible glass height (2.174 in == full module height)
disp_header  = 7.0;    // extra hang below PCB back for pin header / wires
// Active (lit) area, landscape -- NOT user-supplied; lcdwiki value, VERIFY:
act_w        = 64.8;   // active area along X
act_h        = 48.6;   // active area along Y
win_margin   = 1.0;    // window opening = active area grown by this on each side
glass_clr    = 0.5;    // clearance around the glass in its lid recess
lip_th       = 0.9;    // lid frame thickness the glass front sits behind
clip_grip    = 1.2;    // how far the corner clips hook over the PCB back
clip_w       = 6;      // clip footprint along each edge
// Position of the display's CENTRE on the lid (interior coords):
disp_cx      = 62;     // X position (kept clear of the corner screw bosses)
disp_cy      = -1;     // Y centre on the lid; -1 = auto-centre between long walls

/* [Rotary encoder]  CHECK (EC11-style: ~7mm threaded bushing, 6mm shaft) */
enc_hole_d   = 7.4;    // clearance hole for the threaded bushing
enc_recess_d = 0;      // optional underside flat recess dia for the nut (0 = off)
enc_cx       = -1;     // X on lid; -1 = auto-centre between screen edge & right wall
enc_cy       = -1;     // Y on lid; -1 = auto so the encoder+button column centres in Y

/* [Buttons - 12mm panel-mount, in a column under the encoder] */
btn_count    = 3;      // number of buttons
btn_hole_d   = 12.2;   // panel hole for a 12mm threaded button bushing
btn_pitch    = 19;     // centre-to-centre spacing (encoder->1st button and between)

/* [Corner screws - bottom<->lid join]
   Bosses hang from the TOP of the corners (fused to the walls) and stop partway
   down, so the floor corners stay clear for the breadboard. */
scr_d        = 2.72;   // lid through-hole (was 3.2; shrunk ~15% for tighter screws)
scr_head_d   = 6.2;    // M3 head counterbore dia in lid (unchanged so head still seats)
scr_head_h   = 3.0;    // counterbore depth
insert_d     = 3.4;    // boss screw bore (was 4.0; shrunk ~15%)
insert_depth = 13;     // how deep the insert hole runs down from the lid join
boss_d       = 8.5;    // screw boss outer dia
boss_inset   = 7.0;    // boss centre inset from the interior corner
boss_h       = 20;     // vertical extent of the boss (from the wall top downward)

/* [Front USB / charge port - in the -Y (front) long wall] */
usb_w        = 16;     // cutout width  (>= 0.6")        (set usb_w=0 to remove)
usb_h        = 8;      // cutout height (>= 0.3")
usb_z        = 19.8;   // centre 0.882" (22.4mm) above the EXTERIOR bottom => 22.4-floor_th
usb_x        = 40;     // X position of port centre (on the -Y wall)

/* [ESP32 USB access - rectangular opening in the RIGHT (+X) end wall]
   Y measured from the OUTSIDE face of the front (-Y) wall; Z from inside floor. */
esp_open     = true;   // set false to remove
esp_y_left   = 17.78;  // edge nearer the front wall   (0.70")
esp_y_right  = 48.26;  // edge farther from the front  (1.90")
esp_z_bot    = 17.78;  // opening bottom, above floor  (0.70")
esp_z_top    = 24.13;  // opening top, above floor     (0.95")

/* [Optional display screw bosses on lid underside]  (off by default)
   The snap-clips already hold the screen. The measured holes sit only 0.635 mm
   (0.025") from each PCB edge, which is too close for bosses -- so this stays
   off unless that measurement is revised. */
use_disp_screws = false;
disp_hole_dx    = 90.96 - 2*0.635;  // long-axis hole spacing (0.025" inset)
disp_hole_dy    = 55.22 - 2*0.635;  // short-axis hole spacing
disp_screw_pilot= 1.6;    // tiny self-tap pilot

// =============================================================================
//  DERIVED
// =============================================================================
// Interior plan dimensions (X = length, Y = width)
end_gap = 3.5;                                  // breadboard-to-endwall slack
in_l = bb_l + 2*end_gap;                        // interior length
side_gap = 1.5;
in_w = bb_w + bat_gap + bat_w + 2*side_gap;     // interior width

ext_l = in_l + 2*wall;
ext_w = in_w + 2*wall;
ext_h = floor_th + in_h + lid_th;

// breadboard origin (lower-left) in interior coords
bb_x0 = (in_l - bb_l)/2;
bb_y0 = side_gap;

// battery pocket origin
bat_x0 = (in_l - bat_l)/2;
bat_y0 = bb_y0 + bb_w + bat_gap;

// breadboard hold-down posts: 3 M3 holes on the board centreline
bb_screw_xs = [bb_x0 + bb_m3_inset, bb_x0 + bb_m3_mid, bb_x0 + bb_l - bb_m3_inset];
bb_screw_y  = bb_y0 + bb_w/2;

rim_h = 4;   // lid alignment-rim depth (shared by lid_rim and corner bosses)

// window opening size (landscape)
win_w = act_w + 2*win_margin;
win_h = act_h + 2*win_margin;

// effective display Y centre (resolve the -1 auto-centre sentinel here, where
// in_w is known — a top-level var can't reference one defined later in the file)
disp_cy_eff = (disp_cy < 0) ? in_w/2 : disp_cy;

// Encoder + button column placement (resolve the -1 auto sentinels here).
// Encoder X centred between the screen's visible right edge and the right wall;
// the encoder sits at the top of a vertical column, buttons descending in -Y,
// with the whole cluster centred in Y.
screen_right_x = disp_cx + disp_glass_w/2;
enc_cx_eff = (enc_cx < 0) ? (screen_right_x + in_l)/2 : enc_cx;
// encoder on top, a single horizontal row of buttons one pitch below it; the
// encoder+row cluster is centred in Y.
enc_cy_eff = (enc_cy < 0) ? (in_w/2 + btn_pitch/2) : enc_cy;
btn_row_y  = enc_cy_eff - btn_pitch;
function btn_cx(i) = enc_cx_eff + (i - (btn_count-1)/2)*btn_pitch;  // centred row

// Display mount Z geometry, measured from the lid TOP face (z = lid_th):
//   glass front sits `lip_th` below the top face (behind the window frame);
//   the module body then hangs into the case interior.
glass_front_z = lid_th - lip_th;            // z of the glass outer face (in lid coords)
pcb_back_z    = glass_front_z - disp_total_th;   // z of the PCB rear face (negative)
disp_drop     = disp_total_th + disp_header;      // total hang below the lid top (for clearance/ghost)

// =============================================================================
//  2D HELPERS
// =============================================================================
module rrect(l, w, r) {                 // rounded rectangle, lower-left at origin
    hull() for (x=[r, l-r], y=[r, w-r]) translate([x,y]) circle(r=r);
}

// =============================================================================
//  BOTTOM TRAY
// =============================================================================
// Corner screw bosses that HANG from the wall tops and stop partway down, so the
// floor corners stay clear for the breadboard. Each is a screw boss tied to the
// two corner walls by a gusset; the gusset stops just below the lid rim.
// Local z: 0 = floor top, in_h = lid underside.  (call at floor_th, no sink)
module corner_supports() {
    z0   = in_h - boss_h;          // boss bottom (well above the floor)
    gtop = in_h - rim_h - 0.6;     // gusset top, just under the lid alignment rim
    for (i=[0:3]) {
        bx = (i%2==0) ? boss_inset : in_l-boss_inset;
        by = (i<2)    ? boss_inset : in_w-boss_inset;
        cx = (i%2==0) ? -0.5 : in_l+0.5;   // corner point, pushed into the wall
        cy = (i<2)    ? -0.5 : in_w+0.5;
        difference() {
            union() {
                translate([bx,by,z0]) cylinder(d=boss_d, h=boss_h);   // screw boss
                hull() {                                              // wall-fused gusset
                    translate([bx,by,z0]) cylinder(d=boss_d, h=gtop-z0);
                    translate([cx,cy,z0]) cylinder(d=3,     h=gtop-z0);
                }
            }
            // insert hole, down from the lid join
            translate([bx,by,in_h-insert_depth]) cylinder(d=insert_d, h=insert_depth+0.2);
        }
    }
}

// Three standoff posts on the breadboard's M3 centreline holes. The board rests
// on the posts (lifted off the floor) and is screwed down from above.
module breadboard_posts() {
    for (xc = bb_screw_xs)
        translate([xc, bb_screw_y, 0]) difference() {
            cylinder(d=bb_post_d, h=bb_standoff);
            translate([0,0,-0.1]) cylinder(d=bb_post_pilot, h=bb_standoff+0.2);
        }
}

module battery_pocket() {
    pw  = 1.8;  // pocket wall thickness
    ph  = min(bat_h, 12);   // walls only need to be tall enough to retain laterally
    bfit= 0.4;  // fit clearance around the holder
    difference() {
        translate([bat_x0-pw, bat_y0-pw, 0])
            cube([bat_l+2*pw+2*bfit, bat_w+2*pw+2*bfit, ph]);
        translate([bat_x0-bfit, bat_y0-bfit, -0.1])
            cube([bat_l+2*bfit, bat_w+2*bfit, ph+0.2]);
        // wire pass-through notch toward the breadboard
        translate([bat_x0+bat_l/2-7, bat_y0-pw-0.1, ph-7])
            cube([14, pw+0.2, 7+0.2]);
    }
}

// through-holes in the floor for the holder's two mounting screws (on the
// battery centreline, bat_hole_inset in from each short end). Screw enters from
// the case underside; head counterbored flush.  Called in interior coords.
module battery_floor_holes() {
    yc = bat_y0 + bat_w/2;
    for (xc = [bat_x0 + bat_hole_inset, bat_x0 + bat_l - bat_hole_inset])
        translate([xc, yc, 0]) {
            translate([0,0,-(floor_th+0.5)]) cylinder(d=bat_hole_d, h=floor_th+1);
            translate([0,0,-(floor_th+0.5)]) cylinder(d=bat_head_d, h=bat_head_h+0.5);
        }
}

module bottom() {
    difference() {
        union() {
            // outer solid up to wall top
            linear_extrude(floor_th + in_h) rrect(ext_l, ext_w, fillet);
        }
        // hollow interior (leave floor)
        translate([wall, wall, floor_th])
            linear_extrude(in_h + 1) rrect(in_l, in_w, max(0.1, fillet-wall));
        // USB / charge port on -Y (front) wall
        if (usb_w > 0)
            translate([wall+usb_x-usb_w/2, -1, floor_th+usb_z-usb_h/2])
                cube([usb_w, wall+2, usb_h]);
        // ESP32 USB access opening on +X (right) end wall
        if (esp_open)
            translate([wall+in_l-1, esp_y_left, floor_th+esp_z_bot])
                cube([wall+2, esp_y_right-esp_y_left, esp_z_top-esp_z_bot]);
        // battery holder mounting screws through the floor
        translate([wall, wall, floor_th]) battery_floor_holes();
    }
    // corner bosses fuse to the WALL tops (call at floor_th so they reach the
    // lid underside; they don't touch the floor).
    translate([wall, wall, floor_th]) corner_supports();
    // floor-standing features, sunk 0.2mm into the floor to weld watertight.
    translate([wall, wall, floor_th-0.2]) {
        breadboard_posts();
        battery_pocket();
    }
}

// =============================================================================
//  LID
// =============================================================================
module lid_screwholes() {
    for (cx=[boss_inset, in_l-boss_inset], cy=[boss_inset, in_w-boss_inset])
        translate([wall+cx, wall+cy, -0.1]) {
            cylinder(d=scr_d, h=lid_th+0.2);
            // counterbore opens on the TOP face of the lid
            translate([0,0,lid_th-scr_head_h])
                cylinder(d=scr_head_d, h=scr_head_h+0.1);
        }
}

// --- Display mount: window through the frame + a glass recess + corner clips.
// Module inserts from the underside; the glass slides up into the recess until
// its front meets the `lip_th` window frame; clips hook over the PCB back.

module display_window() {                 // SUBTRACT: lit-area opening through lid
    translate([wall+disp_cx, wall+disp_cy_eff, lid_th/2])
        cube([win_w, win_h, lid_th+2], center=true);
}

module display_recess() {                 // SUBTRACT: glass-sized pocket up to the frame
    rw = disp_glass_w + 2*glass_clr;
    rh = disp_glass_h + 2*glass_clr;
    translate([wall+disp_cx-rw/2, wall+disp_cy_eff-rh/2, -0.1])
        cube([rw, rh, glass_front_z + 0.1]);   // z=-0.1 .. glass_front_z
}

module display_clips() {                  // ADD: 4 corner clips capturing the PCB
    // Each clip = a vertical post just OUTSIDE the PCB edge (in X) running from
    // the lid underside down past the PCB, with an inward hook over the PCB back.
    cg   = 0.3;                           // side clearance to the PCB edge
    pt   = 2.0;                           // post thickness
    foot = pcb_back_z - 1.6;             // post bottom (just below the PCB back)
    for (sx=[-1,1], sy=[-1,1])
        translate([wall+disp_cx + sx*(disp_pcb_w/2),
                   wall+disp_cy_eff + sy*(disp_pcb_h/2), 0]) {
            post_x0 = (sx>0) ? cg : -(cg+pt);
            // vertical post (z = foot .. 0)
            translate([post_x0, -clip_w/2, foot]) cube([pt, clip_w, -foot]);
            // inward hook over the PCB rear face
            hook_x0  = (sx>0) ? -clip_grip : -(cg+pt);
            hook_len = cg + pt + clip_grip;
            translate([hook_x0, -clip_w/2, pcb_back_z - 1.4])
                cube([hook_len, clip_w, 1.4]);
        }
}

module display_screw_bosses() {           // ADD: optional, off by default
    if (use_disp_screws)
        for (sx=[-1,1], sy=[-1,1])
            translate([wall+disp_cx + sx*disp_hole_dx/2,
                       wall+disp_cy_eff + sy*disp_hole_dy/2, pcb_back_z+disp_pcb_th])
                difference() {
                    cylinder(d=4.5, h=glass_front_z-(pcb_back_z+disp_pcb_th));
                    translate([0,0,-3]) cylinder(d=disp_screw_pilot, h=12);
                }
}

module encoder_cut() {
    translate([wall+enc_cx_eff, wall+enc_cy_eff, -0.1]) {
        cylinder(d=enc_hole_d, h=lid_th+0.2);
        if (enc_recess_d > 0)
            translate([0,0,lid_th-1.2]) cylinder(d=enc_recess_d, h=1.3);
    }
}

module button_cut() {                     // SUBTRACT: horizontal row of 12mm holes
    for (i = [0:btn_count-1])
        translate([wall+btn_cx(i), wall+btn_row_y, -0.1])
            cylinder(d=btn_hole_d, h=lid_th+0.2);
}

module lid_rim() {
    // downward alignment rim that nests inside the tray walls
    rh = rim_h;
    rt = 1.8;     // rim wall thickness
    translate([wall+clr, wall+clr, -rh])
        linear_extrude(rh)
            difference() {
                rrect(in_l-2*clr, in_w-2*clr, max(0.1, fillet-wall-clr));
                offset(-rt) rrect(in_l-2*clr, in_w-2*clr, max(0.1, fillet-wall-clr));
            }
}

module lid() {
    union() {
        difference() {
            union() {
                linear_extrude(lid_th) rrect(ext_l, ext_w, fillet);
                lid_rim();
            }
            lid_screwholes();
            display_window();
            display_recess();
            encoder_cut();
            button_cut();
        }
        display_clips();
        display_screw_bosses();
    }
}

// =============================================================================
//  GHOST PARTS (assembly preview only)
// =============================================================================
module ghost_breadboard() color([0.1,0.4,0.8,0.5])
    translate([wall+bb_x0, wall+bb_y0, floor_th]) cube([bb_l, bb_w, bb_h]);

module ghost_battery() color([0.2,0.2,0.2,0.5])
    translate([wall+bat_x0, wall+bat_y0, floor_th]) cube([bat_l, bat_w, bat_h]);

module ghost_display() {
    // lid underside sits at z = floor_th+in_h in the assembly
    base = floor_th + in_h;
    color([0.05,0.05,0.05,0.6])      // PCB
        translate([wall+disp_cx-disp_pcb_w/2, wall+disp_cy_eff-disp_pcb_h/2,
                   base + pcb_back_z])
            cube([disp_pcb_w, disp_pcb_h, disp_pcb_th]);
    color([0.1,0.2,0.35,0.6])        // glass stack
        translate([wall+disp_cx-disp_glass_w/2, wall+disp_cy_eff-disp_glass_h/2,
                   base + pcb_back_z + disp_pcb_th])
            cube([disp_glass_w, disp_glass_h, disp_total_th - disp_pcb_th]);
}

// =============================================================================
//  RENDER SELECT
// =============================================================================
if (part == "bottom") {
    bottom();
} else if (part == "lid") {
    // flip the lid so its outer face is down (print orientation)
    translate([0, ext_w, lid_th]) rotate([180,0,0]) lid();
} else {  // assembly preview
    bottom();
    ghost_breadboard();
    ghost_battery();
    ghost_display();
    translate([0,0,floor_th+in_h]) lid();
}
