open BRA_util
open Type
open Syntax
open BRA_types
open BRA_state

type inputForm = Definitions | Expr

let connector f = if f = Definitions then "\n" else " in "

let rec is_form_of = function
  | {desc = Let (Nonrecursive, [id, args, body], u); typ = t} when id.Id.name = "main" -> Definitions
  | {desc = Let (rec_flag, bindings, body)} as t -> is_form_of body
  | t -> Expr

(***** Constants *****)

let hole_term = make_var (Id.new_var "__HOLE__" TBool)

(***** Functions *****)

(* apply a transformation throughout an AST in bottom-up manner *)
let rec everywhere_expr f {desc = desc; typ = typ} =
  let ev = everywhere_expr f in
  let expr =
    begin
      match desc with
	| App (func, args) -> App (ev func, List.map ev args)
	| If (cond_expr, then_expr, else_expr) -> If (ev cond_expr, ev then_expr, ev else_expr)
	| Let (flag, bindings, e) ->
	  let fmap (ident, args, body) = (ident, args, ev body) in
	  Let (flag, List.map fmap bindings, ev e)
	| BinOp (op, e1, e2) -> BinOp (op, ev e1, ev e2)
	| Not e -> Not (ev e)
	| Fun (f, body) -> Fun (f, ev body)
	| Match (e, mclauses) -> Match (ev e, List.map (fun (p, t1, t2) -> (p, ev t1, ev t2)) mclauses)
	| e -> e
    end
  in f { desc = expr
       ; typ = typ }

(* regularization of program form *)
let rec regularization = function
  | {desc = Let (Nonrecursive, [top_id, _, body], {desc = Const Unit; typ = TUnit})} when top_id.Id.name <> "main" -> body
  | t -> t

(* conversion to parse-able string *)
let parens s = "(" ^ s ^ ")"
let modify_id v = if v.Id.name = "_" then "_" else Id.to_string v
let rec show_typed_term t = show_term t.desc
and show_term = function
  | Const Unit -> "()"
  | Const True -> "true"
  | Const False -> "false"
  | Const (Int n) -> string_of_int n
  | App ({desc=RandInt _}, _) -> "Random.int 0"
  | Var v when v.Id.typ = TUnit -> "(" ^ modify_id v ^ " : unit)"
  | Var v when v.Id.typ = TBool -> "(" ^ modify_id v ^ " : bool)"
  | Var v when v.Id.typ = TInt -> "(" ^ modify_id v ^ " : int)"
  | Var v -> modify_id v
  | Fun (f, body) -> "fun " ^ modify_id f ^ " -> " ^ show_typed_term form body
  | App ({desc=Event("fail", _)}, _) -> "assert false"
  | App (f, args) -> show_typed_term form f ^ List.fold_left (fun acc a -> acc ^ " " ^ parens (show_typed_term form a)) "" args
  | If (t1, t2, t3) -> "if " ^ show_typed_term form t1 ^ " then " ^ show_typed_term form t2 ^ " else " ^ show_typed_term form t3
  | Let (_, [], _) -> assert false
  | Let (Nonrecursive, [id, args, body], {desc=Unit; typ=TUnit}) when id.Id.name = "main" ->
    let show_args args = List.fold_left (fun acc a -> acc ^ " " ^ modify_id a) "" args in
    "let main "
    ^ show_args args
    ^ " = "
    ^ show_typed_term form body
  | Let (rec_flag, b::bs, t) ->
    let show_bind (x, args, body) =
      modify_id x
      ^ (List.fold_left (fun acc a -> acc ^ " " ^ modify_id a) "" args)
      ^ "="
      ^ show_typed_term Expr body in
    (if rec_flag = Nonrecursive then "let " else "let rec ")
    ^ show_bind b
    ^ List.fold_left (fun acc x -> acc ^ " and " ^ show_bind x) "" bs
    ^ (connector form)
    ^ show_typed_term form t
  | BinOp (binop, t1, t2) -> parens (show_typed_term form t1) ^ show_binop binop ^ parens (show_typed_term form t2)
  | Not t -> "not " ^ parens (show_typed_term form t)
  | t -> raise (Invalid_argument "show_term")
and show_binop = function
  | Eq -> "="
  | Lt -> "<"
  | Gt -> ">"
  | Leq -> "<="
  | Geq -> ">="
  | And -> "&&"
  | Or -> "||"
  | Add -> "+"
  | Sub -> "-"
  | Mult -> "*"

