let rec sum n =
  if n <= 0 then
    0
  else
    n + sum (n-1)
let a () = ()
let main () =
  let n = read_int () in
  sum n
