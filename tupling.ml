open Util
open Type
open Syntax
open Term_util




let is_none_term t =
  match t.desc with
    Pair(t1,t2) -> t1 = true_term && t2.desc = Const (Int 0)
  | _ -> false

let is_some_term t =
  match t.desc with
    Pair(t1,t2) -> t1 = false_term
  | _ -> false

(*
let get_some_term t =
    Pair(t1,t2) -> assert (t1 = false_term); t2
  | _ -> assert false
*)


let pair_let = make_trans ()

let pair_let_desc desc =
  match desc with
    Pair(t1, t2) ->
      let t1' = pair_let.tr_term t1 in
      let t2' = pair_let.tr_term t2 in
      let lhs = Id.new_var "l" t1'.typ in
      let rhs = Id.new_var "r" t2'.typ in
      (make_lets [rhs,[],t2'; lhs,[],t1'] @@ make_pair (make_var lhs) (make_var rhs)).desc
  | _ -> pair_let.tr_desc_rec desc

let () = pair_let.tr_desc <- pair_let_desc

let pair_let = pair_let.tr_term



type form =
  FSimpleRec
| FNonRec
| FOther

exception Cannot_compose
exception Not_recursive

let assoc_env f env =
  let _,xs,t = Id.assoc f env in
  assert (xs = []);
  let ys,t' = decomp_fun t in
  ys, t'

let rec decomp_let t =
  match t.desc with
    Let(flag, [f,xs,t1], t2) ->
      let bindings,t2' = decomp_let t2 in
      (flag,(f,xs,t1))::bindings, t2'
  | _ ->
    let r = Id.new_var "r" t.typ in
    [Nonrecursive, (r,[],t)], make_var r

let partition_bindings x t =
Format.printf "PB: x:%a@." Id.print x;
  let bindings,t' = decomp_let t in
  let check t =
    if List.mem x (get_fv t)
    then (assert false;raise Cannot_compose)
  in
  let aux (flag,(f,xs,t)) (before,app_x,after) =
    match app_x, xs, t with
      None, [], {desc=App({desc=Var y}, ts)} when Id.same x y ->
        assert (flag = Nonrecursive);
        before, Some (f,ts), after
    | None, _, _ ->
Format.printf "CHECK: %a@." pp_print_term t;
        check t;
        before, app_x, (flag,(f,xs,t))::after
    | Some _, _, {desc=App({desc=Var y}, ts)} when Id.same x y ->
        raise Cannot_compose
    | Some _, _, _ ->
        check t;
        (flag,(f,xs,t))::before, app_x, after
  in
  let before,app_x,after = List.fold_right aux bindings ([],None,[]) in
  match app_x with
    None -> raise Not_recursive
  | Some xts -> before, xts, after, t'

let classify f t =
  try
    ignore (partition_bindings f t); FSimpleRec
  with
    Not_recursive -> FNonRec
  | Cannot_compose -> FOther

let compose_let_same_arg map fg f t1 g t2 =
Format.printf "compose_let_same_arg@.";
  let before1,(x1,ts1),after1,t1' = partition_bindings f t1 in
  let before2,(x2,ts2),after2,t2' = partition_bindings g t2 in
  let aux ts_small ts_big map =
    assert (List.length map = List.length ts_big);
    if List.exists2 (fun t -> function None -> false | Some i -> t <> List.nth ts_small i) ts_big map
    then raise Cannot_compose;
    ts_big
  in
  let ts =
    match map with
      `Subset map' -> aux ts1 ts2 map'
    | `Supset map' -> aux ts2 ts1 map'
  in
  let x = Id.new_var "r" (TPair(Id.new_var "l" t1.typ, t2.typ)) in
  let before = before1 @ before2 in
  let after = after1 @ after2 in
  let p = Id.new_var "p" (TPair(x1, Id.typ x2)) in
  let pat =
    [p,  [], make_app (make_var fg) ts;
     x1, [], make_fst @@ make_var p;
     x2, [], make_snd @@ make_var p]
  in
  make_lets_f before @@ make_lets pat @@ make_lets_f after @@ make_pair t1' t2'

