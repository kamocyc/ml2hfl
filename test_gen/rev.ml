let k1 k r1 r2 =
  assert (r2 > 0); k (r1 + 1) (r2 - 1)
let rec h x y k =
  if x = 0 then k 0 y else h (x - 1) y (k1 k)
let k2 r1 r2 = assert (r2 = 0); r1
let rev x = h x x k2
let main n = assert (rev n >= n)
