let rec ack m n =
  if m = 0 then n + 1
  else if n = 0 then ack (m-1) 1
  else ack (m-1) (ack m (n-1))

let main () =
  let m = read_int () in
  let n = read_int () in
  if n>0 && m>0 then
    ack m n
  else
    0