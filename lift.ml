
open Utilities
open Syntax

let new_var b x =
  if b
  then {id=new_int(); origin=String.capitalize x.origin; typ=x.typ}
  else {id=new_int(); origin=x.origin; typ=x.typ}

let rec abstract non_terms = function
    Unit -> [], Unit
  | True -> [], True
  | False -> [], False
  | Unknown -> [], Unknown
  | Int n -> [], Int n
  | NInt x -> [], NInt x
  | Var x -> [], Var x
  | App(t, ts) ->
      let map, t' = abstract non_terms t in
      let maps, ts' = List.split (List.map (abstract non_terms) ts) in
        map@(List.flatten maps), App(t', ts')
  | If(t1, t2, t3, t4) ->
      let map1, t1' = abstract non_terms t1 in
      let map2, t2' = abstract non_terms t2 in
      let map3, t3' = abstract non_terms t3 in
      let map4, t4' = abstract non_terms t4 in
        map1@@map2@@map3@@map4, If(t1', t2', t3', t4')
  | Branch(t1, t2) ->
      let map1, t1' = abstract non_terms t1 in
      let map2, t2' = abstract non_terms t2 in
        map1@@map2, Branch(t1', t2')
  | Let(f, xs, t1, t2) ->
      let f' = new_var true f in
      let fv = diff (get_fv t1) xs in
      let fv = uniq fv in
      let fv = List.filter (fun x -> not (List.mem x non_terms)) fv in
      let fv' = List.map (new_var false) fv in
      let map_fv = List.combine fv fv' in
      let f'' = {f' with typ = List.fold_right (fun x typ -> TFun((x,x.typ),typ)) fv' f.typ} in
      let aux = List.fold_left (fun t x -> App(t, [Var x])) (Var f'') in
      let f1 = aux fv' in
      let f2 = aux fv in
      let t1' = List.fold_right2 (fun x x' -> subst x (Var x')) fv fv' t1 in
      let non_terms' = f''::non_terms in
      let map1, t1'' = abstract non_terms' (subst f f1 t1') in
      let map2, t2' = abstract non_terms' (subst f f2 t2) in
      let t2'' = subst f (Var f'') t2' in
        (f,f'')::map_fv@@map1@@map2, Let(f'', fv'@xs, t1'', t2'')
  | Letrec(f, xs, t1, t2) ->
      let f' = new_var true f in
      let fv = diff (get_fv t1) (f::xs) in
      let fv = uniq fv in
      let fv = List.filter (fun x -> not (List.mem x non_terms)) fv in
      let fv' = List.map (new_var false) fv in
      let map_fv = List.combine fv fv' in
      let f'' = {f' with typ = List.fold_right (fun x typ -> TFun((x,x.typ),typ)) fv' f.typ} in
      let t1 = subst f (Var f'') t1 in
      let aux = List.fold_left (fun t x -> App(t, [Var x])) (Var f) in
      let f1 = aux fv' in
      let f2 = aux fv in
      let t1' = List.fold_right2 (fun x x' -> subst x (Var x')) fv fv' t1 in
      let non_terms' = f''::non_terms in
      let map1, t1'' = abstract non_terms' (subst f f1 t1') in
      let t1''' = subst f (Var f'') t1'' in
      let map2, t2' = abstract non_terms' (subst f f2 t2) in
      let t2'' = subst f (Var f'') t2' in
        (f,f'')::map_fv@@map1@@map2, Letrec(f'', fv'@xs, t1''', t2'')
  | BinOp(op, t1, t2) ->
      let map1, t1' = abstract non_terms t1 in
      let map2, t2' = abstract non_terms t2 in
        map1@@map2, BinOp(op, t1', t2')
  | Not t ->
      let map, t' = abstract non_terms t in
        map, Not t'
  | Fail -> [], Fail
  | Fun(x,t) ->
      let rec aux xs = function
          Fun(x,t) ->
            aux (x::xs) t
        | t -> List.rev xs, t
      in
      let xs,t = aux [] (Fun(x,t)) in
      let f = new_var' "f" in
      let t' = Let(f, xs, t, Var f) in
        abstract non_terms t'
  | Label(b,t) ->
      let map, t' = abstract non_terms t in
        map, Label(b,t')
  | Event s -> [], Event s

let abstract = abstract []


(* Remove definitions *)
let rec remove = function
    Unit -> Unit, []
  | True -> True, []
  | False -> False, []
  | Unknown -> Unknown, []
  | Int n -> Int n, []
  | NInt x -> NInt x, []
  | Var x -> Var x, []
  | App(t, ts) ->
      let t', def1 = remove t in
      let ts', def2s = List.split (List.map remove ts) in
      let def2 = rev_flatten def2s in
        App(t', ts'), def1 @@ def2 
  | If(t1, t2, t3, t4) ->
      let t1', def1 = remove t1 in
      let t2', def2 = remove t2 in
      let t3', def3 = remove t3 in
      let t4', def4 = remove t4 in
        If(t1', t2', t3', t4'), def1 @@ def2 @@ def3 @@ def4
  | Branch(t1, t2) ->
      let t1', def1 = remove t1 in
      let t2', def2 = remove t2 in
        Branch(t1', t2'), def1 @@ def2
  | Let(f, xs, t1, t2) ->
      let t1', def1 = remove t1 in
      let t2', def2 = remove t2 in
        t2', (f,xs,t1')::def1 @@ def2
  | Letrec(f, xs, t1, t2) ->
      let t1', def1 = remove t1 in
      let t2', def2 = remove t2 in
        t2', (f,xs,t1')::def1 @@ def2
  | BinOp(op, t1, t2) ->
      let t1', def1 = remove t1 in
      let t2', def2 = remove t2 in
        BinOp(op, t1', t2'), def1 @@ def2
  | Not t ->
      let t', def = remove t in
        Not t', def
  | Fail -> Fail, []
  | Fun _ -> assert false
  | Label(b,t) ->
      let t',def = remove t in
        Label(b,t'), def
  | Event s -> Event s, []

let lift t =
  let map, t' = abstract t in
  let t'' = part_eval t' in
    map, remove t''
































let rec lift_aux xs = function
    Unit -> [], Unit
  | True -> [], True
  | False -> [], False
  | Unknown -> [], Unknown
  | Int n -> [], Int n
  | NInt x -> [], NInt x
  | RandInt None -> [], RandInt None
  | RandInt (Some t) ->
      let defs,t' = lift_aux xs t in
        defs, RandInt (Some t')
  | Var x -> [], Var x
  | Fun _ -> Format.printf "Not implemented@."; assert false
  | App(t, ts) ->
      let defs,t' = lift_aux xs t in
      let defss,ts' = List.split (List.map (lift_aux xs) ts) in
        defs @ (List.flatten defss), App(t', ts')
  | If(t1,t2,t3) ->
      let defs1,t1' = lift_aux xs t1 in
      let defs2,t2' = lift_aux xs t2 in
      let defs3,t3' = lift_aux xs t3 in
        defs1 @ defs2 @ defs3, If(t1',t2',t3')
  | Branch(t1,t2) ->
      let defs1,t1' = lift_aux xs t1 in
      let defs2,t2' = lift_aux xs t2 in
        defs1 @ defs2, Branch(t1',t2')
  | Let(Nonrecursive,f,ys,t1,t2) ->
      let fv = xs in
      let ys' = fv @ ys in
      let typ = List.fold_right (fun x typ -> TFun((x,x.typ),typ)) ys' TUnit in
      let f' = {(new_var_id f) with typ=typ} in
      let f'' = List.fold_left (fun t x -> app2app t [Var x]) (Var f') fv in
      let defs1,t1' = lift_aux ys' t1 in
      let defs2,t2' = lift_aux xs (subst f f'' t2) in
        defs1 @ [(f',(ys',t1'))] @ defs2, t2'
  | Let(Recursive,f,ys,t1,t2) ->
      let fv = xs in
      let ys' = fv @ ys in
      let typ = List.fold_right (fun x typ -> TFun((x,x.typ),typ)) ys' TUnit in
      let f' = {(new_var_id f) with typ=typ} in
      let f'' = List.fold_left (fun t x -> app2app t [Var x]) (Var f') fv in
      let defs1,t1' = lift_aux ys' (subst f f'' t1) in
      let defs2,t2' = lift_aux xs (subst f f'' t2) in
        defs1 @ [(f',(ys',t1'))] @ defs2, t2'
  | BinOp(op,t1,t2) ->
      let defs1,t1' = lift_aux xs t1 in
      let defs2,t2' = lift_aux xs t2 in
        defs1 @ defs2, BinOp(op,t1',t2')
  | Not t ->
      let defs,t' = lift_aux xs t in
        defs, Not t'
  | Fail -> [], Fail
  | Label(b,t) ->
      let defs,t' = lift_aux xs t in
        defs, Label(b,t')
  | Event s -> [], Event s
  | Record(b,fields) ->
      let aux (s,(f,t)) =
        let defs,t' = lift_aux xs t in
          defs, (s,(f,t'))
      in
      let defss,fields' = List.split (List.map aux fields) in
        List.flatten defss, Record(b,fields')
  | Proj(n,i,s,f,t) ->
      let defs,t' = lift_aux xs t in
        defs, Proj(n,i,s,f,t')
  | Nil -> [], Nil
  | Cons(t1,t2) ->
      let defs1,t1' = lift_aux xs t1 in
      let defs2,t2' = lift_aux xs t2 in
        defs1 @ defs2, Cons(t1',t2')
  | Match(t1,t2,x,y,t3) ->
      let defs1,t1' = lift_aux xs t1 in
      let defs2,t2' = lift_aux xs t2 in
      let defs3,t3' = lift_aux xs t3 in
        defs1 @ defs2 @ defs3, Match(t1',t2',x,y,t3')
  | Constr(c,ts) ->
      let defss,ts' = List.split (List.map (lift_aux xs) ts) in
        List.flatten defss, Constr(c,ts')
  | Match_(t,pats) ->
      let defs,t' = lift_aux xs t in
      let aux (pat,cond,t) (defs,pats) =
        let xs' = get_vars_pat pat @@ xs in
        let defs',cond' =
          match cond with
              None -> [], None
            | Some t ->
                let defs',t' = lift_aux xs' t in
                  defs', Some t'
        in
        let defs'',t' = lift_aux xs' t in
          defs''@defs'@defs, (pat,cond',t')::pats
      in
      let defs',pats' = List.fold_right aux pats (defs,[]) in
        defs', Match_(t',pats')
  | Type_decl(decls,t) ->
      let defs,t' = lift_aux xs t in
        defs, Type_decl(decls,t')
let lift t = lift_aux [](*(get_fv2 t)*) t

