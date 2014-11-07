
open Util
open CEGAR_syntax
open CEGAR_type


type linearBinOp = LinEqInt | LinGt | LinLt | LinGeq | LinLeq
type linearArithTerm = int * CEGAR_syntax.var option
type linearBoolTerm =
    BBoolTerm of CEGAR_syntax.t
  | BArithTerm of linearBinOp * linearArithTerm list * linearArithTerm list
type prop = LinearTerm of linearBoolTerm | PropAnd of prop list | PropOr of prop list

exception BBoolTrans
exception NonLinear

let counter = ref 0
let new_id x =
  let x' = x ^ "_" ^ string_of_int !counter in
    incr counter;
    x'

let rec occur_arg_pred x = function
  | TBase(_,ps) -> List.mem x @@ List.rev_flatten_map get_fv @@ ps (Const Unit)
  | TFun(typ1,typ2) -> occur_arg_pred x typ1 || occur_arg_pred x @@ typ2 (Const Unit)
  | TAbs _ -> assert false
  | TApp(typ1,typ2) -> occur_arg_pred x typ1 || occur_arg_pred x typ2

let rec print_var = Format.pp_print_string

and print_var_typ env fm x = Format.fprintf fm "(%a:%a)" print_var x print_typ (List.assoc x env)

and print_typ_base fm = function
  | TUnit -> Format.fprintf fm "unit"
  | TBool -> Format.fprintf fm "bool"
  | TInt -> Format.fprintf fm "int"
  | TTuple n -> Format.fprintf fm "tuple"
  | TList -> assert false
  | TAbst s -> Format.pp_print_string fm s

