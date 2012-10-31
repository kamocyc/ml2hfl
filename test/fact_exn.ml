(*
Sukyoung Ryu, Exception Analysis for Languages with Exceptions, Ph.D. thesis

let rec fact n =
  if n <= 0
  then raise ZERO
  else
    try
      n * fact (n-1)
    with ZERO -> 1
*)

let rec fact n exn =
  if n <= 0
  then exn 0
  else
    let exn n = if n = 0 then 1 else exn n in
      n * fact (n-1) exn
in
let exn n = fail();1 in
  if n > 0
  then (fact n exn; ())
  else ()