let compose_non_recursive first t1 t2 =
  let bindings,t = decomp_let (if first then t1 else t2) in
  let r = Id.new_var "r" (if first then t1.typ else t2.typ) in
  let t' =
    if first
    then make_pair (make_var r) t2
    else make_pair t1 (make_var r)
  in
  make_lets_f (bindings @ [Nonrecursive,(r,[],t)]) t'

let compose_typ typ1 typ2 =
  match typ1, typ2 with
    TFun(x1,typ1'), TFun(x2,typ2') ->
      TFun(x1, TFun(x2, TPair(Id.new_var "r" typ1', typ2')))
  | _ -> assert false

let compose_let_diff_arg fg f t1 g t2 =
  let before1,(x1,ts1),after1,t1' = partition_bindings f t1 in
  let before2,(x2,ts2),after2,t2' = partition_bindings g t2 in
  let x = Id.new_var "r" (TPair(Id.new_var "l" t1.typ, t2.typ)) in
  let before = before1 @ before2 in
  let after = after1 @ after2 in
  let p = Id.new_var "p" (TPair(x1, Id.typ x2)) in
  let pat =
    [p,  [], make_app (make_var fg) (ts1 @ ts2);
     x1, [], make_fst @@ make_var p;
     x2, [], make_snd @@ make_var p]
  in
  make_lets_f before @@ make_lets pat @@ make_lets_f after @@ make_pair t1' t2'