and print_typ_aux var fm = function
  | TBase(b,ps) ->
      let x,occur = match var with None -> new_id "x", false | Some(x,occur) -> x, occur in
      let preds = ps (Var x) in
      if occur || List.mem x @@ List.rev_flatten_map get_fv preds then Format.fprintf fm "%a:" print_var x;
      Format.fprintf fm "%a" print_typ_base b;
      if preds <> [] then Format.fprintf fm "[@[%a@]]" (Color.blue @@ print_list print_linear_exp ";@ ") preds
  | TFun _ as typ ->
      let rec aux b fm = function
        | TFun(typ1, typ2) ->
            let x = new_id "x" in
            let typ2 = typ2 (Var x) in
            let s1,s2 = if b then "(",")" else "","" in
            let var' = Some(x, occur_arg_pred x typ2) in
            begin
              match typ2 with
              | TFun _ -> Format.fprintf fm "%s@[%a@ ->@ %a@]%s" s1 (print_typ_aux var') typ1 (aux false) typ2 s2
              | _ -> Format.fprintf fm "%s%a@ ->@ %a%s" s1 (print_typ_aux var') typ1 (aux false) typ2 s2
            end
        | typ -> print_typ_aux None fm typ
      in
      aux true fm typ
  | TApp _ as typ ->
      let typ,typs = decomp_tapp typ in
      Format.fprintf fm "(%a)" (print_list (print_typ_aux None) " ") (typ::typs)
  | TAbs _ -> assert false

and print_typ fm typ =
  counter := 1;
  print_typ_aux None fm typ

and print_env fm env =
  let pr (f,typ) = Format.fprintf fm "  %a : @[%a@]@." (Color.yellow print_var) f print_typ typ in
  List.iter pr env

and print_const fm = function
  | Unit -> Format.fprintf fm "()"
  | True -> Format.fprintf fm "true"
  | False -> Format.fprintf fm "false"
  | Char c -> Format.fprintf fm "%C" c
  | String s -> Format.fprintf fm "%S" s
  | Float s -> Format.fprintf fm "%s" s
  | Int32 n -> Format.fprintf fm "%ldl" n
  | Int64 n -> Format.fprintf fm "%LdL" n
  | Nativeint n -> Format.fprintf fm "%ndn" n
  | RandBool -> Format.fprintf fm "rand_bool"
  | RandInt None -> Format.fprintf fm "rand_int"
  | RandInt (Some n) -> Format.fprintf fm "rand_int[%d]" n
  | RandVal s -> Format.fprintf fm "rand_%s" s
  | And -> Format.fprintf fm "&&"
  | Or -> Format.fprintf fm "||"
  | Not -> Format.fprintf fm "not"
  | Lt -> Format.fprintf fm "<"
  | Gt -> Format.fprintf fm ">"
  | Leq -> Format.fprintf fm "<="
  | Geq -> Format.fprintf fm ">="
  | EqUnit -> Format.fprintf fm "="
  | EqInt -> Format.fprintf fm "="
  | EqBool -> Format.fprintf fm "<=>"
  | CmpPoly(typ,s) -> Format.pp_print_string fm s
  | Int n when (n < 0) -> Format.fprintf fm "(%d)" n
  | Int n -> Format.fprintf fm "%d" n
  | Add -> Format.fprintf fm "+"
  | Sub -> Format.fprintf fm "-"
  | Mul -> Format.fprintf fm "*"
  | Tuple n -> Format.fprintf fm "(%d)" n
  | Proj(_,i) -> Format.fprintf fm "#%d" i
  | If -> Format.fprintf fm "if"
  | Bottom -> Format.fprintf fm "_|_"
  | Temp s -> Format.fprintf fm "Temp{%s}" s
  | Label n -> Format.fprintf fm "l%d" n
  | CPS_result -> Format.fprintf fm "end"

and print_arg_var fm (x,typ) =
  match typ with
  | Some typ when !Flag.print_fun_arg_typ -> Format.fprintf fm "(%a:%a)" print_var x print_typ typ
  | _ -> print_var fm x

and print_term fm = function
  | Const c -> print_const fm c
  | Var x -> print_var fm x
  | App(App(App(Const If, Const RandBool), Const True), Const False) ->
      print_const fm RandBool
  | App(App(Const ((EqInt|EqBool|CmpPoly _|Lt|Gt|Leq|Geq|Add|Sub|Mul|Or|And) as op), t1), t2) ->
      Format.fprintf fm "(@[%a@ %a@ %a@])" print_term t1 print_const op print_term t2
  | App _ as t ->
      let t,ts = decomp_app t in
      let rec pr fm = function
        | [] -> ()
        | t::ts -> Format.fprintf fm "@ %a%a" print_term t pr ts
      in
      Format.fprintf fm "(@[<hov 1>%a%a@])" print_term t pr ts
  | Let(x,t1,t2) ->
      let xs,t1 = decomp_annot_fun t1 in
      Format.fprintf fm "(@[let %a %a@ =@ %a@ in@ %a@])"
                     print_var x (print_list print_arg_var " ") xs print_term t1 print_term t2
  | Fun _ as t ->
      let env,t' = decomp_annot_fun t in
      Format.fprintf fm "(@[fun %a@ ->@ %a@])" (print_list print_arg_var " ") env print_term t'

and print_fun_def fm (f,xs,t1,es,t2) =
  let aux s = function
      (Event e) -> Format.sprintf " {%s} =>" e ^ s
    | (Branch n) -> Format.sprintf " l%d =>" n ^ s
  in
  let s = List.fold_left aux "" es in
  if t1 = Const True
  then
    let ys,t2 = decomp_fun t2 in
    Format.fprintf fm "@[<hov 4>%a ->%s@ %a;;@]" (print_list print_var " ") (f::xs@ys) s print_term t2
  else Format.fprintf fm "@[<hov 4>%a when %a ->%s@ %a;;@]" (print_list print_var " ") (f::xs) print_term t1 s print_term t2

and print_attr fm = function
  | ACPS -> Format.fprintf fm "ACPS"

and print_attr_list fm = List.print print_attr fm

and print_prog fm prog =
  Format.fprintf fm "@[Main: %a@\n  @[%a@]@."
                 print_var prog.main
                 (print_list print_fun_def "@\n") prog.defs

and print_prog_typ fm prog =
  print_prog fm prog;
  Format.fprintf fm "Types:@.@[%a@]@?" print_env prog.env






and linearArithTerm_of_term t =
  match t with
    App(App(Const Add, t1), t2) ->
    linearArithTerm_of_term t1 @ linearArithTerm_of_term t2
  | App(App(Const Sub, t1), t2) ->
      let neg_terms = List.map (fun (n,x) -> -n,x) in
      linearArithTerm_of_term t1 @ neg_terms (linearArithTerm_of_term t2)
  | App(App(Const Mul, Const (Int n)), Var x) -> [n, Some x]
  | Const (Int n) -> [n, None]
  | Var x -> [1, Some x]
  | _ -> raise NonLinear


and linearBoolTerm_of_term t =
  try
    let binop,t1,t2 =
      match t with
        App(App(Const op, t1), t2) -> op, t1, t2
      | _ -> raise BBoolTrans
    in
    let binop' =
      match binop with
        EqInt -> LinEqInt
      | Gt -> LinGt
      | Lt -> LinLt
      | Geq -> LinGeq
      | Leq -> LinLeq
      | _ -> raise BBoolTrans
    in
    BArithTerm (binop', linearArithTerm_of_term t1, linearArithTerm_of_term t2)
  with BBoolTrans -> BBoolTerm t

and prop_of_term t =
  let rec decomp op = function
      App(App(Const op', t1), t2) when op = op' -> decomp op t1 @ decomp op t2
    | t -> [t]
  in
  let rec trans t =
    match t with
      App(App(Const And, _), _) ->
      let ts = decomp And t in
      PropAnd (List.map trans ts)
    | App(App(Const Or, _), _) ->
        let ts = decomp Or t in
        PropOr (List.map trans ts)
    | _ -> LinearTerm (linearBoolTerm_of_term t)
  in
  trans t

and print_linearArithTerm_list fm ts =
  let sign n = if n < 0 then "-" else "+" in
  let pr_tail fm = function
      n, None -> Format.fprintf fm "@ %s %d" (sign n) (abs n)
    | 1, Some x -> Format.fprintf fm "@ + %a" print_var x
    | -1, Some x -> Format.fprintf fm "@ - %a" print_var x
    | n, Some x -> Format.fprintf fm "@ %s %d*%a" (sign n) (abs n) print_var x
  in
  let pr_head fm = function
      n, None -> Format.pp_print_int fm n
    | 1, Some x -> print_var fm x
    | -1, Some x -> Format.fprintf fm "-%a" print_var x
    | n, Some x -> Format.fprintf fm "%d*%a" n print_var x
  in
  pr_head fm @@ List.hd ts;
  print_list pr_tail "" fm @@ List.tl ts

and print_linearBoolTerm fm = function
    BBoolTerm t -> print_term fm t
  | BArithTerm(op,ts1,ts2) ->
      let s =
        match op with
          LinEqInt -> "="
        | LinGt -> ">"
        | LinLt -> "<"
        | LinGeq -> ">="
        | LinLeq -> "<="
      in
      Format.fprintf fm "@[@[%a@]@ %s@ @[%a@]@]"
                     print_linearArithTerm_list ts1
                     s
                     print_linearArithTerm_list ts2

and print_prop fm = function
    LinearTerm t -> print_linearBoolTerm fm t
  | PropAnd ps ->
      let aux fm p =
        match p with
          PropOr _ -> Format.fprintf fm "(@[%a@])" print_prop p
        | _ -> print_prop fm p
      in
      print_list aux " && " fm ps
  | PropOr ps ->
      print_list print_prop " || " fm ps

and print_linear_exp fm t =
  try
    print_prop fm (prop_of_term t)
  with NonLinear -> print_term fm t





and print_const_ML fm = function
  | Unit -> Format.fprintf fm "()"
  | True -> Format.fprintf fm "true"
  | False -> Format.fprintf fm "false"
  | Char c -> Format.fprintf fm "%C" c
  | String s -> Format.fprintf fm "%S" s
  | Float s -> Format.fprintf fm "%s" s
  | Int32 n -> Format.fprintf fm "%ldl" n
  | Int64 n -> Format.fprintf fm "%LdL" n
  | Nativeint n -> Format.fprintf fm "%ndn" n
  | RandBool -> Format.fprintf fm "(Random.bool())"
  | RandInt _ -> Format.fprintf fm "rand_int()"
  | RandVal s -> Format.fprintf fm "rand_%s()" s
  | And -> Format.fprintf fm "(&&)"
  | Or -> Format.fprintf fm "(||)"
  | Not -> Format.fprintf fm "(not)"
  | Lt -> Format.fprintf fm "(<)"
  | Gt -> Format.fprintf fm "(>)"
  | Leq -> Format.fprintf fm "(<=)"
  | Geq -> Format.fprintf fm "(>=)"
  | EqBool -> Format.fprintf fm "(=)"
  | EqInt -> Format.fprintf fm "(=)"
  | Int n -> Format.fprintf fm "%d" n
  | Add -> Format.fprintf fm "(+)"
  | Sub -> Format.fprintf fm "(-)"
  | Mul -> Format.fprintf fm "(*)"
  | Tuple 0 -> Format.fprintf fm "()"
  | Tuple 1 -> ()
  | Tuple n -> Format.fprintf fm "(%d)" n
  | Proj(_,0) -> ()
  | Proj(_,i) -> Format.fprintf fm "#%d" i
  | If -> Format.fprintf fm "if_term"
  | Temp _ -> assert false
  | Bottom -> Format.fprintf fm "()"
  | EqUnit -> assert false
  | Label n -> Format.fprintf fm "print_int %d;" n
  | CmpPoly _ -> assert false
  | CPS_result -> Format.fprintf fm "end"

and print_term_ML fm = function
    Const c -> print_const_ML fm c
  | Var x -> print_var fm x
  | App(App(App(Const If, t1), t2), t3) ->
      Format.fprintf fm "(if %a then %a else %a)" print_term_ML t1 print_term_ML t2 print_term_ML t3
  | App(t1,t2) ->
      Format.fprintf fm "(%a %a)" print_term_ML t1 print_term_ML t2
  | Let(x,t1,t2) ->
      let xs,t1 = decomp_fun t1 in
      Format.fprintf fm "(let %a %a= %a in %a)" print_var x (print_list print_var " " ~last:true) xs print_term_ML t1 print_term_ML t2
  | Fun(x,_,t) ->
      Format.fprintf fm "(fun %a -> %a)" print_var x print_term_ML t

and print_fun_def_ML fm (f,xs,t1,_,t2) =
  if t1 = Const True
  then Format.fprintf fm "and %a = %a@." (print_list print_var " ") (f::xs) print_term_ML t2
  else Format.fprintf fm "%a when %a = %a@." (print_list print_var " ") (f::xs) print_term_ML t1 print_term_ML t2

and print_prog_ML fm (env,defs,s) =
  Format.fprintf fm "let rec f x = f x@.";
  List.iter (print_fun_def_ML fm) defs;
  if env <> [] then Format.fprintf fm "Types:\n%a@." print_env env

let prog_ML fm {defs;env;main} = print_prog_ML fm (env,defs,main)



let rec print_base_typ_as_tree fm = function
    TUnit -> Format.fprintf fm "TUnit"
  | TInt -> Format.fprintf fm "TInt"
  | TBool -> Format.fprintf fm "TBool"
  | TList -> Format.fprintf fm "TList"
  | TTuple n -> Format.fprintf fm "(TTuple %d)" n
  | TAbst s -> Format.fprintf fm "%s" s

and print_typ_as_tree fm = function
    TBase(b,ps) ->
      let x = new_id "x" in
        Format.fprintf fm "(TBase(%a,fun %s->%a))" print_base_typ_as_tree b x (print_list_as_tree print_term_as_tree) (ps (Var x))
  | TAbs _ -> assert false
  | TApp _ -> assert false
  | TFun(typ1,typ2) ->
      let x = new_id "x" in
        Format.fprintf fm "(TFun(%a,fun %s->%a))" print_typ_as_tree typ1 x print_typ_as_tree (typ2 (Var x))

and print_var_as_tree fm x = Format.printf "\"%s\"" x

and print_const_as_tree fm = function
  | Unit -> Format.fprintf fm "Unit"
  | True -> Format.fprintf fm "True"
  | False -> Format.fprintf fm "False"
  | Char c -> Format.fprintf fm "%C" c
  | String s -> Format.fprintf fm "%S" s
  | Float s -> Format.fprintf fm "%s" s
  | Int32 n -> Format.fprintf fm "%ldl" n
  | Int64 n -> Format.fprintf fm "%LdL" n
  | Nativeint n -> Format.fprintf fm "%ndn" n
  | RandBool -> Format.fprintf fm "RandBool"
  | RandInt _ -> Format.fprintf fm "RandInt"
  | RandVal s -> Format.fprintf fm "Rand_%s" s
  | And -> Format.fprintf fm "And"
  | Or -> Format.fprintf fm "Or"
  | Not -> Format.fprintf fm "Not"
  | Lt -> Format.fprintf fm "Lt"
  | Gt -> Format.fprintf fm "Gt"
  | Leq -> Format.fprintf fm "Leq"
  | Geq -> Format.fprintf fm "Geq"
  | EqBool -> Format.fprintf fm "EqBool"
  | EqInt -> Format.fprintf fm "EqInt"
  | Int n -> Format.fprintf fm "(Int %d)" n
  | Add -> Format.fprintf fm "Add"
  | Sub -> Format.fprintf fm "Sub"
  | Mul -> Format.fprintf fm "Mult"
  | Tuple n -> assert false
  | Proj _ -> assert false
  | If -> Format.fprintf fm "If"
  | Temp _ -> assert false
  | Bottom -> Format.fprintf fm "Bottom"
  | EqUnit -> assert false
  | Label _ -> assert false
  | CmpPoly _ -> assert false
  | CPS_result -> Format.fprintf fm "End"

and print_term_as_tree fm = function
    Const c -> Format.fprintf fm "(Const %a)" print_const_as_tree c
  | Var x -> Format.fprintf fm "(Var %a)" print_var_as_tree x
  | App(t1,t2) -> Format.fprintf fm "(App(%a,%a))" print_term_as_tree t1 print_term_as_tree t2
  | Let _ -> assert false
  | Fun _ -> assert false

and print_event_as_tree fm = function
    Event s -> Format.fprintf fm "(Event \"%s\")" s
  | Branch n -> Format.fprintf fm "(Branch %d)" n

and print_list_as_tree (pr:Format.formatter -> 'a -> unit) fm xs = Format.fprintf fm "[%a]" (print_list pr ";") xs

and print_fun_def_as_tree fm (f,xs,t1,es,t2) =
  Format.fprintf fm "%a,%a,%a,%a,%a"
    print_var_as_tree f
    (fun fm xs -> Format.fprintf fm "[%a]" (print_list print_var_as_tree ";") xs) xs
(*(print_list_as_tree Format.pp_print_string) xs
*)
    print_term_as_tree t1
    (fun fm xs -> Format.fprintf fm "[%a]" (print_list print_event_as_tree ";") xs) es
    print_term_as_tree t2

and print_env_as_tree fm env =
  let aux fm (f,typ) = Format.printf "%a,%a" print_var_as_tree f print_typ_as_tree typ in
    Format.fprintf fm "[%a]" (print_list aux ";") env

and print_prog_as_tree fm (env,defs,s) =
  Format.fprintf fm "(%a,%a,%a)"
    print_env_as_tree env
    (fun fm xs -> Format.fprintf fm "[%a]" (print_list print_fun_def_as_tree ";") xs) defs
    print_var_as_tree s


(*
let print_node fm = function
    BranchNode n -> Format.fprintf fm "#%d" n
  | EventNode s -> Format.fprintf fm "%s" s

let print_node fm = function
    BranchNode n -> Format.fprintf fm "BranchNode %d" n
  | EventNode s -> Format.fprintf fm "EventNode %S" s
*)
let print_node = Format.pp_print_int

let print_ce = print_list print_node "; "





let const = print_const
let fun_def = print_fun_def
let term = print_term
let var = print_var
let typ = print_typ
let typ_base = print_typ_base
let ce = print_ce
let env = print_env
let attr = print_attr_list
let prog = print_prog
let prog_typ = print_prog_typ


let string_of_const = make_string_of print_const




let rec print_head limit fm t =
  match t with
  | Const c -> print_const fm c
  | Var x -> print_var fm x
  | App(t1, _) -> Format.fprintf fm "(%a ...)" (print_term' limit) t1
  | Fun _ -> Format.fprintf fm "(fun ...)"
  | Let _ -> Format.fprintf fm "(let ...)"

and print_term' limit fm t =
  match t with
  | Const c -> print_const fm c
  | Var x -> print_var fm x
  | App(App(App(Const If, Const RandBool), Const True), Const False) ->
      print_const fm RandBool
  | App(App(Const ((EqInt|EqBool|CmpPoly _|Lt|Gt|Leq|Geq|Add|Sub|Mul|Or|And) as op), t1), t2) ->
      Format.fprintf fm "(@[%a@ %a@ %a@])" (print_term' limit) t1 print_const op (print_term' limit) t2
  | App _ as t ->
      let t,ts = decomp_app t in
      let rec pr fm = function
        | [] -> ()
        | t::ts when size t > limit ->
            Format.fprintf fm "@ %a%a" (print_head limit) t pr ts
        | t::ts ->
            Format.fprintf fm "@ %a%a" (print_term' limit) t pr ts
      in
      Format.fprintf fm "(@[<hov 1>%a%a@])" (print_term' limit) t pr ts
  | Let(x,t1,t2) ->
      let xs,t1 = decomp_fun t1 in
      Format.fprintf fm "(@[let %a %a@ =@ %a@ in@ %a@])"
                     print_var x (print_list print_var " ") xs (print_term' limit) t1 (print_term' limit) t2
  | Fun _ as t ->
      let env,t' = decomp_annot_fun t in
      let pr fm (x,typ) =
        match typ with
          Some typ when !Flag.print_fun_arg_typ -> Format.fprintf fm "(%a:%a)" print_var x print_typ typ
        | _ -> print_var fm x
      in
      Format.fprintf fm "(@[fun %a@ ->@ %a@])" (print_list pr " ") env (print_term' limit) t'

let term' = print_term' 100
