open Util

type var = V of string
  [@@deriving show]

type op =
  | Add
  | Sub
  | Mul
  | Div
  | Eq
  | Neq
  | Leq
  | Geq
  | Lt
  | Gt
  | And
  | Or
  [@@deriving show]

type hflz =
  | Bool   of bool
  | Int    of int
  | Var    of var
  | Abs    of var * hflz
  | App    of hflz * hflz
  | Op     of op   * hflz * hflz
  | Forall of var * hflz
  | Exists of var * hflz
  [@@deriving show]

type rule = { fn : var; args: var list; body : hflz }
  [@@deriving show]

type hes = rule list
  [@@deriving show]

let mk_var ~toplevel s =
  let s = Re2.replace_exn ~f:(fun _ -> "_") (Re2.create_exn "'") s in
  if List.mem s toplevel
  then V (String.uppercase_ascii s)
  else V s

let rec negate = function
  | Bool b -> Bool (not b)
  | Op (Neq, x, y) -> Op (Eq , x, y)
  | Op (Eq , x, y) -> Op (Neq, x, y)
  | Op (Geq, x, y) -> Op (Lt , x, y)
  | Op (Leq, x, y) -> Op (Gt , x, y)
  | Op (Gt , x, y) -> Op (Leq, x, y)
  | Op (Lt , x, y) -> Op (Geq, x, y)
  | Op (And, x, y) -> Op (Or , negate x, negate y)
  | Op (Or , x, y) -> Op (And, negate x, negate y)
  | t ->
      Format.eprintf "Cannot negate %a@." pp_hflz t;
      assert false

let rec hflz_of_cegar ~toplevel : CEGAR_syntax.t -> hflz = fun t ->
  Format.printf "hflz_of_cegar\n%a@.%a@."
    CEGAR_syntax.pp t
    CEGAR_print.term t;
  let rec contains_f (t : CEGAR_syntax.t) f =
    Format.printf "contains_f\n%a@.%a@."
      CEGAR_syntax.pp t
      CEGAR_print.term t;
    match t with
    | App (Const (Label _), b) -> contains_f b f
    | App (a, _) -> contains_f a f
    | a when f a -> true
    | _ -> false
  in
  let contains_fail t =
    contains_f t (fun t ->
      match t with
      | Var name when String.length name >= 5 && String.sub name 0 5 = "fail_" -> true
      | _ -> false) in
  let contains_cps_result t =
    contains_f t (fun t ->
      match t with
      | Const CPS_result -> true
      | _ -> false) in
  let rec aux : CEGAR_syntax.t -> hflz = fun t ->
    match t with
    | Var v -> Var (mk_var ~toplevel v)
    | Let _ -> assert false
    | Const Unit -> Bool true
    | Const CPS_result ->
      begin
      match !Flag.Method.mode with
        | NonTermination -> Var (V "Bool_false")
        | Reachability   -> Bool true
        | _ -> unsupported "HFLz.of_cegar: mode"
      end
    | App (App (App (Const If, x), y), z) when contains_cps_result y && contains_fail z -> begin
      Bool false
    end
    | Const Bottom -> Bool true
    | Const True -> Bool true
    | Const False -> Bool false
    | Const (Int   i) -> Int i
    | Const (Int32 i) -> Int (Int32.to_int i)
    | Const (Int64 i) -> Int (Int64.to_int i)
    | App (App ((App (Const If, x)), y), z) ->
        (* (not x \/ y) /\ (x \/ y) *)
        Op (And, (Op (Or, negate (aux x), aux y))
               , (Op (Or, aux x         , aux z)))
    | App ((App (Const Add, x)), y) -> Op (Add, aux x, aux y)
    | App ((App (Const Sub, x)), y) -> Op (Sub, aux x, aux y)
    | App ((App (Const Mul, x)), y) -> Op (Mul, aux x, aux y)
    | App ((App (Const Div, x)), y) -> Op (Div, aux x, aux y)
    | App ((App (Const And, x)), y) -> Op (And, aux x, aux y)
    | App ((App (Const Or , x)), y) -> Op (Or , aux x, aux y)
    | App ((App (Const Lt , x)), y) -> Op (Lt , aux x, aux y)
    | App ((App (Const Gt , x)), y) -> Op (Gt , aux x, aux y)
    | App ((App (Const Leq, x)), y) -> Op (Leq, aux x, aux y)
    | App ((App (Const Geq, x)), y) -> Op (Geq, aux x, aux y)
    | App ((App (Const EqInt, x)), y) -> Op (Eq, aux x, aux y)
    | App (Const Not, x) -> negate (aux x)
    | App (Const (TreeConstr _), x) -> aux x
    | App (Const (Label _), x) -> aux x
    (* I do not know why *)
    (*| App(Const (Rand(_, None)), Fun(f, _, t)) -> Forall(mk_var ~toplevel f, aux t)*)
    | App(Const (Rand(TInt, None)), Fun(f, _, t)) -> begin
      match !Flag.Method.mode with
      | NonTermination -> begin
        if String.length f >= 7 && String.sub f 0 7 = "dummy__" then
          Bool false
        else
          Exists(mk_var ~toplevel f, aux t)
      end
      (* | Reachability -> Forall(mk_var ~toplevel f, aux t) *)
      | _ -> unsupported "HFLz.of_cegar: mode"
    end
    | App(Const (Rand _), _) -> failwith "hflz_of_cegar"
    | App (x,y) -> App (aux x, aux y)
    (* | Const (Rand (TInt, None)) -> 
      (* I have little time! *)
      begin
      match !Flag.Method.mode with
        | NonTermination -> Var (V "Exists") 
        | Reachability   -> Var (V "Forall")
        | _ -> unsupported "HFLz.of_cegar: mode"
      end *)
    | Fun (f,_,x) -> Abs (mk_var ~toplevel f, aux x)
    | t ->
      Format.printf "%a@.%a@."
        CEGAR_syntax.pp t
        CEGAR_print.term t;
      assert false
  in aux t

