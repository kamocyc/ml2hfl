open Util
open CEGAR_syntax
open CEGAR_type
open CEGAR_print
open CEGAR_util
open Fpat.Combinator

module String = Fpat.Util.String
module List = Fpat.Util.List
module Array = Fpat.Util.Array

let rec conv_typ ty =
  match ty with
  | TBase(TUnit, _) -> Fpat.Type.mk_unit
  | TBase(TInt, _) -> Fpat.Type.mk_int
  | TBase(TBool, _) -> Fpat.Type.mk_bool
  | TBase(TAbst "string", _) -> Fpat.Type.mk_string
  | TBase(TAbst "float", _) -> Fpat.Type.mk_float
  | TBase(TAbst s, _) ->
     Fpat.Type.mk_const (Fpat.TypConst.Ext s)
  | TFun(ty1,tmp) ->
     let ty2 = tmp (Const True) in
     Fpat.Type.mk_fun [conv_typ ty1; conv_typ ty2]
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
  | RandInt _ -> Fpat.Const.RandInt
  | Add -> Fpat.Const.Add Fpat.Type.mk_int
  | Sub -> Fpat.Const.Sub Fpat.Type.mk_int
  | Mul -> Fpat.Const.Mul Fpat.Type.mk_int
  | Char c -> Fpat.Const.Int (int_of_char c)
  | String s -> Fpat.Const.String s
  | Float s -> Fpat.Const.Float (float_of_string s)
  | Int32 n -> Fpat.Const.Int (Int32.to_int n)
  | Int64 n -> Fpat.Const.Int (Int64.to_int n)
  | Nativeint n -> Fpat.Const.Int (Nativeint.to_int n)
  | CPS_result ->
     Fpat.Const.UFun
       (Fpat.Type.mk_const (Fpat.TypConst.Ext "X"),
        Fpat.Idnt.make "end")
  | _ -> Format.printf "%a@." CEGAR_print.const c; assert false

let conv_var x =
  if Fpat.EHCCSSolver.is_parameter x || isEX_COEFFS x then
    Fpat.Idnt.mk_coeff x
  else
    Fpat.Idnt.make x

let rec conv_term env t =
  match t with
  | Const(RandInt (Some n)) ->
      let env' = List.filter (is_base -| snd) env in
      let typs = List.map (conv_typ -| snd) env' in
      let r = Fpat.Const.ReadInt (Fpat.Idnt.make @@ make_randint_name n, typs) in
      Fpat.Term.mk_app (Fpat.Term.mk_const r) @@ List.map (Fpat.Term.mk_var -| conv_var -| fst) env'
  | Const(RandVal s) ->
     Fpat.Term.mk_var (Fpat.Idnt.make (new_id "r")) (***)
  | Const(c) ->
     Fpat.Term.mk_const (conv_const c)
  | Var(x) ->
      Fpat.Term.mk_var @@ conv_var x
  | App(t1, t2) -> Fpat.Term.mk_app (conv_term env t1) [conv_term env t2]
  | Fun _ -> assert false
  | Let _ -> assert false

let conv_formula t = t |> conv_term [] |> Fpat.Formula.of_term

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
  | Fpat.Const.RandInt -> RandInt None
  | Fpat.Const.Add ty when Fpat.Type.is_int ty -> Add
  | Fpat.Const.Sub ty when Fpat.Type.is_int ty -> Sub
  | Fpat.Const.Mul ty when Fpat.Type.is_int ty -> Mul
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
  | Fpat.Const.Float x -> Float (string_of_float x)
  | Fpat.Const.UFun(ty, x)
       when Fpat.Idnt.string_of x = "end"
            && Fpat.Type.is_ext ty && Fpat.Type.let_ext ty ((=) "X") ->
     CPS_result
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
     assert (x = "fail");
     Fpat.Term.mk_const (Fpat.Const.Event(x))
  | Branch(_) -> assert false

let conv_fdef env (f, args, guard, events, body) =
  { Fpat.Fdef.name = f;
    Fpat.Fdef.args = List.map (Fpat.Idnt.make >> Fpat.Pattern.mk_var) args;
    Fpat.Fdef.guard = conv_formula guard;
    Fpat.Fdef.body =
      List.fold_right
        (fun e t ->
         Fpat.Term.mk_app
           (conv_event e)
           [Fpat.Term.mk_const Fpat.Const.Unit])
        events (conv_term env body) } (***)