let compose_let map f t1 g t2 =
Format.printf "compose_let@.%a:%a@.@.%a:%a@.@." Id.print f pp_print_term t1 Id.print g pp_print_term t2;
  match classify f t1, classify g t2, map with
    FNonRec,    _,          _ -> compose_non_recursive true t1 t2
  | _,          FNonRec,    _ -> compose_non_recursive false t1 t2
  | FOther,     _,          _
  | _,          FOther,     _ -> raise Cannot_compose
  | FSimpleRec, FSimpleRec, Some (map',fg) -> compose_let_same_arg map' fg f t1 g t2
  | FSimpleRec, FSimpleRec, None ->
      let fg = Id.new_var (Id.name f ^ "_" ^ Id.name g) @@ compose_typ (Id.typ f) (Id.typ g) in
      compose_let_diff_arg fg f t1 g t2

let rec compose f t1 g t2 =
Format.printf "compose@.";
  match t1.desc, t2.desc with
    If(t11, t12, t13), _ ->
      make_if t11 (compose f t12 g t2) (compose f t13 g t2)
  | _, If(t21, t22, t23) ->
      make_if t21 (compose f t1 g t22) (compose f t1 g t23)
  | _ -> raise Cannot_compose

let rec compose_same_arg map fg f t1 g t2 =
Format.printf "compose_same_arg@.";
  match t1.desc, t2.desc with
    If(t11, t12, t13), If(t21, t22, t23) when t11 = t21 ->
      let t2' = compose_same_arg map fg f t12 g t22 in
      let t3' = compose_same_arg map fg f t13 g t23 in
      make_if t11 t2' t3'
  | If(t11, t12, t13), _ ->
      let t2' = compose_same_arg map fg f t12 g t2 in
      let t3' = compose_same_arg map fg f t13 g t2 in
      make_if t11 t2' t3'
  | _, If(t21, t22, t23) ->
      make_if t21 (compose_same_arg map fg f t1 g t22) (compose_same_arg map fg f t1 g t23)
  | _ -> compose_let (Some (map, fg)) f t1 g t2


let same_arg_map xs1 xs2 =
  let rec find i x xs =
    match xs with
      [] -> None
    | x'::xs' when Id.same x x' -> Some i
    | _::xs' -> find (i+1) x xs'
  in
  let find x xs = find 0 x xs in
  let make_map xs1 xs2 = List.map (fun x -> find x xs1) xs2 in
  if subset xs1 xs2 then
    Some (`Subset (make_map xs1 xs2))
  else if subset xs2 xs1 then
    Some (`Supset (make_map xs2 xs1))
  else
    None

let get_comb_pair t1 t2 =
  let diff = Trans.diff_terms t1 t2 in
(*
  if List.length diff > 2 then
      (Format.printf "t1:%a@.t2:%a@." pp_print_term t1 pp_print_term t2;
       List.iter (fun (t1,t2) -> Format.printf "DIFF %a, %a@."  pp_print_term t1 pp_print_term t2) diff;
       Format.printf "@.");
*)
  let check (t1',t2') =
    match t1'.desc, t2'.desc with
      Fst t1'', Snd t2'' ->
        begin
        let diff = Trans.diff_terms t1'' t2'' in
        if diff = []
        then Some []
        else
          match t1''.desc, t2''.desc with
            App({desc=Var f}, [{desc=Pair(t11,t12)}]), App({desc=Var g}, [{desc=Pair(t21,t22)}])
              when Id.same f g && is_some_term t11 && is_none_term t12 && is_none_term t21 && is_some_term t22 ->
                let x = Id.new_var "x" t1''.typ in
                let t1''' = subst_rev t1'' x t1 in
                let t2''' = subst_rev t2'' x t2 in
                if has_no_effect t1''' && has_no_effect t2'''
                then
                  let t = make_app (make_var f) [make_pair t11 t22] in
                  Some [make_lets [x,[],t] @@ make_pair t1''' t2''']
                else None
          | _ -> None
        end
    | _ -> None
  in
  let diff' = List.map check diff in
  if List.exists ((=) None) diff'
  then None
  else
    match List.filter (function Some [_] -> true | _ -> false) diff' with
      [] -> None
    | [Some [t]] -> Some t
    | _ -> assert false


let get_comb_pairs env =
  let aux (_,(_,xs,t)) =
    match t.desc with
      Fun _ -> []
    | _ when xs <> [] -> []
    | _ -> [t]
  in
  let ts = flatten_map aux env in
  let rec diffs ts =
    match ts with
      [] -> []
    | t::ts' -> List.map (get_comb_pair t) ts'
  in
  diffs ts



let get_pair_diffs = make_col [] List.rev_append

let get_pair_diffs_desc desc =
  match desc with
    Pair(t1,t2) -> Trans.diff_terms t1 t2
  | _ -> get_pair_diffs.col_desc_rec desc

let () = get_pair_diffs.col_desc <- get_pair_diffs_desc

let get_pair_diffs = get_pair_diffs.col_term



let tupling = make_trans2 ()

let is_wrapped t =
  match t.desc with
    If(t1,t2,t3) ->
      begin match is_is_none t1 with
        Some t1' when is_none t2 -> Some (t1', t3)
      | _ -> None
      end
  | _ -> None

let inline_wrapped = make_trans ()