(* fun_def list は同じものが複数入っている *)
let rule_of_fun_def ~toplevel : CEGAR_syntax.fun_def -> rule option = fun def  ->
  let fn = mk_var ~toplevel def.fn in
  let args = List.map (mk_var ~toplevel) def.args in
  if List.mem (CEGAR_syntax.Event "fail") def.events then
    None
  else
    let body = 
      ((*Format.printf "%a@." 
        CEGAR_print.term def.cond; *)
      match negate (hflz_of_cegar ~toplevel def.cond) with
      | Bool false -> hflz_of_cegar ~toplevel def.body
      | p -> Op (Or, p, hflz_of_cegar ~toplevel def.body)
      )
      in
    Some { fn; args; body}

let rec get_occuring_variables (phi : hflz) =
  let rec go phi = match phi with
    | Bool _ -> []
    | Int n -> []
    | Var v -> [v]
    | App (psi1, psi2) -> (go psi1) @ (go psi2)
    | Abs (x, psi) -> List.filter (fun v -> v <> x) (go psi)
    | Op (op, psi1, psi2) -> (go psi1) @ (go psi2)
    | Forall(v, t) -> List.filter (fun v' -> v' <> v) (go t)
    | Exists(v, t) -> List.filter (fun v' -> v' <> v) (go t) in
  go phi

let remove_first_exists phi =
  match phi with
  | Exists (v, psi) -> begin
    match List.find_opt ((=)v) (get_occuring_variables psi) with
    | None -> psi
    | Some _ -> phi
  end
  | _ -> phi

