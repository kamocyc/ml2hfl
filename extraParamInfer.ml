open Syntax
open Type

let withExparam = ref (Syntax.make_int 0)

let rec transType = function
  | TFun ({Id.name=t1Name; Id.typ=t1} as t1Id, t2) when is_fun_typ t1 ->
    let t1 = transType t1 in
    TFun (Id.new_var (t1Name^"_EXPARAM") TInt, TFun ({t1Id with Id.typ = t1}, transType t2))
  | TFun (t1, t2) -> TFun (t1, transType t2)
  | t -> t

let counter = ref 0
let nthCoefficient = ref []

let freshCoefficient () = 
  let _ = counter := !counter + 1 in
  let freshName = "c" ^ string_of_int (!counter - 1) ^ "_COEFFICIENT" in
  let freshId = Id.new_var freshName TInt in
  let _ = nthCoefficient := !nthCoefficient @ [freshId] in
  make_var freshId

let rec makeTemplate = function
  | [] -> freshCoefficient ()
  | x :: xs ->
    let term = make_mul (freshCoefficient ()) (make_var x) in
    make_add term (makeTemplate xs)

let rec insertExparam scope expr =
  match expr.desc with
    | Const _
    | Unknown
    | RandInt _
    | RandValue _ -> expr
    | Var v -> 
      let typ = transType v.Id.typ in
      {desc = Var {v with Id.typ = typ}; typ = typ}
    | Fun (x, e) -> assert false (* ? *)
    | App (f, args) ->
      let insertToArgs = function
	| t when is_base_typ t.typ -> [insertExparam scope t]
	| t -> [makeTemplate scope; insertExparam scope t]
      in
      { expr with
	desc = App (insertExparam scope f, BRA_util.concat_map insertToArgs args)}
    | If (predicate, thenClause, elseClause) ->
      { expr with
	desc = If ((insertExparam scope predicate),
		   (insertExparam scope thenClause),
		   (insertExparam scope elseClause))}
    | Branch (_, _) -> assert false (* ? *)
    | Let (flag, bindings, e) ->
      let scope =
	let rec extend sc = function
	  | [] -> sc
	  | (x, [], body) :: bs when (Id.typ x) = TInt -> extend (x :: sc) bs
	  | _ :: bs -> extend sc bs
	in
	if flag = Nonrecursive then scope else extend scope bindings
      in
      let insertExparamBinding (x, args, body) = 
	let insertExparamArgs (sc, ags) = function
	  | t when Id.typ t = TInt -> (t::sc, ags@[t])
	  | t when is_base_typ (Id.typ t) -> (sc, ags@[t])
	  | t when is_fun_typ (Id.typ t) ->
	    let t_exparamId = Id.new_var ((Id.name t) ^ "_EXPARAM") TInt in
	    (t_exparamId::sc, ags@[t_exparamId; {t with Id.typ = transType t.Id.typ}])
	  | _ -> assert false
	in
	let (scope, args) =
	  List.fold_left
	    insertExparamArgs
	    (scope, [])
	    args
	in
	({x with Id.typ = transType x.Id.typ}, args, insertExparam scope body)
      in
      { expr with
	desc = Let (flag, List.map insertExparamBinding bindings, insertExparam scope e)}
    | BinOp (op, expr1, expr2) ->
      { expr with
	desc = BinOp (op, insertExparam scope expr1, insertExparam scope expr2)}
    | Not e ->
      { expr with
	desc = Not (insertExparam scope e)}
    | _ -> assert false (* unimplemented *)

let isEX_COEFFS id =
  let len = (String.length id) in
  len > 12 && String.sub id (len - 12) 12 = "_COEFFICIENT"

let rec removeDummySubstitutions = function
  | { desc = Let (Recursive, [id, [], {desc = Const (Int 0)}], e) } -> removeDummySubstitutions e
  | e -> e

let substituteZero e =
  let toZero = function
    | { desc = Var id } when isEX_COEFFS (Id.name id) -> make_int 0
    | e -> e
  in
  BRA_transform.everywhere_expr toZero e

let initPreprocessForExparam e =
  let e = removeDummySubstitutions e in
  let _ = withExparam := e in
  substituteZero e

let addTemplate prog =
  let _ = counter := 0 in
  let prog = insertExparam [] prog in
  let maxIndex = !counter - 1 in
  let rec tmp = function
    | (-1) -> prog
    | n -> make_letrec [(List.nth !nthCoefficient n), [], make_int 0] (tmp (n-1))
(*    | n -> make_letrec [(List.nth !nthCoefficient n), [], make_var (List.nth !nthCoefficient n)] (tmp (n-1))*)
  in
  tmp maxIndex
