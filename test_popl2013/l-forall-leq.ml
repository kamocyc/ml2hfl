(*let nil = (0, fun i -> assert false)
let cons a (len, l) =
  (len + 1, fun i -> if i = 0 then a else l (i - 1))*)
let hd (len, l) = l 0
let tl (len, l) = (len - 1, fun i -> l (i + 1))
let is_nil (len, l) = len = 0

let rec for_all (*ex*) f xs =
  if is_nil xs then
    true
  else
    f (hd xs) && for_all (*ex*) f (tl xs)
let main len =
  assert (for_all (*len*) (fun x -> x <= len) (len, fun i -> len - i))
