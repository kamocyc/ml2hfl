open ExtList
open Term

(** Logical formulas (i.e., term expressions of the type bool) *)

(** {6 Constructors} *)

(** tautology *)
let ttrue = Const([], Const.True)

(** contradiction *)
let tfalse = Const([], Const.False)

let band ts =
  let rec aux ts =
    match ts with
      [] -> ttrue
    | [t] -> t
    | (Const(_, Const.True))::ts' -> aux ts'
    | (Const(_, Const.False))::_ -> raise Not_found
    | t::ts' ->
        let t' = aux ts' in
        (match t' with
          Const(_, Const.True) ->
            t
        | _ ->
            apply (Const([], Const.And)) [t; t'])
  in
  try
    aux (List.unique ts)
  with Not_found ->
    tfalse

let bor ts =
  let rec aux ts =
    match ts with
      [] -> tfalse
    | [t] -> t
    | (Const(_, Const.True))::_ -> raise Not_found
    | (Const(_, Const.False))::ts' -> aux ts'
    | t::ts' ->
        let t' = aux ts' in
        (match t' with
          Const(_, Const.False) ->
            t
        | _ ->
            apply (Const([], Const.Or)) [t; t'])
  in
  try
    aux (List.unique ts)
  with Not_found ->
    ttrue

let bnot t =
  match fun_args t with
    Const(a, Const.True), [] -> Const(a, Const.False)
  | Const(a, Const.False), [] -> Const(a, Const.True)
  | Const(a, Const.Not), [t] -> t
  | _ -> apply (Const([], Const.Not)) [t]

let imply t1 t2 =
  if Term.equiv t1 ttrue then
    t2
  else if Term.equiv t1 tfalse then
    ttrue
  else if Term.equiv t2 ttrue then
    ttrue
  else if Term.equiv t2 tfalse then
    bnot t1
  else
    apply (Const([], Const.Imply)) [t1; t2]

let forall env t =
  let xs = fvs t in
  let _ = if false then Format.printf "env: %a@,xs: %a@," SimType.pr_env env Var.pr_list xs in
  let env = List.filter (fun (x, _) -> List.mem x xs) env in
  if env = [] then t else Forall([], env, t)

let exists env t =
  let xs = fvs t in
  let _ = if false then Format.printf "env: %a@,xs: %a@," SimType.pr_env env Var.pr_list xs in
  let env = List.filter (fun (x, _) -> List.mem x xs) env in
  if env = [] then t else Exists([], env, t)
  (*bnot (forall env (bnot t))*)

let iff t1 t2 =
  if Term.equiv t1 t2 then
    ttrue
  else
    apply (Const([], Const.Iff)) [t1; t2]
    (*band [imply t1 t2; imply t2 t1]*)

let eqUnit t1 t2 = apply (Const([], Const.EqUnit)) [t1; t2]
let neqUnit t1 t2 = apply (Const([], Const.NeqUnit)) [t1; t2]
let eqBool t1 t2 = apply (Const([], Const.EqBool)) [t1; t2]
let neqBool t1 t2 = apply (Const([], Const.NeqBool)) [t1; t2]
let eqInt t1 t2 = apply (Const([], Const.EqInt)) [t1; t2]
let neqInt t1 t2 = apply (Const([], Const.NeqInt)) [t1; t2]
(** ignore equalities on functions *)
let eq_tty (t1, ty1) (t2, ty2) =
  let _ = if !Global.debug then assert (ty1 = ty2) in
  match ty1 with
    SimType.Unit ->
      eqUnit t1 t2
  | SimType.Bool ->
      eqBool t1 t2
  | SimType.Int ->
      eqInt t1 t2
  | SimType.Fun(_, _) ->
      ttrue(*???assert false*)
  | _ ->
      let _ = Format.printf "%a@," SimType.pr ty1 in
      assert false
let lt t1 t2 = apply (Const([], Const.Lt)) [t1; t2]
let gt t1 t2 = apply (Const([], Const.Gt)) [t1; t2]
(*let gt t1 t2 = apply (Const([], Const.Lt)) [t2; t1]*)
let leq t1 t2 = apply (Const([], Const.Leq)) [t1; t2]
(*let leq t1 t2 = apply (Const([], Const.Or)) [lt t1 t2; eq t1 t2]*)
let geq t1 t2 = apply (Const([], Const.Geq)) [t1; t2]
(*let geq t1 t2 = apply (Const([], Const.Or)) [gt t1 t2; eq t1 t2]*)
let ibrel c t1 t2 = apply (Const([], c)) [t1; t2]

(** ignore equalities on functions *)
let of_subst_elem (x, t, ty) =
  eq_tty (Term.make_var x, ty) (t, ty)
let of_subst sub = band (List.map of_subst_elem sub)

let forall_imply conds_envs t =
  List.fold_right
    (fun (cond, env) t ->
      let sub = List.filter (fun (x, _, _) -> List.mem_assoc x env) (TypSubst.sub_of cond) in
      try
        subst (TypSubst.fun_of sub) t
      with Not_found ->
        forall env (imply cond t))
    conds_envs t

(** {6 Destructors} *)

let rec atoms t =
  match fun_args t with
    Var(_, _), [] ->
      [t]
  | Const(_, Const.True), []
  | Const(_, Const.False), [] ->
      []
  | Const(_, Const.And), [t1; t2]
  | Const(_, Const.Or), [t1; t2]
  | Const(_, Const.Imply), [t1; t2]
  | Const(_, Const.Iff), [t1; t2] ->
      atoms t1 @ atoms t2
  | Const(_, Const.Not), [t] -> 
      atoms t
  | Const(_, bop), [_; _] ->
      [t]
  | t, _->
      Format.printf "@,%a@," Term.pr t; assert false

let rec conjuncts t =
  match fun_args t with
    Const(_, Const.And), [t1; t2] ->
      conjuncts t1 @ conjuncts t2
  | _, _ -> [t]

let rec disjuncts t =
  match fun_args t with
    Const(_, Const.Or), [t1; t2] ->
      disjuncts t1 @ disjuncts t2
  | _, _ -> [t]
