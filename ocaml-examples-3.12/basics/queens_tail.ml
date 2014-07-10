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

(* $Id: queens_tail.ml,v 1.5 2011-08-08 19:31:17 weis Exp $ *)

(**

                         E I G H T   Q U E E N S

 The Eight Queens Program tail recursive version.

*)

open List;;

let map f l =
  let rec loop accu = function
    | [] -> accu
    | x :: l -> loop (f x :: accu) l in
  loop [] l
;;

let rec interval n m =
  if n > m then [] else n :: interval (n + 1) m
;;

let rev_append l1 l2 =
  let rec loop accu = function
    | [] -> accu
    | h :: t -> loop (h :: accu) t in
  loop l2 l1
;;

let filter_append p l l0 =
  let rec loop accu = function
    | [] -> accu
    | h :: t -> if p h then loop (h :: accu) t else loop accu t in
  let rev_res = loop [] l in
  rev_append rev_res l0
;;

let concmap f l =
  let rec loop accu = function
  | [] -> accu
  | h :: t -> loop (f h accu) t in
  loop [] l
;;

let rec safe x d  = function
  | [] -> true
  | h :: t ->
    x <> h && x <> h + d && x <> h - d && safe x (d + 1) t
;;

let rec ok = function
  | [] -> true
  | h :: t -> safe h 1 t
;;

let find_solutions size =
  let line = interval 1 size in
  let rec gen n size =
    if n = 0 then [[]] else
    concmap
     (fun b -> filter_append ok (map (fun q -> q :: b) line))
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

let print_result size =
  let solutions = find_solutions size in
  let sol_num = List.length solutions in
  Printf.printf "The %i queens problem has %i solutions.\n" size sol_num;
  print_newline ();
  let pr =
    print_string "Do you want to see the solutions <n/y> ? "; read_line () in
  if pr = "y" then print_solutions size solutions
;;

(* 3. Main program. *)

let queens () =
  let size =
    print_string "Chess board's size ? "; read_int () in
  print_result size
;;

if !Sys.interactive then () else queens ()
;;

