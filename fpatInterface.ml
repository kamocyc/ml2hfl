open Util
open CEGAR_syntax
open CEGAR_type
open CEGAR_print
open CEGAR_util
open Fpat.Combinator

module CS = CEGAR_syntax
module S = Syntax

module String = Fpat.Util.String
module List = Fpat.Util.List
module Array = Fpat.Util.Array

module Debug = Debug.Make(struct let check = make_debug_check __MODULE__ end)

let rec conv_typ ty =
  match ty with
  | TBase(TUnit, _) -> Fpat.Type.mk_unit
  | TBase(TInt, _) -> Fpat.Type.mk_int
  | TBase(TBool, _) -> Fpat.Type.mk_bool
  | TBase(TAbst "string", _) -> Fpat.Type.mk_string
  | TBase(TAbst "float", _) -> Fpat.Type.mk_real
  | TBase(TAbst s, _) ->
     Fpat.Type.mk_const (Fpat.TypConst.Ext s)
  | TFun(ty1,tmp) ->
     let ty2 = tmp (Const True) in
     Fpat.Type.mk_fun [conv_typ ty1; conv_typ ty2]
  | TApp _ when is_ttuple ty ->
      let _,tys = decomp_tapp ty in
      Fpat.Type.mk_tuple @@ List.map conv_typ tys
  | TApp(TConstr TAssumeTrue, ty) -> conv_typ ty
  | _ ->
     Format.printf "%a@." CEGAR_print.typ ty;
     assert false

let conv_const c =
  match c with
  | Bottom -> Fpat.Const.Bot
  | Unit -> Fpat.Const.Unit
  | True -> Fpat.Const.True
  | False -> Fpat.Const.False
  | And -> Fpat.Const.And
  | Or -> Fpat.Const.Or
  | Not -> Fpat.Const.Not
  | Lt -> Fpat.Const.Lt Fpat.Type.mk_int
  | Gt -> Fpat.Const.Gt Fpat.Type.mk_int
  | Leq -> Fpat.Const.Leq Fpat.Type.mk_int
  | Geq -> Fpat.Const.Geq Fpat.Type.mk_int
  | EqUnit -> Fpat.Const.Eq Fpat.Type.mk_unit
  | EqBool -> Fpat.Const.Eq Fpat.Type.mk_bool
  | EqInt -> Fpat.Const.Eq Fpat.Type.mk_int
  | CmpPoly(typ,"=") ->
     Fpat.Const.Eq (Fpat.Type.mk_const (Fpat.TypConst.Ext typ))
  | CmpPoly(typ,"<>") ->
     Fpat.Const.Neq (Fpat.Type.mk_const (Fpat.TypConst.Ext typ))
  | CmpPoly(typ,"<") ->
     Fpat.Const.Lt (Fpat.Type.mk_const (Fpat.TypConst.Ext typ))
  | CmpPoly(typ,">") ->
     Fpat.Const.Gt (Fpat.Type.mk_const (Fpat.TypConst.Ext typ))
  | CmpPoly(typ,"<=") ->
     Fpat.Const.Leq (Fpat.Type.mk_const (Fpat.TypConst.Ext typ))
  | CmpPoly(typ,">=") ->
     Fpat.Const.Geq (Fpat.Type.mk_const (Fpat.TypConst.Ext typ))
  | Int(n) -> Fpat.Const.Int(n)
  | Rand(TInt, _) -> Fpat.Const.RandInt
  | Rand(typ, _) -> unsupported @@ Format.asprintf "Rand[%a]" CEGAR_print.typ_base typ
  | Add -> Fpat.Const.Add Fpat.Type.mk_int
  | Sub -> Fpat.Const.Sub Fpat.Type.mk_int
  | Mul -> Fpat.Const.Mul Fpat.Type.mk_int
  | Div -> Fpat.Const.Div Fpat.Type.mk_int
  | Char c -> Fpat.Const.Int (int_of_char c)
  | String s -> Fpat.Const.String s
  | Float r -> Fpat.Const.Real r
  | Int32 n -> Fpat.Const.Int (Int32.to_int n)
  | Int64 n -> Fpat.Const.Int (Int64.to_int n)
  | Nativeint n -> Fpat.Const.Int (Nativeint.to_int n)
  | CPS_result ->
     Fpat.Const.UFun
       (Fpat.Type.mk_const (Fpat.TypConst.Ext "X"),
        Fpat.Idnt.make "end")
  | Proj(n,i) -> Fpat.Const.Proj(List.make n (Fpat.Type.mk_const (Fpat.TypConst.Ext "?")), i)
  | Tuple n -> Fpat.Const.Tuple(List.make n (Fpat.Type.mk_const (Fpat.TypConst.Ext "?")))
  | CmpPoly (_, _) -> assert false
  | Temp s -> assert false
  | If  -> assert false
  | Label _ -> assert false
  | TreeConstr (_, _) -> assert false

