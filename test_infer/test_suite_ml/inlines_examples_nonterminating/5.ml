(* START: 0;

FROM: 0;
TO: 3;

FROM: 3;
  assume(x>0);
TO: 10;

FROM: 10;
   rho := nondet();
TO: 11;
         
FROM: 11;
  assume(rho>0);
TO: 12;

FROM: 11;
  assume(rho<=0);
TO: 13;
                    
FROM: 12;
  x := x-1;
TO: 3;

FROM: 13;
  y := y-1;
  x := z;
TO: 3; *)

let rec state3 x y z =
  if x>0 then state10 x y z else ()
and state10 x y z =
  let rho = read_int () in
  if rho > 0 then state3 (x-1) y z else state3 z (y-1) z
let main () =
  let x = read_int () in
  let y = read_int () in
  let z = read_int () in
  state3 x y z; assert false