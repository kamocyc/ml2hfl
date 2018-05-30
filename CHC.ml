open Util
open Syntax
open Type
open Term_util

module Debug = Debug.Make(struct let check = Flag.Debug.make_check __MODULE__ end)

type atom = Term of term | PApp of id * id list
type constr = {head:atom; body:atom list} (* if head is the form of `PApp(p,xs)`, `xs` must be distinct each other *)
type t = constr list
type pvar = id

let is_base_const t =
  match t.desc with
  | Const _ -> is_base_typ t.typ
  | _ -> false

let is_simple_expr t =
  is_simple_bexp t || is_simple_aexp t || is_base_const t

let term_of_atom a =
  match a with
  | Term t -> t
  | PApp(p,xs) -> Term.(var p @ vars xs)

let atom_of_term t =
  match t.desc with
  | App({desc=Var p}, ts) ->
      let xs = List.map (function {desc=Var x} -> x | _ -> invalid_arg "CHC.atom_of_term") ts in
      if not @@ Id.is_predicate p then invalid_arg "CHC.atom_of_term";
      PApp(p, xs)
  | App _ ->
      Format.eprintf "%a@." Print.term t;
      invalid_arg "CHC.atom_of_term"
  | _ ->
      if is_simple_expr t then
        Term t
      else
        (Format.eprintf "%a@." Print.term t;
         invalid_arg "CHC.atom_of_term")

let print_atom fm a =
  match a with
  | Term t -> Print.term fm t
  | PApp(p, xs) -> Format.fprintf fm "@[%a(%a)@]" Id.print p (print_list Id.print ", ") xs
let print_constr fm {head;body} = Format.fprintf fm "@[<hov 2>%a |=@ %a@]" (List.print print_atom) body print_atom head
let print fm (constrs:t) = List.print print_constr fm constrs

let print_one_sol fm (p,(xs,atoms)) = Format.fprintf fm "@[%a := %a@]" print_atom (PApp(p,xs)) (List.print print_atom) atoms
let print_sol fm sol = List.print print_one_sol fm sol

let of_term_list (constrs : (term list * term) list) =
  List.map (fun (body,head) -> {body=List.map atom_of_term body; head=atom_of_term head}) constrs

let to_term_list (constrs : t) =
  List.map (fun {body;head} -> List.map term_of_atom body, term_of_atom head) constrs

let decomp_app a =
  match a with
  | PApp(p,xs) -> Some (p,xs)
  | Term _ -> None
let is_app_of a p = decomp_app a |> Option.exists (fst |- Id.(=) p)
let is_app = decomp_app |- Option.is_some
let is_term = decomp_app |- Option.is_none
let decomp_term a =
  match a with
  | PApp _ -> None
  | Term t -> Some t

let same_atom a1 a2 = same_term (term_of_atom a1) (term_of_atom a2)
let unique = List.unique ~eq:same_atom

let pvar_of a =
  match a with
  | PApp(p, _) -> Some p
  | _ -> None

let rename_map ?(body=false) map a =
  match a with
  | PApp(p,xs) ->
      let dom,range = List.split map in
      if not body && List.Set.(disjoint ~eq:Id.eq range (diff ~eq:Id.eq xs dom)) then
        (Format.eprintf "%a %a@." Print.(list (pair id id)) map print_atom a;
         invalid_arg "CHC.rename_map");
      PApp(p, List.map (fun z -> List.assoc_default ~eq:Id.eq z z map) xs)
  | Term t' -> Term (subst_var_map map t')

let rename ?(body=false) x y a =
  match a with
  | PApp(p,xs) when Id.mem x xs ->
      if not body && Id.mem y xs then (Format.eprintf "[%a |-> %a](%a)@." Id.print x Id.print y print_atom a; invalid_arg "CHC.rename");
      PApp(p, List.map (fun z -> if Id.eq x z then y else z) xs)
  | PApp _ -> a
  | Term t' -> Term (subst_var x y t')

let get_fv a =
  match a with
  | Term t -> get_fv t
  | PApp(_,xs) -> xs

let get_fv_constr {head; body} = List.unique ~eq:Id.eq @@ List.flatten_map get_fv (head::body)

let map_head f {head; body} = {head=f head; body}
let map_body f {head; body} = {head; body=f body}
let map f {head;body} = {head=f head; body=List.map f body}

