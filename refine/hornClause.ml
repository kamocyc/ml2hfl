open ExtList
open ExtString

(** Horn clauses *)

(** The type of Horn clauses
    @invariant Given Hc(popt, atms, t), List.for_all (fun atm -> Atom.coeffs atm = []) atms *)
type t = Hc of (Var.t * (Var.t * SimType.t) list) option * Atom.t list * Term.t

(** {6 Printers} *)

let pr_elem ppf (Hc(popt, atms, t)) =
  let _ = Format.fprintf ppf "@[<hov>" in
  let _ =
    if atms <> [] then
      Format.fprintf ppf "%a" (Util.pr_list Atom.pr ",@ ") atms
  in
  let _ =
    if not (Term.equiv t Formula.ttrue) then
      let _ = if atms <> [] then Format.fprintf ppf ",@ " in
      Format.fprintf ppf "%a@ " Term.pr t
  in
  match popt with
    None ->
      Format.fprintf ppf "|- bot@]"
  | Some(p) ->
      Format.fprintf ppf "|- %a@]"
        Atom.pr
        (Atom.of_pred p)

let pr ppf hcs =
  Format.fprintf ppf "@[<v>%a@]" (Util.pr_list pr_elem "@,@,") hcs

(** {6 Functions on Horn clauses} *)

let fvs (Hc(popt, atms, t)) =
  Util.diff
    (List.unique (Util.concat_map Atom.fvs atms @ Term.fvs t))
    (Util.fold_opt [] (fun (_, xtys) -> List.map fst xtys) popt)

let coeffs (Hc(popt, atms, t)) =
  List.unique (Util.concat_map Atom.coeffs atms @ Term.coeffs t)

let is_root (Hc(popt, _, _)) = popt = None
let is_coeff (Hc(popt, _, _)) =
  match popt with
    None -> false
  | Some(pid, _) -> Var.is_coeff pid

(** @require not (Util.intersects (Util.dom sub) (fvs popt)) *)
let subst sub (Hc(popt, atms, t)) =
  Hc(popt, List.map (Atom.subst sub) atms, FormulaUtil.subst sub t)

(** rename free variables to fresh ones *)
let fresh (Hc(popt, atms, t) as hc) =
  let fvs = fvs hc in
  let sub = List.map (fun x -> x, Term.make_var (Var.new_var ())) fvs in
  Hc(popt,
    List.map (Atom.subst (fun x -> List.assoc x sub)) atms,
    FormulaUtil.subst (fun x -> List.assoc x sub) t)

(** {6 Functions on sets of Horn clauses} *)

let lhs_pids hcs =
  Util.concat_map
    (fun (Hc(_, atms, _)) ->
      List.map fst atms)
    hcs

let rhs_pids hcs =
  Util.concat_map
    (function
      Hc(None, _, _) -> []
    | Hc(Some(pid, _), _, _) -> [pid])
    hcs

let pids hcs = rhs_pids hcs @ lhs_pids hcs

(** @return false if and only if a subset of hcs is equivalent to a disjunctive constraint like (P(...) or Q(...)) => phi *)
let is_non_disjunctive hcs =
  let popts = List.map (function Hc(None, _, _) -> None | Hc(Some(pid, _), _, _) -> Some(pid)) hcs in
  not (Util.is_dup popts)

let is_well_defined hcs =
  Util.subset (lhs_pids hcs) (rhs_pids hcs)

let is_non_redundant hcs =
  Util.subset (rhs_pids hcs) (lhs_pids hcs)

let mem pid hcs =
  List.exists (function Hc(Some(pid', _), _, _) -> pid = pid' | _ -> false) hcs

let lookup (pid, ttys) hcs =
  let hcs' =
    List.find_all
      (function Hc(Some(pid', _), _, _) -> pid = pid' | _ -> false)
      hcs
  in
  match hcs' with
    [] -> raise Not_found
  | _ ->
      let res =
        List.map
          (function (Hc(Some(_, xtys), _, _) as hc) ->
            let Hc(_, atms, t) = fresh hc in
            let sub = List.combine (List.map fst xtys) (List.map fst ttys) in
            List.map (Atom.subst (fun x -> List.assoc x sub)) atms,
            FormulaUtil.subst (fun x -> List.assoc x sub) t
          | _ -> assert false)
          hcs'
      in
      if List.for_all (fun (atms, _) -> atms = []) res then
        [[], Formula.bor (List.map snd res)]
      else
        res

(** @require is_non_disjunctive hcs *)
let lookup_nd (pid, ttys) hcs =
  Util.elem_of_singleton (lookup (pid, ttys) hcs)



let rec depend pids0 hcs =
  let hcs1, hcs2 =
    List.partition
      (fun hc -> Util.intersects pids0 (pids [hc]))
      hcs
  in
  let pids1 = Util.diff (List.unique (pids hcs1)) pids0 in
  if pids1 = [] then
    hcs1
  else
    hcs1 @ depend pids1 hcs2

(** find Horn clauses which depend backward to the predicate variables in pids0 or roots *)
let rec backward_depend pids0 hcs =
  let hcs1, hcs2 =
    List.partition
      (fun hc -> is_root hc || Util.intersects pids0 (rhs_pids [hc]))
      hcs
  in
  let pids1 = List.unique (lhs_pids hcs1) in
  if pids1 = [] then
    hcs1
  else
    hcs1 @ backward_depend pids1 hcs2