let inv_fdef fdef =
  fdef.Fpat.Fdef.name,
  fdef.Fpat.Fdef.args,
  inv_formula fdef.Fpat.Fdef.guard,
  [],
  inv_term fdef.Fpat.Fdef.body

let conv_prog (typs, fdefs, main) =
  { Fpat.Prog.fdefs =
      List.map (conv_fdef typs) fdefs;
    Fpat.Prog.types =
      List.map (fun (x, ty) -> Fpat.Idnt.make x, conv_typ ty) typs;
    Fpat.Prog.main = main }

let rec inv_abst_type aty =
  match aty with
  | Fpat.AbsType.Base(Fpat.TypConst.Ext(id), x, ts) ->
     let x = Fpat.Idnt.string_of x in
     TBase(TAbst(id),
           fun s -> List.map (fun t -> subst x s (inv_formula t)) ts)
  | Fpat.AbsType.Base(Fpat.TypConst.Unit, x, ts) ->
     let x = Fpat.Idnt.string_of x in
     TBase(TUnit,
           fun s -> List.map (fun t -> subst x s (inv_formula t)) ts)
  | Fpat.AbsType.Base(Fpat.TypConst.Bool, x, ts) ->
     let x = Fpat.Idnt.string_of x in
     TBase(TBool,
           fun s -> List.map (fun t -> subst x s (inv_formula t)) ts)
  | Fpat.AbsType.Base(Fpat.TypConst.Int, x, ts) ->
     let x = Fpat.Idnt.string_of x in
     TBase(TInt,
           fun s -> List.map (fun t -> subst x s (inv_formula t)) ts)
  | Fpat.AbsType.Base(Fpat.TypConst.Float, x, ts) ->
     let x = Fpat.Idnt.string_of x in
     TBase(TAbst("float"),
           fun s -> List.map (fun t -> subst x s (inv_formula t)) ts)
  | Fpat.AbsType.Base(Fpat.TypConst.String, x, ts) ->
     let x = Fpat.Idnt.string_of x in
     TBase(TAbst("string"),
           fun s -> List.map (fun t -> subst x s (inv_formula t)) ts)
  | Fpat.AbsType.Fun(aty1, aty2) ->
     let x =
       if Fpat.AbsType.is_base aty1 then
         Fpat.Idnt.string_of (Fpat.AbsType.bv_of aty1)
       else
         "_dummy"
     in
     TFun(inv_abst_type aty1, fun t -> subst_typ x t (inv_abst_type aty2))
  | _ ->
     Format.printf "%a@." Fpat.AbsType.pr aty;
     assert false


let init prog =
  let prog =
    conv_prog
      (prog.CEGAR_syntax.env,
       prog.CEGAR_syntax.defs,
       prog.CEGAR_syntax.main)
  in
  prog
  |> Fpat.RefTypJudge.mk_temp_env
  |> List.map snd
  |> List.concat_map Fpat.RefType.pvars
  |> List.map
       (Fpat.PredVar.reset_uid >> Fpat.PredVar.normalize_args)
  |> List.unique
  |> Fpat.HCCSSolver.init_rsrefine

let verify fs (*cexs*) prog =
  let prog =
    conv_prog
      (prog.CEGAR_syntax.env,
       prog.CEGAR_syntax.defs,
       prog.CEGAR_syntax.main)
  in
  Format.printf "@[<v>BEGIN verification:@,  %a@," Fpat.Prog.pr prog;
  assert false(*Verifier.verify fs prog*);
  Format.printf "END verification@,@]"

let is_cp {env=env;defs=defs;main=main} =
  let prog = conv_prog (env, defs, main) in
  Fpat.RefTypInfer.is_cut_point prog

let infer labeled is_cp cexs ext_cexs prog =
  let prog = conv_prog prog in
  let env = Fpat.AbsTypInfer.refine prog labeled is_cp cexs false ext_cexs in
  Flag.time_parameter_inference :=
    !Flag.time_parameter_inference +. !Fpat.EHCCSSolver.elapsed_time;
  List.map
    (fun (f, rty) ->
     match f with Fpat.Idnt.V(id) -> id, inv_abst_type rty | _ -> assert false)
    env

