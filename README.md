

Dependency
==========

- re2
- fmt
- str
- unix
- yojson
- batteries
- compiler-libs.common

All of them can be installed via opam.

Build
=====

```
$ cp parser_wrapper_[YOUR-VERSION-OF-OCAML].ml parser_wrapper.ml
$ dune build ./ml2hfl.exe
```

Usage
=====

```
dune exec ./ml2hfl.exe -- -non-termination INPUT
```

Input File Format
====

```
(* let declarations ... *)

(* function named "main" with type of unit -> int or unit -> unit *)
let main () =
  (* optionally use random integer values with ``read_int ()`` or ``Random.int 0`` *)
  (* ... *)
  (* expression that returns int or unit value that comes from the result of the let declarations above *)
```

* Example

```
let rec mult m n =
  if m>0 then n + mult (m-1) n
  else 0

let main () =
  let n = read_int () in
  let m = read_int () in
  if m>0 then mult m n else 0
```

## Programs that returns a function type value

* For programs that return a function type value, use variables prefixed with "dummy__" to fully apply arguments and return an int or unit value.
Those dummy variables are erased before outputting HFL.

* Example

```
let compose (f : int -> int) (g : int -> int) x = f (g x)
let id (x : int) = x
let succ x = x + 1
let rec toChurch n f =
  if n = 0 then id else compose f (toChurch (n - 1) f)
let main () =
  let x = Random.int 0 in
  if x>=0 then
    let tos = toChurch x succ in
    let dummy__1 = Random.int 0 in tos dummy__1
  else 0
(* (* Original *)
let main () =
  let x = Random.int 0 in
  if x>=0 then
    let tos = toChurch x succ in ()
  else ()
*)
```

Note
====

This project reuses code of [MoCHi](http://www-kb.is.s.u-tokyo.ac.jp/~ryosuke/mochi/).
Rest of this README is MoCHi's original one.

--------------------------------------------------------------------------------

How to build MoCHi
==================

 Install the required tools/libraries listed below,
 and run "bash build", which generates "mochi.opt".


What do you need?
=================

- OCaml compiler (from 4.03 to 4.08; 4.04.2 is recommended)
- Libraries available via OPAM
  - ocamlfind/findlib
  - Z3 4.7.1
  - ppx_deriving
  - Yojson
  - batteries
  - camlp4
  - camlp5
  - zarith
  - apron
- HorSat2 binary (https://github.com/hopv/horsat2)


Dockerfile
==========

 There is a Dockerfile for compiling MoCHi.
 Dockerfile assumes the HorSat2 binary is in the same directory.


Licenses
========

 This software is licensed under the Apache License, Version2.0 (http://www.apache.org/licenses/LICENSE-2.0.txt).

 The software uses the following libraries/tools.
 Please also confirm each license of the library/tool.
- CSIsat (https://github.com/dzufferey/csisat)
- ATP (http://www.cl.cam.ac.uk/~jrh13/atp/)


Author
=======

 MoCHi is developed/maintained by Ryosuke SATO <sato@ait.kyushu-u.ac.jp>


Contributors
============

- Hiroshi Unno
- Takuya Kuwahara
- Keiichi Watanabe
- Naoki Iwayama
