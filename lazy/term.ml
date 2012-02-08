open ExtList
open ExtString

(** Terms *)

(** {6 Type} *)

type t =
  Var of Attr.t * Var.t
| Const of Attr.t * Const.t
| App of Attr.t * t * t
| Call of Attr.t * t * t list
| Ret of Attr.t * t * t * SimType.t
| Error of Attr.t
| Forall of Attr.t * (Var.t * SimType.t) list * t
| Exists of Attr.t * (Var.t * SimType.t) list * t

(** {6 Basic functions} *)

let rec fun_args t =
  match t with
    App(_, t1, t2) ->
      let f, args = fun_args t1 in
      f, args @ [t2]
  | _ ->
      t, []

let rec pr ppf t =
  match t with
    Var(_, x) ->
      Format.fprintf ppf "%a" Var.pr x
      (*Format.fprintf ppf "%a%d" Idnt.pr id (try Attr.arity a with Not_found -> 0)*)
  | Const(_, c) ->
      Format.fprintf ppf "%a" Const.pr c
  | App(_, _, _) ->
      let f, args = fun_args t in
      (match f, args with
        Var(_, _), _ ->
          Format.fprintf ppf "(@[<hov2>%a@ @[<hov>%a@]@])" pr f (Util.pr_list pr "@ ") args
      | Const(_, _), [t] ->
          Format.fprintf ppf "(%a %a)" pr f pr t
      | Const(_, c), [t1; t2] when Const.is_bin c ->
          Format.fprintf ppf "(@[<hov>%a %a@ %a@])" pr t1 Const.pr_bin c pr t2
      | Const(_, _), _ ->
          Format.fprintf ppf "(@[<hov2>%a@ @[<hov>%a@]@])" pr f (Util.pr_list pr "@ ") args
      | _, _ ->
          assert false)
  | Call(_, f, args) ->
      Format.fprintf ppf "Call(@[<hov>%a@])" (Util.pr_list pr ",@ ") (f::args)
  | Ret(_, ret, t, _) ->
      Format.fprintf ppf "Ret(@[<hov>%a,@ %a@])" pr ret pr t
  | Error(_) ->
      Format.fprintf ppf "Error"
  | Forall(_, env, t) ->
      Format.fprintf ppf "Forall(%a, %a)" (Util.pr_list SimType.pr_bind ",") env pr t
  | Exists(_, env, t) ->
      Format.fprintf ppf "Exists(%a, %a)" (Util.pr_list SimType.pr_bind ",") env pr t

let rec pr2 ppf t =
  match t with
    Var(_, x) ->
      Format.fprintf ppf "%a" Var.pr x
  | Const(_, c) ->
      Format.fprintf ppf "%a" Const.pr c
  | App(_, _, _) ->
      let f, args = fun_args t in
      (match f, args with
        Var(_, _), _ ->
          Format.fprintf ppf "(%a %a)" pr2 f (Util.pr_list pr2 " ") args
      | Const(_, _), [t] ->
          Format.fprintf ppf "(%a %a)" pr2 f pr2 t
      | Const(_, c), [t1; t2] when Const.is_bin c ->
          Format.fprintf ppf "(%a %a %a)" pr2 t1 Const.pr_bin c pr2 t2
      | Const(_, _), _ ->
          Format.fprintf ppf "(%a %a)" pr2 f (Util.pr_list pr2 " ") args
      | _, _ ->
          assert false)
  | Call(_, f, args) ->
      Format.fprintf ppf "Call(%a)" (Util.pr_list pr2 ", ") (f::args)
  | Ret(_, ret, t, _) ->
      Format.fprintf ppf "Ret(%a, %a)" pr2 ret pr2 t
  | Error(_) ->
      Format.fprintf ppf "Error"
  | Forall(_, _, _) | Exists(_, _, _) ->
      assert false

(** ToDo: implement equivalence up to attributes and binders *)
let equiv t1 t2 = t1 = t2

let rec fvs t =
  match t with
    Var(_, x) -> [x]
  | Const(_, _) -> []
  | App(_, t1, t2) -> List.unique (fvs t1 @ fvs t2)
  | Forall(_, env, t) | Exists(_, env, t) -> Util.diff (fvs t) (List.map fst env)
  | _ -> assert false

let rec subst sub t =
  match t with
    Var(a, x) -> (try sub x with Not_found -> Var(a, x))
  | Const(a, c) -> Const(a, c)
  | App(a, t1, t2) -> App(a, subst sub t1, subst sub t2)
  | Forall(a, env, t) ->
      let xs = List.map fst env in
      let sub x = if List.mem x xs then raise Not_found else sub x in
      Forall(a, env, subst sub t)
  | Exists(a, env, t) ->
      let xs = List.map fst env in
      let sub x = if List.mem x xs then raise Not_found else sub x in
      Exists(a, env, subst sub t)
  | _ -> assert false

