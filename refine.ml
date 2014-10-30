
open Util
open CEGAR_syntax
open CEGAR_type
open CEGAR_util
open CEGAR_trans


exception CannotRefute

let add_preds_env map env =
  let aux (f,typ) =
    try
      f, merge_typ typ (List.assoc f map)
    with Not_found -> f, typ
  in
    List.map aux env

let add_preds_env map env =
  let aux (f,typ) =
    try
      let typ1 = typ in
      let typ2 = List.assoc f map in
      let typ' = merge_typ typ1 typ2 in
        f, typ'
    with Not_found -> f, typ
  in
    List.map aux env

let add_renv map env =
  let aux (n, preds) = make_randint_name n, TBase(TInt, preds) in
  add_preds_env (List.map aux map) env

let add_preds map prog =
  {prog with env = add_preds_env map prog.env}


let rec add_to_path path typ1 typ2 =
  match path,typ2 with
  | [],_ -> merge_typ typ1 typ2
  | 0::path',TFun(typ21,typ22) -> TFun(add_to_path path' typ1 typ21, typ22)
  | 1::path',TFun(typ21,typ22) -> TFun(typ21, fun x -> add_to_path path' typ1 (typ22 x))
  | _ -> Format.printf "%a@." CEGAR_print.typ typ2; assert false

let rec add_pred n path typ =
  match typ with
  | TBase _ -> assert false
  | TFun(typ1,typ2) when n=0 ->
      TFun(typ1, fun x -> add_to_path (List.tl path) typ1 (typ2 x))
  | TFun(typ1,typ2) ->
      assert (List.hd path = 1);
      TFun(typ1, fun x -> add_pred (n-1) (List.tl path) (typ2 x))
  | TAbs _ -> assert false
  | TApp _ -> assert false



let refine labeled is_cp prefix ces ext_ces {env=env;defs=defs;main=main} =
  let tmp = get_time () in
  try
    if !Flag.print_progress then
      Color.printf
	    Color.Green
	    "(%d-4) Discovering predicates ... @."
	    !Flag.cegar_loop;
    if Flag.use_prefix_trace then
	  raise (Fatal "Not implemented: Flag.use_prefix_trace");
    let map =
      Format.printf "@[<v>";
      let ces =
	    if !Flag.use_multiple_paths then
	      ces
	    else
	      [FpatInterface.List.hd ces]
	  in
      let map =
	    FpatInterface.infer
	      labeled
	      is_cp
	      ces
          ext_ces
	      (env, defs, main)
	  in
      Format.printf "@]";
      map
    in
    let env' =
	  if !Flag.disable_predicate_accumulation then
	    map
	  else
	    add_preds_env map env
    in
    if !Flag.print_progress then Format.printf "DONE!@.@.";
    Fpat.SMTProver.close ();
    Fpat.SMTProver.open_ ();
    add_time tmp Flag.time_cegar;
    map, {env=env';defs=defs;main=main}
  with e ->
    Fpat.SMTProver.close ();
    Fpat.SMTProver.open_ ();
    add_time tmp Flag.time_cegar;
    raise e

let refine_with_ext labeled is_cp prefix ces ext_ces {env=env;defs=defs;main=main} =
  let tmp = get_time () in
  try
    if !Flag.print_progress then
      Color.printf
	    Color.Green
	    "(%d-4) Discovering predicates ... @."
	    !Flag.cegar_loop;
    if Flag.use_prefix_trace then
	  raise (Fatal "Not implemented: Flag.use_prefix_trace");
    let map =
      Format.printf "@[<v>";
      let map =
	    FpatInterface.infer_with_ext
	      labeled
	      is_cp
	      ces
	      ext_ces
	      (env, defs, main)
	  in
      Format.printf "@]";
      map
    in
    let env' =
	  if !Flag.disable_predicate_accumulation then
	    map
	  else
	    add_preds_env map env
    in
    if !Flag.print_progress then Format.printf "DONE!@.@.";
    Fpat.SMTProver.close ();
    Fpat.SMTProver.open_ ();
    add_time tmp Flag.time_cegar;
    map, {env=env';defs=defs;main=main}
  with e ->
    Fpat.SMTProver.close ();
    Fpat.SMTProver.open_ ();
    add_time tmp Flag.time_cegar;
    raise e

exception PostCondition of (Fpat.Idnt.t * Fpat.Type.t) list * Fpat.Formula.t * Fpat.Formula.t

let print_list fm = function
  | [] -> Format.fprintf fm "[]@."
  | x::xs ->
    let rec iter = function
      | [] -> ""
      | y::ys -> ", " ^ string_of_int y ^ iter ys
    in
    Format.fprintf fm "[%d%s]@." x (iter xs)

let progWithExparam = ref {env=[]; defs=[]; main="main(DUMMY)"}

let refine_rank_fun ce { env=env; defs=defs; main=main } =
  let tmp = get_time () in
    try
      (*Format.printf "(%d)[refine_rank_fun] %a @." !Flag.cegar_loop print_list ce;
      Format.printf "    %a@." (print_prog_typ' [] []) { env=env; defs=defs; main=main };*)
      if !Flag.print_progress then Format.printf "(%d-4) Discovering ranking function ... @." !Flag.cegar_loop;
      let env, spc =
        Format.printf "@[<v>";
        let env, spc = FpatInterface.compute_strongest_post (env, defs, main) ce in
        Format.printf "@]";
        env, spc
      in

      let spcWithExparam =
        let {env=envWithExparam; defs=defsWithExparam; main=mainWithExparam} = !progWithExparam in
        Format.printf "@[<v>";
        let _, spcWithExparam =
          if !Flag.add_closure_exparam then
            FpatInterface.compute_strongest_post (envWithExparam, defsWithExparam, mainWithExparam) ce
          else
            [], spc (* dummy *)
        in
        Format.printf "@]";
        spcWithExparam
      in

      (* TEMPORARY *)
      (*Format.printf "[exparam]@.%a@." FpatInterface.Formula.pr spcWithExparam;
      Format.printf "[instantiated]@.%a@." FpatInterface.Formula.pr spc;*)

      if !Flag.print_progress then Format.printf "DONE!@.@.";
      Fpat.SMTProver.close ();
      Fpat.SMTProver.open_ ();
      add_time tmp Flag.time_cegar;
      raise (PostCondition (env, spc, spcWithExparam))
    with e ->
      Fpat.SMTProver.close ();
      Fpat.SMTProver.open_ ();
      add_time tmp Flag.time_cegar;
      raise e
