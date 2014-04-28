open Util
open Type
open Syntax
open Term_util


let trans = make_trans2 ()

let rec root x bb path_rev =
  let aux = function
      y, {desc=Fst{desc=Var z}} when Id.same x y -> Some (z,1)
    | y, {desc=Snd{desc=Var z}} when Id.same x y -> Some (z,2)
    | _ -> None
  in
  try
    let y,dir = get_opt_val @@ List.find ((<>) None) @@ List.map aux bb in
    root y bb (dir::path_rev)
  with Not_found -> x, List.rev path_rev
let root x bb = root x bb []

let rec find_fst x bb =
  match bb with
    [] -> None
  | (y,{desc=Fst{desc=Var z}})::bb' when Id.same x z -> Some y
  | _::bb' -> find_fst x bb'

let rec find_snd x bb =
  match bb with
    [] -> None
  | (y,{desc=Snd{desc=Var z}})::bb' when Id.same x z -> Some y
  | _::bb' -> find_snd x bb'

let rec find_app x bb =
  match bb with
    [] -> []
  | (_,{desc=App({desc=Var y},[t])})::bb' when Id.same x y -> t::find_app x bb'
  | _::bb' -> find_app x bb'


let rec make_tree x bb =
  Color.printf Color.Red "make_tree: %a@." Id.print x;
  match find_fst x bb, find_snd x bb, find_app x bb with
    Some lhs, Some rhs, _ -> Tree.Node(make_tree lhs bb, make_tree rhs bb)
  | None, None, args ->
      let typ =
        try
          Some (Id.typ @@ arg_var @@ Id.typ x)
        with Invalid_argument "arg_var" -> None
      in
      Tree.Leaf(typ, args)
  | Some _, None, _ -> raise (Fatal "not implemented: make_tree")
  | None, Some _, _ -> raise (Fatal "not implemented: make_tree")
  | _ -> assert false

let rec make_trees tree =
  match tree with
    Tree.Leaf(None, []) -> assert false
  | Tree.Leaf(None, _) -> assert false
  | Tree.Leaf(Some typ, []) -> [Tree.Leaf (make_none typ)]
  | Tree.Leaf(Some _, args) -> List.map (fun t -> Tree.Leaf (make_some t)) args
  | Tree.Node(lhs,rhs) ->
      let trees1 = make_trees lhs in
      let trees2 = make_trees rhs in
      flatten_map (fun t1 -> List.map (fun t2 -> Tree.Node(t1, t2)) trees2) trees1

let rec term_of_tree tree =
  match tree with
    Tree.Leaf t -> t
  | Tree.Node(t1,t2) -> make_pair (term_of_tree t1) (term_of_tree t2)

(*
let rec make_args tree =
  match tree with
    Tree.Leaf(None, []) -> assert false
  | Tree.Leaf(None, _) -> assert false
  | Tree.Leaf(Some typ, []) -> [make_bottom typ]
  | Tree.Leaf(Some _, args) -> args
  | Tree.Node(lhs,rhs) ->
      let trees1 = make_args lhs in
      let trees2 = make_args rhs in
      flatten_map (fun t1 -> List.map (fun t2 -> make_pair t1 t2) trees2) trees1
*)

let rec proj_of_path top path t =
  match path with
    [] when top -> t
  | [] -> make_get_val t
  | 1::path' -> proj_of_path false path' @@ make_fst t
  | 2::path' -> proj_of_path false path' @@ make_snd t
  | _::path' -> assert false
let proj_of_path path t = proj_of_path true path t

let make_some' t =
  if is_none t
  then t
  else make_some t

let rec same_arg path_rev t1 t2 =
  match t1,t2 with
    Tree.Leaf t1', Tree.Leaf t2' when t1' = t2' -> List.rev path_rev
  | Tree.Leaf t1', Tree.Leaf t2' -> []
  | Tree.Node(t11,t12), Tree.Node(t21,t22) -> same_arg (1::path_rev) t11 t21 @ same_arg (2::path_rev) t12 t22
  | _ -> assert false
let same_arg t1 t2 = same_arg [] t1 t2