let conv_var x =
  if Fpat.RefTypInfer.is_parameter x || is_extra_coeff_name x then
    Fpat.Idnt.mk_coeff x
  else
    Fpat.Idnt.make x

let rec conv_term env t =
  match t with
  | App(App(App(Const(If), t1), Const(True)), Const(False)) ->
     conv_term env t1
  | Const(Rand(TInt, Some n)) ->
      let typs,_ = decomp_rand_typ @@ assoc_renv n env in
      let typs' = List.map conv_typ typs in
      Fpat.Term.mk_const @@ Fpat.Const.ReadInt (Fpat.Idnt.make @@ make_randint_name n, typs')
  | Const(Rand(_, Some _)) -> assert false
  | Const(c) ->
     Fpat.Term.mk_const (conv_const c)
  | Var(x) ->
      Fpat.Term.mk_var @@ conv_var x
  | App(t1, t2) -> Fpat.Term.mk_app (conv_term env t1) [conv_term env t2]
  | Fun _ -> assert false
  | Let _ -> assert false

let conv_formula t = t |> conv_term [] |> Fpat.Formula.of_term

let rec of_typ typ =
  match Type.elim_tattr typ with
  | Type.TBase Type.TUnit -> Fpat.Type.mk_unit
  | Type.TBase Type.TInt -> Fpat.Type.mk_int
  | Type.TBase Type.TBool -> Fpat.Type.mk_bool
  | Type.TFun(x,typ) -> Fpat.Type.mk_fun [of_typ @@ Id.typ x; of_typ typ]
  | Type.TData "string" -> Fpat.Type.mk_string
  | _ ->
      Format.printf "FpatInterface of_typ: %a@." Print.typ typ;
      assert false

let rec of_term t =
  match S.desc t with
  | S.Const S.Unit -> Fpat.Term.mk_const @@ Fpat.Const.Unit
  | S.Const S.True -> Fpat.Term.mk_const @@ Fpat.Const.True
  | S.Const S.False -> Fpat.Term.mk_const @@ Fpat.Const.False
  | S.Const (S.Int n) -> Fpat.Term.mk_const @@ Fpat.Const.Int n
  | S.Const (S.String s) -> Fpat.Term.mk_const @@ Fpat.Const.String s
  | S.Var x -> Fpat.Term.mk_var @@ Fpat.Idnt.make @@ Id.to_string x
  | S.Not t1 -> Fpat.Term.mk_app (Fpat.Term.mk_const Fpat.Const.Not) [of_term t1]
  | S.BinOp(op, t1, t2) ->
      let op' =
        match op with
        | S.Eq ->
            begin
              match Type.elim_tattr @@ S.typ t1 with
              | Type.TBase Type.TUnit -> Fpat.Const.Eq Fpat.Type.mk_unit
              | Type.TBase Type.TInt -> Fpat.Const.Eq Fpat.Type.mk_int
              | Type.TBase Type.TBool -> Fpat.Const.Eq Fpat.Type.mk_bool
              | typ when typ = Type.typ_unknown -> Fpat.Const.Eq Fpat.Type.mk_int
              | typ ->
                  Format.eprintf "t1.S.typ: %a@." Print.typ typ;
                  unsupported "FpatInterface.of_term"
            end
        | S.Lt -> Fpat.Const.Lt Fpat.Type.mk_int
        | S.Gt -> Fpat.Const.Gt Fpat.Type.mk_int
        | S.Leq -> Fpat.Const.Leq Fpat.Type.mk_int
        | S.Geq -> Fpat.Const.Geq Fpat.Type.mk_int
        | S.And -> Fpat.Const.And
        | S.Or -> Fpat.Const.Or
        | S.Add -> Fpat.Const.Add Fpat.Type.mk_int
        | S.Sub -> Fpat.Const.Sub Fpat.Type.mk_int
        | S.Mult -> Fpat.Const.Mul Fpat.Type.mk_int
        | S.Div -> Fpat.Const.Div Fpat.Type.mk_int
      in
      Fpat.Term.mk_app (Fpat.Term.mk_const op') [of_term t1; of_term t2]
  | S.App({S.desc=S.Var p}, ts) when String.starts_with (Id.to_string p) "P_"  -> (* for predicate variables *)
      let ts' =
        ts
        |> List.map @@ Pair.add_right @@ of_typ -| S.typ
        |> List.map @@ Pair.map_fst of_term
      in
      Fpat.Pva.make (Fpat.Idnt.make @@ Id.to_string p) ts'
      |> Fpat.Pva.to_formula
      |> Fpat.Formula.term_of
  | S.Proj(i, t) ->
      let tys =
        match t.S.typ with
        | Type.TTuple xs ->
            List.map (Id.typ |- of_typ) xs
        | _ ->
            Format.printf "%a@." Print.typ t.S.typ;
            assert false
      in
      Fpat.Term.mk_app (Fpat.Term.mk_const @@ Fpat.Const.Proj(tys, i)) [of_term t]
  | S.Tuple ts ->
      let tys = List.map (S.typ |- of_typ) ts in
      Fpat.Term.mk_app (Fpat.Term.mk_const @@ Fpat.Const.Tuple tys) @@ List.map of_term ts
  | desc ->
      Format.eprintf "desc: %a@." Print.desc desc;
      unsupported "FpatInterface.of_term"

let inv_const c =
  match c with
  | Fpat.Const.Unit -> Unit
  | Fpat.Const.True -> True
  | Fpat.Const.False -> False
  | Fpat.Const.And -> And
  | Fpat.Const.Or -> Or
  | Fpat.Const.Not -> Not
  | Fpat.Const.Lt ty when Fpat.Type.is_int ty -> Lt
  | Fpat.Const.Gt ty when Fpat.Type.is_int ty -> Gt
  | Fpat.Const.Leq ty when Fpat.Type.is_int ty -> Leq
  | Fpat.Const.Geq ty when Fpat.Type.is_int ty -> Geq
  | Fpat.Const.Eq ty when Fpat.Type.is_unit ty -> EqUnit
  | Fpat.Const.Eq ty when Fpat.Type.is_bool ty -> EqBool
  | Fpat.Const.Eq ty when Fpat.Type.is_int ty -> EqInt
  | Fpat.Const.Int(n) -> Int(n)
  | Fpat.Const.RandInt -> Rand(TInt, None)
  | Fpat.Const.Add ty when Fpat.Type.is_int ty -> Add
  | Fpat.Const.Sub ty when Fpat.Type.is_int ty -> Sub
  | Fpat.Const.Mul ty when Fpat.Type.is_int ty -> Mul
  | Fpat.Const.Div ty when Fpat.Type.is_int ty -> Div
  | Fpat.Const.Eq ty when Fpat.Type.is_ext ty ->
     Fpat.Type.let_ext ty (fun typ -> CmpPoly(typ,"="))
  | Fpat.Const.Neq ty when Fpat.Type.is_ext ty ->
     Fpat.Type.let_ext ty (fun typ -> CmpPoly(typ,"<>"))
  | Fpat.Const.Lt ty when Fpat.Type.is_ext ty ->
     Fpat.Type.let_ext ty (fun typ -> CmpPoly(typ,"<"))
  | Fpat.Const.Gt ty when Fpat.Type.is_ext ty ->
     Fpat.Type.let_ext ty (fun typ -> CmpPoly(typ,">"))
  | Fpat.Const.Leq ty when Fpat.Type.is_ext ty ->
     Fpat.Type.let_ext ty (fun typ -> CmpPoly(typ,"<="))
  | Fpat.Const.Geq ty when Fpat.Type.is_ext ty ->
     Fpat.Type.let_ext ty (fun typ -> CmpPoly(typ,">="))
  | Fpat.Const.String s -> String s
  | Fpat.Const.Real r -> Float r
  | Fpat.Const.UFun(ty, x)
       when Fpat.Idnt.string_of x = "end"
            && Fpat.Type.is_ext ty && Fpat.Type.let_ext ty ((=) "X") ->
     CPS_result
  | Fpat.Const.Proj(typs, i) -> Proj(List.length typs, i)
  | Fpat.Const.Iff -> And (* for -safe-fun-arg-pred_true (to fix) *)
  | _ -> Format.printf "%s@." (Fpat.Const.string_of c); assert false

let rec inv_term t =
  match t with
  | Fpat.Term.Const(c) -> Const(inv_const c)
  | Fpat.Term.Var(x) -> Var(Fpat.Idnt.string_of x)
  | Fpat.Term.App(Fpat.Term.App(t1, t2), t3) ->
     (match t1 with
      | Fpat.Term.Const(Fpat.Const.Neq (ty)) when Fpat.Type.is_unit ty ->
         App(Const(Not), App(App(Const(EqUnit), inv_term t2), inv_term t3))
      | Fpat.Term.Const(Fpat.Const.Neq (ty)) when Fpat.Type.is_bool ty ->
         App(Const(Not), App(App(Const(EqBool), inv_term t2), inv_term t3))
      | Fpat.Term.Const(Fpat.Const.Neq (ty)) when Fpat.Type.is_int ty ->
         App(Const(Not), App(App(Const(EqInt), inv_term t2), inv_term t3))
      | _ ->
         App(App(inv_term t1, inv_term t2), inv_term t3))
  | Fpat.Term.App(t1, t2) -> App(inv_term t1, inv_term t2)
  | Fpat.Term.Binder(_, _, _) -> assert false

let inv_formula t = t |> Fpat.Formula.term_of |> inv_term


let conv_event e = (***)
  match e with
  | Event(x) ->
    if x <> "fail" && Flag.Method.(!mode <> FairNonTermination) then
      Format.eprintf "Warning: fpat does not support general events.";
    Fpat.Term.mk_const (Fpat.Const.Event(x))
  | Branch(_) -> assert false

let conv_fdef typs (f, args, guard, events, body) =
  { Fpat.Fdef.name = f;
    Fpat.Fdef.args = List.map (Fpat.Idnt.make >> Fpat.Pattern.mk_var) args;
    Fpat.Fdef.guard = conv_formula guard;
    Fpat.Fdef.body =
      List.fold_right
        (fun e t ->
          let t' =
            if e <> Event "fail" && Flag.Method.(List.mem !mode  [FairTermination; FairNonTermination]) then
              t
            else
              Fpat.Term.mk_const Fpat.Const.Unit in
          Fpat.Term.mk_app
            (conv_event e)
            [t'])
        events (conv_term typs body) } (***)

let inv_fdef fdef =
  fdef.Fpat.Fdef.name,
  fdef.Fpat.Fdef.args,
  inv_formula fdef.Fpat.Fdef.guard,
  [],
  inv_term fdef.Fpat.Fdef.body

let conv_prog prog =
  let typs = prog.CEGAR_syntax.env in
  let fdefs = prog.CEGAR_syntax.defs in
  let main = prog.CEGAR_syntax.main in
  { Fpat.Prog.fdefs =
      List.map (conv_fdef typs) fdefs;
    Fpat.Prog.types =
      List.map (fun (x, ty) -> Fpat.Idnt.make x, conv_typ ty) typs;
    Fpat.Prog.main = main }

(* TODO: merge this function to conversion from refinement types to abstraction types *)
let add_to_temp t1 t2 =
  let rec aux t =
    match decomp_app t with
    | Const (Int 0), [] -> []
    | Const Add, [Const (Int n); t2] -> Const (Int n) :: aux t2
    | _ -> assert false
  in
  make_app (Const (Temp "path")) (t2 :: aux t1)
let rec path_to_attr ty =
  match ty with
  | TBase(b, p) -> ty
  | TConstr c -> unsupported "FpatInterface.path_to_attr (TConstr)"
  | TApp _ -> unsupported "FpatInterface.path_to_attr (TApp)"
  | TFun(TBase(b,p), ty2) ->
      let x = new_id "x" in
      let aux t =
        match decomp_app t with
        | Const And, [t1;t2] -> [add_to_temp t1 t2]
        | Const Add, _ -> [add_to_temp t (Const True)]
        | _ ->
            Format.printf "%a@." CEGAR_print.term t;
            assert false
      in
      let preds = List.concat_map aux @@ p (Var x) in
      let p' t = List.map (subst x t) preds in
      let ty2' = path_to_attr -| ty2 in
      TFun(TBase(b,p'), ty2')
  | TFun(ty1, ty2) -> TFun(path_to_attr ty1, path_to_attr -| ty2)

let rec inv_abst_type aty =
  match aty with
  | Fpat.AbsType.Base(Fpat.TypConst.Ext("X"), x, ts) ->
      TBase(TAbst("X"), fun s -> [])
  | Fpat.AbsType.Base(b, x, ts) ->
      let x = Fpat.Idnt.string_of x in
      let base =
        let open Fpat.TypConst in
        match b with
        | Ext id -> TAbst id
        | Unit -> TUnit
        | Bool -> TBool
        | Int -> TInt
        | Real -> TAbst "float"
        | String -> TAbst "string"
        | _ ->
            Format.printf "%a@." Fpat.AbsType.pr aty;
            assert false
      in
      TBase(base, fun s -> List.map (subst x s -| inv_formula) ts)
  | Fpat.AbsType.Fun(aty1, aty2) ->
      let x =
        if Fpat.AbsType.is_base aty1 then
          Fpat.Idnt.string_of (Fpat.AbsType.bv_of aty1)
        else
          "_dummy"
      in
      TFun(inv_abst_type aty1, subst_typ x -$- (inv_abst_type aty2))
let inv_abst_type ty =
  ty
  |> inv_abst_type
  |&(!Flag.PredAbst.shift_pred<>None)&> path_to_attr


let verify fs (*cexs*) prog =
  let prog = conv_prog prog in
  Format.printf "@[<v>BEGIN verification:@,  %a@," Fpat.Prog.pr prog;
  assert false(*Verifier.verify fs prog;
  Format.printf "END verification@,@]"*)

let is_cp prog =
  prog
  |> conv_prog
  |> Fpat.RefTypInfer.is_cut_point

let infer labeled is_cp cexs ext_cexs prog =
  let fs = List.map fst prog.env in
  let defs' =
    if Flag.Method.(!mode = FairNonTermination || !verify_ref_typ) then (* TODO: ad-hoc fix, remove after Fpat is fiexed *)
      let aux f =
        if CEGAR_syntax.is_randint_var f then
          []
        else
          let argss =
            List.filter_map (fun (g, args, _, _, _) ->
              if f = g then
                Some args
              else
                None
            ) prog.defs in
          let n = List.length argss in
          List.make (3 - n) (f, List.hd argss, Const True, [Event "fail"], Const Unit) in
      prog.defs @ List.concat_map aux fs
    else
      prog.defs in
  let prog = conv_prog {prog with defs=defs'} in
  let cexs =
    if Flag.Method.(!mode = FairNonTermination || !verify_ref_typ) then (* TODO: ad-hoc fix, remove after Fpat is fiexed *)
      List.map (flip (@) [2]) cexs
    else
      cexs in
  let env = Fpat.AbsTypInfer.refine prog labeled is_cp cexs false ext_cexs in
  Flag.Log.time_parameter_inference :=
    !Flag.Log.time_parameter_inference +. !Fpat.EAHCCSSolver.elapsed_time;
  List.map (Pair.map Fpat.Idnt.base inv_abst_type) env

let infer_with_ext
    (labeled: string list)
    (is_cp: Fpat.Idnt.t -> bool)
    (cexs: int list list)
    (ext_cexs: ((Fpat.Idnt.t * Fpat.Pred.t list) list) list)
    (prog: CEGAR_syntax.prog)
  =
  Verbose.printf "labeled %a@." (Util.List.print Format.pp_print_string) labeled;
  Verbose.printf "cexs %a@." (Util.List.print @@ Util.List.print Format.pp_print_int) cexs;
  let pr ppf (tenv, phi) =
    Verbose.fprintf ppf "(%a).%a" Fpat.TypEnv.pr tenv Fpat.Formula.pr phi
  in
  Verbose.printf "ext_cexs %a@." (Util.List.print @@ Util.List.print (fun fm (x,p) -> Format.fprintf fm "%a, %a" Fpat.Idnt.pr x (Util.List.print pr) p)) ext_cexs;
  let fs = List.map fst prog.env in
  let defs' =
    if Flag.Method.(!mode = FairNonTermination) then (* TODO ad-hoc fix, remove after Fpat is fiexed *)
      let aux f =
        if CEGAR_syntax.is_randint_var f then
          []
        else
          let argss =
          List.filter_map (fun (g, args, _, _, _) ->
            if f = g then
              Some args
            else
              None
          ) prog.defs in
          let n = List.length argss in
          List.make (3 - n) (f, List.hd argss, Const True, [Event "fail"], Const Unit) in
      prog.defs @ List.concat_map aux fs
    else
      prog.defs in

  let prog = conv_prog {prog with defs=defs'} in

  let cexs =
    if Flag.Method.(!mode = FairNonTermination) then (* TODO ad-hoc fix, remove after Fpat is fiexed *)
      List.map (flip (@) [2]) cexs
    else
      cexs in
  Verbose.printf "@[<v>BEGIN refinement:@,  %a@," Fpat.Prog.pr prog;
  let old_split_eq = !Fpat.AbsType.split_equalities in
  let old_eap = !Fpat.AbsType.extract_atomic_predicates in
  let old_hccs_solver = Fpat.HCCSSolver.get_dyn () in
  Fpat.AbsType.split_equalities := true;
  Fpat.AbsType.extract_atomic_predicates := true;
  Fpat.HCCSSolver.link_dyn
    (fst -| fst -| Fpat.AEHCCSSolver.solve
        (Fpat.EAHCCSSolver.solve [] [] [] Fpat.BwIPHCCSSolver.solve));
  let env = Fpat.AbsTypInfer.refine prog labeled is_cp cexs true ext_cexs in
  Fpat.AbsType.split_equalities := old_split_eq;
  Fpat.AbsType.extract_atomic_predicates := old_eap;
  Fpat.HCCSSolver.link_dyn old_hccs_solver;
  Verbose.printf "END refinement@,@]";

  Flag.Log.time_parameter_inference :=
    !Flag.Log.time_parameter_inference +. !Fpat.EAHCCSSolver.elapsed_time;
  List.map (Pair.map Fpat.Idnt.base inv_abst_type) env


(** TODO: move the following codes to another file *)

let gen_id =
  let cnt = ref 0 in
  fun () -> cnt := !cnt + 1; string_of_int !cnt

let rec trans_type typ =
  let xs, tyret = Type.decomp_tfun typ in
  let xs' =
    List.flatten
      (List.map
         (fun x ->
          let x' = trans_id x in
          (match x'.Id.typ with
           | Type.TFun(_, _)
           | Type.TTuple _(* ToDo: fix it *) ->
              Fpat.Util.List.unfold
                (fun i ->
                 if i < !Fpat.RefTypInfer.number_of_extra_params then
                   Some(Id.new_var ~name:"ex" Type.Ty.int, i + 1)
                 else
                   None)
                0
           | _ ->
              []) @ [x'])
         xs)
  in
  List.fold_right (fun x ty -> Type.TFun(x,ty)) xs' tyret
and trans_id x = Id.map_typ trans_type x

let of_desc t = assert false (* @todo translate FPAT term to S.term *)

let insert_extra_param t =
  let tmp = Time.get() in
  Fpat.RefTypInfer.masked_params := [];
  let rec aux rfs bvs exs t =
    let desc =
      match t.S.desc with
      | S.Const c -> S.Const c
      | S.Var y -> S.Var (trans_id y)
      | S.Fun(y, t1) ->
         let y' = trans_id y in
         let ys =
           match y'.Id.typ with
           | Type.TFun(_, _)
           | Type.TTuple _(* ToDo: fix it *) ->
              Fpat.Util.List.unfold
                (fun i ->
                 if i < !Fpat.RefTypInfer.number_of_extra_params then
                   Some(Id.new_var ~name:("ex" ^ gen_id ()) Type.Ty.int, i + 1)
                 else
                   None)
                0
           | _ ->
              []
         in
         let ys' = ys @ [y'] in
         let rfs =
           match rfs with
           | [] -> assert false
           | (f, xxs, recursive)::rfs' ->
              (f, xxs @ [y', ys], recursive)::rfs' in
         let f, _ =
           List.fold_left
             (fun (f, ty) y ->
              (fun t ->
               f {S.desc=S.Fun(y, t); S.typ=ty; S.attr=[]}),
              match ty with Type.TFun(_, ty') -> ty' | _ -> assert false)
             ((fun t -> t), trans_type t.S.typ)
             ys'
         in
         let bvs, exs =
           (if true then
              bvs @ ys'
            else
              bvs @ [y']),
           exs @ ys
         in
         (f (aux rfs bvs exs t1)).S.desc
      | S.App(t1, ts) ->
         (match t1.S.desc with S.App(_, _) -> assert false | _ -> ());
         let t1' = aux rfs bvs exs t1 in
         let recursive, xss =
           match t1'.S.desc with
           | S.Var(f) ->
              (try
                  let _, xxss, _ =
                    List.find
                      (fun (f', _, recursive) -> recursive && Id.same f' f)
                      rfs
                  in
                  (Debug.printf "rec: %a@." Print.term t1');
                  let xxss =
                    List.take (List.length ts) xxss
                  in
                  true,
                  List.map2
                    (fun t (x, xs) ->
                     match t.S.typ with
                     | Type.TFun(_, _)
                     | Type.TTuple _(* ToDo: fix it *) ->
                        (match t.S.desc with
                         | S.Var(y) when Id.same x y ->
                             Debug.printf "arg %a of %a not changed@," Print.id x Print.id f;
                             xs
                         | _ -> [])
                     | _ -> [])
                    ts xxss
                with Not_found ->
                  (*let _ = List.iter (fun f -> Format.printf "r: %s@." f) rfs in*)
                  Debug.printf "non_rec: %a@." Print.term t1';
                  false, [])
           | _ ->
               Debug.printf "non_rec: %a@." Print.term t1';
               false, []
         in
         let ts' = List.map (aux rfs bvs exs) ts in
         let tss =
           List.mapi
             (fun i t ->
              match t.S.typ with
              | Type.TFun(_, _)
              | Type.TTuple _(* ToDo: fix it *) ->
                 let bvs =
                   bvs
                   |> List.filter (fun x -> x.Id.typ = Type.Ty.int)
                   |> List.map (Id.to_string >> Fpat.Idnt.make)
                 in
                 let exs = List.map (Id.to_string >> Fpat.Idnt.make) exs in
                 Fpat.RefTypInfer.new_params
                   (if recursive then
                      Some(Fpat.Util.List.nth xss i
                           |> List.map (Id.to_string >> Fpat.Idnt.make))
                    else
                      None)
                   bvs exs
                 |> List.map of_desc
              | _ -> [])
             ts'
         in
         let ts'' =
           List.flatten
             (List.map2 (fun ts t -> ts @ [t]) tss ts')
         in
         S.App(t1', ts'')
      | S.If(t1, t2, t3) ->
         S.If(aux rfs bvs exs t1, aux rfs bvs exs t2, aux rfs bvs exs t3)
      | S.Local(S.Decl_type decls, t2) -> S.Local(S.Decl_type decls, aux rfs bvs exs t2)
      | S.Local(S.Decl_let bindings, t2) ->
         let bvs' =
           bvs @ List.map fst bindings
         in
         let aux' (f,t) =
           let f' = trans_id f in
           (* mutual recursion and binding partial applied functions are not supported
              let rfs' = (if flag = Flag.Nonrecursive then [] else List.map (fun (f, _, _) -> Id.to_string f) bindings) @ rfs in
            *)
           f', aux rfs bvs' exs t
         in
         let bindings' = List.map aux' bindings in
         S.Local
           (S.Decl_let bindings',
            aux rfs
                (bvs @
                   List.map
                     fst
                     bindings')
                exs t2)
      | S.BinOp(op, t1, t2) -> S.BinOp(op, aux rfs bvs exs t1, aux rfs bvs exs t2)
      | S.Not t1 -> S.Not (aux rfs bvs exs t1)
      | S.Event(s,b) -> S.Event(s,b)
      | S.Record fields -> S.Record (List.map (Pair.map_snd @@ aux rfs bvs exs) fields)
      | S.Field(t1,s) -> S.Field(aux rfs bvs exs t1,s)
      | S.SetField(t1,s,t2) -> S.SetField(aux rfs bvs exs t1,s,aux rfs bvs exs t2)
      | S.Nil -> S.Nil
      | S.Cons(t1,t2) ->
         S.Cons(aux rfs bvs exs t1, aux rfs bvs exs t2)
      | S.Constr(s,ts) ->
         S.Constr(s, List.map (aux rfs bvs exs) ts)
      | S.Match(t1,pats) ->
         let aux' (pat, cond, t) =
           (* ToDo: need to update pat!? *)
           pat,
           aux rfs (bvs @ S.get_bv_pat pat) exs cond,
           aux rfs (bvs @ S.get_bv_pat pat) exs t
         in
         S.Match(aux rfs bvs exs t1, List.map aux' pats)
      | S.Raise t -> S.Raise (aux rfs bvs exs t)
      | S.TryWith(t1,t2) -> S.TryWith(aux rfs bvs exs t1, aux rfs bvs exs t2)
      | S.Tuple ts -> S.Tuple (List.map (aux rfs bvs exs) ts)
      | S.Proj(i,t) -> S.Proj(i, aux rfs bvs exs t)
      | S.Bottom -> S.Bottom
      | S.Label(info,t) -> S.Label(info, aux rfs bvs exs t)
      | S.Ref t -> S.Ref(aux rfs bvs exs t)
      | S.Deref t -> S.Deref(aux rfs bvs exs t)
      | S.SetRef(t1,t2) ->
         S.SetRef(aux rfs bvs exs t1, aux rfs bvs exs t2)
      | S.TNone -> S.TNone
      | S.TSome t -> S.TSome(aux rfs bvs exs t)
      | S.Module decls -> unsupported "insert_extra_param Module"
    in
    {t with S.desc}
  in
  let res = aux [] [] [] t in
  let _ = Time.add tmp Flag.Log.time_parameter_inference in
  res

let instantiate_param prog =
  let tmp = Time.get() in
  let typs = prog.CEGAR_syntax.env in
  let fdefs = prog.CEGAR_syntax.defs in
  let main = prog.CEGAR_syntax.main in
  (if !Fpat.RefTypInfer.prev_sol = [] then
     Fpat.RefTypInfer.init_sol (conv_prog prog));
  let map =
    List.map
      (fun (x, t) ->
       Fpat.Idnt.string_of x, inv_term t)
      !Fpat.RefTypInfer.prev_sol
  in
  let res =
    typs,
    List.map
      (fun (f, args, guard, events, body) ->
       (f,
        args,
        CEGAR_util.subst_map map guard,
        events,
        CEGAR_util.subst_map map body))
      fdefs,
    main
  in
  Time.add tmp Flag.Log.time_parameter_inference;
  res





let simplify_term t =
(*
  if false then
  let _, t = CEGAR_trans.trans_term {S.desc = t; S.typ = Type.TBool } in
  let t = conv_formula t in
  let t = Fpat.FormulaSimplifier.simplify t in
  let t = inv_formula t in
  (CEGAR_trans.trans_inv_term t).S.desc
  else
 *)
  t

let simplify_term p =
  { p with S.desc = simplify_term p.S.desc }

let compute_strongest_post prog ce ext_cex =
  Fpat.RankFunInfer.compute_strongest_post (conv_prog prog) ce ext_cex


let implies = Fpat.SMTProver.implies_dyn
let is_sat = Fpat.SMTProver.is_sat_dyn
let is_valid t = implies [Fpat.Formula.of_term @@ Fpat.Term.mk_const Fpat.Const.True] [t]
let is_valid_forall_exists xs ys cond p =
  let open Fpat in
  let aux x = Idnt.make x, Type.mk_int in
  let p' =
    Formula.forall (List.map aux xs) @@
      Formula.exists (List.map aux ys) @@
        Formula.imply (Formula.band @@ List.map conv_formula cond) @@
          conv_formula p
  in
  SMTProver.is_valid_dyn p'

let conv_pred (env: CEGAR_syntax.env) (p: CEGAR_syntax.t) =
  let env = env
  |> List.filter (is_base -| snd)
  |> List.map (Fpat.Pair.map Fpat.Idnt.make conv_typ) in
  let phi = conv_formula p in
  ((env, phi) : Fpat.Pred.t)

let trans_ext (renv : (int * CEGAR_syntax.env) list) (map : (int * (CEGAR_syntax.t -> CEGAR_syntax.t list)) list) (n, bs) =
  let r = make_randint_name n in
  let env = List.assoc n renv in
  let new_var = Var(r) in
  let abst_preds = (List.assoc n map) new_var in
  let rand_var = conv_var r in
  let add_pred acc p = function
    | Positive -> make_and p acc
    | Negative -> make_and (make_not p) acc
    | Do_not_Care -> acc
  in
  let ext_abstraction = List.map (List.fold_left2 add_pred (Const True) abst_preds) bs in
  let preds_sequence = List.map (conv_pred env) ext_abstraction in
  rand_var, preds_sequence


let parse_arg arg =
  let args = Array.of_list @@ "FPAT" :: Util.String.split_blanc arg in
  let usage = "Options for FPAT are:" in
  try
    Arg.parse_argv ~current:(ref 0) args (Arg.align Fpat.FPATConfig.arg_spec) ignore usage
  with
  | Arg.Bad s
  | Arg.Help s -> Format.printf "%s" s; exit 0
