
open Utilities
open CEGAR_syntax
open CEGAR_type
open CEGAR_print
open CEGAR_util
open CEGAR_abst_util



let abst_arg x typ =
  let ps =
    match typ with
        TBase(_,ps) -> ps (Var x)
      | _ -> []
  in
  let n = List.length ps in
    Utilities.mapi (fun i p -> p, App(Const (Proj(n,i)), Var x)) ps



let rec coerce env cond pts typ1 typ2 t =
  match typ1,typ2 with
      _ when congruent env cond typ1 typ2 -> Format.printf "COERCE: %a  ===>  %a@." CEGAR_print.print_typ typ1 CEGAR_print.print_typ typ2;t
    | TBase(_,ps1),TBase(_,ps2) ->
        let var = match t with Var x -> Some x | _ -> None in
        let x = match var with None -> new_id "x" | Some x -> x in
        let env' = (x,typ1)::env in
        let pts' = abst_arg x typ1 @@ pts in
        let ts = List.map (abst env' cond pts') (ps2 (Var x)) in
          begin
            match var with
                None -> Let(x, t, make_app (Const (Tuple (List.length ts))) ts)
              | Some _ -> make_app (Const (Tuple (List.length ts))) ts
          end
    | TFun(typ11,typ12), TFun(typ21,typ22) ->
        let x = new_id "x" in
        let typ12 = typ12 (Var x) in
        let typ22 = typ22 (Var x) in
        let env' = (x,typ11)::env in
        let t1 = coerce env' cond pts typ21 typ11 (Var x) in
        let t2 = coerce env' cond pts typ12 typ22 (App(t, t1)) in
          Fun(x, t2)
    | _ -> Format.printf "COERCE: %a, %a@." print_typ typ1 print_typ typ2; assert false

let coerce env cond pts typ1 typ2 =
  if false then Format.printf "COERCE: %a  ===>  %a@." CEGAR_print.print_typ typ1 CEGAR_print.print_typ typ2;
  coerce env cond pts typ1 typ2



let rec abstract_term env cond pbs t typ =
  match t with
      Var x -> coerce env cond pbs (List.assoc x env) typ t
    | t when is_base_term env t ->
        let typ',src =
          match get_typ env t with
              TBase(TInt,_) -> TBase(TInt, fun x -> [make_eq_int x t]), App(Const (Tuple 1), Const True)
            | TBase(TBool,_) -> TBase(TBool, fun x -> [make_eq_bool x t]), App(Const (Tuple 1), Const True)
            | TBase(TUnit,_) -> TBase(TUnit, fun x -> []), Const (Tuple 0)
            | _ -> assert false
        in
          coerce env cond pbs typ' typ src
    | Const c -> coerce env cond pbs (get_const_typ c) typ t
    | App(Const RandInt, t) -> App(abstract_term env cond pbs t (TFun(typ_int, fun _ -> typ)), Const (Tuple 0))
    | App(t1, t2) ->
        let typ' = get_typ env t1 in
        let typ1,typ2 =
          match typ' with
              TFun(typ1,typ2) -> typ1, typ2 t2
            | _ -> assert false
        in
        let t1' = abstract_term env cond pbs t1 typ' in
        let t2' = abstract_term env cond pbs t2 typ1 in
          coerce env cond pbs typ2 typ (App(t1',t2'))
    | Let(x,t1,t2) ->
        let typ' = get_typ env t1 in
        let t1' = abstract_term env cond pbs t1 typ' in
        let env' = (x,typ')::env in
        let pbs' = abst_arg x typ' @@ pbs in
        let t2' = abstract_term env' cond pbs' t2 typ in
          Let(x,t1',t2')
    | Fun _ -> assert false



