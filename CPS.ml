
open Syntax
open Type
open Utilities

let funs = ref []
(*
let rec inlining funs defs t =
  let desc =
    match t.desc with
        Unit -> Unit
      | True -> True
      | False -> False
      | Unknown -> Unknown
      | Int n -> Int n
      | NInt x -> NInt x
      | RandInt None -> RandInt None
      | RandInt (Some t) -> RandInt (Some (inlining funs defs t))
      | Var x -> Var x
      | Fun _ -> assert false
      | App({desc=Var f}, ts) ->
          if List.exists (Id.same f) funs && List.length (get_args (Id.typ f)) = List.length ts
          then
            let xs,t = Id.assoc f defs in
              (List.fold_right2 subst xs ts t).desc
          else App({desc=Var f;typ=Id.typ f}, ts)
      | App({desc=Fail}, ts) -> t.desc
      | App({desc=Event s}, ts) -> t.desc
      | App _ -> assert false
      | If(t1, t2, t3) ->
          let t2' = inlining funs defs t2 in
          let t3' = inlining funs defs t3 in
            If(t1, t2', t3')
      | Branch(t1, t2) ->
          let t1' = inlining funs defs t1 in
          let t2' = inlining funs defs t2 in
            Branch(t1', t2')
      | Let(flag, f, xs, t1, t2) ->
          if flag = Flag.Nonrecursive
          then
            let t1' = inlining funs defs t1 in
            let t2' = inlining funs ((f,(xs,t1'))::defs) t2 in
              Let(flag, f, xs, t1', t2')
          else
            let t1' = inlining funs defs t1 in
            let t2' = inlining funs defs t2 in
              Let(flag, f, xs, t1', t2')
      | BinOp(op, t1, t2) ->
          let t1' = inlining funs defs t1 in
          let t2' = inlining funs defs t2 in
            BinOp(op, t1', t2')
      | Not t ->
          let t' = inlining funs defs t in
            Not t'
      | Fail -> Fail
      | Label _ -> assert false
      | Event s -> Event s
      | Nil -> Nil
      | Cons(t1,t2) -> Cons(inlining funs defs t1, inlining funs defs t2)
      | Match(t1,t2,x,y,t3) ->
          Match(inlining funs defs t1, inlining funs defs t2, x, y, inlining funs defs t3)
      | Constr(c,ts) -> Constr(c, List.map (inlining funs defs) ts)
      | Match_(t,pats) ->
          let aux (pat,cond,t) = pat, apply_opt (inlining funs defs) cond, inlining funs defs t in
            Match_(inlining funs defs t, List.map aux pats)
  in
    {desc=desc; typ=t.typ}