let infer_with_ext
    (labeled: string list)
    (is_cp: Fpat.Idnt.t -> bool)
    (cexs: int list list)
    (ext_cexs: ((Fpat.Idnt.t * Fpat.Pred.t list) list) list)
    (prog: (string * CEGAR_syntax.typ) list * (string * string list * CEGAR_syntax.t * CEGAR_syntax.event list * CEGAR_syntax.t) list * string)
  =
  let prog = conv_prog prog in
  let env = Fpat.AbsTypInfer.refine prog labeled is_cp cexs true ext_cexs in
  Flag.time_parameter_inference :=
    !Flag.time_parameter_inference +. !Fpat.EHCCSSolver.elapsed_time;
  List.map
    (fun (f, rty) ->
     match f with Fpat.Idnt.V(id) -> id, inv_abst_type rty | _ -> assert false)
    env

(*
  List.map
    (fun (f, _) ->
      try
        f, conv_siz_type (List.assoc (Fpat.Idnt.make f) env)
      with Not_found ->
        assert false)
    prog.Fpat.Prog.types
 *)


(** move the following codes to another file *)

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
                 if i < !Fpat.EHCCSSolver.number_of_extra_params then
                   Some(Id.new_var ~name:"ex" Type.TInt, i + 1)
                 else
                   None)
                0
           | _ ->
              []) @ [x'])
         xs)
  in
  List.fold_right (fun x ty -> Type.TFun(x,ty)) xs' tyret
and trans_id x = Id.make x.Id.id x.Id.name (trans_type x.Id.typ)

let of_term t = assert false (* @todo translate FPAT term to Syntax.typed_term *)

