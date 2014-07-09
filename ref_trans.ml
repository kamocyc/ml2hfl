open Util
open Type
open Syntax
open Term_util


let debug () = List.mem "Ref_trans" !Flag.debug_module

let trans = make_trans2 ()

let rec root x bb path_rev =
  let aux (y,t) =
    match t with
    | {desc=Proj(i,{desc=Var z})} when Id.same x y -> Some (z,i)
    | _ -> None
  in
  try
    let y,dir = Option.get @@ List.find ((<>) None) @@ List.map aux bb in
    begin
      match elim_tpred @@ fst_typ @@ Id.typ y with
      | TFun _ -> root y bb (dir::path_rev)
      | _ -> raise Not_found
    end
  with Not_found -> x, List.rev path_rev
let root x bb = root x bb []

let rec find_proj i x bb =
  match bb with
  | [] -> None
  | (y,{desc=Proj(j,{desc=Var z})})::bb' when i = j && Id.same x z -> Some y
  | _::bb' -> find_proj i x bb'

let rec find_app x bb =
  match bb with
  | [] -> []
  | (_,{desc=App({desc=Var y},[t])})::bb' when Id.same x y ->
      let args = find_app x bb' in
      if List.exists (same_term t) args then
        args
      else
        t::args
  | _::bb' -> find_app x bb'

