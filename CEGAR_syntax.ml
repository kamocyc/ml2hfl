
open Util
open CEGAR_type
open CEGAR_const

let new_id s = Id.to_string (Id.new_var s Type.TUnknown)
let rename_id s =
  let len = String.length s in
  let n =
    try
      let i = String.rindex s '_' in
      let n = String.sub s (i+1) (len-i-1) in
      let _ = int_of_string n in
        i
    with _ -> len
  in
    String.sub s 0 n ^ "_" ^ string_of_int (Id.new_int ())

type var = string


type const =
    Fail
  | Event of string
  | Label of int
  | Unit
  | True
  | False
  | RandInt
  | RandBool
  | And
  | Or
  | Not
  | Lt
  | Gt
  | Leq
  | Geq
  | Eq
  | Int of int
  | Add
  | Sub
  | Mul
  | Tuple of int
  | Proj of int * int (* 0-origin *)
  | If (* for abstraction and model-checking *)
  | Branch (* for for abstraction and model-checking *)



type t =
    Const of const
  | Var of var
  | App of t * t
  | Let of var * t * t (* for abstraction *)
  | Fun of var * t (* for abstraction and CPS-trasformation *)

type fun_def = var * var list * t * t

type prog = (var * t CEGAR_type.t ) list * fun_def list * var



let rec get_fv = function
    Const _ -> []
  | Var x -> [x]
  | App(t1, t2) -> get_fv t1 @@@ get_fv t2



let make_app t ts = List.fold_left (fun t1 t2 -> App(t1, t2)) t ts
let make_fun xs t =
  let f = new_id "f" in
    [f, xs, Const True, t], f
let make_temp_if t1 t2 t3 = make_app (Const If) [t1;t2;t3]
let make_and t1 t2 = make_app (Const And) [t1; t2]
let make_or t1 t2 = make_app (Const Or) [t1; t2]
let make_not t = App(Const Not, t)
let make_lt t1 t2 = make_app (Const Lt) [t1; t2]
let make_gt t1 t2 = make_app (Const Gt) [t1; t2]
let make_leq t1 t2 = make_app (Const Leq) [t1; t2]
let make_geq t1 t2 = make_app (Const Geq) [t1; t2]
let make_eq t1 t2 = make_app (Const Eq) [t1; t2]
let make_add t1 t2 = make_app (Const Add) [t1; t2]
let make_sub t1 t2 = make_app (Const Sub) [t1; t2]
let make_mul t1 t2 = make_app (Const Mul) [t1; t2]
let loop_var = "loop"
let loop_def = loop_var, ["u"], Const True, App(Var loop_var, Const Unit)
let loop_term = App(Var loop_var, Const Unit)




let apply_body_def f (g,xs,t1,t2) = g, xs, t1, f t2