let restore_ids = 
  let trans_id ({Id.name = name_; Id.typ = typ} as orig) =
    try
      let i = String.rindex name_ '_' in
      let name = String.sub name_ 0 i in
      let id = int_of_string (String.sub name_ (i+1) (String.length name_ - i - 1)) in
      {Id.name = name; Id.id = id; Id.typ = typ}
    with _ -> orig
  in
  let sub = function
    | {desc = Let (rec_flag, bindings, cont); typ = t} ->
      {desc = Let (rec_flag, List.map (fun (f, args, body) -> (trans_id f, List.map trans_id args, body)) bindings, cont); typ = t}
    | {desc = Fun (f, body); typ = t} -> {desc = Fun (trans_id f, body); typ = t}
    | {desc = Var v; typ = t} -> {desc = Var (trans_id v); typ = t}
    | t -> t
  in everywhere_expr sub

let retyping t =
  (*Format.eprintf "@.%s@." (show_typed_term (is_form_of t) t);*)
  let lb = t |> show_typed_term (is_form_of t)
             |> Lexing.from_string
  in
  let () = lb.Lexing.lex_curr_p <-
    {Lexing.pos_fname = Filename.basename !Flag.filename;
     Lexing.pos_lnum = 1;
     Lexing.pos_cnum = 0;
     Lexing.pos_bol = 0};
  in
  let orig = Parse.use_file lb in
  let parsed = Parser_wrapper.from_use_file orig in
  let parsed = restore_ids parsed in
  let _ =
    if true && !Flag.debug_level > 0
    then Format.printf "transformed::@. @[%a@.@." Syntax.pp_print_term parsed
  in
  (orig, parsed)

let extract_functions (target_program : typed_term) =
  let ext acc (id, args, body) = if args = [] then acc else {id=id; args=args}::acc in
  let rec iter t =
    match t.desc with
      | Let (_, [id, _, _], _) when id.Id.name = "main" -> []
      | Let (_, bindings, body) -> List.fold_left ext [] bindings @ iter body
      | t -> []
  in
  let extracted = iter (regularization target_program) in
  extracted

let rec transform_function_definitions f term =
  let sub ((_, args, _) as binding) = if args <> [] then f binding else binding in
  match term with 
    | {desc = Let (Nonrecursive, [id, _, _], _)} as t when id.Id.name = "main" -> t
    | {desc = Let (rec_flag, bindings, cont)} as t -> { t with desc = Let (rec_flag, List.map sub bindings, transform_function_definitions f cont) }
    | t -> t

let rec transform_main_expr f = function
  | {desc = Let (Nonrecursive, [id, args, body], u); typ = t} when id.Id.name = "main" -> {desc = Let (Nonrecursive, [id, args, everywhere_expr f body], u); typ = t}
  | {desc = Let (rec_flag, bindings, body)} as t -> { t with desc = Let (rec_flag, bindings, transform_main_expr f body) }
  | t -> everywhere_expr f t

let extract_id = function
  | {desc = (Var v)} -> v
  | _ -> assert false

let implement_recieving ({program = program; state = state} as holed) =
  let passed = passed_statevars holed in
  let placeholders f = List.map (fun v -> Id.new_var "_" (Id.typ (extract_id v))) (passed f) in (* (expl) placeholders 4 = " _ _ _ _ " *)
  let rec set_state f = function
    | [] -> []
    | [arg] -> (List.map extract_id (passed f))@[arg]
    | arg::args -> (placeholders f)@[arg]@(set_state f) args
  in
  { holed with program = transform_function_definitions (fun (id, args, body) -> (id, set_state id args, body)) program }

let implement_transform_initial_application ({program = program; state = state} as holed) =
  let sub = function
    | {desc = App (func, args)} as t -> {t with desc = App (func, concat_map (fun arg -> state.BRA_types.initial_state@[arg]) args)}
    | t -> t
  in
  { holed with program = transform_main_expr sub program }

let implement_propagation ({program = program; state = state} as holed) =
  let propagated = propagated_statevars holed in
  let sub = function
    | {desc = App (func, args)} as t -> {t with desc = App (func, concat_map (fun arg -> propagated@[arg]) args)}
    | t -> t
  in
  { holed with program = transform_function_definitions (fun (id, args, body) -> (id, args, everywhere_expr sub body)) program }

let transform_program_by_call holed =
  holed |> implement_recieving
        |> implement_transform_initial_application
        |> implement_propagation

(* restore type *)
let restore_type state = function
  | {desc = Var v; typ = t} as e ->
    let rec restore_type' acc i = function
      | TFun ({Id.typ = t1}, t2) as t ->
	let fresh_id = Id.new_var ("d_"^v.Id.name^(string_of_int i)) t1 in
	{ desc = Fun (fresh_id
			,(restore_type'
			    { desc = App (acc, (state.initial_state@[make_var fresh_id]))
			    ; typ = t}
			    (i+1)
			    t2))
	; typ = t}
      | t -> acc
    in restore_type' e 0 t
  | _ -> raise (Invalid_argument "restore_type")

