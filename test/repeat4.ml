let succ x = x + 1 in
let rec repeat f n =
  if n = 0
  then 0
  else f (repeat f (n-1))

let main n =
  assert (repeat succ n = n)