let inst_var_fun x tt bb t =
  match Id.typ x with
    TFun(y,_) ->
      let y' = Id.new_var_id y in
      Format.printf "x: %a, y': %a@." Id.print x Id.print y';
      let r,path = root x bb in
      if Id.same x r
      then
        make_app (make_var x) [t]
      else
        let r' = trans.tr2_var (tt,bb) r in
        let tree = make_tree r bb in
        let tree' = Tree.update path (Tree.Leaf(Some (Id.typ y'), [make_var y'])) tree in
let pr _ (_,ts) =
  Format.printf "[%a]" (print_list pp_print_term' "; ") ts
in
Format.printf "TREE: %a@." (Tree.print pr) tree';
Format.printf "r': %a:%a@." Id.print r' pp_print_typ (Id.typ r');
        let trees = make_trees tree' in
Format.printf "|trees|': %d@." (List.length trees);
Format.printf "hd trees: %a@." (Tree.print pp_print_term) (List.hd trees);
        let argss = List.map Tree.flatten trees in
Color.printf Color.Red "BEGIN@.";
        let args = List.map (fun args -> [make_tuple args]) argss in
        let apps = List.map (make_app (make_var r')) args in
Color.printf Color.Red "END@.";
(*
        Format.printf "TREE(%a --%a-- %a):%d@." Id.print r (print_list Format.pp_print_int "") path Id.print x @@ List.length apps;
        List.iter (Format.printf "  %a@." pp_print_term) apps;
        Format.printf "orig: %a@." pp_print_term t;
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
        let xs = List.map (fun t -> Id.new_var "x" t.typ) apps in
Format.printf "root: %a, %a@." Id.print r pp_print_typ (Id.typ r);
Format.printf "hd: %a, %a@." Id.print (List.hd xs) pp_print_typ (Id.typ @@ List.hd xs);
        let t' =
          let t' = proj_of_path path @@ make_var @@ List.hd xs in
          let t' =
            let aux t (i,j,path) =
              let t1 = make_var (List.nth xs i) in
              let t2 = make_var (List.nth xs j) in
              make_assume (make_eq t1 t2) t
            in
            List.fold_left aux t' same_arg_apps
          in
          List.fold_left2 (fun t x app -> make_let [x,[],app] t) t' xs apps
        in
        let x' = Id.new_var_id x in
        subst y' t t'
  | _ -> make_app (make_var x) [t] (* negligence *)

let rec tree_of_typ typ =
  match typ with
    TPair(x,typ') ->
      let t1 = tree_of_typ @@ Id.typ x in
      let t2 = tree_of_typ typ' in
      Tree.Node(t1,t2)
  | _ -> Tree.Leaf typ

let rec typ_of_tree t =
  match t with
    Tree.Leaf typ -> typ
  | Tree.Node(t1,t2) -> TPair(Id.new_var "x" (typ_of_tree t1), typ_of_tree t2)

let rec elim_none t =
  match t with
    Tree.Leaf None -> None
  | Tree.Leaf (Some typ) -> Some (Tree.Leaf (opt_typ typ))
  | Tree.Node(t1,t2) ->
    match elim_none t1, elim_none t2 with
      None, None -> None
    | Some t, None
    | None, Some t -> Some t
    | Some t1, Some t2 -> Some (Tree.Node(t1,t2))

(*
let trans_typ' (tt,bb) typ =
  match typ with
    TPair _ ->
      let tree = tree_of_typ typ in
      if Tree.exists (Type.is_fun_typ) tree
      then
        let arg = Tree.map (fun _ -> function TFun(x, _) -> Some (Id.typ x) | _ -> None) tree in
        let arg' = elim_none arg in
        match arg' with
          None -> trans.tr2_typ_rec (tt,bb) typ, None
        | Some arg'' ->
          let result = Tree.map (fun _ -> function TFun(_, typ) -> opt_typ typ | typ -> typ) tree in
          let typs = Tree.flatten arg'' in
          let typ = typ_of_tree result in
          List.fold_right (fun typ typ' -> TFun(Id.new_var "x" typ, typ')) typs typ, Some typs
      else trans.tr2_typ_rec (tt,bb) typ, None
  | _ -> trans.tr2_typ_rec (tt,bb) typ, None

let trans_typ (tt,bb) typ = fst (trans_typ' (tt,bb) typ)
*)

let decomp_tfun_ttuple typ =
  let typs = decomp_ttuple typ in
  let decomp typ =
    match typ with
      TFun(x,typ') -> Some (x,typ')
    | _ -> None
  in
  let xtyps = List.map decomp typs in
  if List.mem None xtyps
  then None
  else Some (List.map get_opt_val xtyps)

let trans_typ ttbb typ =
  match typ with
  | TPair _ ->
      begin match decomp_tfun_ttuple typ with
      | None -> trans.tr2_typ_rec ttbb typ
      | Some xtyps ->
          let xtyps' = List.map (fun (x,typ) -> trans.tr2_var ttbb x, trans.tr2_typ ttbb typ) xtyps in
          let arg_typs = List.map (fun (x,_) -> opt_typ @@ Id.typ x) xtyps' in
          let ret_typs = List.map (fun (_,typ) -> opt_typ typ) xtyps' in
          let name = List.fold_right (^) (List.map (fun (x,_) -> Id.name x) xtyps') "" in
          TFun(Id.new_var name @@ make_ttuple arg_typs, make_ttuple ret_typs)
      end
  | _ -> trans.tr2_typ_rec ttbb typ

(*
let trans_typ ttbb typ =
  trans_typ ttbb typ |@>
  Color.printf Color.Yellow "%a@ ===>@ @[%a@]@.@." print_typ typ print_typ
*)

let trans_desc (tt,bb) desc =
  match desc with
  | Let(Nonrecursive, [x,[],({desc=App({desc=Var x1},[t11])} as t1)], t) ->
      let x' = trans.tr2_var (tt,bb) x in
      let x1' = trans.tr2_var (tt,bb) x1 in
      let t11' = trans.tr2_term (tt,bb) t11 in
      let bb' = (x,t1)::bb in
Format.printf "B: ";
List.iter (fun (x,t) -> Format.printf "%a = %a; " Id.print x pp_print_term t) bb';
Format.printf "@.";
      let t' = trans.tr2_term (tt,bb') t in
      let tx = inst_var_fun x1' tt bb' t11' in
Color.printf Color.Green "x1: %a@." Id.print x1;
Color.printf Color.Green "t11: %a@." pp_print_term t11;
Color.printf Color.Green "tx: %a@." pp_print_term tx;
      (make_let [x',[],tx] t').desc
  | Let(Nonrecursive, [x,[],({desc=Pair({desc=Var x1},{desc=Var x2})} as t1)], t) ->
Color.printf Color.Reverse "x1=%a, x2=%a@." print_id_typ x1 print_id_typ x2;
      let x' =  trans.tr2_var (tt,bb) x in
      let x1' = trans.tr2_var (tt,bb) x1 in
      let x2' = trans.tr2_var (tt,bb) x2 in
      let bb' = (x,t1)::bb in
      let t' = trans.tr2_term (tt,bb') t in
      let t1' =
        match trans_typ (tt,bb) @@ Id.typ x with
          TFun(y, _) ->
            let y' = Id.new_var_id y in
            let ty1 = make_fst (make_var y') in
            let ty2 = make_snd (make_var y') in
            let y1 = Id.new_var (Id.name y ^ "1") ty1.typ in
            let y2 = Id.new_var (Id.name y ^ "2") ty2.typ in
Color.printf Color.Yellow "y1=%a, y2=%a@." print_id_typ y1 print_id_typ y2;
            let t1 = make_some @@ make_app (make_var x1') [make_get_val @@ make_var y1] in
            let t1' = make_if (make_is_none @@ make_var y1) (make_none @@ get_opt_typ t1.typ) t1 in
            let t2 = make_some @@ make_app (make_var x2') [make_get_val @@ make_var y2] in
            let t2' = make_if (make_is_none @@ make_var y2) (make_none @@ get_opt_typ t2.typ) t2 in
            make_fun y' @@ make_lets [y1,[],ty1; y2,[],ty2] @@ make_pair t1' t2'
        | _ -> make_pair (make_var x1') (make_var x2')
      in
      (make_let [x',[],t1'] t').desc
(*
  | Let(Nonrecursive, [x,[],({desc=Pair({desc=Var x1},{desc=Var x2})} as t1)], t) ->
      let x' =  trans.tr2_var (tt,bb) x in
      let x1' = trans.tr2_var (tt,bb) x1 in
      let x2' = trans.tr2_var (tt,bb) x2 in
      let bb' = (x,t1)::bb in
      let t' = trans.tr2_term (tt,bb') t in
      let t1' =
        match snd @@ trans_typ' (tt,bb) @@ Id.typ x with
        | Some [typ1;typ2] ->
            let y1 = Id.new_var "x" typ1 in
            let y2 = Id.new_var "x" typ2 in
Color.printf Color.Yellow "y1:%a, y2:%a@." Id.print y1 Id.print y2;
            let t1 = make_some @@ make_app (make_var x1') [make_get_val @@ make_var y1] in
            let t1' = make_if (make_is_none @@ make_var y1) (make_none @@ get_opt_typ t1.typ) t1 in
            let t2 = make_some @@ make_app (make_var x2') [make_get_val @@ make_var y2] in
            let t2' = make_if (make_is_none @@ make_var y2) (make_none @@ get_opt_typ t2.typ) t2 in
            make_fun y1 @@ make_fun y2 @@ make_pair t1' t2'
        | Some _ -> assert false (* NOT IMPLEMENTED *)
        | None -> make_pair (make_var x1') (make_var x2')
      in
      (make_let [x',[],t1'] t').desc
*)
  | Let(Nonrecursive, [x,[],({desc=Fst{desc=Var x1}} as t1)], t) ->
      let x' = trans.tr2_var (tt,bb) x in
      let x1' = trans.tr2_var (tt,bb) x1 in
      let bb' = (x,t1)::bb in
      let t' = trans.tr2_term (tt,bb') t in
      let t1' =
        match Id.typ x1' with
        | TPair _ -> make_fst @@ make_var x1'
        | TFun(y,typ) ->
            begin match decomp_tfun_ttuple @@ Id.typ x1 with
            | None -> assert false
            | Some [z1,typ1; z2,typ2] ->
                let z = Id.new_var_id z1 in
                make_fun z @@ make_get_val @@ make_fst @@ make_app (make_var x1') [make_pair (make_some @@ make_var z) (make_none @@ Id.typ z2)]
            | Some xtyps -> assert false (* Not implemented *)
            end
        | _ -> assert false
      in
      (make_let [x',[],t1'] t').desc
  | Let(Nonrecursive, [x,[],({desc=Snd{desc=Var x1}} as t1)], t) ->
      let x' = trans.tr2_var (tt,bb) x in
      let x1' = trans.tr2_var (tt,bb) x1 in
      let bb' = (x,t1)::bb in
      let t' = trans.tr2_term (tt,bb') t in
      let t1' =
        match Id.typ x1' with
        | TPair _ -> make_snd @@ make_var x1'
        | TFun(y,typ) ->
            begin match decomp_tfun_ttuple @@ Id.typ x1 with
            | None -> assert false
            | Some [z1,typ1; z2,typ2] ->
                let z = Id.new_var_id z2 in
                make_fun z @@ make_get_val @@ make_snd @@ make_app (make_var x1') [make_pair (make_none @@ Id.typ z1) (make_some @@ make_var z)]
            | Some xtyps -> assert false (* Not implemented *)
            end
        | _ -> assert false
      in
      (make_let [x',[],t1'] t').desc
  | _ -> trans.tr2_desc_rec (tt,bb) desc

let () = trans.tr2_desc <- trans_desc
let () = trans.tr2_typ <- trans_typ

let trans tt t = t
  |@> Format.printf "INPUT: %a@." pp_print_term
  |> Trans.inline_no_effect
  |@> Format.printf "inline_no_effect: %a@." pp_print_term_typ
  |> Trans.normalize_let
  |@> Format.printf "normalize_let: %a@." pp_print_term_typ
  |> Trans.flatten_let
  |@> Format.printf "flatten_let: %a@." pp_print_term_typ
  |@> flip Type_check.check TUnit
  |> trans.tr2_term (tt,[])
  |> Trans.inline_no_effect
  |*@> Format.printf "ref_trans: %a@." pp_print_term'