let rec make_arg_let t =
  let desc =
    match t.Syntax.desc with
        Syntax.Unit -> Syntax.Unit
      | Syntax.True -> Syntax.True
      | Syntax.False -> Syntax.False
      | Syntax.Unknown -> assert false
      | Syntax.Int n -> Syntax.Int n
      | Syntax.Var x -> Syntax.Var x
      | Syntax.App(t, ts) ->
          let f = Id.new_var "f" (t.Syntax.typ) in
          let xts = List.map (fun t -> Id.new_var "x" (t.Syntax.typ), t) ts in
          let t' = {Syntax.desc=Syntax.App(Syntax.make_var f, List.map (fun (x,_) -> Syntax.make_var x) xts); Syntax.typ=Type.TUnknown} in
            (List.fold_left (fun t2 (x,t1) -> {Syntax.desc=Syntax.Let(Flag.Nonrecursive,x,[],t1,t2);Syntax.typ=t2.Syntax.typ}) t' ((f,t)::xts)).Syntax.desc
      | Syntax.If(t1, t2, t3) ->
          let t1' = make_arg_let t1 in
          let t2' = make_arg_let t2 in
          let t3' = make_arg_let t3 in
            Syntax.If(t1',t2',t3')
      | Syntax.Branch(t1, t2) -> assert false
      | Syntax.Let(flag,f,xs,t1,t2) -> 
          let t1' = make_arg_let t1 in
          let t2' = make_arg_let t2 in
            Syntax.Let(flag,f,xs,t1',t2')
      | Syntax.BinOp(op, t1, t2) ->
          let t1' = make_arg_let t1 in
          let t2' = make_arg_let t2 in
            Syntax.BinOp(op, t1', t2')
      | Syntax.Not t -> Syntax.Not (make_arg_let t)
      | Syntax.Fail -> Syntax.Fail
      | Syntax.Fun(x,t) -> assert false
      | Syntax.Event s -> assert false
  in
    {Syntax.desc=desc; Syntax.typ=t.Syntax.typ}




let rec trans_typ = function
    Type.TUnit -> TBase(TUnit, fun _ -> [])
  | Type.TBool -> TBase(TBool, fun x -> [x])
  | Type.TAbsBool -> assert false
  | Type.TInt _ -> TBase(TInt, fun _ -> [])
  | Type.TRInt _  -> assert false
  | Type.TVar _  -> assert false
  | Type.TFun(x,typ) -> TFun(fun _ -> trans_typ (Id.typ x), trans_typ typ)
  | Type.TList _ -> assert false
  | Type.TConstr _ -> assert false
  | Type.TVariant _ -> assert false
  | Type.TRecord _ -> assert false
  | Type.TUnknown -> assert false
  | Type.TBottom -> TBase(TBottom, fun _ -> [])

let trans_var x = Id.to_string x

let rec trans_binop = function
    Syntax.Eq -> Const Eq
  | Syntax.Lt -> Const Lt
  | Syntax.Gt -> Const Gt
  | Syntax.Leq -> Const Leq
  | Syntax.Geq -> Const Geq
  | Syntax.And -> Const And
  | Syntax.Or -> Const Or
  | Syntax.Add -> Const Add
  | Syntax.Sub -> Const Sub
  | Syntax.Mult -> Const Mul

let rec trans_term xs env t =
  match t.Syntax.desc with
      Syntax.Unit -> [], Const Unit
    | Syntax.True -> [], Const True
    | Syntax.False -> [], Const False
    | Syntax.Unknown -> assert false
    | Syntax.Int n -> [], Const (Int n)
    | Syntax.NInt _ -> [], App(Const RandInt, Const Unit)
    | Syntax.Var x ->
        let x' = trans_var x in
          [], Var x'
    | Syntax.App(t, ts) ->
        let defs,t' = trans_term xs env t in
        let defss,ts' = List.split (List.map (trans_term xs env) ts) in
          defs @ (List.flatten defss), make_app t' ts'
    | Syntax.If(t1, t2, t3) ->
        let defs1,t1' = trans_term xs env t1 in
        let defs2,t2' = trans_term xs env t2 in
        let defs3,t3' = trans_term xs env t3 in
        let f = new_id "f" in
        let x = new_id "b" in
        let typs = TBase(TBool,fun x -> [x]) :: List.map (fun x -> List.assoc x env) xs in
        let typ = List.fold_right (fun typ1 typ2 -> TFun(fun _ -> typ1,typ2)) typs (trans_typ t2.Syntax.typ) in
        let def1 = f, typ, x::xs, Var x, t2' in
        let def2 = f, typ, x::xs, make_not (Var x), t3' in
        let t = List.fold_left (fun t x -> App(t,Var x)) (App(Var f,t1')) xs in
          def1::def2::defs1@defs2@defs3, t
    | Syntax.Let _ -> assert false
    | Syntax.BinOp(op, t1, t2) ->
        let defs1,t1' = trans_term xs env t1 in
        let defs2,t2' = trans_term xs env t2 in
          defs1@defs2, App(App(trans_binop op, t1'), t2')
    | Syntax.Not t ->
        let defs,t' = trans_term xs env t in
          defs, App(Const Not, t')
    | Syntax.Fail -> [], Const Fail
    | Syntax.Fun _
    | Syntax.Event _ -> assert false

let trans_def (f,(xs,t)) =
  let xs' = List.map trans_var xs in
  let env = List.map2 (fun x' x -> x', trans_typ (Id.typ x)) xs' xs in
  let defs,t' = trans_term xs' env t in
    (trans_var f, trans_typ (Id.typ f), xs', Const True, t')::defs

let trans_prog t =
(*
  let t' = make_arg_let t in (* for eliminating side-effects from arguments *)
*)
  let defs,_ = Syntax.lift t in
  let main,_ = Util.last defs in
  let defs' = Util.rev_map_flatten trans_def defs in
  let env,defs'' = List.split (List.map (fun (f,typ,xs,t1,t2) -> (f,typ), (f,xs,t1,t2)) defs') in
    env, defs'', trans_var main


let nil = fun _ -> []

let rec get_const_typ = function
    Fail -> TBase(TBottom, nil)
  | Event _ -> TBase(TUnit, nil)
  | Label _ -> assert false
  | Unit _ -> TBase(TUnit, nil)
  | True _ -> TBase(TBool, fun x -> [x])
  | False _ -> TBase(TBool, fun x -> [make_not x])
  | RandBool _ -> assert false
  | RandInt _ -> assert false
  | And -> TFun(fun x -> TBase(TBool,nil), TFun(fun y -> TBase(TBool,nil), TBase(TBool,fun b -> [make_eq b (make_and x y)])))
  | Or -> TFun(fun x -> TBase(TBool,nil), TFun(fun y -> TBase(TBool,nil), TBase(TBool,fun b -> [make_eq b (make_or x y)])))
  | Not -> assert false
  | Lt -> TFun(fun x -> TBase(TInt,nil), TFun(fun y -> TBase(TInt,nil), TBase(TBool,fun b -> [make_eq b (make_lt x y)])))
  | Gt -> TFun(fun x -> TBase(TInt,nil), TFun(fun y -> TBase(TInt,nil), TBase(TBool,fun b -> [make_eq b (make_gt x y)])))
  | Leq -> TFun(fun x -> TBase(TInt,nil), TFun(fun y -> TBase(TInt,nil), TBase(TBool,fun b -> [make_eq b (make_leq x y)])))
  | Geq -> TFun(fun x -> TBase(TInt,nil), TFun(fun y -> TBase(TInt,nil), TBase(TBool,fun b -> [make_eq b (make_geq x y)])))
  | Eq -> TFun(fun x -> TBase(TInt,nil), TFun(fun y -> TBase(TInt,nil), TBase(TBool,fun b -> [make_eq b (make_eq x y)])))
  | Int n -> TBase(TInt, fun x -> [make_eq x (Const (Int n))])
  | Add -> TFun(fun x -> TBase(TInt,nil), TFun(fun y -> TBase(TInt,nil), TBase(TInt,fun r -> [make_eq r (make_add x y)])))
  | Sub -> TFun(fun x -> TBase(TInt,nil), TFun(fun y -> TBase(TInt,nil), TBase(TInt,fun r -> [make_eq r (make_sub x y)])))
  | Mul -> assert false
  | Tuple _ -> assert false
  | Proj _ -> assert false
  | If _ -> assert false


let rec get_typ env = function
    Const c -> get_const_typ c
  | Var x -> List.assoc x env
  | App(t1,t2) ->
      let _,typ2 =
        match get_typ env t1 with
            TFun typ -> typ t2
          | TBase(TBottom,_) -> TBase(TBottom,fun _ -> []), TBase(TBottom,fun _ -> [])
          | _ -> assert false
      in
        typ2
  | Let(x,t1,t2) ->
      let typ = get_typ env t1 in
      let env' = (x,typ)::env in
        get_typ env' t2
      


let rec decomp_app = function
    App(t1,t2) ->
      let t,ts = decomp_app t1 in
        t, ts@[t2]
  | t -> t, []



let rec subst x t = function
    Const c -> Const c
  | Var y when x = y -> t
  | Var y -> Var y
  | App(t1,t2) -> App(subst x t t1, subst x t t2)
  | Let(y,t1,t2) when x = y -> Let(y, subst x t t1, t2)
  | Let(y,t1,t2) -> Let(y, subst x t t1, subst x t t2)
  | Fun(y,t1) when x = y -> Fun(y,t1)
  | Fun(y,t1) -> Fun(y, subst x t t1)

let subst_map map t =
  List.fold_right (fun (x,t) t' -> subst x t t') map t

let subst_def x t (f,xs,t1,t2) =
  f, xs, subst x t t1, subst x t t2


let map_defs f defs =
  let aux (g,xs,t1,t2) =
    let defs1,t1' = f t1 in
    let defs2,t2' = f t2 in
      (g,xs,t1',t2')::defs1@@defs2
  in
    rev_map_flatten aux defs


let rec extract_temp_if = function
    Const If -> assert false
  | Const c -> [], Const c
  | Var x -> [], Var x
  | App(App(App(Const If, t1), t2), t3) ->
      let defs1,t1' = extract_temp_if t1 in
      let defs2,t2' = extract_temp_if t2 in
      let defs3,t3' = extract_temp_if t3 in
      let f = new_id "f" in
      let x = new_id "b" in
      let xs = get_fv t2 @@@ get_fv t3 in
      let def1 = f, x::xs, Var x, t2 in
      let def2 = f, x::xs, make_not (Var x), t3 in
      let defs,t = [def1;def2], App(List.fold_left (fun t x -> App(t,Var x)) (Var f) xs, t1) in
        defs@@defs1@@defs2@@defs3, t
  | App(t1,t2) ->
      let defs1,t1' = extract_temp_if t1 in
      let defs2,t2' = extract_temp_if t2 in
        defs1@@defs2, App(t1',t2')
let extract_temp_if defs = map_defs extract_temp_if defs



let rec occur_arg_pred x = function
    TBase(_,ps) -> List.mem x (rev_flatten_map get_fv (ps (Const Unit)))
  | TFun typ ->
      let typ1,typ2 = typ (Const Unit) in
        occur_arg_pred x typ1 || occur_arg_pred x typ2




let rec lift_term xs = function
    Const c -> [], Const c
  | Var x -> [], Var x
  | App(t1,t2) ->
      let defs1,t1' = lift_term xs t1 in
      let defs2,t2' = lift_term xs t2 in
        defs1@@defs2, App(t1',t2')
  | Let(f,t1,t2) ->
      let f' = rename_id f in
      let f'' = make_app (Var f') (List.map (fun x -> Var x) xs) in
      let defs1,t1' = lift_term xs t1 in
      let defs2,t2' = lift_term xs (subst f f'' t2) in
        (f',xs,Const True,t1') :: defs1 @ defs2, t2'
  | Fun(x,t) ->
      let f = new_id "f" in
      let x' = if List.mem x xs then rename_id x else x in
      let t' = subst x (Var x') t in
      let xs' = xs@[x'] in
      let f' = make_app (Var f) (List.map (fun x -> Var x) xs) in
      let defs,t' = lift_term xs' t' in
        (f,xs',Const True,t')::defs, f'
let lift_def (f,xs,t1,t2) =
  let defs1,t1' = lift_term xs t1 in
  let defs2,t2' = lift_term xs t2 in
    (f, xs, t1', t2')::defs1@defs2
let lift (_,defs,main) =
  let defs = rev_flatten_map lift_def defs in
    ([],defs,main)


let rec get_env typ xs =
  match typ,xs with
      TFun typ, x::xs ->
        let typ1,typ2 = typ (Var x) in
          (x,typ1) :: get_env typ2 xs
    | _ -> []

    

let rec pop_main (env,defs,main) =
  let compare (f,_,_,_) (g,_,_,_) = compare (g = main) (f = main) in
  let defs = List.sort compare defs in
    env, defs, main

