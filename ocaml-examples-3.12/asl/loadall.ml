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

(* $Id: loadall.ml,v 1.3 2011-08-08 19:31:17 weis Exp $ *)

let compile f =
  match Sys.command ("ocamlc -c " ^ f) with
  | 0 -> ()
  | _ -> failwith ("Cannot compile " ^ f)
;;

compile "prel.mli";;
compile "prel.ml";;
#load "prel.cmo";;

compile "asl.mli";;
compile "asl.ml";;
#load "asl.cmo";;

compile "token.mli";;
compile "token.ml";;
#load "token.cmo";;

compile "parser.mli";;
compile "parser.ml";;
#load "parser.cmo";;

compile "semant.ml";;
#load "semant.cmo";;

compile "typing.ml";;
#load "typing.cmo";;

compile "main.mli";;
compile "main.ml";;
#load "main.cmo";;
open Main;;

print_string
 "\nTo run: type\n   go ();;\n\n \
  Try for instance:\n  \
   let I = \x. x;\n \
  and then\n  \
  I I;\n\n  \
  See the README file for more information.\n";
print_newline()
;;