let insert_extra_param t =
  let tmp = get_time() in
  let debug = !Flag.debug_level > 0 in
  Fpat.EHCCSSolver.masked_params := [];
  let rec aux rfs bvs exs t =
    let desc =
      match t.Syntax.desc with
      | Syntax.Const c -> Syntax.Const c
      | Syntax.Var y -> Syntax.Var (trans_id y)
      | Syntax.Fun(y, t1) ->
         let y' = trans_id y in
         let ys =
           match y'.Id.typ with
           | Type.TFun(_, _)
           | Type.TTuple _(* ToDo: fix it *) ->
              Fpat.Util.List.unfold
                (fun i ->
                 if i < !Fpat.EHCCSSolver.number_of_extra_params then
                   Some(Id.new_var ~name:("ex" ^ gen_id ()) Type.TInt, i + 1)
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
               f {Syntax.desc=Syntax.Fun(y, t); Syntax.typ=ty; Syntax.attr=Syntax.ANone}),
              match ty with Type.TFun(_, ty') -> ty' | _ -> assert false)
             ((fun t -> t), trans_type t.Syntax.typ)
             ys'
         in
         let bvs, exs =
           (if true then
              bvs @ ys'
            else
              bvs @ [y']),
           exs @ ys
         in
         (f (aux rfs bvs exs t1)).Syntax.desc
      | Syntax.App(t1, ts) ->
         (match t1.Syntax.desc with Syntax.App(_, _) -> assert false | _ -> ());
         let t1' = aux rfs bvs exs t1 in
         let recursive, xss =
           match t1'.Syntax.desc with
           | Syntax.Var(f) ->
              (try
                  let _, xxss, _ =
                    List.find
                      (fun (f', _, recursive) -> recursive && Id.same f' f)
                      rfs
                  in
                  (if debug then
                     Format.printf "rec: %a@." Syntax.print_term t1');
                  let xxss =
                    List.take (List.length ts) xxss
                  in
                  true,
                  List.map2
                    (fun t (x, xs) ->
                     match t.Syntax.typ with
                     | Type.TFun(_, _)
                     | Type.TTuple _(* ToDo: fix it *) ->
                        (match t.Syntax.desc with
                         | Syntax.Var(y) when Id.same x y ->
                            let _ =
                              if debug then
                                Format.printf
                                  "arg %a of %a not changed@,"
                                  Syntax.print_id x Syntax.print_id f in xs
                         | _ -> [])
                     | _ -> [])
                    ts xxss
                with Not_found ->
                  (*let _ = List.iter (fun f -> Format.printf "r: %s@." f) rfs in*)
                  let _ =
                    if debug then
                      Format.printf "nonrec: %a@." Syntax.print_term t1'
                  in
                  false, [])
           | _ ->
              let _ =
                if debug then
                  Format.printf "nonrec: %a@." Syntax.print_term t1'
              in
              false, []
         in
         let ts' = List.map (aux rfs bvs exs) ts in
         let tss =
           List.mapi
             (fun i t ->
              match t.Syntax.typ with
              | Type.TFun(_, _)
              | Type.TTuple _(* ToDo: fix it *) ->
                 let bvs =
                   bvs
                   |> List.filter (fun x -> x.Id.typ = Type.TInt)
                   |> List.map (Id.to_string >> Fpat.Idnt.make)
                 in
                 let exs = List.map (Id.to_string >> Fpat.Idnt.make) exs in
                 Fpat.EHCCSSolver.new_params
                   (if recursive then
                      Some(Fpat.Util.List.nth xss i
                           |> List.map (Id.to_string >> Fpat.Idnt.make))
                    else
                      None)
                   bvs exs
                 |> List.map of_term
              | _ -> [])
             ts'
         in
         let ts'' =
           List.flatten
             (List.map2 (fun ts t -> ts @ [t]) tss ts')
         in
         Syntax.App(t1', ts'')
      | Syntax.If(t1, t2, t3) ->
         Syntax.If(aux rfs bvs exs t1, aux rfs bvs exs t2, aux rfs bvs exs t3)
      | Syntax.Branch(t1, t2) ->
         Syntax.Branch(aux rfs bvs exs t1, aux rfs bvs exs t2)
      | Syntax.Let(flag, bindings, t2) ->
         let bvs' =
           bvs @
             (if flag = Syntax.Nonrecursive then
                []
              else
                List.map
                  Fpat.Triple.fst bindings)
         in
         let aux' (f,xs,t) =
           let f' = trans_id f in
           let xs' = List.map trans_id xs in

           let xss =
             List.map
               (fun x ->
                match x.Id.typ with
                | Type.TFun(_, _)
                | Type.TTuple _(* ToDo: fix it *) ->
                   Fpat.Util.List.unfold
                     (fun i ->
                      if i < !Fpat.EHCCSSolver.number_of_extra_params then
                        Some(Id.new_var ~name:("ex" ^ gen_id ()) Type.TInt, i + 1)
                      else
                        None)
                     0
                | _ ->
                   [])
               xs'
           in
           let xs'' =
             List.flatten
               (List.map2 (fun xs x -> xs @ [x]) xss xs')
           in
           let bvs, exs =
             (if true then
                bvs' @ xs''
              else
                bvs' @ xs'),
             exs @ List.flatten xss
           in
           let rfs' =
             (f,
              List.map2
                (fun xs x -> x, xs)
                xss xs',
              flag <> Syntax.Nonrecursive) :: rfs
           in
           (* mutual recursion and binding partial applied functions are not supported
              let rfs' = (if flag = Flag.Nonrecursive then [] else List.map (fun (f, _, _) -> Id.to_string f) bindings) @ rfs in
            *)
           f', xs'', aux rfs' bvs exs t
         in
         let bindings' = List.map aux' bindings in
         Syntax.Let
           (flag, bindings',
            aux rfs
                (bvs @
                   List.map
                     Fpat.Triple.fst
                     bindings')
                exs t2)
      | Syntax.BinOp(op, t1, t2) -> Syntax.BinOp(op, aux rfs bvs exs t1, aux rfs bvs exs t2)
      | Syntax.Not t1 -> Syntax.Not (aux rfs bvs exs t1)
      | Syntax.Event(s,b) -> Syntax.Event(s,b)
      | Syntax.Record fields -> Syntax.Record (Fpat.Util.List.map (fun (f,(s,t1)) -> f,(s,aux rfs bvs exs t1)) fields)
      | Syntax.Field(i,s,f,t1) -> Syntax.Field(i,s,f,aux rfs bvs exs t1)
      | Syntax.SetField(n,i,s,f,t1,t2) -> Syntax.SetField(n,i,s,f,aux rfs bvs exs t1,aux rfs bvs exs t2)
      | Syntax.Nil -> Syntax.Nil
      | Syntax.Cons(t1,t2) ->
         Syntax.Cons(aux rfs bvs exs t1, aux rfs bvs exs t2)
      | Syntax.Constr(s,ts) ->
         Syntax.Constr(s, List.map (aux rfs bvs exs) ts)
      | Syntax.Match(t1,pats) ->
         let aux' (pat, cond, t) =
           (* ToDo: need to update pat!? *)
           pat,
           aux rfs (bvs @ Syntax.get_vars_pat pat) exs cond,
           aux rfs (bvs @ Syntax.get_vars_pat pat) exs t
         in
         Syntax.Match(aux rfs bvs exs t1, List.map aux' pats)
      | Syntax.Raise t -> Syntax.Raise (aux rfs bvs exs t)
      | Syntax.TryWith(t1,t2) -> Syntax.TryWith(aux rfs bvs exs t1, aux rfs bvs exs t2)
      | Syntax.Tuple ts -> Syntax.Tuple (List.map (aux rfs bvs exs) ts)
      | Syntax.Proj(i,t) -> Syntax.Proj(i, aux rfs bvs exs t)
      | Syntax.Bottom -> Syntax.Bottom
      | Syntax.Label(info,t) -> Syntax.Label(info, aux rfs bvs exs t)
      | Syntax.Ref t -> Syntax.Ref(aux rfs bvs exs t)
      | Syntax.Deref t -> Syntax.Deref(aux rfs bvs exs t)
      | Syntax.SetRef(t1,t2) ->
         Syntax.SetRef(aux rfs bvs exs t1, aux rfs bvs exs t2)
      | Syntax.TNone -> Syntax.TNone
      | Syntax.TSome t -> Syntax.TSome(aux rfs bvs exs t)
    in
    {Syntax.desc=desc; Syntax.typ=trans_type t.Syntax.typ; Syntax.attr=Syntax.ANone}
  in
  let res = aux [] [] [] t in
  let _ = add_time tmp Flag.time_parameter_inference in
  res

let instantiate_param (typs, fdefs, main as prog) =
  let tmp = get_time() in
  (if !Fpat.RefTypInfer.prev_sol = [] then
     Fpat.RefTypInfer.init_sol (conv_prog prog));
  let map =
    List.map
      (fun (x, n) ->
       Fpat.Idnt.string_of x, inv_term (Fpat.IntTerm.make n))
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
  add_time tmp Flag.time_parameter_inference;
  res





let simplify_term t =
(*
  if false then
  let _, t = CEGAR_trans.trans_term {Syntax.desc = t; Syntax.typ = Type.TBool } in
  let t = conv_formula t in
  let t = Fpat.FormulaSimplifier.simplify t in
  let t = inv_formula t in
  (CEGAR_trans.trans_inv_term t).Syntax.desc
  else
 *)
  t

let simplify_typed_term p =
  { p with Syntax.desc = simplify_term p.Syntax.desc }

let rec simplify typ =
  match typ with
  | Ref_type.Base(base, x, p) ->
     Ref_type.Base(base, x, simplify_typed_term p)
  | Ref_type.Fun(x,typ1,typ2) ->
     Ref_type.Fun(x, simplify typ1, simplify typ2)
  | Ref_type.Tuple xtyps ->
     Ref_type.Tuple (List.map (fun (x,typ) -> x, simplify typ) xtyps)
  | Ref_type.Inter typs ->
     Ref_type.Inter (List.map simplify typs)
  | Ref_type.Union typs ->
     Ref_type.Union (List.map simplify typs)
  | Ref_type.ExtArg(x,typ1,typ2) ->
     Ref_type.ExtArg(x, simplify typ1, simplify typ2)
  | Ref_type.List(x,p_len,y,p_i,typ) ->
     Ref_type.List(x, simplify_typed_term p_len, y, simplify_typed_term p_i, typ)

let compute_strongest_post prog ce ext_cex =
  Fpat.RankFunInfer.compute_strongest_post (conv_prog prog) ce ext_cex


let implies = Fpat.SMTProver.implies_dyn
let is_sat = Fpat.SMTProver.is_sat_dyn
let is_sat_forall_exists xs ys cond p =
  let open Fpat in
  let aux x = Fpat.Idnt.make x, Type.mk_int in
  let p' =
    Formula.forall (List.map aux xs) @@
      Formula.exists (List.map aux ys) @@
        Formula.imply (Formula.band @@ List.map conv_formula cond) @@
          conv_formula p
  in
  Fpat.SMTProver.is_sat_dyn p'
