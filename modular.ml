open Util
open Syntax
open Term_util
open Type
open Modular_common

module Debug = Debug.Make(struct let check = make_debug_check __MODULE__ end)

let num_tycheck = ref 0
let time_check = ref 0.
let time_synthesize = ref 0.

exception NoProgress

let merge_neg_tenv env' env =
  Ref_type.NegEnv.normalize @@ Ref_type.NegEnv.merge env' env
let merge_tenv env' env =
  Ref_type.Env.normalize @@ Ref_type.Env.merge env' env

let normalize_ce_set (ce_set:ce_set) =
  let prefix (f,ce1) (g,ce2) = List.is_prefix ce1 ce2 in
  List.remove_lower prefix ce_set


let is_closed f def_env depth =
  let fs = take_funs_of_depth def_env f depth in
  let def_env' = List.filter (fst |- Id.mem -$- fs) def_env in
  let fv = List.flatten_map (snd |- snd |- get_fv) def_env' in
  let bv = List.flatten_map (fun (f,(xs,_)) -> f::xs) def_env' in
  List.Set.subset ~eq:Id.eq fv bv

let report_safe env =
  Format.printf "Safe!@.@.";
  Format.printf "Refinement types: %a@.@." Ref_type.Env.print env

let report_unsafe neg_env ce_set =
  Format.printf "Unsafe!@.@.";
  Format.printf "Negative refinement types: %a@.@." Ref_type.NegEnv.print neg_env;
  Format.printf "Modular counterexamples: %a@.@." print_ce_set ce_set



let is_external_id f =
  let name = Id.name f in
  String.contains name '.' && is_uppercase name.[0]

let make_init_env cmp fbindings =
  let make f =
    Id.typ f
    |> Trans.inst_tvar_tunit_typ
    |> (if is_external_id f then Ref_type.of_simple else Ref_type.make_weakest)
  in
  List.flatten_map (snd |- List.map Triple.fst) fbindings
  |> Ref_type.Env.create make