let to_holed_programs (target_program : typed_term) (defined_functions : function_info list) =
  let state_template = build_state defined_functions in
  let hole_insert target state typed =
    let sub (id, args, body) =
      let body' =
	if id = target.id then
	  let prev_set_flag = get_prev_set_flag state target in
	  let set_flag = get_set_flag state target in
	  let update_flag = get_update_flag state target in
	  let prev_statevars = get_prev_statevars state target in
	  let statevars = get_statevars state target in
	  let argvars = get_argvars state target in
	  let add_update_statement cont prev_statevar statevar argvar =
	    if !Flag.disjunctive then
              (* let s_x = if * then
                             x
                           else
                             s_prev_x *)
	      make_let [extract_id statevar, [], make_if update_flag (restore_type state argvar) prev_statevar] cont
	    else
              (* let s_x = x *)
  	      make_let [extract_id statevar, [], restore_type state argvar] cont
	  in
	  if !Flag.disjunctive then
            (* let _ = if prev_set_flag then
                         if __HOLE__ then
                           ()
                         else
                           fail
               in *)
            make_let
	      [Id.new_var "_" TUnit, [], make_if prev_set_flag (make_if hole_term unit_term (make_app fail_term [unit_term])) unit_term]
	      
              (* let update_flag = Random.int 0 in *)
	      (make_let
		 [(extract_id update_flag, [], randbool_unit_term)]
		 
		 (* let set_flag = update_flag || prev_set_flag in *)
		 (make_let
		    [(extract_id set_flag, [], make_or update_flag prev_set_flag)]
		    
		    (* each statevars update *)
		    (fold_left3 add_update_statement 
		       body prev_statevars statevars argvars)))
	  else
            (* let _ = if prev_set_flag then
                         if __HOLE__ then
                           ()
                         else
                           fail
               in *)
            make_let
	      [Id.new_var "_" TUnit, [], make_if prev_set_flag (make_if hole_term unit_term (make_app fail_term [unit_term])) unit_term]
	      
	      (* let set_flag = true in *)
	      (make_let
		 [(extract_id set_flag, [], true_term)]
		 
		 (* each statevars update *)
		 (fold_left3 add_update_statement 
		    body prev_statevars statevars argvars))
	else body
      in (id, args, body')
    in
    { typed with desc = match typed.desc with
      | Let (rec_flag, bindings, body) -> Let (rec_flag, List.map sub bindings, body)
      | t -> t
    }
  in
  let hole_inserted_programs =
    List.map (fun f ->
      let f_state = state_template f in
      { program = everywhere_expr (hole_insert f f_state) target_program
      ; verified = f
      ; state = f_state}) defined_functions
  in
  let state_inserted_programs =
    List.map transform_program_by_call hole_inserted_programs
  in state_inserted_programs

let construct_LLRF {variables = variables_; prev_variables = prev_variables_; coefficients = coefficients_} =
  let variables = (make_int 1) :: (List.map make_var variables_) in
  let prev_variables = (make_int 1) :: (List.map make_var prev_variables_) in
  let coefficients = List.map (fun {coeffs = cs; constant = c} -> List.map make_int (c::cs)) coefficients_ in
  let rec rank cs vs = try List.fold_left2
			     (fun rk t1 t2 -> make_add rk (make_mul t1 t2))
			     (make_mul (List.hd cs) (List.hd vs))
			     (List.tl cs)
			     (List.tl vs)
    with Invalid_argument _ -> raise (Invalid_argument "construct_LLRF")
  in
  let rec iter aux = function
    | [r] ->
      (* r(prev_x) > r(x) && r(x) >= 0 *)
      aux (make_and (make_gt (r prev_variables) (r variables))
	     (make_geq (r variables) (make_int 0)))
    | r::rs ->
      let aux_next cond =
	if !Flag.disjunctive then
	  cond
	else
	  make_and (make_eq (r prev_variables) (r variables)) (aux cond)
      in
      (* r(prev_x) > r(x) && r(x) >= 0 || ... *)
      make_or
        (aux (make_and (make_gt (r prev_variables) (r variables))
		(make_geq (r variables) (make_int 0))))
	(iter aux_next rs)
    | [] -> false_term
  in
  iter (fun x -> x) (List.map rank coefficients)

(* plug holed program with predicate *)
let pluging (holed_program : holed_program) (predicate : typed_term) =
  let hole2pred = function
    | {desc = Var {Id.name = "__HOLE__"}} -> predicate
    | t -> t
  in everywhere_expr hole2pred holed_program.program
