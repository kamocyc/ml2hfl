open ExtList

type t = Unit | Bool | Int | Fun of t * t

let is_base ty =
  match ty with
    Unit | Bool | Int -> true
  | Fun(_, _) -> false

let tfun tys =
  List.fold_right
    (fun ty1 ty2 -> Fun(ty1, ty2))
    (Util.init tys)
    (List.last tys)

let rec arity ty =
  match ty with
    Unit
  | Bool
  | Int -> 0
  | Fun(_, ty) -> 1 + arity ty

let rec args_ret ty =
  match ty with
    Fun(ty1, ty2) ->
      let args, ret = args_ret ty2 in
      ty1::args, ret
  | _ ->
      [], ty

let rec pr ppf ty =
  match ty with
    Unit ->
      Format.fprintf ppf "unit"
  | Bool ->
      Format.fprintf ppf "bool"
  | Int ->
      Format.fprintf ppf "int"
  | Fun(ty1, ty2) ->
      let _ = if is_base ty1 then Format.fprintf ppf "@[<hov>%a" pr ty1 else Format.fprintf ppf "@[<hov>(%a)" pr ty1 in
      Format.fprintf ppf "@ ->@ %a@]" pr ty2

let pr_bind ppf (x, ty) = Format.fprintf ppf "%a:%a" Var.pr x pr ty

let equiv ty1 ty2 = ty1 = ty2

let find_last_base env (x, uid) =
  let rec aux ty i j =
    match ty with
		    Unit | Bool | Int ->
        j
		  | Fun(ty1, ty2) ->
		      aux ty2 (i + 1) (if is_base ty1 then i else j)
  in
  let i = aux (env x) 0 (-1) in
		let _ = if i = -1 then ()(* condition must be Term.ttrue *) in
		Var.T(x, uid, i)