let abstract_def env (f,xs,t1,e,t2) =
  let rec aux typ xs env =
    match xs with
        [] -> typ, env
      | x::xs' ->
          let typ1,typ2 =
            match typ with
                TFun(typ1,typ2) -> typ1, typ2 (Var x)
              | _ -> assert false
          in
          let env' = (x,typ1)::env in
            aux typ2 xs' env'
  in
  let typ,env' = aux (List.assoc f env) xs env in
  let pbs = rev_flatten_map (fun (x,typ) -> abst_arg x typ) env' in
  let t2' = abstract_term env' [t1] pbs t2 typ in
    if e <> [] && t1 <> Const True
    then
      let g = new_id "f" in
      let fv = get_fv t2' in
      let t = assume env' [] pbs t1 (make_app (Var g) (List.map (fun x -> Var x) fv)) in
        [g,fv,Const True,e,t2'; f,xs,Const True,[],t]
    else
        [f, xs, Const True, e, assume env' [] pbs t1 t2']




let abstract ((env,defs,main):prog) : prog =
  let (env,defs,main) = make_arg_let (env,defs,main) in
  let (env,defs,main) = add_label (env,defs,main) in
  let () = if false then Format.printf "MAKE_ARG_LET:\n%a@." CEGAR_print.print_prog (env,defs,main) in
  let _ = Typing.infer (env,defs,main) in
  let defs = rev_flatten_map (abstract_def env) defs in
  let () = if true then Format.printf "ABST:\n%a@." CEGAR_print.print_prog ([],defs,main) in
  let prog = Typing.infer ([], defs, main) in
    prog


let abstract prog =
  let tmp = get_time() in
  let () = if Flag.print_progress then Format.printf "\n(%d-1) Abstracting ... @?" !Flag.cegar_loop in
  let abst =
    match !Flag.pred_abst with
        Flag.PredAbstCPS -> CEGAR_abst_CPS.abstract prog
      | Flag.PredAbst -> abstract prog
  in
  let () = if true then Format.printf "Abstracted program::\n%a@." CEGAR_print.print_prog abst in
  let () = if Flag.print_progress then Format.printf "DONE!@." in
  let () = add_time tmp Flag.time_abstraction in
    abst













exception EvalBottom
exception EvalFail
exception EvalValue
exception Skip
exception Restart

let assoc_def defs n t =
  let defs' = List.filter (fun (f,_,_,_,_) -> Var f = t) defs in
    List.nth defs' n

let rec is_value env = function
    Const Bottom -> false
  | Const RandBool -> false
  | Const _ -> true
  | Var x -> get_arg_num (get_typ env (Var x)) > 0
  | App(App(App(Const If, _), _), _) -> false
  | App _ as t ->
      let t1,ts = decomp_app t in
        List.for_all (is_value env) (t1::ts) && get_arg_num (get_typ env t) = List.length ts
  | Let _ -> assert false
  | Fun _ -> assert false

let rec read_bool () =
  Format.printf "RandBool (t/f/r/s): @?";
  let s = read_line () in
    match s with
      | _ when String.length s = 0 -> read_bool ()
      | _ when s.[0] = 't' -> true
      | _ when s.[0] = 'f' -> false
      | _ when s.[0] = 'r' -> raise Restart
      | _ when s.[0] = 's' -> raise Skip
      | _ -> read_bool ()

let rec step_eval_abst_cbn ce env_orig env_abst defs = function
    Const Bottom -> raise EvalBottom
  | Const RandBool ->
      let t =
        if read_bool ()
        then Const True
        else Const False
      in
        ce, t
  | Var x ->
      let ce',(f,xs,tf1,es,tf2) =
        if List.exists (fun (f,_) -> f = x) env_orig
        then List.tl ce, assoc_def defs (List.hd ce) (Var x)
        else ce, assoc_def defs 0 (Var x)
      in
        assert (tf1 = Const True);
        if List.mem (Event "fail") es then raise EvalFail;
        ce', tf2
  | App(App(App(Const If, Const True), t2), _) -> ce, t2
  | App(App(App(Const If, Const False), _), t3) -> ce, t3
  | App(App(App(Const If, t1), t2), t3) ->
      let ce',t1' = step_eval_abst_cbn ce env_orig env_abst defs t1 in
        ce', App(App(App(Const If, t1'), t2), t3)
  | App _ as t ->
      let t1,ts = decomp_app t in
      let ce',(f,xs,tf1,es,tf2) =
        if List.exists (fun (f,_) -> Var f = t1) env_orig
        then List.tl ce, assoc_def defs (List.hd ce) t1
        else ce, assoc_def defs 0 t1
      in
        assert (tf1 = Const True);
        if List.mem (Event "fail") es then raise EvalFail;
        ce', List.fold_right2 subst xs ts tf2
  | _ -> assert false

let rec eval_abst_cbn prog abst ce =
  let env_orig = get_env prog in
  let env_abst = get_env abst in
  let defs = get_defs abst in
  let main = get_main abst in
  let ce' = flatten_map (function BranchNode n -> [n] | _ -> []) ce in
  let rec loop ce t =
    Format.printf "  %a -->@." print_term t;
    let ce',t' = step_eval_abst_cbn ce env_orig env_abst defs t in
      if t' <> Const Unit
      then loop ce' t'
  in
  let pr () =
    try
      loop ce' (Var main)
    with
        Failure "nth" -> Format.printf "RESET (inconsistent)@.@."; eval_abst_cbn prog abst ce
      | Restart -> eval_abst_cbn prog abst ce
      | EvalFail ->
          Format.printf "  ERROR!@.@.";
          Format.printf "Press Enter.@.";
          ignore (read_line())
      | EvalBottom ->
          Format.printf "  DIVERGE!@.@.";
          Format.printf "Press Enter.@.";
          ignore (read_line())
  in
    try
      Format.printf "Evaluation of abstracted program::@.";
      pr ();
    with Skip -> ()