let decomp_tfun_ttuple typ =
  try
    let typs =
      try
        decomp_ttuple typ
      with Invalid_argument "decomp_ttuple" -> [typ]
    in
    let decomp typ =
      match typ with
      | TFun(x,typ') -> x, typ'
      | _ -> raise Option.No_value
    in
    Some (List.map decomp typs)
  with Option.No_value -> None

let rec make_tree x bb =
  if debug() then Color.printf Color.Red "make_tree: %a@." print_id_typ x;
  let children = List.mapi (fun i _ -> find_proj i x bb) @@ Option.get @@ decomp_tfun_ttuple @@ Id.typ x in
  if List.for_all Option.is_some children
  then
    Rose_tree.Node (List.map (flip make_tree bb) @@ List.map Option.get children)
  else
    if List.for_all Option.is_none children
    then
      let typ =
        try
          Some (Id.typ @@ arg_var @@ Id.typ x)
        with Invalid_argument _ -> None
      in
      let args = find_app x bb in
      Rose_tree.Leaf(typ, args)
    else
      unsupported "not implemented: make_tree"

let rec make_trees tree =
  match tree with
  | Rose_tree.Leaf(None, []) -> assert false
  | Rose_tree.Leaf(None, _) -> assert false
  | Rose_tree.Leaf(Some typ, []) -> [Rose_tree.Leaf (make_none typ)]
  | Rose_tree.Leaf(Some _, args) -> List.map (fun t -> Rose_tree.Leaf (make_some t)) args
  | Rose_tree.Node ts ->
      let rec pick xss =
        match xss with
        | [] -> []
        | [xs] -> List.map (fun x -> [x]) xs
        | xs::xss' ->
            let yss = pick xss' in
            List.rev_map_flatten (fun x -> List.map (fun ys -> x::ys) yss) xs
      in
      List.map (fun ts -> Rose_tree.Node ts) @@ pick @@ List.map make_trees ts
  | Rose_tree.Node _ -> assert false

let rec term_of_tree tree =
  match tree with
  | Rose_tree.Leaf t -> t
  | Rose_tree.Node ts -> make_tuple @@ List.map term_of_tree ts

(*
let rec make_args tree =
  match tree with
    Rose_tree.Leaf(None, []) -> assert false
  | Rose_tree.Leaf(None, _) -> assert false
  | Rose_tree.Leaf(Some typ, []) -> [make_bottom typ]
  | Rose_tree.Leaf(Some _, args) -> args
  | Rose_tree.Node(lhs,rhs) ->
      let trees1 = make_args lhs in
      let trees2 = make_args rhs in
      flatten_map (fun t1 -> List.map (fun t2 -> make_pair t1 t2) trees2) trees1
*)

let rec proj_of_path top path t =
  match path with
    [] when top -> t
  | [] -> make_get_val t
  | i::path' -> proj_of_path false path' @@ make_proj i t
let proj_of_path path t = proj_of_path true path t

let make_some' t =
  if is_none t
  then t
  else make_some t

let rec same_arg path_rev t1 t2 =
  match t1,t2 with
    Rose_tree.Leaf t1', Rose_tree.Leaf t2' when t1' = t2' -> List.rev path_rev
  | Rose_tree.Leaf t1', Rose_tree.Leaf t2' -> []
  | Rose_tree.Node ts1, Rose_tree.Node ts2 ->
      List.rev_flatten @@ List.mapi2 (fun i -> same_arg (i::path_rev)) ts1 ts2
  | _ -> assert false
let same_arg t1 t2 = same_arg [] t1 t2

let inst_var_fun x tt bb t =
  match Id.typ x with
  | TFun(y,_) ->
      let y' = Id.new_var_id y in
      if debug() then Format.printf "x: %a, y': %a@." Id.print x Id.print y';
      let r,path = root x bb in
      if Id.same x r
      then
        let () = if debug() then Format.printf "THIS IS ROOT@." in
        make_app (make_var x) [t]
      else
        let () = if debug() then Format.printf "THIS IS NOT ROOT@." in
        let tree = make_tree r bb in
        let tree' = Rose_tree.update path (Rose_tree.Leaf(Some (Id.typ y'), [make_var y'])) tree in
        let r' = trans.tr2_var (tt,bb) r in
        let pr _ (_,ts) =
          Format.printf "[%a]" (print_list print_term' "; ") ts
        in
        if debug() then Format.printf "y': %a@." Id.print y';
        if debug() then Format.printf "path: [%a]@." (print_list Format.pp_print_int ";") path;
        if debug() then Format.printf "TREE: %a@." (Rose_tree.print pr) tree;
        if debug() then Format.printf "TREE': %a@." (Rose_tree.print pr) tree';
        if debug() then Format.printf "r': %a:%a@." Id.print r' print_typ (Id.typ r');
        let trees = make_trees tree' in
        if debug() then Format.printf "|trees|': %d@." (List.length trees);
        if debug() then List.iter (Format.printf "  tree: %a@." (Rose_tree.print print_term)) trees;
        let argss = List.map Rose_tree.flatten trees in
        let args = List.map (fun args -> [make_tuple args]) argss in
        let apps = List.map (make_app (make_var r')) args in
(*
        Format.printf "TREE(%a --%a-- %a):%d@." Id.print r (print_list Format.pp_print_int "") path Id.print x @@ List.length apps;
        List.iter (Format.printf "  %a@." print_term) apps;
        Format.printf "orig: %a@." print_term t;
*)
        let same_arg_apps = (* negligence *)
          let rec aux i ts acc =
            match ts with
              [] -> assert false
            | [t] -> acc
            | t1::t2::ts ->
                let paths = same_arg t1 t2 in
                let paths' = List.map (fun path -> i,i+1,path) paths in
                aux (i+1) (t2::ts) (paths' @ acc)
          in
          aux 0 trees []
        in
        let xs = List.map (fun t -> Id.new_var t.typ) apps in
(*
Format.printf "root: %a, %a@." Id.print r pp_print_typ (Id.typ r);
Format.printf "hd: %a, %a@." Id.print (List.hd xs) pp_print_typ (Id.typ @@ List.hd xs);
*)
        let t' =
          let t1 = proj_of_path path @@ make_var @@ List.hd xs in
          let t2 =
            let aux t (i,j,path) =
              let t1 = make_var (List.nth xs i) in
              let t2 = make_var (List.nth xs j) in
              make_assume (make_eq t1 t2) t
            in
            List.fold_left aux t1 same_arg_apps
          in
          List.fold_left2 (fun t x app -> make_let [x,[],app] t) t2 xs apps
        in
        subst y' t t'
  | _ -> make_app (make_var x) [t] (* negligence *)

let rec tree_of_typ typ =
  match typ with
  | TTuple xs -> Rose_tree.Node (List.map (tree_of_typ -| Id.typ) xs)
  | _ -> Rose_tree.Leaf typ

let rec typ_of_tree t =
  match t with
  | Rose_tree.Leaf typ -> typ
  | Rose_tree.Node typs -> TTuple (List.map (Id.new_var -| typ_of_tree) typs)

let rec elim_none t =
  match t with
  | Rose_tree.Leaf None -> None
  | Rose_tree.Leaf (Some typ) -> Some (Rose_tree.Leaf (opt_typ typ))
  | Rose_tree.Node[t1;t2] ->
      match elim_none t1, elim_none t2 with
      | None, None -> None
      | Some t, None
      | None, Some t -> Some t
      | Some t1, Some t2 -> Some (Rose_tree.Node[t1;t2])

let trans_typ ttbb typ =
  match typ with
  | TTuple _ ->
      begin
        match decomp_tfun_ttuple typ with
        | None -> trans.tr2_typ_rec ttbb typ
        | Some xtyps ->
            let xtyps' = List.map (fun (x,typ) -> trans.tr2_var ttbb x, trans.tr2_typ ttbb typ) xtyps in
            let arg_typs = List.map (fun (x,_) -> opt_typ @@ Id.typ x) xtyps' in
            let ret_typs = List.map (fun (_,typ) -> opt_typ typ) xtyps' in
            let name = List.fold_right (^) (List.map (fun (x,_) -> Id.name x) xtyps') "" in
            TFun(Id.new_var ~name @@ make_ttuple arg_typs, make_ttuple ret_typs)
      end
  | _ -> trans.tr2_typ_rec ttbb typ


let trans_typ ttbb typ =
  trans_typ ttbb typ
  |@debug()&> Color.printf Color.Yellow "%a@ ===>@ @[%a@]@.@." print_typ typ print_typ


let trans_term (tt,bb) t =
  match t.desc with
  | Let(Nonrecursive, [x,[],({desc=App({desc=Var x1},[t11])} as t1)], t) ->
      let x' = trans.tr2_var (tt,bb) x in
      let x1' = trans.tr2_var (tt,bb) x1 in
      let t11' = trans.tr2_term (tt,bb) t11 in
      let bb' = (x,t1)::bb in
      let t' = trans.tr2_term (tt,bb') t in
      let tx = inst_var_fun x1' tt bb' t11' in
      make_let [x',[],tx] t'
  | Let(Nonrecursive, [x,[],({desc=Tuple[{desc=Var x1};{desc=Var x2}]} as t1)], t) when Id.same x1 x2 ->
      let x' =  trans.tr2_var (tt,bb) x in
      let x1' = trans.tr2_var (tt,bb) x1 in
      let bb' = (x,t1)::bb in
      let t' = trans.tr2_term (tt,bb') t in
      let t1' =
        match trans_typ (tt,bb) @@ Id.typ x with
        | TFun(y, _) ->
            let y' = Id.new_var_id y in
            let ty1 = make_fst (make_var y') in
            let ty2 = make_snd (make_var y') in
            let y1 = Id.new_var ~name:(Id.name y ^ "1") ty1.typ in
            let y2 = Id.new_var ~name:(Id.name y ^ "2") ty2.typ in
            let t1 = make_some @@ make_app (make_var x1') [make_get_val @@ make_var y1] in
            let t1' = make_if (make_is_none @@ make_var y1) (make_none @@ get_opt_typ t1.typ) t1 in
            let t2 = make_some @@ make_app (make_var x1') [make_get_val @@ make_var y2] in
            let t2' = make_if (make_is_none @@ make_var y2) (make_none @@ get_opt_typ t2.typ) t2 in
            let t_neq = make_pair t1' t2' in
            let z = Id.new_var ~name:"r" t1.typ in
            let t_eq = make_let [z,[],t1] @@ make_pair (make_var z) (make_var z) in
            let cond1 = make_and (make_is_some @@ make_var y1) (make_is_some @@ make_var y2) in
            let cond2 = make_eq (make_get_val @@ make_var y1) (make_get_val @@ make_var y2) in
            make_fun y' @@ make_lets [y1,[],ty1; y2,[],ty2] @@ make_if (make_and cond1 cond2) t_eq t_neq
        | _ -> make_pair (make_var x1') (make_var x1')
      in
      make_let [x',[],t1'] t'
  | Let(Nonrecursive, [x,[],({desc=Tuple[{desc=Var x1};{desc=Var x2}]} as t1)], t) ->
      let x' =  trans.tr2_var (tt,bb) x in
      let x1' = trans.tr2_var (tt,bb) x1 in
      let x2' = trans.tr2_var (tt,bb) x2 in
      let bb' = (x,t1)::bb in
      let t' = trans.tr2_term (tt,bb') t in
      let t1' =
        match trans_typ (tt,bb) @@ Id.typ x with
        | TFun(y, _) ->
            let y' = Id.new_var_id y in
            let ty1 = make_fst (make_var y') in
            let ty2 = make_snd (make_var y') in
            let y1 = Id.new_var ~name:(Id.name y ^ "1") ty1.typ in
            let y2 = Id.new_var ~name:(Id.name y ^ "2") ty2.typ in
            let t1 = make_some @@ make_app (make_var x1') [make_get_val @@ make_var y1] in
            let t1' = make_if (make_is_none @@ make_var y1) (make_none @@ get_opt_typ t1.typ) t1 in
            let t2 = make_some @@ make_app (make_var x2') [make_get_val @@ make_var y2] in
            let t2' = make_if (make_is_none @@ make_var y2) (make_none @@ get_opt_typ t2.typ) t2 in
            make_fun y' @@ make_lets [y1,[],ty1; y2,[],ty2] @@ make_pair t1' t2'
        | _ -> make_pair (make_var x1') (make_var x2')
      in
      make_let [x',[],t1'] t'
  | Let(Nonrecursive, [x,[],({desc=Tuple ts} as t1)], t) when List.for_all (Option.is_some -| decomp_var) ts ->
      let xs = List.map (function {desc=Var x} -> x | t -> Format.printf "%a@." print_term t; assert false) ts in
      let x' =  trans.tr2_var (tt,bb) x in
      let xs' = List.map (trans.tr2_var (tt,bb)) xs in
      let bb' = (x,t1)::bb in
      let t' = trans.tr2_term (tt,bb') t in
      let t1' =
        match trans_typ (tt,bb) @@ Id.typ x with
        | TFun(y, _) ->
            let y' = Id.new_var_id y in
            let tys = List.map (fun i -> make_proj i @@ make_var y') @@ List.fromto 0 @@ List.length ts in
            let ys = List.mapi (fun i t -> Id.new_var ~name:(Id.name y ^ string_of_int (i+1)) t.typ) tys in
            let aux xi' yi =
              let ti = make_some @@ make_app (make_var xi') [make_get_val @@ make_var yi] in
              let ti' = make_if (make_is_none @@ make_var yi) (make_none @@ get_opt_typ ti.typ) ti in
              ti'
            in
            let ts' = List.map2 aux xs' ys in
            let bindings = List.map2 (fun x t -> x, [], t) ys tys in
            make_fun y' @@ make_lets bindings @@ make_tuple ts'
        | _ -> make_tuple @@ List.map make_var xs
      in
      make_let [x',[],t1'] t'
  | Let(Nonrecursive, [x,[],({desc=Proj(i,{desc=Var x1})} as t1)], t) ->
      let x' = trans.tr2_var (tt,bb) x in
      let x1' = trans.tr2_var (tt,bb) x1 in
      let bb' = (x,t1)::bb in
      let t' = trans.tr2_term (tt,bb') t in
      let t1' =
        match Id.typ x1' with
        | TTuple _ -> make_proj i @@ make_var x1'
        | TFun(y,typ) ->
            begin match decomp_tfun_ttuple @@ Id.typ x1 with
            | None -> assert false
            | Some xtyps ->
                let z = Id.new_var_id @@ fst @@ List.nth xtyps i in
                let arg = make_tuple @@ List.mapi (fun j (z',_) -> if j = i then make_some @@ make_var z else make_none @@ Id.typ z') xtyps in
                make_fun z @@ make_get_val @@ make_proj i @@ make_app (make_var x1') [arg]
            end
        | _ -> assert false
      in
      make_let [x',[],t1'] t'
  | _ -> trans.tr2_term_rec (tt,bb) t

let () = trans.tr2_term <- trans_term
let () = trans.tr2_typ <- trans_typ



let rec decomp_simple_let t =
  match t.desc with
  | Let(Nonrecursive,[x,[],t1],t2) ->
      let bindings,t2' = decomp_simple_let t2 in
      (x,t1)::bindings, t2'
  | _ -> [], t

let sort_let_pair = make_trans ()

let sort_let_pair_aux x t =
  let bindings,t' = decomp_simple_let t in
  let bindings' = List.map (fun (x,t) -> x, [], sort_let_pair.tr_term t) bindings in
  let is_proj (_,_,t) =
    match t.desc with
    | Proj(_, {desc=Var y}) -> Id.same x y
    | _ -> false
  in
  let bindings1,bindings2 = List.partition is_proj bindings' in
  let t'' = sort_let_pair.tr_term t' in
  make_lets bindings1 @@ make_lets bindings2 t''

let sort_let_pair_term t =
  match t.desc with
  | Let(Nonrecursive,[x,[],({desc=Tuple _} as t1)],t2) ->
      let t2' = sort_let_pair_aux x t2 in
      make_let [x,[],t1] t2'
  | Let(flag,[f,xs,t1],t2) ->
      let t1' = sort_let_pair.tr_term t1 in
      let t2' = sort_let_pair.tr_term t2 in
      let t1'' = List.fold_right sort_let_pair_aux xs t1' in
      make_let_f flag [f,xs,t1''] t2'
  | _ -> sort_let_pair.tr_term_rec t

let () = sort_let_pair.tr_term <- sort_let_pair_term



let move_proj = make_trans ()

let rec move_proj_aux x t =
  match Id.typ x with
  | TTuple xs ->
      let ts = List.mapi (fun i _ -> make_proj i @@ make_var x) xs in
      let xs' = List.mapi (fun i x -> Id.new_var ~name:(Id.name x ^ string_of_int (i+1)) @@ Id.typ x) xs in
      let subst_rev' t x t_acc =
        let ts = col_same_term t t_acc in
        List.fold_right (fun t1 t2 -> subst_rev t1 x t2) ts t_acc
      in
      t
      |> Trans.inline_var_const
      |> List.fold_right2 subst_rev' ts xs'
      |@> Format.printf "MPA: %a@.@." print_term
      |> List.fold_right move_proj_aux xs'
      |> make_lets @@ List.map2 (fun x t -> x,[],t) xs' ts
  | _ -> t

let move_proj_aux x t =
(match Id.typ x with TTuple _ -> Format.printf "%a@." print_id_typ x| _ -> ()) ;
move_proj_aux x t


let move_proj_term t =
  match t.desc with
  | Let(flag,bindings,t2) ->
      let bindings' = List.map (fun (f,xs,t) -> f, xs, move_proj.tr_term t) bindings in
      let bindings'' = List.map (fun (f,xs,t) -> f, xs, List.fold_right move_proj_aux xs t) bindings' in
      let t2' = move_proj.tr_term t2 in
      let t2'' = List.fold_right (fun (x,_,_) t -> move_proj_aux x t) bindings t2' in
      make_let_f flag bindings'' t2''
  | Fun(x,t1) -> make_fun x @@ move_proj_aux x t1
  | _ -> move_proj.tr_term_rec t

let () = move_proj.tr_term <- move_proj_term




let trans t = t
  |@debug()&> Format.printf "INPUT: %a@." print_term
  |> move_proj.tr_term
  |@debug()&> Format.printf "move_proj: %a@." print_term_typ
  |@> Trans.inline_no_effect
  |@debug()&> Format.printf "inline_no_effect: %a@." print_term_typ
  |> Trans.normalize_let
  |> Trans.inline_simple_exp
  |@debug()&> Format.printf "normalize_let: %a@." print_term_typ
  |> Trans.flatten_let
  |> Trans.inline_var_const
  |@debug()&> Format.printf "flatten_let: %a@." print_term_typ
  |> sort_let_pair.tr_term
  |@debug()&> Format.printf "sort_let_pair: %a@." print_term_typ
  |@> flip Type_check.check TUnit
  |> trans.tr2_term (assert_false,[])
  |> Trans.inline_no_effect
  |@debug()&> Format.printf "ref_trans: %a@." print_term
  |@> flip Type_check.check Type.TUnit











let col_assert = make_col [] (@@@)

let col_assert_desc desc =
(*Format.printf "CAD: %a@." print_constr {desc=desc; typ=TUnit};*)
  match desc with
  | If(t1, t2, t3) when same_term t2 unit_term && same_term t3 (make_app fail_term [unit_term]) ->
      [t1]
  | Let(Nonrecursive, [x,[],t1], t2) ->
      let ts1 = col_assert.col_term t1 in
      let ts2 = col_assert.col_term t2 in
      let ts2' = List.map (subst x t1) ts2 in
      ts1 @ ts2'
  | _ -> col_assert.col_desc_rec desc

let () = col_assert.col_desc <- col_assert_desc

let col_assert = col_assert.col_term


let has_rand = make_col false (||)

let has_rand_desc desc =
  match desc with
  | RandInt _ -> true
  | RandValue _ -> true
  | _ -> has_rand.col_desc_rec desc

let () = has_rand.col_desc <- has_rand_desc

let has_rand = has_rand.col_term


let col_rand_funs = make_col [] (@@@)

let col_rand_funs_desc desc =
  match desc with
  | Let(_, bindings, t2) ->
      let aux (f,_,t) = if has_rand t then [f] else [] in
      let funs1 = List.flatten_map aux bindings in
      let funs2 = col_rand_funs.col_term_rec t2 in
      funs1 @ funs2
  | _ -> col_rand_funs.col_desc_rec desc

let () = col_rand_funs.col_desc <- col_rand_funs_desc

let col_rand_funs = col_rand_funs.col_term


let col_app_head = make_col [] (@@@)

let col_app_head_desc desc =
  match desc with
  | App({desc=Var f}, _) -> [f]
  | _ -> col_app_head.col_desc_rec desc

let () = col_app_head.col_desc <- col_app_head_desc

let col_app_head = col_app_head.col_term


let compare_pair (x1,x2) (y1,y2) =
  if Id.same x1 y2 && Id.same x2 y1 then
    0
  else
    let r1 = compare x1 y1 in
    if r1 <> 0 then
      r1
    else
      compare x2 y2


let col_fun_arg = make_col [] (List.union ~cmp:compare_pair)

let col_fun_arg_desc desc =
  match desc with
  | App({desc=Var f}, ts) ->
      let funs = List.flatten_map col_app_head ts in
      List.map (fun g -> f, g) funs
  | _ -> col_fun_arg.col_desc_rec desc

let () = col_fun_arg.col_desc <- col_fun_arg_desc
let col_fun_arg = col_fun_arg.col_term



let col_app_terms = make_col2 [] (@@@)

let col_app_terms_term fs t =
  match t.desc with
  | App({desc=Var f}, ts) when Id.mem f fs ->
      t :: List.flatten_map (col_app_terms.col2_term fs) ts
  | _ -> col_app_terms.col2_term_rec fs t

let () = col_app_terms.col2_term <- col_app_terms_term
let col_app_terms = col_app_terms.col2_term



let replace_head fs fs' t =
  let ts = col_app_terms fs t in
  let rec aux fs ts =
    match fs,ts with
    | [], [] -> []
    | [], _ -> unsupported "replace_head"
    | f::fs', _ ->
        let ts1,ts2 = List.partition (fun t -> Id.mem f @@ get_fv t) ts in
        List.hd ts1 :: aux fs' (List.tl ts1 @ ts2)
  in
  let ts' = aux fs ts in
  let xs = List.map (fun t -> Id.new_var t.typ) ts' in
  let t' = List.fold_right2 subst_rev ts' xs t in
  if debug() then Format.printf "t':@.%a@.@." print_term t';
  let ts'' = List.map2 (fun t (f,f') -> subst f (make_var f') t) ts' @@ List.combine fs fs' in
  let t'' = List.fold_right2 subst xs ts'' t' in
  if debug() then Format.printf "t'':@.%a@.@." print_term t'';
  t''


(*
let normalize_tuple_arg = make_trans ()

let normalize_tuple_arg_term t =
  match t.desc with
  | Let(Nonrecursive as flag, bindings, t2)
  | Let(Recursive as flag, ([_] as bindings), t2)->
      let aux (f,xs,t1) (bindings,t2) =
        let is_normalized typ =
          match typ with
          | TPair(TPair)
        in

      in
      let bindings',t2' = List.fold_right aux bindings ([],t2) in
      make_let_f flag bindings' t2'
  | _ -> normalize_tuple_arg.tr_term_rec t

let () = normalize_tuple_arg.tr_term <- normalize_tuple_arg_term
let normalize_tuple_arg = normalize_tuple_arg.tr_term
 *)




let add_fun_tuple = make_trans2 ()

let defined fs env = List.for_all (fun f -> Id.mem f env) fs

let add_fun_tuple_term (funs,env) t =
  match t.desc with
  | Let(flag,[f,xs,t1],t2) ->
      let env' = f::env in
      let funs1,funs2 = List.partition (fun fs -> defined fs env') funs in
      let t1' = add_fun_tuple.tr2_term (funs2,env') t1 in
      let t2' = add_fun_tuple.tr2_term (funs2,env') t2 in
      let aux t fs =
        let name = List.fold_left (fun s x -> Id.name x ^ "_" ^ s) (Id.name @@ List.hd fs) @@ List.tl fs in
        let fg = Id.new_var ~name @@ make_ttuple @@ List.map Id.typ fs in
        let projs = List.mapi (fun i g -> Id.new_var_id g, [], make_proj i (make_var fg)) fs in
        let t' = replace_head fs (List.map (fun (f,_,_) -> f) projs) t in
        let defs = (fg, [], make_tuple @@ List.map make_var fs)::projs in
        make_lets defs t'
      in
      make_let_f flag [f,xs,t1'] @@ List.fold_left aux t2' funs1
  | Let(flag,_,_) -> unsupported "add_fun_tuple (let (rec) ... and ...)"
  | _ -> add_fun_tuple.tr2_term_rec (funs,env) t

let () = add_fun_tuple.tr2_term <- add_fun_tuple_term
let add_fun_tuple rel_funs t = add_fun_tuple.tr2_term (rel_funs,[]) t


let make_fun_tuple t =
  let asserts = col_assert t in
  if debug() then List.iter (Format.printf "ASSERT: %a@." Syntax.print_term) asserts;
  let rand_funs = col_rand_funs t in
  if debug() then List.iter (Format.printf "RAND: %a@." Id.print) rand_funs;
  let aux assrt =
    let funs = col_app_head assrt in
    if debug() then List.iter (Format.printf "FUN: %a@." Id.print) funs;
    let funs' = List.diff ~cmp:Id.compare funs rand_funs in
    if debug() then List.iter (Format.printf "FUN': %a@." Id.print) funs';
    let rec get_pairs acc fs =
      match fs with
      | [] -> acc
      | f::fs' -> get_pairs (List.map (fun g -> (f,g)) fs' @ acc) fs'
    in
    let all_fun_pairs = get_pairs [] funs' in
    if debug() then List.iter (fun (f,g) -> Format.printf "ALL_FUN_ARG: %a, %a@." Id.print f Id.print g) all_fun_pairs;
    let fun_args = col_fun_arg assrt in
    if debug() then List.iter (fun (f,g) -> Format.printf "FUN_ARG: %a, %a@." Id.print f Id.print g) fun_args;
    let rel_funs = List.diff ~cmp:compare_pair all_fun_pairs fun_args in
    if debug() then List.iter (fun (f,g) -> Format.printf "FUN_ARG': %a, %a@." Id.print f Id.print g) rel_funs;
    List.map (fun (f,g) -> [f;g]) rel_funs
  in
  let rel_funs = List.flatten_map aux asserts in
  let t' = add_fun_tuple rel_funs t in
  if debug() then Format.printf "@.@.%a@." print_term t';
  t'
