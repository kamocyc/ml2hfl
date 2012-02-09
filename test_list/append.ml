let rec append (xs1:int list) (xs2:int list) =
  match xs1 with
      [] -> xs2
    | x::xs1' -> x :: append xs1' xs2

let rec length_aux acc (xs:int list) =
  match xs with
      [] -> acc
    | _::xs' -> length_aux (acc+1) xs'

let rec make_list n =
  if n = 0
  then []
  else n :: make_list (n-1)

let main n m =
  let xs = make_list n in
  let ys = make_list m in
    assert (length_aux 0 (append xs ys) = m+n)
