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

(* $Id: queens_lazy.ml,v 1.6 2011-08-08 19:31:17 weis Exp $ *)

(**                         E I G H T   Q U E E N S

 The Eight Queens Program, lazy version.

 How to set n queens on a chessboard of size n such that none
 can catch one each other.

 The program computes and prints the set of solutions
 (without removing symmetrical solutions).
*)

(* 1. Resolution of the n queens problem. *)

(* The type of lazy values. *)
type 'a lval =
   | Val of 'a
   | Delayed of (unit -> 'a)
;;

(* The forcing function. *)
let force = function
  |  Val v -> v
  |  Delayed f -> f ()
;;

(* The type of lazy lists. *)
type 'a llist =
   | Nil
   | Cons of 'a lcell

and 'a lcell = { mutable hd : 'a lval; mutable tl : 'a llist lval}
;;

let ( *::* ) x y = Cons { hd = Delayed x; tl = Delayed y };;
let ( -::* ) x y = Cons { hd = Val x; tl = Delayed y };;
let ( -::- ) x y = Cons { hd = Val x; tl = Val y };;
let ( --::* ) x y = Cons { hd = x; tl = Delayed y };;
let ( --::-- ) x y = Cons { hd = x; tl = y };;

let force_hd = function
  | Cons { hd = Val v; tl = _; } -> v
  | Cons ({ hd = Delayed _ as lv; tl = _; } as c) ->
    let v = force lv in
    c.hd <- Val v;
    v
  | Nil ->
    failwith "force_hd"
;;

let force_tl = function
  | Cons { tl = Val v; hd = _; } -> v
  | Cons ({ tl = Delayed _ as lv; hd = _; } as c) ->
    let v = force lv in
    c.tl <- Val v;
    v;
  | Nil ->
    failwith "force_tl"
;;

let force_hd = function
  | { hd = Val v; tl = _; } -> v
  | { hd = Delayed _ as lv; tl = _; } as c ->
     let v = force lv in
     c.hd <- Val v;
     v
;;

let force_tl = function
  | { hd = _; tl = Val v} -> v
  | { hd = _; tl = Delayed _ as lv} as c ->
    let v = force lv in
    c.tl <- Val v;
    v
;;

(* The corresponding functions and functionals:
   interval, map, filter_append, concmap. *)
let rec map f = function
  | Nil -> Nil
  | Cons c ->
    f (force_hd c) -::* (fun () -> map f (force_tl c))
;;

let rec iter f = function
  | Nil -> ()
  | Cons c ->
    f (force_hd c); iter f (force_tl c)
;;

let rec length = function
  | Nil -> 0
  | Cons c ->
    1 + length (force_tl c)
;;

let rec interval n m =
  if n > m then Nil else n -::* (fun () -> interval (n + 1) m)
;;

let rec rev_append l1 l2 =
  match l1 with
  | Nil -> l2
  | Cons { hd = x; tl = l} ->
    x --::* (fun () -> rev_append (force l) l2)
;;

let rec filter_append p l l0 =
  match (l : 'a llist) with
  | Nil -> l0
  | Cons c ->
    let x = force_hd c in
    if p x then x -::* (fun () -> filter_append p (force_tl c) l0)
    else filter_append p (force_tl c) l0
;;

let rec concmap f = function
  | Nil -> Nil
  | Cons c ->
    f (force_hd c)
      (concmap f (force_tl c))
;;

let rec safe x d  = function
  | Nil -> true
  | Cons { hd = h; tl = t} ->
    let h = force h in
    x <> h && x <> h + d && x <> h - d && safe x (d + 1) (force t)
;;

let rec ok = function
  | Nil -> true
  | Cons { hd = h; tl = t} ->
    safe (force h) 1 (force t)
;;

let find_solutions size =
  let line = interval 1 size in
  let rec gen n size =
    if n = 0 then Nil -::- Nil else
    concmap
     (fun b -> filter_append ok (map (fun q -> q -::- b) line))
     (gen (n - 1) size) in
  gen size size
;;

(* 2. Printing results. *)

let print_solutions size solutions =
  let sol_num = ref 1 in
  iter
    (fun chess ->
     Printf.printf "\nSolution number %i\n" !sol_num;
     sol_num := !sol_num + 1;
     iter
       (fun line ->
        let count = ref 1 in
        while !count <= size do
          if !count = line then print_string "Q " else print_string "- ";
          count := !count + 1
        done;
        print_newline ())
       chess)
    solutions
;;

let print_number_of_solutions size sols =
  let sol_num = length sols in
  Printf.printf "The %i queens problem has %i solutions.\n" size sol_num
;;

let print_result size =
  let sols = find_solutions size in
  print_number_of_solutions size sols;
  print_newline ();
  let pr =
    print_string "Do you want to see the solutions <n/y> ? "; read_line () in
  if pr = "y" then print_solutions size sols
;;

(* 3. Main program. *)

let queens () =
  let size =
    print_string "Chess board's size ? "; read_int () in
  print_result size
;;

if !Sys.interactive then queens () else
  let size =
   if Array.length Sys.argv <> 2 then 8 else (int_of_string Sys.argv.(1)) in
  let sols = find_solutions size in
  print_number_of_solutions size sols
;;

