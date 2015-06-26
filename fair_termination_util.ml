open Util
open Syntax
open Term_util
open Type
open Fair_termination_type


let print_fairness fm fairness =
  let pr fm (a,b) = Format.printf "(%s, %s)" a b in
  Format.fprintf fm "@[<hov 1>{%a}@]" (print_list pr ",@ ") fairness

let print_rank_fun xs fm {coeffs;const} =
  let xs' = List.map Option.some xs @ [None] in
  let pr fm (c,x) =
    match x with
    | Some x' -> Format.fprintf fm "%d*%a" c Id.print x'
    | None -> Format.fprintf fm "%d" c
  in
  Format.fprintf fm "%a" (print_list pr " + ") @@ List.combine (coeffs@[const]) xs'

let event_fun = "event"
let is_event_fun_var x = Id.name x = event_fun


let add_event s = Format.sprintf "let %s (s:string) = ();;\n\n%s" event_fun s

let rec is_value t =
  match t.desc with
  | Var _
  | Const _ -> true
  | BinOp(op, t1, t2) -> is_value t1 && is_value t2
  | _ -> false

let make_s_init fairness =
  make_tuple @@ List.make (List.length fairness) (make_pair false_term false_term)

(* The current FPAT support only int arguments for rank_fun functions *)
let is_ground_typ typ =
  match typ with
  | TInt -> true
  | _ -> false


let apply_rank_fun prev_variables variables {coeffs; const} =
  let rank xs =
    let mul n x = make_mul (make_int n) (make_var x) in
    List.fold_right make_add (List.map2 mul coeffs xs) (make_int const)
  in
  let previous = rank prev_variables in
  let current = rank variables in
  (* R(p_xs) > R(xs) && R(xs) >= 0 *)
  make_and (make_gt previous current) (make_geq current (make_int 0))

let make_check_rank ps xs rank_funs =
  make_ors @@ List.map (apply_rank_fun ps xs) rank_funs




(** remove the definition of "event" introduced by add_event in Mochi.main *)
(** and replace App("event", "P") with App(Event("P"), unit) *)
let remove_and_replace_event = make_trans ()
let remove_and_replace_event_desc desc =
  match desc with
  | App({desc = Var f}, ts) when is_event_fun_var f ->
      begin
        match ts with
        | [{desc = Const (String s)}] -> App(make_event s, [unit_term])
        | _ -> unsupported "the argument of event must be a constant"
      end
  | Let(_, [f, [_], _], t') when is_event_fun_var f -> (remove_and_replace_event.tr_term t').desc
  | _ -> remove_and_replace_event.tr_desc_rec desc
let () = remove_and_replace_event.tr_desc <- remove_and_replace_event_desc
let remove_and_replace_event = remove_and_replace_event.tr_term




(** normalization for redection of fair termination *)
let normalize = make_trans ()

let normalize_aux t =
  if is_value t
  then [], t
  else
    let x = new_var_of_term t in
    [x, [], t], make_var x

let normalize_term t =
  let t' = normalize.tr_term_rec t in
  match t'.desc with
  | BinOp(op, t1, t2) ->
      let bind1, t1' = normalize_aux t1 in
      let bind2, t2' = normalize_aux t2 in
      make_lets (bind1 @ bind2) {t with desc=BinOp(op,t1',t2')}
  | App({desc=Event(q, _)}, [_]) -> t
  | App(t1, ts) ->
      let bind, t1' = normalize_aux t1 in
      let binds, ts' = List.split_map normalize_aux ts in
      make_lets (bind @ List.flatten binds) {t with desc=App(t1', ts')}
  | If(t1, t2, t3) ->
      let bind, t1' = normalize_aux t1 in
      make_let bind {t with desc=If(t1', t2, t3)}
  | _ -> t'

let () = normalize.tr_term <- normalize_term
let normalize = normalize.tr_term -| Trans.short_circuit_eval