let rec apply t ts =
  match ts with
    [] ->
      t
  | t'::ts' ->
      apply (App([], t, t')) ts'

let make_var x = Var([], x)
let tint n = Const([], Const.Int(n))
let tunit = Const([], Const.Unit)
let tevent id = Const([], Const.Event(Idnt.make id))
let event_fail = "fail"
let tfail = apply (tevent event_fail) [tunit]

(** {6 Functions on integers} *)

let add t1 t2 = apply (Const([], Const.Add)) [t1; t2]
let rec sum ts =
  match ts with
    [] -> tint 0
  | [t] -> t
  | (Const(_, Const.Int(0)))::ts' -> sum ts'
  | t::ts' ->
      let t' = sum ts' in
      (match t' with
        Const(_, Const.Int(0)) ->
          t
      | _ ->
          apply (Const([], Const.Add)) [t; t'])

(*let sub t1 t2 = apply (Const([], Const.Add)) [t1; apply (Const([], Const.Minus)) [t2]]*)
let sub t1 t2 = apply (Const([], Const.Sub)) [t1; t2]
let minus t = apply (Const([], Const.Minus)) [t]
let mul t1 t2 = apply (Const([], Const.Mul)) [t1; t2]

let term_of_arith nxs n =
  let ts =
    (if n = 0 then [] else [tint n]) @
    (List.filter_map (fun (n, x) -> if n = 0 then None else Some(mul (tint n) (make_var x))) nxs)
  in
  sum ts

let terms_of_arith (nxs, n) =
  let nxs =
    List.filter_map
      (fun (n, x) ->
        if n = 0 then
          None
        else
          Some(n, x))
      nxs
  in
  let nxs1, nxs2 = List.partition (fun (n, _) -> n > 0) nxs in
  sum ((if n > 0 then [tint n] else []) @ List.map (fun (n, x) -> if n = 1 then make_var x else mul (tint n) (make_var x)) nxs1),
  sum ((if n < 0 then [tint (-n)] else []) @ List.map (fun (n, x) -> if n = -1 then make_var x else mul (tint (-n)) (make_var x)) nxs2)

let rec arith_of t =
  match fun_args t with
    Var(_, x), [] ->
      [1, x], 0
  | Const(_, Const.Int(n)), [] ->
      [], n
  | Const(_, Const.Add), [t1; t2] ->
      let nxs1, n1 = arith_of t1 in
      let nxs2, n2 = arith_of t2 in
      Arith.canonize (nxs1 @ nxs2), n1 + n2
  | Const(_, Const.Sub), [t1; t2] ->
      let nxs1, n1 = arith_of t1 in
      let nxs2, n2 = arith_of t2 in
      let nxs2, n2 =  Arith.minus nxs2, -n2 in
      Arith.canonize (nxs1 @ nxs2), n1 + n2
  | Const(_, Const.Mul), [Const(_, Const.Int(m)); t]
  | Const(_, Const.Mul), [t; Const(_, Const.Int(m))] ->
      let nxs, n = arith_of t in
      Arith.mul m nxs, m * n
  | Const(_, Const.Minus), [t] ->
      let nxs, n = arith_of t in
      Arith.minus nxs, -n
  | Const(_, Const.Unit), [] ->
      [], 0 (*????*)
  | _ ->
      invalid_arg "Term.arith_of"

let int_rel_of t =
		match fun_args t with
		  Const(_, c), [t1; t2] when Const.is_ibin c ->
		    let nxs, n = arith_of (sub t1 t2) in
		    c, nxs, n
		| _ -> invalid_arg "Term.int_rel_of"

(** {6 Other functions} *)

let string_of t =
  Format.fprintf Format.str_formatter "%a" pr2 t;
  Format.flush_str_formatter ()

let rec redex_of env t =
  match t with
(*
				Const(a, Const.RandInt) ->
      (fun t -> t), Const(a, Const.RandInt)
*)
    App(_, _, _) ->
      let f, args = fun_args t in
      let rec r args1 args =
        match args with
          [] -> raise Not_found
        | arg::args2 ->
            (try
              args1, redex_of env arg, args2
            with Not_found ->
              r (args1 @ [arg]) args2)
      in
      (try
        let args1, (ctx, red), args2 = r [] args in
        (fun t -> apply f (args1 @ [ctx t] @ args2)), red
      with Not_found ->
		      (match f with
						    Const(_, Const.Event(id)) when Idnt.string_of id = "fail" ->
            let ar = 1 in
		          if List.length args >= ar then
		            let args1, args2 = List.split_nth ar args in
		            (fun t -> apply t args2), apply f args1
		          else raise Not_found
						  | Const(_, Const.RandInt) ->
            let ar = 1 in
		          if List.length args >= ar then
		            let args1, args2 = List.split_nth ar args in
		            (fun t -> apply t args2), apply f args1
		          else raise Not_found
		      | Var(attr, ff) ->
		          let ar =
		            try
		              SimType.arity (env ff)
		            with Not_found ->
		              raise Not_found (* ff is not a function name *)
		              (*(Format.printf "%a@." Var.pr ff; assert false)*)
		          in
		          if List.length args >= ar then
		            let args1, args2 = List.split_nth ar args in
		            (fun t -> apply t args2), apply f args1
		          else raise Not_found
		      | Const(attr, c) ->
		          raise Not_found
		      | _ -> assert false))
  | Call(a, f, args) ->
      (fun t -> t), Call(a, f, args)
  | Ret(a, ret, t, ty) ->
      (try
        let ctx, red = redex_of env t in
        (fun t -> Ret(a, ret, ctx t, ty)), red
      with Not_found ->
        (fun t -> t), Ret(a, ret, t, ty))
  | _ -> raise Not_found


let rec unit_vars is_unit t =
		match fun_args t with
		  Var(_, v), [] ->
      if is_unit then [v] else []
		| Const(_, c), [] ->
		    []
		| Const(a, Const.And), [t1; t2]
		| Const(a, Const.Or), [t1; t2]
		| Const(a, Const.Imply), [t1; t2]
		| Const(a, Const.Iff), [t1; t2]
		| Const(a, Const.Lt), [t1; t2]
		| Const(a, Const.Gt), [t1; t2]
		| Const(a, Const.Leq), [t1; t2]
		| Const(a, Const.Geq), [t1; t2]
		| Const(a, Const.EqBool), [t1; t2]
		| Const(a, Const.EqInt), [t1; t2]
		| Const(a, Const.NeqBool), [t1; t2]
		| Const(a, Const.NeqInt), [t1; t2]
		| Const(a, Const.Add), [t1; t2]
		| Const(a, Const.Sub), [t1; t2]
		| Const(a, Const.Mul), [t1; t2]
		| Const(a, Const.Minus), [t1; t2] ->
		    unit_vars false t1 @ unit_vars false t2
		| Const(a, Const.Not), [t] -> 
		    unit_vars false t
		| Const(a, Const.EqUnit), [t1; t2]
		| Const(a, Const.NeqUnit), [t1; t2] ->
		    unit_vars true t1 @ unit_vars true t2
		| t, _-> Format.printf "@.%a@." pr t; assert false

let rec boolean_vars is_boolean t =
		match fun_args t with
		  Var(_, v), [] ->
      if is_boolean then [v] else []
		| Const(_, c), [] ->
		    []
		| Const(a, Const.And), [t1; t2]
		| Const(a, Const.Or), [t1; t2]
		| Const(a, Const.Imply), [t1; t2]
		| Const(a, Const.Iff), [t1; t2]
		| Const(a, Const.EqBool), [t1; t2]
		| Const(a, Const.NeqBool), [t1; t2] ->
		    boolean_vars true t1 @ boolean_vars true t2
		| Const(a, Const.Lt), [t1; t2]
		| Const(a, Const.Gt), [t1; t2]
		| Const(a, Const.Leq), [t1; t2]
		| Const(a, Const.Geq), [t1; t2]
		| Const(a, Const.EqUnit), [t1; t2]
		| Const(a, Const.EqInt), [t1; t2]
		| Const(a, Const.NeqUnit), [t1; t2]
		| Const(a, Const.NeqInt), [t1; t2]
		| Const(a, Const.Add), [t1; t2]
		| Const(a, Const.Sub), [t1; t2]
		| Const(a, Const.Mul), [t1; t2]
		| Const(a, Const.Minus), [t1; t2] ->
		    boolean_vars false t1 @ boolean_vars false t2
		| Const(a, Const.Not), [t] -> 
		    boolean_vars true t
		| t, _-> Format.printf "@.%a@." pr t; assert false

(*
let rec set_arity am t =
  match t with
    Var(a, x) -> (try let ar = am x in Var(Attr.Arity(ar)::a, x) with Not_found -> Var(a, x))
  | Const(a, c) -> Const(a, c)
  | App(a, t1, t2) -> App(a, set_arity am t1, set_arity am t2)
  | Call(a, f, args) -> Call(a, set_arity am f, List.map (set_arity am) args)
  | Ret(a, ret, t) -> Ret(a, set_arity am ret, set_arity am t)
  | Error(a) -> Error(a)
*)


(** @param p variables satisfying p are bound *)
let rename_fresh p t =
  let fvs = List.filter (fun x -> not (p x)) (fvs t) in
  let sub = List.map (fun x -> x, make_var (Var.new_var ())) fvs in
  subst (fun x -> List.assoc x sub) t