let rec normalize t =
  let desc =
    match t.desc with
        Unit -> Unit
      | True -> True
      | False -> False
      | Unknown -> Unknown
      | Int n -> Int n
      | NInt x -> NInt x
      | RandInt None -> RandInt None
      | RandInt (Some t) -> RandInt (Some (normalize t))
      | Var x -> Var x
      | Fun _ -> assert false
      | App({desc=Fail;typ=typ}, [t1;t2]) -> assert false (*App(fail_term, [normalize t1])*)
      | App({desc=Fail}, _) -> assert false
      | App({desc=Event s;typ=typ}, [t1;t2]) ->
          let t1' = normalize t1 in
          let t2' = normalize t2 in
            App({desc=Event s;typ=typ}, [{desc=App(t2', [t1']);typ=TUnit}])
      | App({desc=Event s}, _) -> assert false
      | App(f, ts) ->
          let ts' = List.map normalize ts in
          let f' = normalize f in
            App(f', ts')
      | If(t1, t2, t3) ->
          let t1' = normalize t1 in
          let t2' = normalize t2 in
          let t3' = normalize t3 in
            If(t1', t2', t3')
      | Branch(t1, t2) ->
          let t1' = normalize t1 in
          let t2' = normalize t2 in
            Branch(t1', t2')
      | Let(flag, f, xs, t1, t2) ->
          let t1' = normalize t1 in
          let t2' = normalize t2 in
            Let(flag, f, xs, t1', t2')
              (*
                | Let(flag, bindings, t) ->
                let bindings' = List.map (fun (f,xs,t) -> f,xs,normalize t) bindings in
                let t' = normalize t in
                Let(flag, bindings', t')
              *)
      | BinOp(op, t1, t2) ->
          let t1' = normalize t1 in
          let t2' = normalize t2 in
            BinOp(op, t1', t2')
      | Not t -> Not (normalize t)
      | Fail -> Fail
      | Label(b,t) -> Label(b,normalize t)
      | Event s -> assert false
      | Record fields -> Record (List.map (fun (s,(f,t)) -> s,(f,normalize t)) fields)
      | Proj(i,s,f,t) -> Proj(i, s, f, normalize t)
      | Nil -> Nil
      | Cons(t1,t2) -> Cons(normalize t1, normalize t2)
      | Match(t1,t2,x,y,t3) -> Match(normalize t1, normalize t2, x, y, normalize t3)
      | Constr(c,ts) -> Constr(c, List.map normalize ts)
      | Match_(t,pats) ->
          let aux (pat,cond,t) = pat, apply_opt normalize cond, normalize t in
            Match_(normalize t, List.map aux pats)
  in
    {desc=desc; typ=t.typ}




let rec extract_records_typ = function
    TUnit -> TUnit
  | TAbsBool -> TAbsBool
  | TBool -> TBool
  | TInt ts -> TInt ts
  | TRInt t -> TRInt t
  | TVar x -> TVar x
(*
  | TFun({Id.typ=TRecord(_,typs)} as x,typ) ->
      let typ = extract_records_typ typ in
      let aux (s,(_,typ)) typ =
        let x' = Id.new_var (Id.name x^"_"^s) typ in
          TFun(x',typ)
      in
        extract_records_typ (List.fold_right aux typs typ)
*)
  | TFun(y,typ) -> TFun(Id.set_typ y (extract_records_typ (Id.typ y)), extract_records_typ typ)
  | TUnknown -> TUnknown
  | TList(typ,ps) -> TList(extract_records_typ typ, ps)

let rec extract_records env t =
  let desc =
    match t.desc with
        Unit -> Unit
      | True -> True
      | False -> False
      | Unknown -> Unknown
      | Int n -> Int n
      | NInt x -> NInt x
      | RandInt None -> RandInt None
      | RandInt (Some t) -> RandInt (Some (extract_records env t))
      | Var x -> Var x
      | Fun _ -> assert false
      | App(f, ts) ->
          let rec aux = function
              {desc=Var x} ->
                begin
                  match Id.typ x with
                      TRecord _ -> List.map (fun x -> {desc=Var x;typ=Id.typ x}) (Id.assoc x env)
                    | _ -> [{desc=Var x;typ=Id.typ x}]
                end
            | {desc=Record(_,fields)} -> List.flatten (List.map (fun (_,(_,t)) -> aux t) fields)
            | t -> [extract_records env t]
          in
            App(extract_records env f, List.flatten (List.map aux ts))
      | If(t1, t2, t3) -> If(extract_records env t1, extract_records env t2, extract_records env t3)
      | Branch(t1, t2) -> Branch(extract_records env t1, extract_records env t2)
      | Let(flag, f, xs, t1, t2) ->
          let aux x (xs,env) =
            match Id.typ x with
                TRecord(_,typs) ->
                  assert (List.for_all (function _,(_,TRecord _) -> false | _ -> true) typs);
                  let xs' = List.map (fun (s,(_,typ)) -> Id.new_var (Id.name x^"_"^s) typ) typs in
                    xs'@xs, (x,xs')::env
              | _ -> x::xs, env
          in
          let f' = Id.set_typ f (extract_records_typ (Id.typ f)) in
          let xs',env' = List.fold_right aux xs ([],env) in
          let t1' = extract_records env' t1 in
          let t2' = extract_records env t2 in
            Let(flag, f', xs', t1', t2')
      | BinOp(op, t1, t2) -> BinOp(op, extract_records env t1, extract_records env t2)
      | Not t -> Not (extract_records env t)
      | Fail -> Fail
      | Label(b,t) -> Label(b,extract_records env t)
      | Event s -> Event s
      | Record fields -> assert false
      | Proj(i,_,_,{desc=Var x}) -> Var (List.nth (Id.assoc x env) i)
      | Proj _ -> assert false
      | Nil -> Nil
      | Cons(t1,t2) -> Cons(extract_records env t1, extract_records env t2)
      | Match(t1,t2,x,y,t3) -> Match(extract_records env t1, extract_records env t2, x, y, extract_records env t3)
      | Constr(c,ts) -> Constr(c, List.map (extract_records env) ts)
      | Match_(t,pats) ->
          let aux (pat,cond,t) = pat, apply_opt (extract_records env) cond, extract_records env t in
            Match_(extract_records env t, List.map aux pats)
  in
    {desc=desc; typ=t.typ}
let extract_records t = extract_records [] t
*)


