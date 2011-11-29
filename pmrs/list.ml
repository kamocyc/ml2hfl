
let rec make_list m =
  if m <= 0
  then [0]
  else Random.int 0 :: make_list (m-1)

let rec make_list_list m =
  if m <= 0
  then []
  else make_list (Random.int 0) :: make_list_list (m-1)
(*
let rec make_list (u:unit) =
  if Random.int 0 > 0
  then []
  else 0 :: make_list ()

let rec make_list_list (u:unit) =
  if Random.int 0 > 0
  then []
  else make_list () :: make_list_list ()
*)

let head = function
    [] -> assert false
  | x::xs -> x

let ne = function
    [] -> 0
  | x::xs -> 1

let rec filter p = function
    [] -> []
  | x::xs -> if p x = 1 then x::(filter p xs) else filter p xs

let rec map f = function
    [] -> []
  | x::xs -> f x :: map f xs

let main m = map head (filter ne (make_list_list m))
