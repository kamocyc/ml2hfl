(***********************************************************************)
(*                                                                     *)
(*                        Caml examples                                *)
(*                                                                     *)
(*            Pierre Weis                                              *)
(*                                                                     *)
(*                        INRIA Rocquencourt                           *)
(*                                                                     *)
(*  Copyright (c) 1994-2011, INRIA                                     *)
(*  All rights reserved.                                               *)
(*                                                                     *)
(*  Distributed under the BSD license.                                 *)
(*                                                                     *)
(***********************************************************************)

(* $Id: camleyes.ml,v 1.5 2011-08-08 19:31:17 weis Exp $ *)

(* The eyes of Caml (CamlTk) *)
(* Written by Jun P. Furuse *)
(* Adapted to the oc examples repository  by P. Weis *)

open Camltk;;

let make_eyes () =
  let top = openTk () in
  Wm.title_set top "Caml Eyes";
  let fw = Frame.create top [] in
  pack [fw] [];
  let c = Canvas.create fw [Width (Pixels 200); Height (Pixels 200)] in
  let create_eye cx cy wx wy ewx ewy bnd =
    let _ =
      Canvas.create_oval c
       (Pixels (cx - wx)) (Pixels (cy - wy))
       (Pixels (cx + wx)) (Pixels (cy + wy))
       [Outline (NamedColor "black"); Width (Pixels 7);
       FillColor (NamedColor "white")] in
    let o =
      Canvas.create_oval c
       (Pixels (cx - ewx)) (Pixels (cy - ewy))
       (Pixels (cx + ewx)) (Pixels (cy + ewy))
       [FillColor (NamedColor "black")] in
    let curx = ref cx
    and cury = ref cy in
    bind c [[], Motion]
      (BindExtend ([Ev_MouseX; Ev_MouseY],
        (fun e ->
          let nx, ny =
            let xdiff = e.ev_MouseX - cx
            and ydiff = e.ev_MouseY - cy in
            let diff = sqrt ((float xdiff /. (float wx *. bnd)) ** 2.0 +.
                               (float ydiff /. (float wy *. bnd)) ** 2.0) in
            if diff > 1.0 then
              truncate ((float xdiff) *. (1.0 /. diff)) + cx,
              truncate ((float ydiff) *. (1.0 /. diff)) + cy
            else
              e.ev_MouseX, e.ev_MouseY in
          Canvas.move c o (Pixels (nx - !curx)) (Pixels (ny - !cury));
          curx := nx;
          cury := ny))) in
  create_eye 60 100 30 40 5 6 0.6;
  create_eye 140 100 30 40 5 6 0.6;
  pack [c] [];
  let bouton_quit =
    Button.create top
      [Text "Quit"; Command closeTk] in
  pack [bouton_quit] [Side Side_Top]
;;

let caml_eyes () =
 make_eyes ();
 Printexc.print mainLoop ()
;;

if !Sys.interactive then () else begin caml_eyes (); exit 0 end;;