type data = (pvar * pvar) list * pvar list * constr list * (pvar * (pvar list * atom list)) list

let replace_with_true (deps, ps, constrs, sol : data) ps_true =
  let deps' = List.filter_out (fun (p1,p2) -> List.exists (fun p -> Id.(p = p1 || p = p2)) ps_true) deps in
  let sol' =
    let aux p =
      let xs,_ = decomp_tfun @@ Id.typ p in
      p, (xs, [])
    in
    List.map aux ps_true @ sol
  in
  let ps' = List.Set.diff ps ps_true in
  let constrs' =
    constrs
    |> List.filter_out (fun {head} -> List.exists (is_app_of head) ps_true)
    |> List.map (map_body @@ List.filter_out (fun a -> List.exists (is_app_of a) ps_true))
  in
  Debug.printf "SIMPLIFIED: %a@.@.@." print constrs';
  deps', ps', constrs', sol'

let dummy_pred = Id.new_predicate Ty.int

let normalize constrs =
  unsupported "CHC.normalized"

let rec once acc fv =
  match fv with
  | [] -> acc
  | [x] -> x::acc
  | x1::x2::fv' when Id.(x1 <> x2) -> once (x1::acc) (x2::fv')
  | x::fv' ->
      fv'
      |> List.drop_while (Id.(=) x)
      |> once acc
let once xs = once [] xs

let get_dependencies constrs : (pvar * pvar) list =
  let aux {body;head} =
    let p_head = match pvar_of head with None -> dummy_pred | Some p -> p in
    Combination.product (List.filter_map pvar_of body) [p_head]
  in
  constrs
  |> List.flatten_map aux
  |> List.unique ~eq:(Compare.eq_on (Pair.map_same Id.id))