let rec trans_simpl_typ = function
  | TFun(x,typ) ->
    let typ1 = trans_simpl_typ (Id.typ x) in
    let typ2 = trans_simpl_typ typ in
    let y = Id.new_var "x" typ2 in
    let k = Id.new_var "k" (TFun(y,TUnit)) in
      TFun(Id.set_typ x typ1, TFun(k,TUnit))
  | TPair(typ1,typ2) -> TPair(trans_simpl_typ typ1, trans_simpl_typ typ2)
  | TVar _ -> assert false
  | TUnknown -> assert false
  | TList _ -> assert false
  | typ -> typ

let trans_var x = Id.set_typ x (trans_simpl_typ (Id.typ x))

let make_let' f xs t1 t2 =
  match xs,t1.desc with
      [r], App({desc=Var _} as k, [{desc=Var r'}]) when r = r' -> subst f k t2
    | _ -> make_let f xs t1 t2

let rec trans_simpl c t =
  match t.desc with
      Unit
    | True
    | False
    | Int _
    | NInt _
    | Bottom -> c t
    | RandInt None ->
        let r = Id.new_var "r" (TInt[]) in
        let k = Id.new_var "k" (TFun(r,TUnit)) in
        let t = make_let' k [r] (c (make_var r)) (make_var k) in
          {desc=RandInt (Some t); typ=TUnit}
    | RandInt _ -> assert false
    | Var x -> c (make_var (trans_var x))
    | Fun(x, t) ->
        let r = Id.new_var "r" (trans_simpl_typ t.typ) in
        let k = Id.new_var "k" (TFun(r,TUnit)) in
          c (make_fun x (make_fun k (trans_simpl (fun y -> make_app (make_var k) y) t)))
    | App(_, []) -> assert false
    | App(t1, [t2]) ->
        let r = Id.new_var "r" (trans_simpl_typ t.typ) in
        let k = Id.new_var "k" (TFun(r,TUnit)) in
        let c' x = trans_simpl (fun y -> app2app x [y; make_var k]) t2 in
        let t2' = trans_simpl c' t1 in
          make_let' k [r] (c (make_var r)) t2'
    | App(t1, t2::ts) ->
        let typ = match t1.typ with TFun(_,typ) -> typ | _ -> assert false in
          trans_simpl c {desc=App({desc=App(t1,[t2]);typ=typ}, ts); typ=t.typ}
    | If(t1, t2, t3) ->
        let x = Id.new_var "x" (trans_simpl_typ t.typ) in
        let k = Id.new_var "k" (TFun(x,TUnit)) in
        let c' y = make_app (make_var k) y in
        let t2' = trans_simpl c' t2 in
        let t3' = trans_simpl c' t3 in
        let c'' y = make_let' k [x] (c (make_var x)) (make_if y t2' t3') in
          trans_simpl c'' t1
    | Let(Flag.Nonrecursive, x, [], t1, t2) ->
        let x' = trans_var x in
        let c' t = subst x' t (trans_simpl c t2) in
          trans_simpl c' t1
    | Let(Flag.Recursive, f, [], t1, t2) -> assert false
    | Let(flag, f, [x], t1, t2) ->
        let x' = trans_var x in
        let r = Id.new_var "r" (trans_simpl_typ t1.typ) in
        let k = Id.new_var "k" (TFun(r,TUnit)) in
        let f' = trans_var f in
        let c' y = make_app (make_var k) y in
        let t1' = trans_simpl c' t1 in
        let t2' = trans_simpl c t2 in
          make_let_f flag f' [x';k] t1' t2'
    | Let(flag, f, x::xs, t1, t2) ->
        let typ = match Id.typ f with TFun(_,typ) -> typ | _ -> assert false in
        let g = Id.new_var (Id.name f) typ in
        let t1' = make_let g xs t1 (make_var g) in
          trans_simpl c (make_let_f flag f [x] t1' t2)
    | BinOp(op, t1, t2) ->
        let c1 t1' t2' = c {desc=BinOp(op, t1', t2'); typ=t.typ} in
        let c2 y1 = trans_simpl (fun y2 -> c1 y1 y2) t2 in
          trans_simpl c2 t1
    | Not t ->
        let c' t1 = c (make_not t1) in
          trans_simpl c' t
    | Unknown -> c {desc=Unknown;typ=t.typ}
    | Event s ->
        let e = Id.new_var "e" typ_event in
          make_let e [] (make_event s) (c unit_term)
    | Pair(t1, t2) ->
        let c1 t1' t2' = c (make_pair t1' t2') in
        let c2 y1 = trans_simpl (fun y2 -> c1 y1 y2) t2 in
          trans_simpl c2 t1
    | Fst t ->
        let c' t1 = c (make_fst t1) in
          trans_simpl c' t
    | Snd t ->
        let c' t1 = c (make_snd t1) in
          trans_simpl c' t
    | _ -> (Format.printf "%a@." pp_print_term t; assert false)
let trans_simpl = trans_simpl (fun x -> x)


(*
let trans t =
  let cps = trans_simpl t in
  let () = if true then Format.printf "CPS:@.%a@." pp_print_term cps in
  let () = if true then Format.printf "CPS:@.%a@." (Syntax.print_term' Syntax.ML 0 false) cps in
  let () = Type_check.check cps in
  let extracted = extract_records cps in
  let () = if true then Format.printf "EXTRACTED:@.%a@." pp_print_term extracted in
  let normalized = normalize extracted in
  let inlined = inlining !funs [] normalized in
    part_eval inlined
*)

let trans t = trans_simpl t

(*
let test =
  let x = Id.new_var "x" (TVar(ref None)) in
  let y = Id.new_var "y" (TVar(ref None)) in
  let f = Id.new_var "f" (TVar(ref None)) in
  let y = Id.new_var "y" (TVar(ref None)) in
  let z = Id.new_var "z" (TVar(ref None)) in
    make_let f [x] (make_pair (make_fun y (make_add (make_var x) (make_var y))) (make_var x)) unit_term
*)














let rec trans_exc_typ = function
    TUnit -> TUnit
  | TBool -> TBool
  | TAbsBool -> TAbsBool
  | TInt ps -> TInt ps
  | TRInt p -> TRInt p
  | TVar _ -> assert false
  | TFun(x,typ) ->
    let typ1 = trans_exc_typ (Id.typ x) in
    let typ2 = trans_exc_typ typ in
    let y = Id.new_var "x" typ2 in
    let k = Id.new_var "k" (TFun(y,TUnit)) in
    let e = Id.new_var "e" typ_excep in
    let h = Id.new_var "h" (TFun(e,TUnit)) in
      TFun(Id.set_typ x typ1, TFun(k,TFun(h,TUnit)))
  | TList typ -> TList (trans_exc_typ typ)
  | TConstr(s,b) -> TConstr(s,b)
  | TUnknown -> assert false

let trans_exc_var x = Id.set_typ x (trans_exc_typ (Id.typ x))

let rec trans_exc ct ce t =
  match t.desc with
      Unit
    | True
    | False
    | Int _
    | NInt _ -> ct t
    | RandInt None ->
        let r = Id.new_var "r" (TInt[]) in
        let k = Id.new_var "k" (TFun(r,TUnit)) in
          make_let k [r] (ct (make_var r)) (make_app (make_var k) {desc=RandInt None;typ=TInt[]})
    | RandInt _ -> assert false
    | Var x -> ct (make_var (trans_exc_var x))
    | Fun(x, t) -> assert false
    | App(_, []) -> assert false
    | App(t1, [t2]) ->
        let r = Id.new_var "r" (trans_exc_typ t.typ) in
        let k = Id.new_var "k" (TFun(r,TUnit)) in
        let e = Id.new_var "e" typ_excep in
        let h = Id.new_var "h" (TFun(e,TUnit)) in
        let ct' x = trans_exc (fun y -> app2app x [y; make_var  k; make_var h]) ce t2 in
        let t2' = trans_exc ct' ce t1 in
          make_let k [r] (ct (make_var r)) (make_let h [e] (ce (make_var e)) t2')
    | App(t1, t2::ts) ->
        let x,typ = match t1.typ with TFun(x,typ) -> x,typ | _ -> assert false in
          trans_exc ct ce {desc=App({desc=App(t1,[t2]);typ=typ}, ts); typ=t.typ}
    | If(t1, t2, t3) ->
        let x = Id.new_var "x" t.typ in
        let k = Id.new_var "k" (TFun(x,TUnit)) in
        let ct' y = make_app (make_var k) y in
        let t2' = trans_exc ct' ce t2 in
        let t3' = trans_exc ct' ce t3 in
        let ct'' y = make_let k [x] (ct (make_var x)) (make_if y t2' t3') in
          trans_exc ct'' ce t1
    | Let(Flag.Nonrecursive, x, [], t1, t2) ->
        let ct' t = subst x t (trans_exc ct ce t2) in
          trans_exc ct' ce t1
    | Let(Flag.Recursive, f, [], t1, t2) -> assert false
    | Let(flag, f, [x], t1, t2) ->
        let x' = trans_exc_var x in
        let r = Id.new_var "r" (trans_exc_typ t1.typ) in
        let k = Id.new_var "k" (TFun(r,TUnit)) in
        let e = Id.new_var "e" typ_excep in
        let h = Id.new_var "h" (TFun(e,TUnit)) in
        let f' = trans_exc_var f in
        let ct' y = make_app (make_var k) y in
        let ce' y = make_app (make_var h) y in
        let t1' = trans_exc ct' ce' t1 in
        let t2' = trans_exc ct ce t2 in
          make_let_f flag f' [x';k;h] t1' t2'
    | Let(flag, f, x::xs, t1, t2) ->
        let typ = match Id.typ f with TFun(_,typ) -> typ | _ -> assert false in
        let g = Id.new_var (Id.name f) typ in
        let t1' = make_let g xs t1 (make_var g) in
          trans_exc ct ce (make_let_f flag f [x] t1' t2)
    | BinOp(op, t1, t2) ->
        let ct1 t1' t2' = ct {desc=BinOp(op, t1', t2'); typ=t.typ} in
        let ct2 y1 = trans_exc (fun y2 -> ct1 y1 y2) ce t2 in
          trans_exc ct2 ce t1
    | Not t ->
        let ct' t1 = ct (make_not t1) in
          trans_exc ct' ce t
    | Unknown -> ct {desc=Unknown;typ=t.typ}
    | Event s -> ct (make_event s)
    | Nil -> ct (make_nil (t.typ))
    | Cons(t1, t2) ->
        let ct1 t1' t2' = ct {desc=Cons(t1', t2'); typ=t.typ} in
        let ct2 y1 = trans_exc (fun y2 -> ct1 y1 y2) ce t2 in
          trans_exc ct2 ce t1
    | Constr(cstr,[]) -> ct {desc=Constr(cstr,[]);typ=t.typ}
    | Constr(cstr,t1::ts) ->
        let x = Id.new_var "x" t.typ in
        let k = Id.new_var "k" (TFun(x,TUnit)) in
        let aux t1 t2 =
          match t2.desc with
              App({desc=Var k}, [{desc=Constr(c,ts)}]) -> make_app (make_var k) {desc=Constr(c,t1::ts);typ=t.typ}
            | _ -> assert false
        in
        let ct1 x = make_app (make_var k) {desc=Constr(cstr,[x]);typ=t.typ} in
        let ct' = List.fold_right (fun t ct -> fun x -> trans_exc (fun y -> ct (aux x y)) ce t) ts ct1 in
          make_let k [x] (ct (make_var x)) (trans_exc ct' ce t1)
    | Match_(t1,pats) ->
        let x = Id.new_var "x" t.typ in
        let k = Id.new_var "k" (TFun(x,TUnit)) in
        let ct' y = make_app (make_var k) y in
        let aux (pat,None,t) =
          pat, None, trans_exc ct' ce t
        in
        let pats' = List.map aux pats in
        let ct'' y = make_let k [x] (ct (make_var x)) {desc=Match_(y,pats');typ=TUnit} in
          trans_exc ct'' ce t1
    | Raise t -> trans_exc ce ce t
    | TryWith(t1,{desc=Fun(x,t2)}) ->
        let ce' e = trans_exc ct ce t2 in
          trans_exc ct ce' t1
    | _ -> (Format.printf "%a@." pp_print_term t; assert false)
let trans_exc t =
  let u = Id.new_var "u" typ_event in
  let ce _ = make_let u [] fail_term unit_term in
    trans_exc (fun x -> x) ce t


type 'a tree = Leaf of 'a | Node of 'a tree * 'a tree

let root x =
  match x with
      Leaf t -> t
    | Node _ -> assert false
let rec flatten = function
    Leaf f -> [f]
  | Node(lhs,rhs) -> flatten lhs @ flatten rhs

let rec map f path = function
    Leaf t -> Leaf (f path t)
  | Node(t1,t2) -> Node(map f (path@[1]) t1, map f (path@[2]) t2)
let map f t = map f [] t

let rec remove_pair_typ = function
    TUnit -> Leaf TUnit
  | TBool -> Leaf TBool
  | TAbsBool -> Leaf TAbsBool
  | TInt ps -> Leaf (TInt ps)
  | TRInt p -> Leaf (TRInt p)
  | TVar _ -> assert false
  | TFun _ as typ ->
      let xs,typ' = decomp_tfun typ in
      let aux x =
        let typs = remove_pair_typ (Id.typ x) in
          match flatten typs with
              [typ] -> [Id.set_typ x typ]
            | typs' -> mapi (fun i typ -> Id.set_typ (Id.add_name x (string_of_int i)) typ) typs'
      in
      let xs' = List.flatten (List.map aux xs) in
        Leaf (List.fold_right (fun x typ -> TFun(x,typ)) xs' typ')
  | TPair(typ1,typ2) -> Node(remove_pair_typ typ1, remove_pair_typ typ2)
  | TList typ -> Leaf (TList(root (remove_pair_typ typ)))
  | TConstr(s,b) -> Leaf (TConstr(s,b))
  | TUnknown -> assert false
  | TBottom -> Leaf TBottom

let remove_pair_var x =
  let to_string path = List.fold_left (fun acc i -> acc ^ string_of_int i) "" path in
  let aux path typ = Id.set_typ (Id.add_name x (to_string path)) typ in
    map aux (remove_pair_typ (Id.typ x))

let rec remove_pair t typ_opt =
  let typ = match typ_opt with None -> t.typ | Some typ -> typ in
  let typs = remove_pair_typ typ in
    match t.desc with
        Unit
      | True
      | False
      | Int _
      | NInt _
      | RandInt None -> Leaf t
      | RandInt (Some t) -> Leaf {desc=RandInt (Some (root (remove_pair t None))); typ=root typs}
      | Bottom -> map (fun _ _ -> bottom_term) typs
      | Var x -> map (fun _ x -> make_var x) (remove_pair_var x)
      | Fun(x, t) ->
          let xs = flatten (remove_pair_var x) in
          let t' = root (remove_pair t None) in
            Leaf (List.fold_right make_fun xs t')
      | App(t, ts) ->
          let typs = List.map (fun x -> Id.typ x) (get_args t.typ) in
          let typs' = take typs (List.length ts) in
          let t' = root (remove_pair t None) in
          let ts' = List.flatten (List.map2 (fun t typ -> flatten (remove_pair t (Some typ))) ts typs') in
            Leaf (app2app t' ts')
      | If(t1, t2, t3) ->
          let t1' = root (remove_pair t1 None) in
          let t2' = root (remove_pair t2 None) in
          let t3' = root (remove_pair t3 None) in
            Leaf (make_if t1' t2' t3')
      | Branch(t1, t2) ->
          let t1' = root (remove_pair t1 None) in
          let t2' = root (remove_pair t2 None) in
            Leaf {desc=Branch(t1',t2'); typ=t1'.typ}
      | Let(flag, f, xs, t1, t2) ->
          let f' = root (remove_pair_var f) in
          let xs' = List.flatten (List.map (fun x -> flatten (remove_pair_var x)) xs) in
          let t1' = root (remove_pair t1 None) in
          let t2' = root (remove_pair t2 None) in
            Leaf (make_let_f flag f' xs' t1' t2')
      | BinOp(op, t1, t2) ->
          let t1' = root (remove_pair t1 None) in
          let t2' = root (remove_pair t2 None) in
            Leaf {desc=BinOp(op, t1', t2'); typ=root typs}
      | Not t1 ->
          let t1' = root (remove_pair t1 None) in
            Leaf (make_not t1')
      | Label(b, t1) ->
          let t1' = root (remove_pair t1 None) in
            Leaf {desc=Label(b, t1'); typ=root typs}
      | LabelInt(n, t1) ->
          let t1' = root (remove_pair t1 None) in
            Leaf {desc=LabelInt(n, t1'); typ=root typs}
      | Event s -> Leaf (make_event s)
      | Record fields -> assert false
      | Proj(i,s,f,t1) -> assert false
      | SetField(n,i,s,f,t1,t2) -> assert false
      | Nil -> assert false
      | Cons(t1,t2) -> assert false
      | Constr(s,ts) -> assert false
      | Match(t1,t2,y,z,t3) -> assert false
      | Match_(t1,pats) -> assert false
      | TryWith(t1,t2) -> assert false
      | Pair(t1,t2) -> Node(remove_pair t1 None, remove_pair t2 None)
      | Fst t ->
          let t' = 
            match remove_pair t None with
                Leaf _ -> assert false
              | Node(t',_) -> t'
          in
            t'
      | Snd t ->
          let t' = 
            match remove_pair t None with
                Leaf _ -> assert false
              | Node(_,t') -> t'
          in
            t'
      | _ -> (Format.printf "%a@." pp_print_term t; assert false)

let remove_pair t = root (remove_pair t None)
