var program = {
    "0": "",
    "1": "let f x g : unit = g(x+1)\nlet h y = assert (y>0)\nlet main n = if n>0 then f n h",
    "2": "let f x g : unit = g(x+1)\nlet h y = assert (y>0)\nlet main n = if n>=0 then f n h",
    "3": "let f x g :unit= g(x+1)\nlet h z y = assert (y>z)\nlet main n = if n>=0 then f n (h n)",
    "4": "let rec sum n =\n  if n <= 0 then\n    0\n  else\n    n + sum (n-1)\nlet main n = assert (n <= sum n)",
    "5": "let rec mult n m =\n  if n <= 0 || m <= 0 then\n    0\n  else\n    n + mult n (m-1)\nlet main n = assert (n <= mult n n)",
    "6": "let max max2 (x:int) (y:int) (z:int) : int = max2 (max2 x y) z\nlet f x y : int = if x >= y then x else y\nlet main (x:int) y z =\n  let m = max f x y z in\n  assert (f x m = m)",
    "7": "let rec mc91 x =\n  if x > 100 then\n    x - 10\n  else\n    mc91 (mc91 (x + 11))\nlet main n = if n <= 101 then assert (mc91 n = 91)",
    "8": "let rec ackermann m n =\n  if m=0 then\n    n+1\n  else if n=0 then\n    ackermann (m-1) 1\n  else\n    ackermann (m-1) (ackermann m (n-1))\nlet main m n = if (m>=0 && n>=0) then assert (ackermann m n >= n)",
"9": "let rec f g x = if x>=0 then g x else f (f g) (g x)\nlet succ x = x+1\nlet main n = assert (f succ n >= 0)",
"10": "let g (x:int) (y:unit) = x\nlet twice f (x:unit->int) (y:unit) = f (f x) y\nlet neg x (y:unit) = - x ()\nlet main n =\n  if n>=0 then\n    let z = twice neg (g n) () in\n    assert (z>=0)",
"11": "let make_array n i = assert (0 <= i && i < n); 0\nlet update (i:int) (n:int) des x : int -> int =\n  des i;\n  let a j = if i=j then x else des i in a\nlet print_int (n:int) = ()\nlet f (m:int) src des =\n  let rec bcopy (m:int) src des i =\n    if i >= m then\n      des\n    else\n      let des = update i m des (src i) in\n      bcopy m src des (i+1)\n  in\n  let rec print_array m (array:int->int) i =\n    if i >= m then\n      ()\n    else\n      (print_int (des i);\n       print_array m array (i + 1))\n  in\n  let array : int -> int = bcopy m src des 0 in\n    print_array m array 0\nlet main n =\n  let array1 = make_array n in\n  let array2 = make_array n in\n    if n > 0 then f n array1 array2",
"12": "let make_array n i = n - i\nlet rec array_max (n:int) i (a:int->int) m =\n  if i >= n then\n    m\n  else\n    let x = a i in\n    let z = if x>m then x else m in\n    array_max n (i+1) a z\nlet main n i =\n  if n>0 && i>=0 && i<=0 then\n    let m = array_max n i (make_array n) (-1) in\n    assert (m >= n)",
"13": "let f g x y : int = g (x + 1) (y + 1)\nlet rec unzip x k =\n  if x=0 then\n    k 0 0\n  else\n    unzip (x - 1) (f k)\nlet rec zip x y =\n  if x = 0 then\n    if y = 0 then\n      0\n    else\n      assert false\n  else\n    if y = 0 then\n      assert false\n    else\n      1 + zip (x - 1) (y - 1)\nlet main n = unzip n zip",
"14": "let rec zip x y =\n  if x = 0 then\n    if y = 0 then\n      x\n    else\n      assert false\n  else\n    if y = 0 then\n      assert false\n    else\n      1 + zip (x - 1) (y - 1)\nlet rec map x =\n  if x = 0 then x else 1 + map (x - 1)\nlet main n =\n  assert (map (zip n n) = n)",
"15": "let c (q:int) = ()\nlet b x (q:int) : unit = x 1\nlet a (x:int->unit) (y:int->unit) q = if q=0 then (x 0; y 0) else assert false\nlet rec f n x q = if n <= 0 then x q else a x (f (n-1) (b x)) q\nlet s n q = f n c q\nlet main n = s n 0",
"16": "let f n k = if n >= 0 then () else k 0\nlet g n = assert (n = 0)\nlet main n = f n g",
"17": "let rec fact n exn =\n  if n <= 0 then\n    exn 0\n  else\n    let exn n = if n = 0 then 1 else exn n in\n    n * fact (n - 1) exn\nlet exn n = (assert false:unit); 1\nlet main n = if n > 0 then (fact n exn; ())",
"18": "let lock st = assert (st=0); 1\nlet unlock st = assert (st=1); 0\nlet f n st : int= if n > 0 then lock (st) else st\nlet g n st : int = if n > 0 then unlock (st) else st\nlet main n = assert ((g n (f n 0)) = 0)",
"19": "let rec loop x : unit = loop ()\nlet init = 0\nlet opened = 1\nlet closed = 2\nlet ignore = 3\nlet readit st =\n  if st = opened then opened else (if st = ignore then st else assert false)\nlet read_ x st =\n  if x then readit st else st\nlet closeit st =\n  if st = opened then closed else (if st = ignore then st else (loop (); 0))\nlet close_ x st =\n  if x then closeit st else st\nlet rec f x y st : unit =\n  close_ y (close_ x st); f x y (read_ y (read_ x st))\nlet next st = if st=init then opened else ignore\nlet g b3 x st = if b3 > 0 then f x true (next st) else f x false st\nlet main b2 b3 = (if b2 > 0 then g b3 true opened else g b3 false init); ()",
"20": "let rec sum n =\n  if n <= 0 then\n    0\n  else\n    n + sum (n-1)\nlet main n = assert (n+1 <= sum n)",
"21": "let rec mult n m =\n  if n <= 0 || m <= 0 then\n    0\n  else\n    n + mult n (m-1)\nlet main n = assert (n+1 <= mult n n)",
"22": "let rec mc91 x =\n  if x > 100 then\n		  x - 10\n  else\n		  mc91 (mc91 (x + 11))\nlet main n = if n <= 102 then assert (mc91 n = 91)",
"23": "let succ x = x + 1\nlet rec repeat (f:int->int) n s : int =\n  if n = 0 then\n    s\n  else\n    f (repeat f (n-1) s)\nlet main n = assert (repeat succ n 0 > n)",
"24": "let make_array n i = n - i\nlet rec array_max (n:int) i (a:int->int) m =\n  if i >= n then\n    m\n  else\n    let x = a i in\n    let z = if x>m then x else m in\n    array_max n (i+1) a z\nlet main n i =\n  if n>0 && i>=0 && i<=0 then\n    let m = array_max n i (make_array n) (-1) in\n    assert (m >= n)",
"25": "let lock st = assert (st=0); 1\nlet unlock st = assert (st=1); 0\nlet f n st : int= if n > 0 then lock (st) else st\nlet g n st : int = if n >= 0 then unlock (st) else st\nlet main n = assert ((g n (f n 0)) = 0)",
"26": "let add x y = x + y\nlet rec sum n =\n  if n <= 0 then\n    0\n  else\n    add n (sum (n-1))\nlet main n = assert (n <= sum n)",
"27": "let rec fold_right (f:int->int->int) xs acc =\n  match xs with\n    [] -> acc\n  | x::xs' -> f x (fold_right f xs' acc)\n\nlet rec make_list n =\n  if n < 0\n  then []\n  else n :: make_list (n-1)\n\nlet add x y = x + y\n\nlet main n m =\n  let xs = make_list n in\n    assert (fold_right add xs m >= m)",
"28": "let rec for_all f (xs:(int*int) list) =\n  match xs with\n      [] -> true\n    | x::xs' ->\n        f x && for_all f xs'\n\nlet rec eq_pair ((x:int),(y:int)) = x = y\n\nlet rec make_list n =\n  if n < 0\n  then []\n  else (n,n) :: make_list (n-1)\n\nlet main n = assert (for_all eq_pair (make_list n))",
"29": "let rec for_all f (xs:int list) =\n  match xs with\n      [] -> true\n    | x::xs' ->\n        f x && for_all f xs'\n\nlet rec check x = x >= 0\n\nlet rec make_list n =\n  if n < 0\n  then []\n  else n :: make_list (n-1)\n\nlet main n = assert (for_all check (make_list n))",
"30": "let is_nil (xs:int list) =\n  match xs with\n      [] -> true\n    | _ -> false\n\nlet rec make_list n =\n  if n = 0\n  then []\n  else n :: make_list (n-1)\n\nlet main n =\n  let xs = make_list n in\n    if n > 0\n    then assert (not (is_nil xs))\n    else ()",
"31": "let rec iter (f:int -> unit) xs =\n  match xs with\n      [] -> ()\n    | x::xs' -> f x; iter f xs'\n\nlet rec make_list n =\n  if n < 0\n  then []\n  else n :: make_list (n-1)\n\nlet check x = assert (x >= 0)\n\nlet main n =\n  let xs = make_list n in\n    iter check xs",
"32": "let rec mem (x:int) xs =\n  match xs with\n      [] -> false\n    | x'::xs -> x = x' || mem x xs\n\nlet rec make_list n (x:int) =\n  if n < 0\n  then []\n  else x :: make_list (n-1) x\n\nlet is_nil (xs:int list) =\n  match xs with\n      [] -> true\n    | _ -> false\n\nlet main n m =\n  let xs = make_list n m in\n    assert (is_nil xs || mem m xs)",
"33": "let is_nil (xs:int list) =\n  match xs with\n      [] -> true\n    | _ -> false\n\nlet rec nth n (xs:int list) =\n  match xs with\n    | [] -> assert false\n    | x::xs' -> if n = 0 then x else nth (n-1) xs'\n\nlet rec make_list n =\n  if n < 0\n  then []\n  else n :: make_list (n-1)\n\nlet main n =\n  let xs = make_list n in\n    if is_nil xs\n    then 0\n    else nth 0 xs",
"34": "let rec div (x:int) y = assert (y <> 0); 0\n\nlet rec fold_left (f:int->int->int) acc xs =\n  match xs with\n      [] -> acc\n    | x::xs' -> fold_left f (f acc x) xs'\n\nlet rec range i j =\n  if i > j then\n    []\n  else\n    let is = range (i+1) j in\n      i::is\n\nlet harmonic n =\n  let ds = range 1 n in\n    fold_left (fun s k -> s + div 10000 k) 0 ds",
"35": "let rec fold_left (f:int->int->int) acc xs =\n  match xs with\n      [] -> acc\n    | x::xs' -> fold_left f (f acc x) xs'\n\nlet rec make_list n =\n  if n < 0\n  then []\n  else n :: make_list (n-1)\n\nlet add x y = x + y\n\nlet main n m =\n  let xs = make_list n in\n    assert (fold_left add m xs >= m)",
"36": "let rec zip (xs:int list) (ys:int list) =\n  match xs with\n      [] ->\n        begin\n          match ys with\n              [] -> []\n            | _ -> assert false\n        end\n    | x::xs' ->\n        match ys with\n            [] -> assert false\n          | y::ys' -> (x,y)::zip xs' ys'\n\nlet rec make_list n =\n  if n < 0\n  then []\n  else n :: make_list (n-1)\n\nlet main n =\n  let xs = make_list n in\n    zip xs xs",
"37": "let rec make_list m =\n  if m <= 0\n  then []\n  else Random.int 0 :: make_list (m-1)\n\nlet rec make_list_list m =\n  if m <= 0\n  then []\n  else make_list (Random.int 0) :: make_list_list (m-1)\n\nlet head = function\n    [] -> assert false\n  | x::xs -> x\n\nlet ne = function\n    [] -> false\n  | x::xs -> true\n\nlet rec filter p = function\n    [] -> []\n  | x::xs -> if p x then x::(filter p xs) else filter p xs\n\nlet rec map f = function\n    [] -> []\n  | x::xs -> f x :: map f xs\n\nlet main m = map head (filter ne (make_list_list m))",
"38": "let rec make_list m =\n  if m <= 0\n  then []\n  else (Random.int 0) :: make_list (m-1)\n\nlet risersElse x = function\n    [] -> assert false\n  | s::ss -> [x]::s::ss\n\nlet risersThen x = function\n    [] -> assert false\n  | s::ss -> (x::s)::ss\n\nlet rec risers = function\n    [] -> []\n  | [x] -> [[x]]\n  | x::y::etc ->\n      if x < y\n      then risersThen x (risers (y::etc))\n      else risersElse x (risers (y::etc))\n\nlet main m = risers (make_list m)",
"39": "exception NotPositive\n\nlet rec fact n =\n  if n <= 0\n  then\n    raise NotPositive\n  else\n    try\n      n * fact (n-1)\n    with NotPositive -> 1\n\nlet main n =\n  try\n    fact n\n  with NotPositive when n <= 0 -> 0",
"40": "let rec for_all f (xs:int list) =\n  match xs with\n      [] -> true\n    | x::xs' ->\n        f x && for_all f xs'\n\nlet rec map (f:(int->int)->int) xs =\n  match xs with\n      [] -> []\n    | x::xs' -> f x :: map f xs'\n\nlet id x = x\nlet succ x = x + 1\nlet double x = x + x\n\nlet main (x:int) =\n  let fs = [id;succ;double] in\n  let xs' = map (fun f -> f 0) fs in\n  let check x = x >= 0 in\n    assert (for_all check xs')",
"41": "let rec reverse acc xs =\n  match xs with\n      [] -> acc\n    | x::xs' -> reverse (x::acc) xs'\nlet reverse xs = reverse [] xs\n\nlet rec make_list n =\n  if n = 0\n  then []\n  else n :: make_list (n-1)\n\nlet hd xs =\n  match xs with\n      [] -> assert false\n    | x::xs' -> x\n\nlet main len =\n  let xs = make_list len in\n    if len > 0\n    then hd (reverse xs)\n    else 0",
"42": "type tree = Leaf | Node of tree * tree\n\nlet max x y = if x > y then x else y\n\nlet rec depth = function\n    Leaf -> 0\n  | Node(t1,t2) -> 1 + max (depth t1) (depth t2)\n\nlet rec make_tree () =\n  if Random.bool ()\n  then Leaf\n  else Node(make_tree(), make_tree())\n\nlet main (n:int) = assert (depth (make_tree()) >= 0)",
"43": "type tree = Leaf | Node of int * tree * tree\n\nlet rec forall f = function\n    Leaf -> true\n  | Node(n,t1,t2) -> f n && forall f t1 && forall f t2\n\nlet rec make_tree n =\n  if n <= 0\n  then Leaf\n  else Node(0, make_tree (n-1), make_tree (n-1))\n\nlet main n =\n  assert (forall (fun n -> n = 0) (make_tree n))",
"44": "type tree = Leaf | Node of int * tree * tree\n\nlet rec forall f = function\n    Leaf -> true\n  | Node(n,t1,t2) -> f n && forall f t1 && forall f t2\n\nlet rec make_tree n =\n  if n <= 0\n  then Leaf\n  else Node(n, make_tree (n-1), make_tree (n-1))\n\nlet main n =\n  assert (forall (fun n -> n > 0) (make_tree n))",
"45": "type exp = Const of int | Add of exp * exp\n\nlet rec eval e =\n  match e with\n      Const n -> n\n    | Add(e1,e2) -> eval e1 + eval e2\n\nlet rec make_exp () =\n  if Random.bool ()\n  then Const (Random.int 21 - 10)\n  else Add(make_exp (), make_exp ())\n\nlet rec map f e =\n  match e with\n      Const n -> Const (f n)\n    | Add(e1,e2) -> Add(map f e1, map f e2)\n\nlet abs x = if x >= 0 then x else -x\n\nlet main () =\n  let e = make_exp () in\n  let e' = map abs e in\n    assert (eval e' >= 0)",
    "46": "let rec copy x = if x=0 then 0 else 1 + copy (x-1)\nlet main n = assert (copy (copy n) = n)",
    "47": "let rec make_list n =\n  if n <= 0\n  then []\n  else (fun m -> n + m) :: make_list (n-1)\n\nlet rec fold_right f xs init =\n  match xs with\n      [] -> init\n    | x::xs' -> f x (fold_right f xs' init)\n\nlet compose f g x = f (g x)\n\nlet main n =\n  let xs = make_list n in\n  let f = fold_right compose xs (fun x -> x) in\n    assert (f 0 >= 0)",
    "48": "let rec length xs =\n  match xs with\n      [] -> 0\n    | _::xs' -> 1 + length xs'\n\nlet rec make_list n =\n  if n = 0\n  then []\n  else n :: make_list (n-1)\n\nlet main n =\n  let xs = make_list n in\n    assert (length xs = n)",
    "49": "let rec nth n (xs:int list) =\n  match xs with\n    | [] -> assert false\n    | x::xs' -> if n = 0 then x else nth (n-1) xs'\n\nlet rec make_list n =\n  if n < 0\n  then []\n  else n :: make_list (n-1)\n\nlet main n =\n  if n > 0\n  then nth (n-1) (make_list n)\n  else 0",
    "50": "type option = None | Some of int\n\nlet rec exists test f n m =\n  if n < m\n  then\n    if test (f n)\n    then Some n\n    else exists test f (n+1) m\n  else\n    None\n\nlet mult3 n = 3 * n\n\nlet main n m =\n  let test x = x = m in\n    match exists test mult3 0 n with\n        None -> ()\n      | Some x -> assert (0 <= x && x < n)",
    "51": "exception NotPositive\n\nlet rec fact n =\n  if n <= 0\n  then\n    raise NotPositive\n  else\n    try\n      n * fact (n-1)\n    with NotPositive -> 1\n\nlet main n =\n  try\n    fact n\n  with NotPositive -> assert (n < 0) ; 0",
    "52": "let rec div x y =\n  assert (y <> 0);\n  if x < y\n  then 0\n  else 1 + div (x-y) y\n\nlet rec fold_left f acc xs =\n  match xs with\n      [] -> acc\n    | x::xs' -> fold_left f (f acc x) xs'\n\nlet rec range i j =\n  if i > j then\n    []\n  else\n    let is = range (i+1) j in\n      i::is\n\nlet harmonic n =\n  let ds = range 0 n in\n    fold_left (fun s k -> s + div 10000 k) 0 ds",
    "53": "let rec make_list m =\n  if m <= 0\n  then []\n  else Random.int 0 :: make_list (m-1)\n\nlet rec make_list_list m =\n  if m <= 0\n  then []\n  else make_list (Random.int 0) :: make_list_list (m-1)\n\nlet head = function\n    [] -> assert false\n  | x::xs -> x\n\nlet ne = function\n    [] -> 1\n  | x::xs -> 0\n\nlet rec filter p = function\n    [] -> []\n  | x::xs -> if p x = 1 then x::(filter p xs) else filter p xs\n\nlet rec map f = function\n    [] -> []\n  | x::xs -> f x :: map f xs\n\nlet main m = map head (filter ne (make_list_list m))",
    "54": "type option = None | Some of int\n\nlet rec exists test f n m =\n  if n < m\n  then\n    if test (f n)\n    then Some n\n    else exists test f (n+1) m\n  else\n    None\n\nlet mult3 n = 3 * n\n\nlet main n m =\n  let test x = x = m in\n    match exists test mult3 0 n with\n        None -> ()\n      | Some x -> assert (0 < x && x < n)"
}

function ex(form) {
    form.input.value = program[form.program.value];
    $('textarea').elastic();
}

function run() {
    $('#result').html('<h2>Now verifying...</h2>');
    $.post(
        'mochi.cgi',
        {'input':$('#input').val(), 'verbose':$("#verbose").attr("checked")},
        function(result){
            $('#result').html(result);
        }
    );
}

function clear_form(form) {
    form.reset();
    $('#result').text('');
}

$(document).ready(function(){
    $('#demo_body').css('display', 'block');
    $('textarea').elastic();
    $('textarea').trigger('update');
})