let hes_of_prog : CEGAR_syntax.prog -> hes = fun ({defs; main=orig_main; _} as prog) ->
  (* Format.eprintf "%a" CEGAR_print.prog prog; *)
  let toplevel = List.map (fun x -> x.CEGAR_syntax.fn) defs in
  let rules =
    let fold_left1 f = function
      | x::xs -> List.fold_left f x xs
      | [] -> assert false
    in
    let merge rule1 rule2 =
      let body = Op (And, rule1.body, rule2.body) in
      { rule1 with body }
    in
    defs
    |> List.filter_map (rule_of_fun_def ~toplevel)
    |> List.sort (fun x y -> compare x.fn y.fn)
    |> List.group_consecutive (fun x y -> x.fn = y.fn)
    |> List.map (fold_left1 merge)
  in
  let main, others =
    let main_var = mk_var ~toplevel orig_main in
    let others = List.remove_if (fun x -> x.fn = main_var) rules in
    let main = List.find (fun x -> x.fn = main_var) rules in
    let remove_forall : hflz -> hflz * var list =
      let rec go acc = function
        | App (Var (V "Forall"), Abs (v, t)) -> go (v::acc) t
        | t -> (t, acc)
      in
      go []
    in
    let main =
      let body, args = remove_forall main.body in
      let body = remove_first_exists body in
      (* { main' with args; body } *) (* 鈴木さんのはこっちに非対応 *)
      { main with body }
    in
    main, others
  in
  main :: others

module Print = struct(*{{{*)
  open Fmt
  open Format
  let list_comma : 'a Fmt.t -> 'a list Fmt.t =
    fun format_x ppf xs ->
      let sep ppf () = Fmt.pf ppf ",@," in
      Fmt.pf ppf "[@[%a@]]" Fmt.(list ~sep format_x) xs
  let list_semi : 'a Fmt.t -> 'a list Fmt.t =
    fun format_x ppf xs ->
      let sep ppf () = Fmt.pf ppf ";@," in
      Fmt.pf ppf "[@[%a@]]" Fmt.(list ~sep format_x) xs
  let list_set : 'a Fmt.t -> 'a list Fmt.t =
    fun format_x ppf xs ->
      let sep ppf () = Fmt.pf ppf ",@," in
      Fmt.pf ppf "{@[%a@]}" Fmt.(list ~sep format_x) xs
  let list_ketsucomma : 'a Fmt.t -> 'a list Fmt.t =
    fun format_x ppf xs ->
      let sep = fun ppf () -> pf ppf "@,, " in
      pf ppf "[ @[<hv -2>%a@] ]" (list ~sep format_x) xs

  module Prec = struct(*{{{*)
    type t = int
    let succ x = x + 1
    let succ_if b x = if b then x + 1 else x

    let zero  = 0
    let arrow = 1
    let abs   = 1
    let or_   = 2
    let and_  = 3
    let eq    = 4
    let add   = 6
    let mul   = 7
    let div   = 8
    let neg   = 9
    let app   = 10

    let of_op = function
      | Add -> add
      | Sub -> add
      | Mul -> mul
      | Div -> div
      | Eq  -> eq
      | Neq -> eq
      | Leq -> eq
      | Geq -> eq
      | Lt  -> eq
      | Gt  -> eq
      | And -> and_
      | Or  -> or_
    let op_is_leftassoc = function
      | Add -> true
      | Sub -> true
      | Mul -> true
      | Div -> true
      | And -> true
      | Or  -> true
      | Eq  -> false
      | Neq -> false
      | Leq -> false
      | Geq -> false
      | Lt  -> false
      | Gt  -> false
    let op_is_rightassoc = function
      | _ -> false
  end(*}}}*)
  type prec = Prec.t
  type 'a t_with_prec = Prec.t -> 'a t
  let ignore_prec : 'a t -> 'a t_with_prec =
    fun orig ->
      fun _prec ppf x ->
        orig ppf x
  let show_paren
       : bool
      -> formatter
      -> ('a, formatter, unit) format
      -> 'a =
    fun b ppf fmt ->
      if b
      then Fmt.pf ppf ("(" ^^ fmt ^^ ")")
      else Fmt.pf ppf fmt
  
  let convert_var s =
    if String.length s >= 5 && String.sub s 0 5 = "MAIN_" then
      "Sentry"
    else s
  
  let var ppf (V x) = Fmt.string ppf (convert_var x)
  let rec hflz_ prec ppf (phi : hflz) = match phi with
    | Bool true -> Fmt.string ppf "true"
    | Bool false -> Fmt.string ppf "false"
    | Int n when n >= 0 -> Fmt.int ppf n
    | Int n -> Fmt.pf ppf "(%d)" n
    | Var v -> var ppf v
    | App (psi1, psi2) ->
        show_paren (prec > Prec.app) ppf "@[<1>%a@ %a@]"
          (hflz_ Prec.app) psi1
          (hflz_ Prec.(succ app)) psi2
    | Abs (x, psi) ->
        show_paren (prec > Prec.abs) ppf "@[<1>\\%a.@,%a@]"
          var x
          (hflz_ Prec.abs) psi
    | Op (op, psi1, psi2) ->
        let op_prec = Prec.of_op op in
        let nx_prec = op_prec + 1 in
        let pr = show_paren (prec > op_prec) in
        let recur = hflz_ nx_prec in
        begin match op with
        | Add -> pr ppf "@[<hv 0>%a@ + %a@]"   recur psi1 recur psi2
        | Sub -> pr ppf "@[<hv 0>%a@ - %a@]"   recur psi1 recur psi2
        | Mul -> pr ppf "@[<hv 0>%a@ * %a@]"   recur psi1 recur psi2
        | Div -> pr ppf "@[<hv 0>%a@ / %a@]"   recur psi1 recur psi2
        | Eq  -> pr ppf "@[<hv 0>%a@ = %a@]"   recur psi1 recur psi2
        | Neq -> pr ppf "@[<hv 0>%a@ != %a@]"  recur psi1 recur psi2
        | Leq -> pr ppf "@[<hv 0>%a@ <= %a@]"  recur psi1 recur psi2
        | Geq -> pr ppf "@[<hv 0>%a@ >= %a@]"  recur psi1 recur psi2
        | Lt  -> pr ppf "@[<hv 0>%a@ < %a@]"   recur psi1 recur psi2
        | Gt  -> pr ppf "@[<hv 0>%a@ > %a@]"   recur psi1 recur psi2
        | And -> pr ppf "@[<hv 0>%a@ /\\ %a@]" recur psi1 recur psi2
        | Or  -> pr ppf "@[<hv 0>%a@ \\/ %a@]" recur psi1 recur psi2
        end
    | Forall(v, t) -> 
        show_paren (prec > Prec.abs) ppf "@[<1>∀%a.@,%a@]"
          var v
          (hflz_ Prec.abs) t
    | Exists(v, t) -> 
        show_paren (prec > Prec.abs) ppf "@[<1>∃%a.@,%a@]"
          var v
          (hflz_ Prec.abs) t
  let hflz : hflz Fmt.t = hflz_ Prec.zero

  let rule : rule Fmt.t = fun ppf rule ->
    Fmt.pf ppf "@[<2>%a %a@ =v@ %a.@]"
      var rule.fn
      (list ~sep:(fun ppf () -> string ppf " ") var) rule.args
      hflz rule.body

  let hes : hes Fmt.t = fun ppf hes ->
    Fmt.pf ppf "%%HES@.";
    Fmt.pf ppf "@[<v>%a@]@." (Fmt.list rule)  hes;
    (* Fmt.pf ppf "Forall p      =v ∀n. p n.@.";
    Fmt.pf ppf "Exists p        =v ExistsAux 1000 0 p.@.";
    Fmt.pf ppf "ExistsAux x p =v x > 0 /\\ (p x \\/ p (0-x) \\/ ExistsAux (x-1) p).@." *)

end(*}}}*)