let apply_sol_atom sol fv a =
  match a with
  | PApp(p,xs) ->
      begin
        match Id.assoc_option p sol with
        | Some (ys,atoms,fv') ->
            let fv'',atoms' =
              if List.Set.disjoint ~eq:Id.eq fv fv' then
                fv', atoms
              else
                let fv'' = List.map Id.new_var_id fv' in
                fv'', List.map (rename_map ~body:true (List.combine fv' fv'')) atoms
            in
            if not @@ List.Set.disjoint ~eq:Id.eq fv fv'' then assert false;
            if List.length xs <> List.length ys then invalid_arg "CHC.apply_sol_atom";
            Debug.printf "[apply_sol_atom] fv: %a@." Print.(list id) fv;
            Debug.printf "[apply_sol_atom] fv': %a@." Print.(list id) fv';
            Debug.printf "[apply_sol_atom] fv'': %a@." Print.(list id) fv'';
            Debug.printf "[apply_sol_atom] sol: %a@." print_one_sol (p,(ys,atoms));
            Debug.printf "[apply_sol_atom] a: %a@." print_atom a;
            List.map (rename_map ~body:true (List.combine ys xs)) atoms'
            |@> Debug.printf "[apply_sol_atom] r: %a@.@." (Print.list print_atom)
        | None -> [a]
      end
  | _ -> [a]

let apply_sol_constr remove_matched_head sol {head;body} =
  if not remove_matched_head then unsupported "CHC.apply_sol_constr";
  let fv = get_fv_constr {head;body} in
  let body = unique @@ List.flatten_map (apply_sol_atom sol fv) body in
  if List.exists (fun (p,_) -> is_app_of head p) sol then
    []
  else
    let heads = apply_sol_atom sol fv head in
    List.map (fun head -> {head; body}) heads
    |@> Debug.printf "[apply_sol_constr] input: %a@.[apply_sol_constr] output: %a@.@." print_constr {head;body} (List.print print_constr)

let apply_sol remove_matched_head sol' (deps,ps,constrs,sol : data) : data =
  if not remove_matched_head then unsupported "CHC.apply_sol";
  Debug.printf "[apply_sol] input: %a@." print constrs;
  let add_fv (p,(xs,atoms)) = p, (xs, atoms, List.unique ~eq:Id.eq @@ List.Set.diff ~eq:Id.eq (List.flatten_map get_fv atoms) xs) in
  Debug.printf "[apply_sol] sol': %a@." print_sol sol';
  let fixed_sol =
    let aux sol =
      let sol' = List.map add_fv sol in
      let aux (p,(xs,atoms)) =
        let fv = List.Set.diff (List.flatten_map get_fv atoms) xs in
        p, (xs, unique @@ List.flatten_map (apply_sol_atom sol' fv) atoms)
      in
      List.map aux sol
    in
    fixed_point aux sol'
  in
  Debug.printf "[apply_sol] fixed_sol: %a@." print_sol fixed_sol;
  let deps' =
    let deps_sol = List.flatten_map (fun (p,(_,atoms)) -> List.map (fun p' -> p, p') @@ List.filter_map pvar_of atoms) fixed_sol in
    let aux (p1,p2) =
      if Id.mem_assoc p2 deps_sol then
        []
      else
        match List.filter_map (fun (p1',p2') -> if Id.(p1 = p1') then Some p2' else None) deps_sol with
        | [] -> [p1,p2]
        | ps -> List.map (fun p -> p, p2) ps
    in
    List.flatten_map aux deps
  in
  let ps' = List.filter_out (Id.mem_assoc -$- sol') ps in
  let constrs' = List.flatten_map (apply_sol_constr remove_matched_head @@ List.map add_fv fixed_sol) constrs in
  let sol'' = fixed_sol @ sol in
  Debug.printf "[apply_sol] output: %a@." print constrs';
  deps', ps', constrs', sol''

(* Trivial simplification *)
let simplify_trivial (deps,ps,constrs,sol : data) =
  let rec loop need_rerun body1 body2 head head_fv =
    if !!Debug.check then assert (List.Set.eq ~eq:Id.eq (get_fv head) head_fv);
    match body2 with
    | [] ->
        begin
          match head with
          | Term {desc=Const True} -> None
          | Term {desc=BinOp(Eq, t1, t2)} when is_simple_expr t1 && same_term t1 t2 -> None
          | _ -> Some (need_rerun, {body=body1; head})
        end
    | a::body2' ->
        match a with
        | Term {desc=Const True} -> loop need_rerun body1 body2' head head_fv
        | Term {desc=Const False} -> None
        | Term {desc=BinOp(Eq, t1, t2)} when is_simple_expr t1 && same_term t1 t2 -> loop true body1 body2' head head_fv
        | Term {desc=BinOp(And, t1, t2)} -> loop need_rerun body1 ((Term t1)::(Term t2)::body2') head head_fv
        | Term {desc=BinOp(Eq, {desc=Var x}, {desc=Var y})} when not (Id.mem x head_fv && is_app head && Id.mem y head_fv) ->
            let head' = rename x y head in
            let rn = List.map (rename ~body:true x y) in
            let head_fv' = get_fv head' in
            loop true [] (rn body1 @ rn body2') head' head_fv'
        | _ -> loop need_rerun (a::body1) body2' head head_fv
  in
  let need_rerun,constrs' =
    let aux {body;head} (b,acc) =
      match loop false [] body head (get_fv head) with
      | None -> true, acc
      | Some(need_rerun,constr') -> b||need_rerun, constr'::acc
    in
    List.fold_right aux constrs (false,[])
  in
  let deps' = if need_rerun then get_dependencies constrs' else deps in
  Some (need_rerun, (deps',ps,constrs',sol))

(* Remove constraint whose body is empty *)
let simplify_empty_body (deps,ps,constrs,sol as x : data) =
  let ps' =
    constrs
    |> List.filter_map (fun {head;body} -> if body = [] then decomp_app head else None)
    |> List.map fst
  in
  if ps' = [] then
    None
  else
    let () = Debug.printf "REMOVE2: %a@." Print.(list id) ps' in
    Some (true, replace_with_true x ps')

(* Remove predicates which do not occur in a body *)
let simplify_unused (deps,ps,constrs,sol as x : data) =
  let ps1,ps2 = List.partition (fun p -> List.exists (fun (p1,_) -> Id.(p = p1)) deps) ps in
  if ps2 = [] then
    None
  else
    let () = Debug.printf "REMOVE1: %a@." Print.(list id) ps2 in
    Some (true, replace_with_true x ps2)

(* Forwarad inlinining *)
let simplify_inlining_forward (deps,ps,constrs,sol as x : data) =
  let check p =
    let count (n_head,n_body) {head;body} =
      (if is_app_of head p then 1+n_head else n_head),
      List.count (is_app_of -$- p) body + n_body
    in
    let n_head,n_body = List.fold_left count (0,0) constrs in
    let self_implication p {head;body} = is_app_of head p && List.exists (is_app_of -$- p) body in
    n_head = 1 && not @@ List.exists (self_implication p) constrs
  in
  let ps' = List.filter check ps in
  Debug.printf "ps': %a@." Print.(list id) ps';
  let assoc p = List.find (fun {head} -> is_app_of head p) constrs in
  let sol' =
    let aux p =
      let {head;body} = assoc p in
      let _,xs = Option.get @@ decomp_app head in
      p, (xs, body)
    in
    List.map aux ps'
  in
  if sol' = [] then
    None
  else
    Some (true, apply_sol true sol' x)

(* Backward inlinining *)
let simplify_inlining_backward (deps,ps,constrs,sol as x : data) =
  let aux {head;body} =
    let body1,body2 = List.partition is_app body in
    if is_term head then
      match body1 with
      | [PApp(p,xs)] ->
          let ts = List.map term_of_atom body2 in
          let t = term_of_atom head in
          Some(p, (xs, Term (Term.(not (ands ts) || t))))
      | _ -> None
    else
      None
  in
  let goals = List.filter_map aux constrs in
  if goals = [] then
    None
  else
    let () = Debug.printf "goals: %a@." Print.(list (pair id (pair (list id) print_atom))) goals in
    let deps' = assert false in
    let ps' = assert false in
    let constrs' = assert false in
    let sol' = assert false in
    Some (true, (deps', ps', constrs', sol'))

(* Remove clause whose body is unsatisfiable *)
let simplify_unsat (deps,ps,constrs,sol as x : data) =
  let is_sat {body} =
    body
    |> List.filter is_term
    |> List.map term_of_atom
    |> make_ands
    |> FpatInterface.of_term
    |> Fpat.Formula.of_term
    |> FpatInterface.is_sat
  in
  let constrs1,constrs2 = List.partition is_sat constrs in
  if constrs2 = [] then
    None
  else
    let deps' = get_dependencies constrs in
    let ps' = ps in
    let constrs' = constrs1 in
    let sol' = sol in
    Some (true, (deps', ps', constrs', sol'))

(* Remove trivially satisfiable clauses *)
let simplify_head_in_body (deps,ps,constrs,sol : data) =
  let is_sat {head;body} = List.exists (same_atom head) body in
  let constrs1,constrs2 = List.partition is_sat constrs in
  if constrs1 = [] then
    None
  else
    Some(true, (deps,ps,constrs2,sol))

let simplifiers : (data -> (bool * data) option) list =
  [simplify_unused;
   simplify_empty_body;
   simplify_trivial;
   simplify_inlining_forward;
(* simplify_inlining_backward; *)
   simplify_head_in_body;
   simplify_unsat]

let simplify ?(normalized=false) (constrs:t) =
  let constrs = if normalized then constrs else normalize constrs in
  Debug.printf "dummy_pred: %a@." Id.print dummy_pred;
  Debug.printf "INPUT: %a@." print constrs;
  let deps = get_dependencies constrs in
  Debug.printf "deps: %a@." Print.(list (pair id id)) deps;
  let ps =
    deps
    |> List.flatten_map Pair.to_list
    |> List.unique ~eq:Id.eq
    |> List.filter_out (Id.(=) dummy_pred)
  in
  let rec loop orig rest x =
    match rest with
    | [] -> x
    | f::rest' ->
        match f x with
        | None -> loop orig rest' x
        | Some(true, x') -> loop orig orig x'
        | Some(false, x') -> loop orig rest' x'
  in
  let loop orig x = loop orig orig x in
  let deps',ps',constrs',sol = loop simplifiers (deps, ps, constrs, []) in
  Debug.printf "REMOVED: %a@." Print.(list id) @@ List.map fst sol;
  Debug.printf "deps': %a@." Print.(list (pair id id)) @@ List.sort (Compare.on (Pair.map_same Id.id)) deps';
  Debug.printf "SIMPLIFIED: %a@." print constrs';
  sol, constrs'