let rec main_loop history c prog cmp f typ depth ce_set =
  let {fun_typ_env=env; fun_typ_neg_env=neg_env; fun_def_env} = prog in
  if Ref_type.subtype (Ref_type.Env.assoc f env) typ then
    `Typable, env, neg_env, ce_set
  else if false && Ref_type.suptype (Ref_type.NegEnv.assoc f neg_env) typ then
    `Untypable, env, neg_env, ce_set
  else
    let space = String.make (8*List.length history) ' ' in
    Debug.printf "%sTIME: %.3f@." space !!get_time;
    let pr f = MVerbose.printf ("%s%a@[<hov 2>#[MAIN_LOOP]%t" ^^ f ^^ "@.") space Color.set Color.Red Color.reset in
    pr " history: %a" (List.print @@ Pair.print Id.print Ref_type.print) history;
    pr "%a{%a,%d}%t env:@ %a" Color.set Color.Blue Id.print f c Color.reset Ref_type.Env.print @@ Ref_type.Env.filter_out (fun (f,_) -> is_external_id f) env;
    if false then pr "%a{%a,%d}%t neg_env:@ %a" Color.set Color.Blue Id.print f c Color.reset Ref_type.NegEnv.print neg_env;
    if false then pr "%a{%a,%d}%t ce_set:@ %a" Color.set Color.Blue Id.print f c Color.reset print_ce_set ce_set;
    pr "%a{%a,%d}%t:@ %a :? %a" Color.set Color.Blue Id.print f c Color.reset Id.print f Ref_type.print typ;
    incr num_tycheck;
    let r = measure_and_add_time time_check (fun () -> Modular_check.check prog f typ depth) in
    match r with
    | Modular_check.Typable env' ->
        pr "%a{%a,%d}%t TYPABLE: %a :@ %a@." Color.set Color.Blue Id.print f c Color.reset Id.print f Ref_type.print typ;
        `Typable, merge_tenv env' env, neg_env, ce_set
    | Modular_check.Untypable ce when is_closed f fun_def_env depth ->
        pr "%a{%a,%d}%t UNTYPABLE (closed):@ %a : %a@." Color.set Color.Blue Id.print f c Color.reset Id.print f Ref_type.print typ;
        let neg_env' = merge_neg_tenv neg_env @@ Ref_type.NegEnv.of_list [f, typ] in
        `Untypable, env, neg_env', normalize_ce_set @@ (f,ce)::ce_set
    | Modular_check.Untypable ce ->
        pr "%a{%a,%d}%t UNTYPABLE:@ %a : %a@." Color.set Color.Blue Id.print f c Color.reset Id.print f Ref_type.print typ;
        let rec refine_loop infer_mode neg_env ce_set2 =
          if true then pr "%a{%a,%d}%t ce_set2:@ %a" Color.set Color.Blue Id.print f c Color.reset print_ce_set @@ List.filter_out (fst |- is_external_id) ce_set2;
          let r = measure_and_add_time time_synthesize (fun () -> Modular_infer.infer infer_mode prog f typ ce_set2) in
          match r with
          | None ->
              pr "%a{%a,%d}%t THERE ARE NO CANDIDATES" Color.set Color.Blue Id.print f c Color.reset;
              let neg_env' = merge_neg_tenv neg_env @@ Ref_type.NegEnv.of_list [f, typ] in
              `Untypable, env, neg_env', ce_set2
          | Some candidate ->
              let candidate' =
                candidate
                |> Ref_type.Env.to_list
                |> List.filter_out (fst |- Id.same f)
                |> List.filter_out (fst |- is_external_id)
                |> List.sort ~cmp:(Compare.on ~cmp fst)
                |*> List.flatten_map (fun (g,typ) -> List.map (Pair.pair g) @@ Ref_type.decomp_inter typ)
              in
              pr "%a{%a,%d}%t CANDIDATES:@ %a" Color.set Color.Blue Id.print f c Color.reset Ref_type.Env.print @@ Ref_type.Env.of_list candidate';
              let aux (r,env',neg_env',ce_set4) (g,typ') =
                main_loop ((f,typ)::history) 0 {prog with fun_typ_env=env'; fun_typ_neg_env=neg_env'} cmp g typ' depth ce_set4
              in
              let _,env',neg_env',ce_set3 = List.fold_left aux (`Typable, env, neg_env, ce_set2) candidate' in
              if not @@ Ref_type.Env.eq env' env then
                main_loop history (c+1) {prog with fun_typ_env=env'; fun_typ_neg_env=neg_env'} cmp f typ depth ce_set3
              else if not @@ List.Set.eq ce_set3 ce_set2 then
                refine_loop Modular_infer.init_mode neg_env' ce_set3
              else if not @@ Modular_infer.is_last_mode infer_mode then
                (MVerbose.printf "%schange infer_mode@." space;
                 refine_loop (Modular_infer.next_mode infer_mode) neg_env' ce_set3)
              else if true then
                (MVerbose.printf "%sdepth := %d@." space (depth+1);
                 main_loop history (c+1) prog cmp f typ (depth+1) ce_set3)
              else
                raise NoProgress
        in
        refine_loop Modular_infer.init_mode neg_env (normalize_ce_set @@ (f,ce)::ce_set)
let main_loop prog cmp f typ = main_loop [] 0 prog cmp f typ 1 []

let rec last_def_to_fun t =
  match t.desc with
  | Let(flag, [f,xs,t1], ({desc=Const Unit} as t2)) ->
      let f',xs' =
        if xs = [] then
          let u = Id.new_var ~name:"u" TUnit in
          let typ = TFun(u, Id.typ f) in
          Id.set_typ f typ, [u]
        else
          f, xs
      in
      let desc = Let(flag, [f',xs',t1], t2) in
      {t with desc}
  | Let(flag, _, {desc=Const Unit}) -> unsupported "last_def_to_fun"
  | Let(flag, defs, t2) ->
      let t2' = last_def_to_fun t2 in
      {t with desc = Let(flag, defs, t2')}
  | _ -> assert false

let main _ spec parsed =
  Flag.print_only_if_id := true;
  if spec <> Spec.init then unsupported "Modular.main: spec";
  let fbindings,body =
    let pps =
      Preprocess.all spec
      |> Preprocess.before Preprocess.CPS
      |> Preprocess.filter_out [Preprocess.Beta_reduce_trivial]
    in
    parsed
    |@> Debug.printf "PARSED: %a@.@." Print.term'
    |> Preprocess.run pps
    |> Preprocess.last_t
    |> last_def_to_fun
    |@> Debug.printf "INITIALIZED: %a@.@." Print.term_typ
    |> normalize true
    |@> Debug.printf "NORMALIZED: %a@.@." Print.term
    |> decomp_prog
  in
  assert (body.desc = Const Unit);
  Debug.printf "TOP_FUNS: %a@." (print_list Print.id_typ "@\n") @@ List.flatten_map (snd |- List.map Triple.fst) fbindings;
  if List.exists (snd |- List.exists (Triple.fst |- is_fun_var |- not)) fbindings then
    unsupported "top-level let-bindings of non-functions";
  List.iter (fun (flag,bindings) -> if flag=Recursive then assert (List.length bindings=1)) fbindings;
  let fun_env = List.flatten_map (fun (_,bindings) -> List.map Triple.to_pair_r bindings) fbindings in
  let _,(main,_) = List.decomp_snoc fun_env in
  let typ = Ref_type.of_simple @@ Id.typ main in
  let cmp =
    let edges = List.flatten_map (fun (f,(xs,t)) -> List.map (fun g -> g, f) @@ List.Set.diff ~eq:Id.eq (get_fv t) (f::xs)) fun_env in
    Compare.topological ~eq:Id.eq ~dom:(List.map fst fun_env) edges
  in
  let prog =
    let env_init = make_init_env cmp fbindings in
    Debug.printf "ENV_INIT: %a@." Ref_type.Env.print env_init;
    let fun_typ_neg_env =
      List.flatten_map (snd |- List.map Triple.fst) fbindings
      |> Ref_type.NegEnv.create (Ref_type.union -$- [] -| Id.typ)
    in
    let exn_decl =
      match find_exn_typ parsed with
      | None -> []
      | Some(Type(["exn", TVariant decl], "exn")) -> decl
      | Some _ -> assert false
    in
    {fun_typ_env=env_init; fun_typ_neg_env; fun_def_env=fun_env; exn_decl}
  in
  let r, env, neg_env, ce_set = main_loop prog cmp main typ in
  Main_loop.print_result_delimiter ();
  match r with
  | `Typable ->
      report_safe env;
      true
  | `Untypable ->
      report_unsafe neg_env ce_set;
      false