let inline_wrapped_desc desc =
  match desc with
    Pair(t1,t2) ->
      let t1' = inline_wrapped.tr_term t1 in
      let t2' = inline_wrapped.tr_term t2 in
      begin match is_wrapped t1', is_wrapped t2' with
        Some(t11, t12), Some(t21, t22) ->
          (make_if (make_is_none t11)
            (make_pair (make_none @@ get_opt_typ t1'.typ) t2')
            (make_if (make_is_none t21)
               (make_pair t12 (make_none @@ get_opt_typ t2'.typ))
               (make_pair t12 t22))).desc
      | _ -> inline_wrapped.tr_desc_rec desc
      end
  | _ -> inline_wrapped.tr_desc_rec desc

let () = inline_wrapped.tr_desc <- inline_wrapped_desc


let tupling_desc env desc =
(*
Format.printf "desc: %a@." pp_print_term {desc=desc;typ=TUnit};
*)
  match desc with
    Let(Nonrecursive, [fg,[],({desc=Fun _} as t1)], t2) ->
      begin
        match decomp_fun t1 with
          xs, {desc=Pair({desc=App({desc=Var f}, ts1)}, {desc=App({desc=Var g}, ts2)})} ->
            begin
              try
                let tupling_args = function {desc=Var x} -> x | _ -> raise Cannot_compose in
                let xs1 = List.map tupling_args ts1 in
                let xs2 = List.map tupling_args ts2 in
                let get_body env f ts =
                  let xs,t = assoc_env f env in
                  List.fold_right2 subst xs ts t
                in
                let t' =
                  match same_arg_map xs1 xs2 with
                    None -> None
                  | Some map ->
                      try
                        Some (compose_same_arg map fg f (get_body env f ts1) g (get_body env g ts2))
                      with Cannot_compose -> None
                in
                let xs',t'' =
                  match t' with
                    None ->
                      xs1@xs2, compose f (get_body env f ts1) g (get_body env g ts2)
                  | Some t'' -> xs, t''
                in
                let t1' = List.fold_right make_fun xs' t'' in
                let t2' = tupling.tr2_term env t2 in
                Let(Recursive, [fg,[],t1'], t2')
              with Cannot_compose -> tupling.tr2_desc_rec env desc
            end
        | _ -> tupling.tr2_desc_rec env desc
      end
  | Let(Nonrecursive, [fg,[],({desc=Fun _} as t1)], t2) ->
      begin
        match decomp_fun t1 with
          xs, {desc=Pair({desc=App({desc=Var f}, ts1)}, {desc=App({desc=Var g}, ts2)})} ->
            begin
              try
                let tupling_args = function {desc=Var x} -> x | _ -> raise Cannot_compose in
                let xs1 = List.map tupling_args ts1 in
                let xs2 = List.map tupling_args ts2 in
                let get_body env f ts =
                  let xs,t = assoc_env f env in
                  List.fold_right2 subst xs ts t
                in
                let t' =
                  match same_arg_map xs1 xs2 with
                    None -> None
                  | Some map ->
                      try
                        Some (compose_same_arg map fg f (get_body env f ts1) g (get_body env g ts2))
                      with Cannot_compose -> None
                in
                let xs',t'' =
                  match t' with
                    None ->
                      xs1@xs2, compose f (get_body env f ts1) g (get_body env g ts2)
                  | Some t'' -> xs, t''
                in
                let t1' = List.fold_right make_fun xs' t'' in
                let t2' = tupling.tr2_term env t2 in
                Let(Recursive, [fg,[],t1'], t2')
              with Cannot_compose -> tupling.tr2_desc_rec env desc
            end
        | _ -> tupling.tr2_desc_rec env desc
      end
  | Fun(x,t) ->
      begin
        match Id.typ x with
          TPair({Id.typ=TPair _}, TPair _) ->
            let diffs = get_pair_diffs t in
(*
            let diffs' = List.filter (fun (t1,t2) -> Id.mem x @@ get_fv t1 || Id.mem x @@ get_fv t2) diffs in
*)
            let diffs' = diffs in
            let check (t1,t2) =
              match t1.desc, t2.desc with
                Fst {desc=Var x}, Snd {desc=Var y} -> Id.same x y
              | _ -> false
            in
            if diffs' <> [] && List.for_all check diffs'
            then
              let t' = List.fold_left (fun t (t1,t2) -> Format.printf "[%a |-> %a](%a)@." pp_print_term t2 pp_print_term t1 pp_print_term t; replace_term t2 t1 t) t diffs' in
              let cond1 = make_eq (make_fst (make_fst (make_var x))) (make_fst (make_snd (make_var x))) in
              let cond2 = make_eq (make_snd (make_fst (make_var x))) (make_snd (make_snd (make_var x))) in
              let cond = make_and cond1 cond2 in
              let t'' = make_seq (make_assert cond) t' in
              (make_fun x t'').desc
            else tupling.tr2_desc_rec env desc
        | _ -> tupling.tr2_desc_rec env desc
      end
  | Let(flag, bindings, t) ->
      let bindings' = List.map (fun (f,xs,t) -> f, xs, tupling.tr2_term env t) bindings in
      let env' = List.map (fun (f,xs,t) -> f,(f,xs,t)) bindings' @ env in
      Let(flag, bindings', tupling.tr2_term env' t)
  | Pair(t1, t2) ->
      let t1' = tupling.tr2_term env t1 in
      let t2' = tupling.tr2_term env t2 in
      let t' =
        match get_comb_pair t1 t2 with
          None -> compose_non_recursive false t1' t2'
        | Some t -> Format.printf "COMB: %a@." pp_print_term t; t
      in
      t'.desc
  | _ -> tupling.tr2_desc_rec env desc





























let classify f t =
  try
    ignore (partition_bindings f t); FSimpleRec
  with
    Not_recursive -> FNonRec
  | Cannot_compose -> FOther

let compose_let_same_arg map fg f t1 g t2 =
Format.printf "compose_let_same_arg@.";
  let before1,(x1,ts1),after1,t1' = partition_bindings f t1 in
  let before2,(x2,ts2),after2,t2' = partition_bindings g t2 in
  let aux ts_small ts_big map =
    assert (List.length map = List.length ts_big);
    if List.exists2 (fun t -> function None -> false | Some i -> t <> List.nth ts_small i) ts_big map
    then raise Cannot_compose;
    ts_big
  in
  let ts =
    match map with
      `Subset map' -> aux ts1 ts2 map'
    | `Supset map' -> aux ts2 ts1 map'
  in
  let x = Id.new_var "r" (TPair(Id.new_var "l" t1.typ, t2.typ)) in
  let before = before1 @ before2 in
  let after = after1 @ after2 in
  let p = Id.new_var "p" (TPair(x1, Id.typ x2)) in
  let pat =
    [p,  [], make_app (make_var fg) ts;
     x1, [], make_fst @@ make_var p;
     x2, [], make_snd @@ make_var p]
  in
  make_lets_f before @@ make_lets pat @@ make_lets_f after @@ make_pair t1' t2'

let compose_non_recursive first t1 t2 =
  let bindings,t = decomp_let (if first then t1 else t2) in
  let r = Id.new_var "r" (if first then t1.typ else t2.typ) in
  let t' =
    if first
    then make_pair (make_var r) t2
    else make_pair t1 (make_var r)
  in
  make_lets_f (bindings @ [Nonrecursive,(r,[],t)]) t'

let rec compose f t1 g t2 =
Format.printf "compose@.";
  match t1.desc, t2.desc with
    If(t11, t12, t13), _ ->
      make_if t11 (compose f t12 g t2) (compose f t13 g t2)
  | _, If(t21, t22, t23) ->
      make_if t21 (compose f t1 g t22) (compose f t1 g t23)
  | _ -> raise Cannot_compose

let rec compose_same_arg map fg f t1 g t2 =
Format.printf "compose_same_arg@.";
  match t1.desc, t2.desc with
    If(t11, t12, t13), If(t21, t22, t23) when t11 = t21 ->
      let t2' = compose_same_arg map fg f t12 g t22 in
      let t3' = compose_same_arg map fg f t13 g t23 in
      make_if t11 t2' t3'
  | If(t11, t12, t13), _ ->
      let t2' = compose_same_arg map fg f t12 g t2 in
      let t3' = compose_same_arg map fg f t13 g t2 in
      make_if t11 t2' t3'
  | _, If(t21, t22, t23) ->
      make_if t21 (compose_same_arg map fg f t1 g t22) (compose_same_arg map fg f t1 g t23)
  | _ -> compose_let (Some (map, fg)) f t1 g t2


let same_arg_map xs1 xs2 =
  let rec find i x xs =
    match xs with
      [] -> None
    | x'::xs' when Id.same x x' -> Some i
    | _::xs' -> find (i+1) x xs'
  in
  let find x xs = find 0 x xs in
  let make_map xs1 xs2 = List.map (fun x -> find x xs1) xs2 in
  if subset xs1 xs2 then
    Some (`Subset (make_map xs1 xs2))
  else if subset xs2 xs1 then
    Some (`Supset (make_map xs2 xs1))
  else
    None

let assoc_env f env =
  let _,xs,t = Id.assoc f env in
  let ys,t' = decomp_fun t in
  match xs@ys with
    [x] -> x, t'
  | _ -> assert false

















































let compose_non_recursive first t1 t2 =
Format.printf "compose_non_recursive@.";
  let bindings,t = decomp_let (if first then t1 else t2) in
  let r = Id.new_var "r" (if first then t1.typ else t2.typ) in
  let t' =
    if first
    then make_pair (make_var r) t2
    else make_pair t1 (make_var r)
  in
  make_lets_f (bindings @ [Nonrecursive,(r,[],t)]) t'

let compose_simple_rec fg f t1 g t2 =
Format.printf "compose_let@.";
  let before1,(x1,ts1),after1,t1' = partition_bindings f t1 in
  let before2,(x2,ts2),after2,t2' = partition_bindings g t2 in
  let x = Id.new_var "r" (TPair(Id.new_var "l" t1.typ, t2.typ)) in
  let before = before1 @ before2 in
  let after = after1 @ after2 in
  let p = Id.new_var "p" (TPair(x1, Id.typ x2)) in
  let pat =
    [p,  [], make_app (make_var fg) (ts1 @ ts2);
     x1, [], make_fst @@ make_var p;
     x2, [], make_snd @@ make_var p]
  in
  make_lets_f before @@ make_lets pat @@ make_lets_f after @@ make_pair t1' t2'

let compose_let fg f t1 g t2 =
Format.printf "compose_let@.%a:%a@.@.%a:%a@.@." Id.print f pp_print_term t1 Id.print g pp_print_term t2;
  match classify f t1, classify g t2 with
    FNonRec,    _          -> compose_non_recursive true t1 t2
  | _,          FNonRec    -> compose_non_recursive false t1 t2
  | FOther,     _
  | _,          FOther     -> raise Cannot_compose
  | FSimpleRec, FSimpleRec -> compose_simple_rec fg f t1 g t2

let rec compose fg f t1 g t2 =
Format.printf "compose@.";
  match t1.desc, t2.desc with
    If(t11, t12, t13), _ ->
      make_if t11 (compose fg f t12 g t2) (compose fg f t13 g t2)
  | _, If(t21, t22, t23) ->
      make_if t21 (compose fg f t1 g t22) (compose fg f t1 g t23)
  | _ -> compose_let fg f t1 g t2


let new_funs = ref ([] : (id list * (id * id list * typed_term)) list)

let tupling_term env t =
  match t.desc with
    Pair(t1, t2) when is_some t1 <> None && is_some t2 <> None ->
      Format.printf "PAIR: %a, %a@." pp_print_term t1 pp_print_term t2;
      begin match (get_opt_val @@ is_some t1).desc, (get_opt_val @@ is_some t2).desc with
         App({desc = Var f}, [{desc = Snd {desc = Var x}}]),
         App({desc = Var g}, [{desc = Snd {desc = Var y}}]) ->
           let z1,t1 = assoc_env f env in
           let z2,t2 = assoc_env g env in
           let x' = Id.new_var (Id.name x) @@ get_opt_typ @@ Id.typ x in
           let y' = Id.new_var (Id.name y) @@ get_opt_typ @@ Id.typ y in
           let t1' = subst z1 (make_var x') @@ pair_let t1 in
           let t2' = subst z2 (make_var y') @@ pair_let t2 in
           let typ =
             match t.typ with
               TPair(x,typ2) -> TPair(Id.new_var (Id.name x) @@ get_opt_typ @@ Id.typ x, get_opt_typ typ2)
             | _ -> assert false
           in
           let fg = Id.new_var (Id.name f ^ "_" ^ Id.name g) @@ TFun(x', TFun(y', typ)) in
           let t_body = subst_map [x, make_var x'; y, make_var y'] @@ compose fg f t1' g t2' in
           let r = Id.new_var "r" typ in
           let t_app = make_app (make_var fg) [make_snd @@ make_var x; make_snd @@ make_var y] in
           let t_pair = make_pair (make_some @@ make_fst @@ make_var r) (make_some @@ make_snd @@ make_var r) in
           new_funs := ([f;g], (fg, [x';y'], t_body)) :: !new_funs;
           Format.printf "ADD: %a@." Id.print fg;
           make_let [r, [], t_app] t_pair
      | _ -> tupling.tr2_term_rec env t
      end
  | Let(flag, bindings, t) ->
      let bindings' = List.map (fun (f,xs,t) -> f, xs, tupling.tr2_term env t) bindings in
      let env' = List.map (fun (f,xs,t) -> f,(f,xs,t)) bindings' @ env in
      make_let_f flag bindings' @@ tupling.tr2_term env' t
  | _ -> tupling.tr2_term_rec env t

let () = tupling.tr2_term <- tupling_term

let add_funs = make_trans ()

let add_funs_desc desc =
  match desc with
    Let(flag, bindings, t) ->
      let bindings' = List.map (fun (f,xs,t) -> add_funs.tr_var f, List.map add_funs.tr_var xs, add_funs.tr_term t) bindings in
      let funs1,funs2 =
        let aux (fs,_) = List.exists (fun (f,_,_) -> Id.mem f fs) bindings in
        List.partition aux !new_funs
      in
      let funs1' =
        let aux (fs,def) =
          List.filter (fun f -> not @@ List.exists (fun (g,_,_) -> Id.same f g) bindings) fs,
          def
        in
        List.map aux funs1 in
      let funs11,funs12 = List.partition (fun (fs,_) -> fs = []) funs1' in
      new_funs := funs12 @ funs2;
      let t' =
        let t' = add_funs.tr_term t in
        List.fold_left (fun t (_,def) -> make_letrec [def] t) t' funs11
      in
      Let(flag, bindings', t')
  | _ -> add_funs.tr_desc_rec desc

let () = add_funs.tr_desc <- add_funs_desc

let tupling t =
  new_funs := [];
  let t' = tupling.tr2_term [] t in
  add_funs.tr_term t'









let compose_app = make_trans ()

let compose_app_term t =
  match t.desc with
    Let _ ->
      let bindings,t' = decomp_let t in
      begin
        match bindings with
          (Nonrecursive,(x,[],{desc=Snd({desc=App({desc=Var f},[{desc=Pair(t11,t12)}])})}))::
          (Nonrecursive,(y,[],{desc=Fst({desc=App({desc=Var g},[{desc=Pair(t21,t22)}])})}))::bindings'
            when Id.same f g && is_none_term t11 && is_some_term t12 && is_some_term t21 && is_none_term t22 ->
          Format.printf "%a, %a@." Id.print f Id.print g;
          assert false;
              let p = Id.new_var "p" (TPair(x, (Id.typ y))) in
              let bindings'' =
                [p, [], make_app (make_var f) [make_pair t12 t21];
                 x, [], make_snd (make_var p);
                 y, [], make_fst (make_var p)]
              in
              make_lets bindings'' @@ compose_app.tr_term @@ make_lets_f bindings' t'
        | _ -> compose_app.tr_term_rec t
      end
  | _ -> compose_app.tr_term_rec t

let () = compose_app.tr_term <- compose_app_term

let compose_app = compose_app.tr_term








let rec decomp_let_app t =
  match t.desc with
    Let(Nonrecursive, [x,[], ({desc=App _} as t1)], t2) ->
      let bindings,t' = decomp_let_app t2 in
      (x,[],t1)::bindings, t'
  | _ -> [], t

let is_depend t x = List.mem x @@ get_fv t

let let_normalize = make_trans ()

let let_normalize_desc desc =
  match desc with
    Let(Nonrecursive, [x,[],{desc=App _}], _) -> let_normalize.tr_desc_rec desc
  | Let(Nonrecursive, [x,[],t1], t2) ->
      let t1' = let_normalize.tr_term t1 in
      let t2' = let_normalize.tr_term t2 in
      let bindings,t2'' = decomp_let_app t2' in
      let rec aux acc bindings =
        match bindings with
          [] -> acc,[]
        | (_,_,t)::bindings' when is_depend t x -> acc, bindings
        | (y,_,t)::bindings' -> aux (acc@[y,[],t]) bindings'
      in
      let bindings1,bindings2 = aux [] bindings in
      if bindings1 = []
      then Let(Nonrecursive, [x,[],t1'], t2')
      else
        let t2''' = make_lets bindings2 t2'' in
        (make_lets bindings1 @@ make_lets [x,[],t1'] t2''').desc
  | _ -> let_normalize.tr_desc_rec desc

let () = let_normalize.tr_desc <- let_normalize_desc

let let_normalize = let_normalize.tr_term



let elim_check t1 t2 =
Color.printf Color.Yellow "%a, %a@." pp_print_term t1 pp_print_term t2;
  match t1.desc, t2.desc with
    App({desc=Var f},ts1), App({desc=Var g},ts2) when Id.same f g && List.length ts1 = List.length ts2 ->
      List.for_all2 (fun t1 t2 -> same_term t1 t2 || is_none t1) ts1 ts2
  | _ -> false

let elim_same_app = make_trans ()

let elim_same_app_desc desc =
  match desc with
    Let(Nonrecursive, [x,[],t1],
        {desc = Let(Nonrecursive, [y,[],t2], t)}) when not (is_depend t2 x) && elim_check t1 t2 ->
      let t' = subst x (make_var y) t in
      elim_same_app.tr_desc @@ Let(Nonrecursive, [y,[],t2], t')
  | _ -> elim_same_app.tr_desc_rec desc

let () = elim_same_app.tr_desc <- elim_same_app_desc

let elim_same_app = elim_same_app.tr_term




let trans t = t
  |> inline_wrapped.tr_term
  |> Trans.flatten_let
  |> let_normalize
  |@> Format.printf "%a:@.%a@.@." Color.red "normalize let" pp_print_term
  |> elim_same_app
  |@> Format.printf "%a:@.%a@.@." Color.red "elim_same_app" pp_print_term
  |> tupling
  |@> Format.printf "%a:@.%a@.@." Color.red "tupled" pp_print_term
  |> Trans.inline_no_effect
(*
  |> do_and_return (Format.printf "BEFORE!:@.%a@.@." pp_print_term)
  |> Trans.let2fun
  |> do_and_return (Format.printf "BEFORE:@.%a@.@." pp_print_term)
  |> Trans.inline_no_effect
  |> do_and_return (Format.printf "INLINE:@.%a@.@." pp_print_term)
  |> Trans.beta_no_effect
  |> do_and_return (Format.printf "BETA:@.%a@.@." pp_print_term)
  |> tupling
  |> pair_let
  |> do_and_return (Format.printf "???:@.%a@.@." pp_print_term)
  |> tupling
  |> Trans.inline_no_effect
  |> tupling
*)
(*
  |> Trans.inline_no_effect
  |> Trans.beta_no_effect
  |> print_and_return (Format.printf "!!!:@.%a@.@." pp_print_term)
  |> tupling
  |> compose_app
  |> tupling
*)
