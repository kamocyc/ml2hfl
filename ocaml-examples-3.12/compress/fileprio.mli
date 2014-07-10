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

(* $Id: fileprio.mli,v 1.3 2011-08-08 19:31:17 weis Exp $ *)

type 'a t;;

val vide : 'a t;;
val ajoute : 'a t -> int -> 'a -> 'a t;;
val extraire : 'a t -> int * 'a * 'a t;;

exception File_vide;;